#!/bin/bash
#
# northstar_docs_test.sh  (PR-1, N1/N2; M1 module-parity gate)
#
# Proves the northstar skill docs are lean, Codex-parity-clean, and carry the
# required delegation/contract keywords.
#
#   1. SKILL.md AND every northstar/modules/*.md pass check-codex-parity.sh.
#      (The existing codex_parity_test.sh globs */SKILL.md only and does NOT
#       cover modules — this is the explicit per-skill module-parity gate, M1.)
#   2. The SKILL.md + modules document the delegation contract (deep-interview
#      primary, grill-me adversarial/skippable, always-raise-issue local-first,
#      ralplan -> sliced goals, A->B handoff, fail-closed prereq).
#   3. description <= 180 chars.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PARITY="scripts/check-codex-parity.sh"
SKILL="northstar/SKILL.md"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# --- 1. codex parity over SKILL.md + every module (M1) -----------------------
docs=("$SKILL")
for m in northstar/modules/*.md; do
  [[ -f "$m" ]] && docs+=("$m")
done

if [[ "${#docs[@]}" -le 1 ]]; then
  bad "northstar/modules/*.md exist for the module-parity loop"
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
require_in "$SKILL" "name: northstar"
require_in "$SKILL" "fail-closed"
require_in "$SKILL" "deep-interview"
require_in "$SKILL" "grill-me"
require_in "$SKILL" "skippable"
require_in "$SKILL" "ralplan"
require_in "$SKILL" "sliced goal"
require_in "$SKILL" "handoff"

# --- 3. description <= 180 chars ----------------------------------------------
desc="$(awk 'NR==1&&$0!="---"{exit} NR==1{next} $0=="---"{exit} /^description:/{sub(/^description:[[:space:]]*/,"");gsub(/^["'"'"']|["'"'"']$/,"");print;exit}' "$SKILL")"
len=${#desc}
if [[ "$len" -gt 0 && "$len" -le 180 ]]; then
  ok "description length $len (<=180)"
else
  bad "description length $len (must be 1..180)"
fi

# --- module content contracts ------------------------------------------------
require_in "northstar/modules/loop.md" "both satisfied"
require_in "northstar/modules/issue.md" "local-first"
require_in "northstar/modules/handoff.md" "schema_version"
require_in "northstar/modules/handoff.md" "optional_branches"
require_in "northstar/modules/command-surface.md" "omx"
require_in "northstar/modules/command-surface.md" "omc"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
