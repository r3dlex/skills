#!/bin/bash
# P1-6: skill-modernization module documents every §4.A modernization-audit dimension.
#
# §4.A audit dimensions (end-state spec):
#   1. compact-description budget (target <=180, hard-fail >280 unless audited exception)
#   2. progressive disclosure
#   3. clear trigger / non-trigger / fallback boundaries
#   4. link / alias / referenced-file / script validation
#   5. cross-skill workflow links
#
# Offline / deterministic: greps the module text only.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODULE="ai-catapult-init/modules/skill-modernization.md"

fail=0
assert_contains() {
    local needle="$1" desc="$2"
    if grep -qi -- "$needle" "$MODULE"; then
        echo "  PASS: $desc"
    else
        echo "  FAIL: $desc (missing: $needle)"
        fail=1
    fi
}

echo "skill-modernization audit-dimension coverage"
echo "============================================"

# 1. description budget
assert_contains "180" "documents <=180 target description budget"
assert_contains "280" "documents >280 hard-fail budget"
assert_contains "description-exceptions" "documents audited exception path"

# 2. progressive disclosure
assert_contains "progressive disclosure" "documents progressive disclosure"

# 3. trigger / non-trigger / fallback boundaries
assert_contains "non-trigger" "documents non-trigger boundary"
assert_contains "fallback" "documents fallback boundary"
assert_contains "trigger" "documents trigger boundary"

# 4. link / alias / referenced-file / script validation
assert_contains "broken link" "documents link validation"
assert_contains "alias" "documents alias validation"
assert_contains "referenced.file\|referenced file" "documents referenced-file validation"
assert_contains "script" "documents bundled-script validation"

# 5. cross-skill workflow links
assert_contains "Cross-skill workflow links" "documents cross-skill workflow links"

if [ "$fail" -ne 0 ]; then
    echo "RESULT: FAILED"
    exit 1
fi
echo "RESULT: PASSED"
