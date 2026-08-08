#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Assert explicitly rather than relying on `set -e` to abort on a bare `[[ ]]`.
# bash 3.2 (the macOS system shell, and what contributors run locally) does NOT
# treat a failing conditional command as an errexit trigger, so a bare
# `[[ a -eq b ]]` line silently continues and the suite exits 0 with the
# assertion inert. Verified on 3.2.57: a false `[[ ]]` under `set -euo pipefail`
# still reaches the next line. `die` makes these fail closed on every shell.
die() { echo "FAIL: $1" >&2; exit 1; }

python3 scripts/catalog-query.py --host codex > /tmp/catalog.default
actual="$(wc -l < /tmp/catalog.default | tr -d ' ')"
[[ "$actual" -eq 25 ]] || die "default catalog count is $actual, expected 25"
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
[[ $rc -eq 2 ]] || die "unknown lifecycle should exit 2, got $rc"
python3 scripts/generate-skill-docs.py --check
