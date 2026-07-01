#!/bin/bash
#
# ai_failure_modes_test.sh
#
# Offline, deterministic structural validation of the generated AI-failure-mode
# review checklist (P1-5, spec §4.B). NO model or network access is used: every
# assertion is a pure file / keyword check, exactly like observability_test.sh
# and mcp_a2a_test.sh.
#
# For BOTH committed v3 fixtures (standalone, umbrella) it asserts that the
# generated AI-failure-mode review checklist (`.ai/reviews/ai-failure-modes.md`)
# exists, is non-empty, and carries actionable review items covering the four
# named failure modes the spec calls out:
#   - hallucinated dependencies
#   - slopsquatting
#   - inadequate error handling
#   - "looks-right" / subtle correctness gaps
#
# It also asserts the artifact is wired into the documentation blueprint tree +
# note, the validation module structural check, and the ci-policy.md PR merge
# gate (the natural review/merge-gate tie-in).
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_nonempty_file() {
  local file="$1" label="$2"
  if [ -s "$file" ]; then ok "$label"; else bad "$label (missing or empty: $file)"; fi
}

# Case-insensitive keyword presence.
assert_file_contains_i() {
  local file="$1" needle="$2" label="$3"
  if [ -f "$file" ] && grep -Fiq "$needle" "$file"; then
    ok "$label"
  else
    bad "$label (missing: $needle in $file)"
  fi
}

assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if [ -f "$file" ] && grep -Fq "$needle" "$file"; then
    ok "$label"
  else
    bad "$label (missing: $needle in $file)"
  fi
}

echo "AI Failure-Mode Review Checklist Tests"
echo "======================================"
echo ""

# --- Generated checklist in both v3 fixtures --------------------------------
for variant in standalone umbrella; do
  checklist="reference/fixtures/v3/$variant/.ai/reviews/ai-failure-modes.md"

  assert_nonempty_file "$checklist" \
    "v3 $variant AI-failure-mode review checklist present + non-empty"

  # Coverage of the four named failure modes (keyword, case-insensitive).
  assert_file_contains_i "$checklist" "hallucinated" \
    "v3 $variant checklist covers hallucinated dependencies"
  assert_file_contains_i "$checklist" "slopsquat" \
    "v3 $variant checklist covers slopsquatting"
  assert_file_contains_i "$checklist" "error handling" \
    "v3 $variant checklist covers inadequate error handling"
  assert_file_contains_i "$checklist" "looks-right" \
    "v3 $variant checklist covers looks-right/subtle correctness gaps"

  # Actionable review items: at least one Markdown checkbox under each mode.
  if [ -f "$checklist" ] && grep -Fq -- "- [ ]" "$checklist"; then
    ok "v3 $variant checklist carries actionable review items (checkboxes)"
  else
    bad "v3 $variant checklist has no actionable checkbox items ($checklist)"
  fi
done

# --- Blueprint + validation + ci-policy wiring ------------------------------
assert_file_contains "ai-catapult-init/modules/documentation-blueprint.md" "ai-failure-modes.md" \
  "documentation-blueprint.md tree names the AI-failure-mode checklist"
assert_file_contains "ai-catapult-init/modules/documentation-blueprint.md" ".ai/reviews/" \
  "documentation-blueprint.md names the .ai/reviews/ surface"
assert_file_contains "ai-catapult-init/modules/validation.md" "ai-failure-modes.md" \
  "validation.md structural check names the AI-failure-mode checklist"
assert_file_contains "ai-catapult-init/modules/ci-policy.md" "ai-failure-modes.md" \
  "ci-policy.md PR merge gate references the AI-failure-mode checklist"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
