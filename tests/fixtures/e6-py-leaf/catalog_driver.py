import json
import sys
from pathlib import Path

import catalog

root = Path(sys.argv[1])
try:
    payload = catalog.load_catalog(root)
    entries = catalog.select(payload, "codex")
    print(json.dumps({"names": [entry["name"] for entry in entries]}, sort_keys=True, separators=(",", ":")))
except catalog.CatalogError as exc:
    print("ERR " + str(exc))
    raise SystemExit(2)
