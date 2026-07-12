#!/usr/bin/env python3
"""Shell-friendly query surface for catalog consumers."""
import argparse, json, sys
from pathlib import Path
from catalog import CatalogError, LIFECYCLES, load_catalog, projection, select

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    p.add_argument("--host", required=True)
    p.add_argument("--include-lifecycle", action="append", default=[])
    p.add_argument("--skill")
    p.add_argument("--projection")
    args = p.parse_args()
    unknown = set(args.include_lifecycle) - LIFECYCLES
    if unknown:
        print(f"unknown lifecycle: {sorted(unknown)[0]}", file=sys.stderr); return 2
    try:
        payload = load_catalog(Path(args.root))
        entries = select(payload, args.host, set(args.include_lifecycle), args.skill)
    except CatalogError as exc:
        print(exc, file=sys.stderr); return 2
    if args.projection:
        Path(args.projection).write_text(json.dumps(projection(payload, entries), indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    for entry in entries:
        print(f"{entry['name']}\t{entry['source_path']}")
    return 0
if __name__ == "__main__": raise SystemExit(main())
