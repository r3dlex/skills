#!/bin/bash
#
# agents_index_test.sh  (P0-5, M1 resolution)
#
# Asserts the 8 P0 SDLC-core skills are present in the AGENTS.md `## Skills`
# table, so they are discoverable as a cross-tool surface.
#
# NOTE: Full index<->catalog parity (all ~21 catalog skills) is deferred to
# P1-7 — this test deliberately checks ONLY the 8 P0 skills.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

AGENTS="AGENTS.md"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Extract the `## Skills` table block (lines from `## Skills` up to the next
# top-level heading) so a skill name mentioned elsewhere does not falsely pass.
table="$(awk '
  /^## Skills/      {inblock=1; next}
  inblock && /^## / {inblock=0}
  inblock           {print}
' "$AGENTS")"

if [[ -z "$table" ]]; then
  bad "AGENTS.md has a '## Skills' table block"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
else
  ok "AGENTS.md has a '## Skills' table block"
fi

P0_SKILLS=(
  init-ai-repo
  write-a-skill
  to-prd
  to-issues
  triage
  tdd
  diagnose
  publish-semver
)

for skill in "${P0_SKILLS[@]}"; do
  # Match the skill as a code-fenced table cell entry: `| `skill` |`.
  if printf '%s\n' "$table" | grep -Eq "\`$skill\`"; then
    ok "AGENTS.md ## Skills table lists $skill"
  else
    bad "AGENTS.md ## Skills table lists $skill"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
