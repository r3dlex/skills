#!/usr/bin/env python3
"""Canonical dependency-free reader for the source skill catalog."""
from __future__ import annotations

import json
from pathlib import Path

LIFECYCLES = {"stable", "compatibility", "experimental", "deprecated"}
HOSTS = {"codex", "claude-code", "gemini", "copilot", "auggie"}
DEFAULT_LIFECYCLES = {"stable", "compatibility"}


class CatalogError(ValueError):
    pass


def load_catalog(root: Path) -> dict:
    path = root / "catalog.json"
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CatalogError(f"invalid catalog: {exc}") from exc
    if payload.get("schema_version") != "1.0":
        raise CatalogError("catalog schema_version must be 1.0")
    phases = payload.get("phases")
    skills = payload.get("skills")
    if (not isinstance(phases, list) or not phases or
            not all(isinstance(phase, str) and phase for phase in phases) or
            len(phases) != len(set(phases))):
        raise CatalogError("phases must be a non-empty unique list")
    if not isinstance(skills, list):
        raise CatalogError("skills must be a list")
    names, paths = set(), set()
    for entry in skills:
        required = {"name", "source_path", "owner_phase", "applies_to_phases", "lifecycle", "supported_hosts"}
        if not isinstance(entry, dict) or not required <= entry.keys():
            raise CatalogError("catalog skill entry is missing required fields")
        name, source = entry["name"], entry["source_path"]
        if not isinstance(name, str) or not name or name in names:
            raise CatalogError(f"duplicate or invalid skill name: {name!r}")
        if not isinstance(source, str) or not source:
            raise CatalogError(f"invalid source_path for {name}: {source!r}")
        source_path = Path(source)
        if source_path.is_absolute() or ".." in source_path.parts or source in paths:
            raise CatalogError(f"duplicate or unsafe source_path: {source!r}")
        owner = entry["owner_phase"]
        applies = entry["applies_to_phases"]
        lifecycle = entry["lifecycle"]
        hosts = entry["supported_hosts"]
        if not isinstance(owner, str) or not isinstance(applies, list) or not all(isinstance(x, str) for x in applies):
            raise CatalogError(f"invalid phase metadata types for {name}")
        if owner not in phases or not set(applies) <= set(phases):
            raise CatalogError(f"invalid phase metadata for {name}")
        if not isinstance(lifecycle, str) or lifecycle not in LIFECYCLES:
            raise CatalogError(f"invalid lifecycle for {name}")
        if not isinstance(hosts, list) or not hosts or not all(isinstance(x, str) for x in hosts) or not set(hosts) <= HOSTS:
            raise CatalogError(f"invalid supported_hosts for {name}")
        skill_file = root / source / "SKILL.md"
        if not skill_file.is_file():
            raise CatalogError(f"missing SKILL.md for {name}: {source}")
        from validate_skill_frontmatter import frontmatter_name
        if frontmatter_name(skill_file) != name:
            raise CatalogError(f"frontmatter name mismatch for {name}: {source}")
        names.add(name); paths.add(source)
    return payload


def select(payload: dict, host: str, included: set[str] | None = None, name: str | None = None) -> list[dict]:
    if host not in HOSTS:
        raise CatalogError(f"unknown host: {host}")
    enabled = DEFAULT_LIFECYCLES | (included or set())
    unknown = enabled - LIFECYCLES
    if unknown:
        raise CatalogError(f"unknown lifecycle: {sorted(unknown)[0]}")
    entries = [e for e in payload["skills"] if host in e["supported_hosts"] and e["lifecycle"] in enabled]
    if name:
        matches = [e for e in payload["skills"] if e["name"] == name and host in e["supported_hosts"]]
        if not matches:
            raise CatalogError(f"unknown skill for {host}: {name}")
        if matches[0]["lifecycle"] not in enabled:
            raise CatalogError(f"skill {name} requires --include-lifecycle {matches[0]['lifecycle']}")
        entries = matches
    return sorted(entries, key=lambda e: e["name"])


def projection(payload: dict, entries: list[dict]) -> dict:
    return {"schema_version": payload["schema_version"], "skills": entries}
