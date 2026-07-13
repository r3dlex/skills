#!/usr/bin/env python3
"""Render selected DPUA CI hosts from one execution profile."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "03-configure-generate/ai-catapult-init/templates/ci"
HOSTS = ("github", "ado", "gitlab")
PROTECTED = {"release", "publish", "deployment", "cas-write"}
ELIGIBLE = {"validation", "test"}
TRANSIENT = {"provider-timed-out", "executor-incomplete-after-heartbeat"}
STATUSES = {"experimental", "blocked", "supported"}


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
            if not isinstance(config.get("hosted_image"), str) or not config["hosted_image"]:
                raise ContractError("github hosted image is required")
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
            if not isinstance(config.get("self_hosted_pool"), str) or not config["self_hosted_pool"]:
                raise ContractError("ADO self-hosted pool is required")
            string_list(config.get("self_hosted_demands"), "ADO self-hosted demands")
            if not isinstance(config.get("hosted_vm_image"), str) or not config["hosted_vm_image"]:
                raise ContractError("ADO hosted VM image is required")
            if config.get("required_read_permission") != "agent-pools:read":
                raise ContractError("ADO selector permission must be agent-pools:read")
        else:
            string_list(config.get("self_hosted_tags"), "GitLab self-hosted tags")
            string_list(config.get("hosted_tags"), "GitLab hosted tags")
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


def actual_files(output: Path) -> dict[str, bytes]:
    if not output.is_dir():
        return {}
    return {
        path.relative_to(output).as_posix(): path.read_bytes()
        for path in output.rglob("*")
        if path.is_file()
    }


def write_transaction(output: Path, files: dict[str, bytes]) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temp = Path(tempfile.mkdtemp(prefix=f".{output.name}.tmp-", dir=output.parent))
    backup = output.with_name(f".{output.name}.bak-{os.getpid()}")
    try:
        for name, body in files.items():
            target = temp / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(body)
        if output.exists():
            os.replace(output, backup)
        os.replace(temp, output)
        shutil.rmtree(backup, ignore_errors=True)
    except Exception:
        if not output.exists() and backup.exists():
            os.replace(backup, output)
        raise
    finally:
        shutil.rmtree(temp, ignore_errors=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--profile", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        expected = render(load_profile(args.profile))
        if args.check:
            if actual_files(args.output) != expected:
                raise ContractError("selected-host CI projection drift detected")
        else:
            write_transaction(args.output, expected)
        return 0
    except ContractError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
