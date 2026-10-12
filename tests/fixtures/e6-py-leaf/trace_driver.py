import json
import sys

import traceability_schema

graph = json.loads(sys.argv[1])
try:
    traceability_schema.validate_graph(graph)
    print("OK")
except ValueError as exc:
    print("ERR " + str(exc))
    raise SystemExit(1)
