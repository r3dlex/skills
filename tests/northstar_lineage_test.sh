#!/bin/bash
#
# northstar_lineage_test.sh  (northstar-autobahn-hardening, Slice 2)
#
# Pins northstar's adversarial pass as a two-skill unit: `grill-with-docs`
# (doc-grounded) then `grill-me` (open-ended), declinable together.
#
# The reach assertion is the point. `scripts/catalog-install.sh` flattens
# northstar for gemini, auggie and copilot, and `has_unavailable_path` drops any
# block whose text names a sidecar path. `## The loop (delegation)` closes on a
# `modules/loop.md` link, so the whole section is stripped: a rule written only
# there reaches 2 of 5 hosts. Asserting the rule survives `flattened_skill_body`
# is what stops the wiring from silently being Claude/Codex-only.
#
#   1. SKILL.md, modules/loop.md and both command JSONs name grill-with-docs.
#   2. The adversarial pass is documented as a declinable unit, not two
#      independently skippable passes.
#   3. The rule survives flattening — it appears in flattened_skill_body output.
#   4. modules/command-surface.md's example matches the shipped JSONs.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SKILL="02-govern-plan/northstar/SKILL.md"
LOOP="02-govern-plan/northstar/modules/loop.md"
SURFACE="02-govern-plan/northstar/modules/command-surface.md"
CMD_DIR="reference/fixtures/v3/standalone/.ai/commands"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# --- 1. every surface names grill-with-docs ---------------------------------
for doc in "$SKILL" "$LOOP" "$SURFACE"; do
  if grep -q "grill-with-docs" "$doc"; then
    ok "$doc names grill-with-docs"
  else
    bad "$doc names grill-with-docs"
  fi
done

for surface in omc omx; do
  json="$CMD_DIR/$surface/northstar.json"
  if [[ ! -f "$json" ]]; then
    bad "$json exists"
    continue
  fi
  if python3 - "$json" <<'PY'
import json, sys
sys.exit(0 if 'grill-with-docs' in json.load(open(sys.argv[1], encoding='utf-8'))['delegates_to'] else 1)
PY
  then
    ok "$surface command JSON delegates_to includes grill-with-docs"
  else
    bad "$surface command JSON delegates_to includes grill-with-docs"
  fi
done

# --- 2. the adversarial pass is one declinable unit -------------------------
# Both names must appear in the same rule; two separately-skippable passes would
# let a user decline one and leave northstar's gate ambiguous.
if grep -qi "as a unit\|both\|together" "$LOOP" && grep -q "grill-with-docs" "$LOOP"; then
  ok "modules/loop.md documents the adversarial pass as a unit"
else
  bad "modules/loop.md documents the adversarial pass as a unit"
fi

# --- 3. the rule survives host flattening -----------------------------------
# shellcheck disable=SC1091
if source scripts/catalog-install.sh >/dev/null 2>&1 \
   && declare -f flattened_skill_body >/dev/null 2>&1; then
  ok "flattened_skill_body is sourceable"

  flat="$(flattened_skill_body "$SKILL" 2>/dev/null)"
  if [[ -z "$flat" ]]; then
    bad "flattened projection is non-empty"
  else
    ok "flattened projection is non-empty"

    if grep -q "grill-with-docs" <<<"$flat"; then
      ok "grill-with-docs survives flattening (reaches all five hosts)"
    else
      bad "grill-with-docs is stripped by the flattener — put the rule in a path-free bullet, not a block naming modules/*.md"
    fi

    if grep -q "grill-me" <<<"$flat"; then
      ok "grill-me survives flattening"
    else
      bad "grill-me is stripped by the flattener"
    fi
  fi
else
  bad "flattened_skill_body is sourceable"
fi

# --- 4. the documented example matches the shipped JSONs --------------------
if python3 - "$SURFACE" "$CMD_DIR/omx/northstar.json" <<'PY'
import json, re, sys
doc, shipped = sys.argv[1:]
blocks = re.findall(r'```json\n(.*?)\n```', open(doc, encoding='utf-8').read(), re.S)
example = next((json.loads(b) for b in blocks if '"name": "northstar"' in b), None)
if example is None:
    sys.exit(1)
sys.exit(0 if example['delegates_to'] == json.load(open(shipped, encoding='utf-8'))['delegates_to'] else 1)
PY
then
  ok "command-surface.md example delegates_to matches the shipped JSON"
else
  bad "command-surface.md example delegates_to matches the shipped JSON"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
