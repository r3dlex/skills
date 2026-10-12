import json
import sys
from pathlib import Path

import catalog

root = Path(sys.argv[1])
mode = sys.argv[2] if len(sys.argv) > 2 else "select"
try:
    payload = catalog.load_catalog(root)
    if mode == "unknown-host":
        catalog.select(payload, "nope")
        print("UNEXPECTED")
    elif mode == "unknown-lifecycle":
        catalog.select(payload, "codex", {"nope"})
        print("UNEXPECTED")
    elif mode == "load":
        print("OK")
    elif mode == "select":
        entries = catalog.select(payload, "codex")
        print(json.dumps({"names": [entry["name"] for entry in entries]}, sort_keys=True, separators=(",", ":")))
    else:
        print("ERR unknown mode " + mode)
        raise SystemExit(2)
except catalog.CatalogError as exc:
    print("ERR " + str(exc))
    raise SystemExit(2)
