#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/catalog-query.py --host codex > /tmp/catalog.default
[[ "$(wc -l < /tmp/catalog.default | tr -d ' ')" -eq 25 ]]
for host in codex claude-code gemini copilot auggie; do
  python3 scripts/catalog-query.py --host "$host" --include-lifecycle experimental --include-lifecycle deprecated > "/tmp/catalog.$host"
  diff -u /tmp/catalog.default "/tmp/catalog.$host"
done
out=$(mktemp); python3 scripts/catalog-query.py --host codex --projection "$out" >/dev/null
python3 - "$out" <<'PY'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); names=[x['name'] for x in data['skills']]
assert names==sorted(names); assert open(p,'rb').read().endswith(b'\n')
PY
set +e
python3 scripts/catalog-query.py --host codex --include-lifecycle unknown >/dev/null 2>&1; rc=$?
set -e
[[ $rc -eq 2 ]]
python3 scripts/generate-skill-docs.py --check
