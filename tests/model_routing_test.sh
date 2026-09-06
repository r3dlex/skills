#!/bin/bash
#
# model_routing_test.sh
#
# Offline, deterministic structural validation of the generated
# `.ai/policies/model-routing.json` contract (P0-4, plan decision D6, ADR-0003,
# refined by ADR-0013 model-binding contract).
# NO model or network access is used: every assertion is pure-shell + python3
# JSON parsing (json.load), exactly like the eval-coverage gate test.
#
# Validation targets:
#   - the SSOT template (03-configure-generate/ai-catapult-init/templates/
#     dot-ai/policies/model-routing.json) — closing the exemption that let
#     non-tier fallback_* keys slip into host_aliases (ADR-0013);
#   - BOTH committed v3 fixtures (standalone, umbrella).
#
# For EACH target it asserts:
#   1. JSON parses (python3 json.load, no network).
#   2. `schema_version` present.
#   3. Forward: every task-class maps to a tier in {frontier, mid, cheap}.
#   4. Reverse coverage: every tier in {frontier, mid, cheap} has >=1 entry in
#      the `host_aliases` table, and no alias points to a tier outside that set.
#   5. Contract fields (ADR-0013): host_aliases keys are strictly tiers —
#      fallback chains live in the top-level `fallbacks` namespace, never
#      inside host_aliases. Per-host `alias_supported` must be a bool and
#      `pinned_at` an ISO date when present.
#   6. Template/fixture parity on contract shape: the same key sets appear in
#      template and fixtures (host set, contract fields, fallbacks hosts).
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
# ADR-0013 contract fields ride alongside tier bindings inside each host and
# are validated separately below.
CONTRACT_FIELDS = {"alias_supported", "pinned_at"}
covered = set()
for host, aliases in host_aliases.items():
    if not isinstance(aliases, dict) or not aliases:
        print(f"host_aliases[{host!r}] missing or empty", file=sys.stderr)
        sys.exit(1)
    for tier, model in aliases.items():
        if tier in CONTRACT_FIELDS:
            continue
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

# ADR-0013: host_aliases keys are strictly tiers; fallback chains live in the
# top-level `fallbacks` namespace. Contract fields, when present, are typed.
import re
for host, aliases in host_aliases.items():
    alias_supported = aliases.get("alias_supported")
    if alias_supported is not None and not isinstance(alias_supported, bool):
        print(f"host {host!r} alias_supported must be a bool", file=sys.stderr)
        sys.exit(1)
    pinned_at = aliases.get("pinned_at")
    if pinned_at is not None:
        if not isinstance(pinned_at, str) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", pinned_at):
            print(f"host {host!r} pinned_at must be an ISO date (YYYY-MM-DD)", file=sys.stderr)
            sys.exit(1)

fallbacks = data.get("fallbacks", {})
if not isinstance(fallbacks, dict):
    print("fallbacks must be an object when present", file=sys.stderr)
    sys.exit(1)
for host, chain in fallbacks.items():
    if host not in host_aliases:
        print(f"fallbacks[{host!r}] has no matching host_aliases entry", file=sys.stderr)
        sys.exit(1)
    if not isinstance(chain, dict) or not chain:
        print(f"fallbacks[{host!r}] missing or empty", file=sys.stderr)
        sys.exit(1)
    for name, model in chain.items():
        if not name or not model:
            print(f"fallbacks[{host!r}][{name!r}] empty", file=sys.stderr)
            sys.exit(1)

contract_shape = {
    "hosts": {h: tuple(sorted(a.keys())) for h, a in host_aliases.items()},
    "fallback_hosts": sorted(fallbacks.keys()),
    "schema_version": data.get("schema_version"),
}
print(json.dumps(contract_shape))
sys.exit(0)
PY
}

contract_shape_of() {
  routing_is_valid "$1" 2>/dev/null | tail -n 1
}

echo "Model Routing Policy Tests"
echo "=========================="
echo ""

TEMPLATE="$REPO_ROOT/03-configure-generate/ai-catapult-init/templates/dot-ai/policies/model-routing.json"

if [ -f "$TEMPLATE" ]; then
  ok "template model-routing.json present"
else
  bad "template model-routing.json missing ($TEMPLATE)"
fi

if [ -f "$TEMPLATE" ] && routing_is_valid "$TEMPLATE"; then
  ok "template model-routing.json parses + forward + reverse coverage + ADR-0013 contract valid"
else
  if [ -f "$TEMPLATE" ]; then
    bad "template model-routing.json failed structural validation (see diagnostic above)"
  fi
fi

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

TEMPLATE_SHAPE="$(contract_shape_of "$TEMPLATE")"
for variant in standalone umbrella; do
  routing="$REPO_ROOT/reference/fixtures/v3/$variant/.ai/policies/model-routing.json"
  [ -f "$routing" ] || continue
  FIXTURE_SHAPE="$(contract_shape_of "$routing")"
  if [ "$TEMPLATE_SHAPE" = "$FIXTURE_SHAPE" ]; then
    ok "v3 $variant contract shape matches template (hosts + fields + fallbacks + schema_version)"
  else
    bad "v3 $variant contract shape diverges from template: template=$TEMPLATE_SHAPE fixture=$FIXTURE_SHAPE"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
