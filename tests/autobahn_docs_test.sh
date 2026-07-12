#!/bin/bash
#
# autobahn_docs_test.sh  (PR-2, A1/A2; M1 module-parity gate)
#
# Proves the autobahn skill docs are lean, Codex-parity-clean, and carry the
# required delegation/contract keywords.
#
#   1. SKILL.md AND every 04-validate-handoff/autobahn/modules/*.md pass check-codex-parity.sh.
#      (The existing codex_parity_test.sh globs */SKILL.md only and does NOT
#       cover modules — this is the explicit per-skill module-parity gate, M1.)
#   2. The SKILL.md + modules document the delegation contract (ultragoal
#      one-PR-per-goal, deterministic engine-pick + override, peer-review loop,
#      CI gate, ready-for-human / admin-bypass merge authority, cascade closure,
#      triage status, fail-closed).
#   3. description <= 180 chars.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PARITY="scripts/check-codex-parity.sh"
SKILL="04-validate-handoff/autobahn/SKILL.md"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# --- 1. codex parity over SKILL.md + every module (M1) -----------------------
docs=("$SKILL")
for m in 04-validate-handoff/autobahn/modules/*.md; do
  [[ -f "$m" ]] && docs+=("$m")
done

if [[ "${#docs[@]}" -le 1 ]]; then
  bad "04-validate-handoff/autobahn/modules/*.md exist for the module-parity loop"
fi

for doc in "${docs[@]}"; do
  if [[ ! -f "$doc" ]]; then
    bad "missing doc: $doc"
    continue
  fi
  if bash "$PARITY" "$doc" >/dev/null 2>&1; then
    ok "codex parity: $doc"
  else
    bad "codex parity: $doc"
  fi
done

# --- 2. required sections / keywords -----------------------------------------
require_in() {
  local file="$1"; local needle="$2"
  if grep -qi -- "$needle" "$file"; then
    ok "$file mentions '$needle'"
  else
    bad "$file mentions '$needle'"
  fi
}

# SKILL.md frontmatter + body contract cues.
require_in "$SKILL" "name: autobahn"
require_in "$SKILL" "fail-closed"
require_in "$SKILL" "ultragoal"
require_in "$SKILL" "one PR per goal"
require_in "$SKILL" "engine"
require_in "$SKILL" "ready-for-human"
require_in "$SKILL" "admin-bypass"
require_in "$SKILL" "cascade"
require_in "$SKILL" "handoff"
require_in "$SKILL" "implementation-ready"
require_in "$SKILL" "legacy-safe"
require_in "$SKILL" "under 30%"

# --- 3. description <= 180 chars ----------------------------------------------
desc="$(awk 'NR==1&&$0!="---"{exit} NR==1{next} $0=="---"{exit} /^description:/{sub(/^description:[[:space:]]*/,"");gsub(/^["'"'"']|["'"'"']$/,"");print;exit}' "$SKILL")"
len=${#desc}
if [[ "$len" -gt 0 && "$len" -le 180 ]]; then
  ok "description length $len (<=180)"
else
  bad "description length $len (must be 1..180)"
fi

# --- module content contracts ------------------------------------------------
require_in "04-validate-handoff/autobahn/modules/engine-pick.md" "ultraqa"
require_in "04-validate-handoff/autobahn/modules/engine-pick.md" "ultrawork"
require_in "04-validate-handoff/autobahn/modules/engine-pick.md" "ralph"
require_in "04-validate-handoff/autobahn/modules/engine-pick.md" "precedence"
require_in "04-validate-handoff/autobahn/modules/engine-pick.md" "override"
require_in "04-validate-handoff/autobahn/modules/orchestration.md" "one PR per goal"
require_in "04-validate-handoff/autobahn/modules/readiness.md" "root_causes"
require_in "04-validate-handoff/autobahn/modules/readiness.md" "evidence"
require_in "04-validate-handoff/autobahn/modules/tdd-safety.md" "any coverage level"
require_in "04-validate-handoff/autobahn/modules/tdd-safety.md" "legacy_risk_reason"
require_in "04-validate-handoff/autobahn/modules/tdd-safety.md" "blast-radius"
require_in "04-validate-handoff/autobahn/modules/review-loop.md" "code-reviewer"
require_in "04-validate-handoff/autobahn/modules/review-loop.md" "architect"
require_in "04-validate-handoff/autobahn/modules/merge-authority.md" "ready-for-human"
require_in "04-validate-handoff/autobahn/modules/merge-authority.md" "thin adapter"
require_in "04-validate-handoff/autobahn/modules/merge-authority.md" "host-policy"
require_in "04-validate-handoff/autobahn/modules/cascade-closure.md" "idempotent"
require_in "04-validate-handoff/autobahn/modules/cascade-closure.md" "triage"
require_in "04-validate-handoff/autobahn/modules/command-surface.md" "omx"
require_in "04-validate-handoff/autobahn/modules/command-surface.md" "omc"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
