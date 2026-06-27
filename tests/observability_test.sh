#!/bin/bash
#
# observability_test.sh
#
# Offline, deterministic structural validation of the generated observability
# surface (P1-1, ADR-0005). NO model or network access is used: every assertion
# is pure-shell file/keyword checks, exactly like the host-policy static checks.
#
# For BOTH committed v3 fixtures (standalone, umbrella) it asserts that the
# generated observability conventions doc and audit checklist exist under the
# `.ai/observability/` tree, are non-empty, and carry the logging/trace
# conventions plus the token-cost and trajectory-audit checklist keywords.
#
# It also asserts that `modules/ci-policy.md` and `modules/validation.md` carry
# the token-cost + trajectory-audit checklist keywords (mirroring the host-policy
# static-keyword check style in validation.md).
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

assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if [ -f "$file" ] && grep -Fq "$needle" "$file"; then
    ok "$label"
  else
    bad "$label (missing: $needle in $file)"
  fi
}

echo "Observability Surface Tests"
echo "==========================="
echo ""

# --- Generated observability surface in both v3 fixtures ---------------------
for variant in standalone umbrella; do
  obs="reference/fixtures/v3/$variant/.ai/observability"
  conventions="$obs/conventions.md"
  checklist="$obs/audit-checklist.md"

  assert_nonempty_file "$conventions" "v3 $variant observability conventions doc present + non-empty"
  assert_nonempty_file "$checklist"   "v3 $variant observability audit checklist present + non-empty"

  assert_file_contains "$conventions" "Logging conventions" "v3 $variant conventions cover logging"
  assert_file_contains "$conventions" "Trace conventions"   "v3 $variant conventions cover traces"
  assert_file_contains "$checklist" "Token-cost audit"  "v3 $variant checklist covers token-cost audit"
  assert_file_contains "$checklist" "Trajectory audit"  "v3 $variant checklist covers trajectory audit"
done

# --- Static-keyword checks on the modules (mirrors host-policy static checks) -
assert_file_contains "init-ai-repo/modules/ci-policy.md" "token-cost" \
  "ci-policy.md carries the token-cost checklist keyword"
assert_file_contains "init-ai-repo/modules/ci-policy.md" "trajectory-audit" \
  "ci-policy.md carries the trajectory-audit checklist keyword"
assert_file_contains "init-ai-repo/modules/validation.md" "token-cost" \
  "validation.md carries the token-cost checklist keyword"
assert_file_contains "init-ai-repo/modules/validation.md" "trajectory-audit" \
  "validation.md carries the trajectory-audit checklist keyword"
assert_file_contains "init-ai-repo/modules/validation.md" ".ai/observability/" \
  "validation.md structural check names the observability tree"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
