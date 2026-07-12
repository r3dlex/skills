#!/usr/bin/env python3
"""Validate staged source links and catalog-backed flat skill references."""
from __future__ import annotations

import argparse
import re
from pathlib import Path, PurePosixPath

from catalog import load_catalog

LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def checked_files(root: Path, catalog: dict) -> list[Path]:
    files = [root / "README.md", root / "AGENTS.md"]
    files.extend(root / phase / "README.md" for phase in catalog["phases"])
    files.extend(root / entry["source_path"] / "SKILL.md" for entry in catalog["skills"])
    return [path for path in files if path.is_file()]


def logical_target(root: Path, source_name: str, target: str, by_name: dict[str, dict]) -> tuple[Path, bool]:
    logical = PurePosixPath(source_name) / target
    parts: list[str] = []
    for part in logical.parts:
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    if not parts:
        return root, False
    skill = by_name.get(parts[0])
    if skill:
        return root / skill["source_path"] / Path(*parts[1:]), True
    return root / Path(*parts), False


def failures(root: Path, files: list[Path], catalog: dict) -> list[str]:
    by_name = {entry["name"]: entry for entry in catalog["skills"]}
    by_skill_file = {
        (root / entry["source_path"] / "SKILL.md").resolve(): entry["name"]
        for entry in catalog["skills"]
    }
    broken: list[str] = []
    for path in files:
        source_name = by_skill_file.get(path.resolve())
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for match in LINK.finditer(line):
                target = match.group(1).split()[0].strip("<>")
                if target.startswith(("#", "http:", "https:", "mailto:")):
                    continue
                local = target.split("#", 1)[0]
                if not local:
                    continue
                direct = path.parent / local
                if direct.exists():
                    continue
                if source_name:
                    resolved, installed_skill_target = logical_target(root, source_name, local, by_name)
                    if resolved.exists():
                        # A cross-skill link must also resolve after skills are installed
                        # flat by name. Repository-document links are source-only.
                        if installed_skill_target:
                            relative = resolved.relative_to(root / by_name[resolved_skill_name(resolved, root, by_name)]["source_path"])
                            installed = root / by_name[resolved_skill_name(resolved, root, by_name)]["source_path"] / relative
                            if not installed.exists():
                                broken.append(f"{path}:{line_number}: broken installed-flat link: {target}")
                        continue
                broken.append(f"{path}:{line_number}: broken source link: {target}")
    return broken


def resolved_skill_name(path: Path, root: Path, by_name: dict[str, dict]) -> str:
    resolved = path.resolve()
    for name, entry in by_name.items():
        skill_root = (root / entry["source_path"]).resolve()
        if resolved == skill_root or skill_root in resolved.parents:
            return name
    raise ValueError(f"catalog skill target not found for {path}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    catalog = load_catalog(root)
    files = [path.resolve() for path in args.files] or checked_files(root, catalog)
    broken = failures(root, files, catalog)
    if broken:
        print("\n".join(broken), file=__import__("sys").stderr)
        return 1
    print(f"markdown link check passed ({len(files)} files; source + installed-flat)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
