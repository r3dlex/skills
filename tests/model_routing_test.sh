#!/bin/bash
#
# model_routing_test.sh
#
# Offline, deterministic structural validation of the generated
# `.ai/policies/model-routing.json` contract (P0-4, plan decision D6, ADR-0003).
# NO model or network access is used: every assertion is pure-shell + python3
# JSON parsing (json.load), exactly like the eval-coverage gate test.
#
# For BOTH committed v3 fixtures (standalone, umbrella) it asserts:
#   1. JSON parses (python3 json.load, no network).
#   2. `schema_version` present.
#   3. Forward: every task-class maps to a tier in {frontier, mid, cheap}.
#   4. Reverse coverage: every tier in {frontier, mid, cheap} has >=1 entry in
#      the `host_aliases` table, and no alias points to a tier outside that set.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# routing_is_valid <model-routing.json>
#   Validates the routing contract structurally and offline. Returns 0 when all
#   of the following hold, non-zero (with a diagnostic on stderr) otherwise:
#     - file parses as JSON;
#     - schema_version present and non-empty;
#     - forward: every task_classes value is in {frontier, mid, cheap};
#     - reverse: every tier in {frontier, mid, cheap} appears at least once
#       across host_aliases, and no alias maps to a tier outside that set.
routing_is_valid() {
  python3 - "$1" <<'PY'
import json, sys

TIERS = {"frontier", "mid", "cheap"}
path = sys.argv[1]

try:
    data = json.load(open(path))
except Exception as e:
    print(f"json.load failed: {e}", file=sys.stderr)
    sys.exit(1)

if not data.get("schema_version"):
    print("schema_version missing or empty", file=sys.stderr)
    sys.exit(1)

task_classes = data.get("task_classes")
if not isinstance(task_classes, dict) or not task_classes:
    print("task_classes missing or empty", file=sys.stderr)
    sys.exit(1)

# Forward: every task-class maps to a known tier.
for tc, tier in task_classes.items():
    if tier not in TIERS:
        print(f"task-class {tc!r} maps to unknown tier {tier!r}", file=sys.stderr)
        sys.exit(1)

host_aliases = data.get("host_aliases")
if not isinstance(host_aliases, dict) or not host_aliases:
    print("host_aliases missing or empty", file=sys.stderr)
    sys.exit(1)

# Reverse: no alias points outside the tier set; collect covered tiers.
covered = set()
for host, aliases in host_aliases.items():
    if not isinstance(aliases, dict) or not aliases:
        print(f"host_aliases[{host!r}] missing or empty", file=sys.stderr)
        sys.exit(1)
    for tier, model in aliases.items():
        if tier not in TIERS:
            print(f"host {host!r} aliases unknown tier {tier!r}", file=sys.stderr)
            sys.exit(1)
        if not model:
            print(f"host {host!r} tier {tier!r} has empty model name", file=sys.stderr)
            sys.exit(1)
        covered.add(tier)

# Reverse coverage: every tier has >=1 alias entry somewhere.
missing = TIERS - covered
if missing:
    print(f"tiers without any host alias: {sorted(missing)}", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
}

echo "Model Routing Policy Tests"
echo "=========================="
echo ""

for variant in standalone umbrella; do
  routing="$REPO_ROOT/reference/fixtures/v3/$variant/.ai/policies/model-routing.json"

  if [ -f "$routing" ]; then
    ok "v3 $variant model-routing.json present"
  else
    bad "v3 $variant model-routing.json missing ($routing)"
    continue
  fi

  if routing_is_valid "$routing"; then
    ok "v3 $variant model-routing.json parses + forward + reverse coverage valid"
  else
    bad "v3 $variant model-routing.json failed structural validation (see diagnostic above)"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
