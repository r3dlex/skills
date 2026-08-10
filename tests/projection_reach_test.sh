#!/bin/bash
#
# projection_reach_test.sh  (northstar-autobahn-hardening, Slice 7)
#
# Guards decision 13. `scripts/catalog-install.sh` flattens skills for gemini,
# auggie and copilot, and `has_unavailable_path` drops any block whose text
# names a sidecar path — evaluated on the JOINED block, so one line naming
# modules/x.md takes the whole paragraph with it. List items are filtered
# individually, which is why bullets survive where prose does not.
#
# Consequence: a gate documented only in a `## Section` that ends "See
# [modules/x.md]" reaches 2 of 5 hosts. It passes every other gate in this repo
# while doing it, because nothing else looks at the projection.
#
# So this test renders the real projection and asserts each fail-closed rule is
# still in it. If a rule stops surviving, it was moved into a stripped block —
# put it back in `## Safety rules` as a path-free bullet.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# shellcheck disable=SC1091
if ! source scripts/catalog-install.sh >/dev/null 2>&1 \
   || ! declare -f flattened_skill_body >/dev/null 2>&1; then
  bad "flattened_skill_body is sourceable from scripts/catalog-install.sh"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "flattened_skill_body is sourceable from scripts/catalog-install.sh"

# reach <skill-path> <label> <pattern> — the rule must survive flattening AS A
# BULLET.
#
# Two things this got wrong the first time, both of which made it inert:
#
#   - Patterns were single words. `lint` matched a neighbouring line, so deleting
#     the entire lint rule left the test green. Verified: removing
#     "- Never commit past a failing lint policy." did not fail this test.
#     Patterns must be distinctive phrases belonging to exactly one rule.
#   - It grepped the whole projection. Only LIST ITEMS survive the flattener
#     individually; prose blocks are dropped wholesale. Matching anywhere meant
#     a rule could pass by appearing in a block that three hosts never receive.
reach() {
  local path="$1" label="$2" pattern="$3"
  local flat bullets
  flat="$(flattened_skill_body "$path" 2>/dev/null)"

  if [[ -z "$flat" ]]; then
    bad "$label (projection was empty)"
    return
  fi

  bullets="$(grep -E '^\s*[-*] ' <<<"$flat")"
  if grep -qiE "$pattern" <<<"$bullets"; then
    ok "$label"
  else
    bad "$label — not present as a surviving bullet; a rule in a prose block reaches 2 of 5 hosts"
  fi
}

AUTOBAHN="04-validate-handoff/autobahn/SKILL.md"
NORTHSTAR="02-govern-plan/northstar/SKILL.md"

# --- autobahn's gate rules --------------------------------------------------
# Distinctive phrases, each belonging to exactly one rule. A single word here is
# how this test went inert.
reach "$AUTOBAHN" "autobahn: TDD evidence rule reaches all hosts"     'recorded red-then-green evidence'
reach "$AUTOBAHN" "autobahn: lint gate rule reaches all hosts"        'never commit past a failing lint policy'
reach "$AUTOBAHN" "autobahn: CI derivation rule reaches all hosts"    'no derivable CI is blocked'
reach "$AUTOBAHN" "autobahn: verification\[\] rule reaches all hosts" 'only commands that are'
reach "$AUTOBAHN" "autobahn: gate driver rule reaches all hosts"      'through the bundled gate driver'
reach "$AUTOBAHN" "autobahn: fail-closed posture reaches all hosts"   'fail closed'

# --- northstar's adversarial-pass rule --------------------------------------
reach "$NORTHSTAR" "northstar: adversarial pass reaches all hosts"  'grill-with-docs'
reach "$NORTHSTAR" "northstar: grill-me reaches all hosts"          'grill-me'

# --- the mechanism itself ---------------------------------------------------
# If a sidecar path ever starts surviving, the flattener changed and the
# path-free-bullet discipline these slices were written around is moot. That is
# worth knowing loudly rather than discovering later.
flat="$(flattened_skill_body "$AUTOBAHN" 2>/dev/null)"
if grep -q "modules/" <<<"$flat"; then
  bad "the flattener still strips sidecar paths (a modules/ path survived — re-check decision 13)"
else
  ok "the flattener still strips sidecar paths"
fi

# Safety rules is the last substantive section three hosts receive. Deleting it
# to fund something else would pass every other gate in the repo.
if grep -q "^## Safety rules" <<<"$flat"; then
  ok "autobahn's Safety rules section survives flattening"
else
  bad "autobahn's Safety rules section survives flattening"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
