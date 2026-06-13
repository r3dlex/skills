#!/bin/bash
#
# Semantic guardrail regressions for release templates and module guidance.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_MODULE="$REPO_ROOT/ai-sdlc-init/modules/release-versioning.md"
TEMPLATE_DIR="$REPO_ROOT/scripts/release"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_contains() {
  local file="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "$file"; then ok "$label"; else bad "$label (missing: $needle)"; fi
}

assert_not_grep() {
  local pattern="$1" path="$2" label="$3"
  if grep -REiq "$pattern" "$path"; then
    bad "$label"
    grep -REin "$pattern" "$path" || true
  else
    ok "$label"
  fi
}

assert_contains "$RELEASE_MODULE" "Green CI required" "green CI guardrail preserved"
assert_contains "$RELEASE_MODULE" "Conventional commits required" "conventional commits guardrail preserved"
assert_contains "$RELEASE_MODULE" "Secrets/permissions preflight required" "secrets preflight guardrail preserved"
assert_contains "$RELEASE_MODULE" "No dirty generated state required" "dirty generated state guardrail preserved"
assert_contains "$RELEASE_MODULE" "Protected tag policy required" "protected tag policy guardrail preserved"
assert_contains "$RELEASE_MODULE" "No production deploys or history rewrites" "production/history safety boundary preserved"
assert_contains "$RELEASE_MODULE" "Version-impact conflicts are an additional fail-closed gate" "version-impact conflicts added as extra gate"

assert_not_grep 'git[[:space:]]+push[[:space:]].*--force|--force-with-lease' "$TEMPLATE_DIR" "release templates do not force-push"
assert_not_grep 'git[[:space:]]+tag[[:space:]].*(-d|--delete)|git[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+:(refs/tags/)?v' "$TEMPLATE_DIR" "release templates do not delete tags"
assert_not_grep 'kubectl[[:space:]]+apply|aws[[:space:]]+s3[[:space:]]+sync|azure[[:space:]]+webapp[[:space:]]+deploy|gcloud[[:space:]]+app[[:space:]]+deploy' "$TEMPLATE_DIR" "release templates do not deploy to production"
assert_not_grep 'echo[[:space:]].*(TOKEN|SECRET|PASSWORD|KEY)[^[:alnum:]_]*\\$' "$TEMPLATE_DIR" "release templates do not echo secret values"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
