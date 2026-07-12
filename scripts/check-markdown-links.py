#!/usr/bin/env python3
"""Fail on broken local Markdown links in catalog navigation and skill entrypoints."""
from __future__ import annotations

import re
import sys
from pathlib import Path

from catalog import load_catalog

LINK = re.compile(r"(?<!!)\[[^\]]+\]\(([^)]+)\)")


def checked_files(root: Path) -> list[Path]:
    catalog = load_catalog(root)
    files = [root / "README.md", root / "AGENTS.md"]
    files.extend(root / phase / "README.md" for phase in catalog["phases"])
    files.extend(root / entry["source_path"] / "SKILL.md" for entry in catalog["skills"])
    return files


def failures(files: list[Path]) -> list[str]:
    broken: list[str] = []
    for path in files:
        for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for match in LINK.finditer(line):
                target = match.group(1).split()[0].strip("<>")
                if target.startswith(("#", "http:", "https:", "mailto:")):
                    continue
                local = target.split("#", 1)[0]
                if local and not (path.parent / local).exists():
                    broken.append(f"{path}:{line_number}: broken link: {target}")
    return broken


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    files = [Path(value).resolve() for value in sys.argv[1:]] or checked_files(root)
    broken = failures(files)
    if broken:
        print("\n".join(broken), file=sys.stderr)
        return 1
    print(f"markdown link check passed ({len(files)} files)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
