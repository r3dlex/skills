#!/usr/bin/env python3
"""Render selected DPUA CI hosts from one execution profile."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import sys
import time
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "03-configure-generate/ai-catapult-init/templates/ci"
HOSTS = ("github", "ado", "gitlab")
PROTECTED = {"release", "publish", "deployment", "cas-write"}
ELIGIBLE = {"validation", "test"}
TRANSIENT = {"provider-timed-out", "executor-incomplete-after-heartbeat"}
STATUSES = {"experimental", "blocked", "supported"}
SAFE_TOKEN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
ADO_DEMAND = re.compile(
    r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63} -(?:equals|notEquals) [A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
)
MANIFEST = ".ai/execution/generated/ci-adapters.json"


class ContractError(ValueError):
    pass


def load_profile(path: Path) -> dict[str, Any]:
    try:
        profile = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"invalid execution profile: {exc}") from exc
    if set(profile) != {"schema_version", "profile_type", "profile_id", "version", "settings"}:
        raise ContractError("execution profile envelope is incomplete or has unknown fields")
    if profile["schema_version"] != "1.0" or profile["profile_type"] != "execution":
        raise ContractError("only execution profile schema 1.0 is supported")
    if not isinstance(profile["settings"], dict):
        raise ContractError("execution settings must be an object")
    validate_policy(profile["settings"])
    return profile


def string_list(value: Any, label: str) -> list[str]:
    if not isinstance(value, list) or not value or any(not isinstance(item, str) or not item for item in value):
        raise ContractError(f"{label} must be a non-empty string list")
    folded = [item.casefold() for item in value]
    if len(folded) != len(set(folded)):
        raise ContractError(f"{label} must not contain duplicates")
    return value


def positive_integer(value: Any, label: str) -> int:
    if type(value) is not int or value < 1:
        raise ContractError(f"{label} must be a positive integer")
    return value


def safe_token(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SAFE_TOKEN.fullmatch(value):
        raise ContractError(f"{label} contains unsafe YAML characters")
    return value


def validate_common(host: str, config: Any, health_field: str) -> dict[str, Any]:
    if not isinstance(config, dict):
        raise ContractError(f"selected host {host} has no adapter policy")
    if set(config.get("fallback_excluded_tasks", [])) != PROTECTED:
        raise ContractError(f"{host} must exclude every protected task from fallback")
    if set(config.get("fallback_eligible_tasks", [])) != ELIGIBLE:
        raise ContractError(f"{host} fallback eligibility must be validation and test only")
    positive_integer(config.get(health_field), f"{host} {health_field}")
    positive_integer(config.get("queue_age_threshold_seconds"), f"{host} queue threshold")
    if type(config.get("max_redispatch_count")) is not int or config["max_redispatch_count"] != 0:
        raise ContractError(f"{host} automatic redispatch must be disabled")
    if config.get("adapter_status") not in STATUSES:
        raise ContractError(f"{host} adapter status is invalid")
    return config


def validate_policy(settings: dict[str, Any]) -> None:
    required = {"runner_preference", "host_selection", "hosted_fallback", "transient_retry"}
    allowed = required | set(HOSTS)
    if not required <= set(settings) or not set(settings) <= allowed:
        raise ContractError("execution policy has missing or unknown fields")
    if settings["runner_preference"] not in {"self-hosted", "hosted"}:
        raise ContractError("runner preference must be self-hosted or hosted")
    if type(settings["hosted_fallback"]) is not bool:
        raise ContractError("hosted fallback must be boolean")
    selected = string_list(settings["host_selection"], "host selection")
    if any(host not in HOSTS for host in selected):
        raise ContractError("Lore is reserved; only github, ado, and gitlab are selectable")

    retry = settings["transient_retry"]
    if not isinstance(retry, dict) or set(retry) != {"max_retries", "classes"}:
        raise ContractError("transient retry policy is incomplete")
    if type(retry["max_retries"]) is not int or retry["max_retries"] != 1:
        raise ContractError("same-executor transient retry budget must be exactly one")
    if set(retry["classes"]) != TRANSIENT:
        raise ContractError("transient retry taxonomy is invalid")

    for host in selected:
        config = validate_common(
            host,
            settings.get(host),
            "minimum_healthy_agents" if host == "ado" else "minimum_healthy_runners",
        )
        if host == "github":
            string_list(config.get("self_hosted_labels"), "github self-hosted labels")
            safe_token(config.get("hosted_image"), "github hosted image")
            scope = config.get("runner_scope")
            if scope == "organization":
                if config.get("required_read_permission") != "self-hosted-runners:read":
                    raise ContractError("organization runner selection requires self-hosted-runners:read")
                if not isinstance(config.get("runner_organization"), str) or not config["runner_organization"]:
                    raise ContractError("organization runner selection requires an organization identity")
                positive_integer(config.get("runner_group_id"), "github runner group")
            elif scope == "repository":
                if config.get("required_read_permission") != "administration:read":
                    raise ContractError("repository runner selection requires administration:read")
                if config.get("runner_organization") is not None or config.get("runner_group_id") is not None:
                    raise ContractError("repository runner selection cannot declare organization runner identity")
            else:
                raise ContractError("github runner scope must be organization or repository")
        elif host == "ado":
            safe_token(config.get("self_hosted_pool"), "ADO self-hosted pool")
            demands = string_list(config.get("self_hosted_demands"), "ADO self-hosted demands")
            if any(not ADO_DEMAND.fullmatch(demand) for demand in demands):
                raise ContractError("ADO demand is outside the safe equality grammar")
            safe_token(config.get("hosted_vm_image"), "ADO hosted VM image")
            if config.get("required_read_permission") != "agent-pools:read":
                raise ContractError("ADO selector permission must be agent-pools:read")
        else:
            self_hosted = string_list(config.get("self_hosted_tags"), "GitLab self-hosted tags")
            hosted = string_list(config.get("hosted_tags"), "GitLab hosted tags")
            if any(not SAFE_TOKEN.fullmatch(tag) for tag in self_hosted + hosted):
                raise ContractError("GitLab tags contain unsafe YAML characters")
            if config.get("child_pipeline_file") != ".gitlab/dpua-child.yml":
                raise ContractError("GitLab child pipeline path is fixed by the adapter contract")
            if config.get("required_read_permission") != "read_api":
                raise ContractError("GitLab selector permission must be read_api")


def replace(template: Path, values: dict[str, str]) -> bytes:
    body = template.read_text(encoding="utf-8")
    for key, value in values.items():
        body = body.replace(f"@@{key}@@", value)
    if "@@" in body:
        raise ContractError(f"unresolved token in {template}")
    return body.encode()


def render(profile: dict[str, Any]) -> dict[str, bytes]:
    settings = profile["settings"]
    preference = settings["runner_preference"]
    files: dict[str, bytes] = {}
    if "github" in settings["host_selection"]:
        config = settings["github"]
        files[".github/workflows/dpua-validation.yml"] = replace(
            TEMPLATES / "github/dpua-validation.yml.template",
            {"HOSTED_IMAGE": config["hosted_image"], "RUNNER_PREFERENCE": preference},
        )
    if "ado" in settings["host_selection"]:
        config = settings["ado"]
        demands = "\n".join(f"            - {item}" for item in config["self_hosted_demands"])
        files["azure-pipelines.yml"] = replace(
            TEMPLATES / "ado/azure-pipelines.yml.template",
            {
                "HOSTED_IMAGE": config["hosted_vm_image"],
                "RUNNER_PREFERENCE": preference,
                "SELF_HOSTED_POOL": config["self_hosted_pool"],
                "SELF_HOSTED_DEMANDS": demands,
            },
        )
    if "gitlab" in settings["host_selection"]:
        config = settings["gitlab"]
        values = {
            "RUNNER_PREFERENCE": preference,
            "CHILD_PIPELINE": config["child_pipeline_file"],
            "SELF_HOSTED_TAGS": ", ".join(config["self_hosted_tags"]),
            "HOSTED_TAGS": ", ".join(config["hosted_tags"]),
        }
        files[".gitlab-ci.yml"] = replace(TEMPLATES / "gitlab/gitlab-ci.yml.template", values)
        files[config["child_pipeline_file"]] = replace(TEMPLATES / "gitlab/dpua-child.yml.template", values)
    manifest = {
        "schema_version": "1.0",
        "profile_id": profile["profile_id"],
        "profile_version": profile["version"],
        "selected_hosts": [host for host in HOSTS if host in settings["host_selection"]],
        "files": {name: hashlib.sha256(body).hexdigest() for name, body in sorted(files.items())},
    }
    files[".ai/execution/generated/ci-adapters.json"] = (
        json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    ).encode()
    return files


def canonical(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def digest(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def safe_relative(name: object) -> str:
    if not isinstance(name, str) or not name or "\\" in name:
        raise ContractError("adapter manifest contains an unsafe path")
    path = Path(name)
    if path.is_absolute() or ".." in path.parts or "." in path.parts:
        raise ContractError("adapter manifest contains an unsafe path")
    return path.as_posix()


def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def durable_write(path: Path, body: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as stream:
        stream.write(body)
        stream.flush()
        os.fsync(stream.fileno())
    fsync_directory(path.parent)


def state_paths(output: Path) -> tuple[Path, Path, Path, Path]:
    state = output / ".ai/execution/generated"
    return (
        state / ".ci-adapters.lock",
        state / ".ci-adapters.journal.json",
        state / ".ci-adapters.stage",
        state / ".ci-adapters.backup",
    )


def validate_output_root(output: Path) -> Path:
    if output.is_symlink() or (output.exists() and not output.is_dir()):
        raise ContractError("output must be a real directory")
    resolved = output.resolve()
    if resolved in {Path("/"), Path.home().resolve()}:
        raise ContractError("refusing an unsafe output root")
    if output.exists() and any(output.iterdir()):
        manifest = output / MANIFEST
        recovery = output / ".ai/execution/generated/.ci-adapters.journal.json"
        if not manifest.is_file() and not recovery.is_file() and not (output / ".ai/matrix.json").is_file():
            raise ContractError("non-empty output is not an initialized AI-SDLC workspace")
    else:
        output.mkdir(parents=True, exist_ok=True)
    return resolved


def ensure_safe_target(output: Path, name: str) -> Path:
    relative = safe_relative(name)
    target = output / relative
    current = output
    for part in Path(relative).parts[:-1]:
        current = current / part
        if current.is_symlink():
            raise ContractError(f"managed path traverses a symlink: {relative}")
    if target.is_symlink():
        raise ContractError(f"managed path is a symlink: {relative}")
    return target


def load_owned_manifest(output: Path) -> dict[str, str]:
    path = output / MANIFEST
    if not path.exists():
        return {}
    if path.is_symlink():
        raise ContractError("adapter manifest must not be a symlink")
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"invalid existing adapter manifest: {exc}") from exc
    if set(payload) != {"schema_version", "profile_id", "profile_version", "selected_hosts", "files"}:
        raise ContractError("existing adapter manifest has unknown or missing fields")
    if payload["schema_version"] != "1.0" or not isinstance(payload["files"], dict):
        raise ContractError("existing adapter manifest is unsupported")
    owned: dict[str, str] = {}
    for name, expected_digest in payload["files"].items():
        name = safe_relative(name)
        if not isinstance(expected_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
            raise ContractError("existing adapter manifest contains an invalid digest")
        owned[name] = expected_digest
    return owned


def verify_ownership(output: Path, previous: dict[str, str], expected: dict[str, bytes]) -> None:
    for name, expected_digest in previous.items():
        target = ensure_safe_target(output, name)
        if not target.is_file() or digest(target.read_bytes()) != expected_digest:
            raise ContractError(f"managed CI projection was modified outside the renderer: {name}")
    for name in expected:
        if name == MANIFEST or name in previous:
            continue
        target = ensure_safe_target(output, name)
        if target.exists():
            raise ContractError(f"refusing to replace an unowned path: {name}")


def write_journal(path: Path, payload: dict[str, object]) -> None:
    pending = path.with_name(f"{path.name}.tmp-{os.getpid()}")
    durable_write(pending, canonical(payload))
    os.replace(pending, path)
    fsync_directory(path.parent)


def load_journal(path: Path, output: Path) -> dict[str, object]:
    try:
        journal = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ContractError(f"invalid CI adapter transaction journal: {exc}") from exc
    if set(journal) != {"schema_version", "phase", "output", "affected", "originally_present"}:
        raise ContractError("CI adapter transaction journal has unknown or missing fields")
    if journal["schema_version"] != "1.0" or journal["phase"] not in {"prepared", "promoting", "committed"}:
        raise ContractError("CI adapter transaction journal is unsupported")
    if Path(str(journal["output"])).resolve() != output.resolve():
        raise ContractError("CI adapter transaction journal belongs to another workspace")
    affected = journal["affected"]
    present = journal["originally_present"]
    if not isinstance(affected, list) or not isinstance(present, list):
        raise ContractError("CI adapter transaction journal file sets are invalid")
    journal["affected"] = [safe_relative(name) for name in affected]
    journal["originally_present"] = [safe_relative(name) for name in present]
    if len(journal["affected"]) != len(set(journal["affected"])) or not set(journal["originally_present"]) <= set(journal["affected"]):
        raise ContractError("CI adapter transaction journal file sets are ambiguous")
    return journal


def recover(
    output: Path,
    journal: Path,
    stage: Path,
    backup: Path,
    *,
    crash_after_restore: int | None = None,
) -> None:
    if not journal.exists():
        shutil.rmtree(stage, ignore_errors=True)
        shutil.rmtree(backup, ignore_errors=True)
        return
    state = load_journal(journal, output)
    affected = state["affected"]
    present = set(state["originally_present"])
    if state["phase"] != "committed":
        restored = 0
        for name in affected:
            target = ensure_safe_target(output, name)
            saved = backup / name
            if name in present:
                if saved.is_symlink() or not saved.is_file():
                    raise ContractError(f"transaction backup is incomplete: {name}")
                restore = backup / ".restore" / name
                durable_write(restore, saved.read_bytes())
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(restore, target)
                fsync_directory(target.parent)
                restored += 1
                if crash_after_restore and restored >= crash_after_restore:
                    os._exit(88)
            elif target.exists():
                if not target.is_file():
                    raise ContractError(f"transaction target changed type: {name}")
                target.unlink()
                fsync_directory(target.parent)
    shutil.rmtree(stage, ignore_errors=True)
    shutil.rmtree(backup, ignore_errors=True)
    journal.unlink(missing_ok=True)
    fsync_directory(journal.parent)


def acquire_workspace_lock(lock: Path) -> int:
    lock.parent.mkdir(parents=True, exist_ok=True)
    descriptor = os.open(lock.parent, os.O_RDONLY)
    try:
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as exc:
        os.close(descriptor)
        raise ContractError("CI adapter workspace lock is held by another renderer") from exc
    durable_write(lock, canonical({"pid": os.getpid(), "created_at": time.time()}))
    return descriptor


def release_workspace_lock(descriptor: int, lock: Path) -> None:
    lock.unlink(missing_ok=True)
    fsync_directory(lock.parent)
    fcntl.flock(descriptor, fcntl.LOCK_UN)
    os.close(descriptor)


def managed_check(output: Path, expected: dict[str, bytes]) -> None:
    previous = load_owned_manifest(output)
    expected_manifest = json.loads(expected[MANIFEST])
    if previous != expected_manifest["files"]:
        raise ContractError("selected-host CI projection drift detected")
    for name, body in expected.items():
        target = ensure_safe_target(output, name)
        if not target.is_file() or target.read_bytes() != body:
            raise ContractError("selected-host CI projection drift detected")


def check_transaction(
    output: Path,
    expected: dict[str, bytes],
    *,
    crash_after_restore: int | None,
) -> None:
    output = validate_output_root(output)
    lock, journal, stage, backup = state_paths(output)
    descriptor = acquire_workspace_lock(lock)
    try:
        recover(output, journal, stage, backup, crash_after_restore=crash_after_restore)
        managed_check(output, expected)
    finally:
        release_workspace_lock(descriptor, lock)


def write_transaction(
    output: Path,
    files: dict[str, bytes],
    *,
    fail_after: int | None,
    crash_after: int | None,
    crash_at: str | None,
    crash_after_restore: int | None,
    hold_lock_seconds: float,
) -> None:
    output = validate_output_root(output)
    lock, journal, stage, backup = state_paths(output)
    descriptor = acquire_workspace_lock(lock)
    try:
        recover(output, journal, stage, backup, crash_after_restore=crash_after_restore)
        if hold_lock_seconds:
            time.sleep(hold_lock_seconds)
        previous = load_owned_manifest(output)
        verify_ownership(output, previous, files)
        affected = sorted(set(previous) | set(files) | {MANIFEST})
        originally_present: list[str] = []
        stage.mkdir(parents=True)
        backup.mkdir(parents=True)
        for name, body in files.items():
            durable_write(stage / name, body)
        for name in affected:
            target = ensure_safe_target(output, name)
            if target.exists():
                if not target.is_file():
                    raise ContractError(f"managed target is not a file: {name}")
                originally_present.append(name)
                durable_write(backup / name, target.read_bytes())
        transaction = {
            "schema_version": "1.0",
            "phase": "prepared",
            "output": str(output),
            "affected": affected,
            "originally_present": originally_present,
        }
        write_journal(journal, transaction)
        if crash_at == "after-intent":
            os._exit(85)
        transaction["phase"] = "promoting"
        write_journal(journal, transaction)
        for index, name in enumerate(affected, 1):
            target = ensure_safe_target(output, name)
            staged = stage / name
            if staged.is_file():
                target.parent.mkdir(parents=True, exist_ok=True)
                os.replace(staged, target)
                fsync_directory(target.parent)
            elif target.exists():
                target.unlink()
                fsync_directory(target.parent)
            if crash_after and index >= crash_after:
                os._exit(86)
            if fail_after and index >= fail_after:
                raise RuntimeError("injected CI adapter promotion failure")
        transaction["phase"] = "committed"
        write_journal(journal, transaction)
        if crash_at == "after-commit":
            os._exit(87)
        recover(output, journal, stage, backup)
    except Exception:
        recover(output, journal, stage, backup)
        raise
    finally:
        release_workspace_lock(descriptor, lock)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--fail-after-promote", type=int)
    parser.add_argument("--crash-after-promote", type=int)
    parser.add_argument("--crash-after-rollback-restore", type=int)
    parser.add_argument("--crash-at", choices=["after-intent", "after-commit"])
    parser.add_argument("--hold-lock-seconds", type=float, default=0)
    args = parser.parse_args()
    try:
        expected = render(load_profile(args.profile))
        if args.check:
            check_transaction(
                args.output,
                expected,
                crash_after_restore=args.crash_after_rollback_restore,
            )
        else:
            write_transaction(
                args.output,
                expected,
                fail_after=args.fail_after_promote,
                crash_after=args.crash_after_promote,
                crash_at=args.crash_at,
                crash_after_restore=args.crash_after_rollback_restore,
                hold_lock_seconds=args.hold_lock_seconds,
            )
        return 0
    except (ContractError, RuntimeError, OSError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
