#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

require_in() {
  local file="$1" needle="$2"
  if grep -qi -- "$needle" "$file"; then ok "$file mentions '$needle'"; else bad "$file mentions '$needle'"; fi
}

require_in 03-configure-generate/tdd/SKILL.md "legacy-safe"
require_in 03-configure-generate/tdd/SKILL.md "under 30%"
require_in 03-configure-generate/tdd/SKILL.md "any coverage level"
require_in 03-configure-generate/tdd/legacy-systems.md "characterization test"
require_in 03-configure-generate/tdd/legacy-systems.md "Sprout Method"
require_in 03-configure-generate/tdd/legacy-systems.md "Sprout Class"
require_in 03-configure-generate/tdd/legacy-systems.md "blast-radius budget"
require_in 03-configure-generate/tdd/legacy-systems.md "one change seam"
require_in 03-configure-generate/tdd/legacy-systems.md "failing behavior test"
require_in 03-configure-generate/tdd/legacy-systems.md "legacy_risk_reason"
require_in 03-configure-generate/tdd/mocking.md "Mock the network, not the model"
require_in 03-configure-generate/tdd/mocking.md "fixture-driven"
require_in 03-configure-generate/tdd/mocking.md "deterministic"
require_in 03-configure-generate/tdd/mocking.md "probabilistic"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
