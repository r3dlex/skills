#!/bin/bash
#
# test-scripts.sh
# Validates and runs tests for all shell scripts in the repository.
#
# Checks:
#   - bash -n (syntax validation) for every *.sh file
#   - Unit tests: discovers _test.sh suffix files and runs them
#   - Reports coverage: which scripts are exercised by test files
#
# Exit 0 on all pass, non-zero on any failure.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

log_pass() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
log_fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }
log_skip() { echo "  SKIP: $1"; SKIP_COUNT=$((SKIP_COUNT + 1)); }

# -----------------------------------------------------------------------------
# Find all .sh files in scripts/ and skill directories, excluding tests/ itself.
# -----------------------------------------------------------------------------
find_scripts() {
    find "$REPO_ROOT" \
        \( -path "*/.git" -o -path "*/.omc" -o -path "*/.claude" -o -path "*/tests" \) -prune -o \
        -name "*.sh" -print
}

# -----------------------------------------------------------------------------
# Syntax-check a single script using bash -n.
# -----------------------------------------------------------------------------
check_syntax() {
    local script="$1"
    relative_path="${script#$REPO_ROOT/}"

    # shellcheck disable=SC2086
    bash -n "$script" 2>&1
}

# -----------------------------------------------------------------------------
# Discover unit test files (*_test.sh) and record the script under test.
# Coverage is computed as: tested_scripts / total_scripts.
# -----------------------------------------------------------------------------
find_unit_tests() {
    find "$REPO_ROOT/tests" -name "*_test.sh" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo "Shell Script Tests"
echo "=================="
echo ""

echo "--- Syntax Validation ---"
echo ""
ALL_SCRIPTS=$(find_scripts)

if [ -z "$ALL_SCRIPTS" ]; then
    echo "WARNING: No .sh files found."
else
    TESTED_SCRIPTS=""
    while IFS= read -r script; do
        [ -z "$script" ] && continue

        relative_path="${script#$REPO_ROOT/}"

        # Skip this very test runner and its sibling scripts.
        case "$relative_path" in
            tests/run-tests.sh|tests/test-scripts.sh|tests/test-skills.sh) continue ;;
        esac

        echo "[ $relative_path ]"

        # Capture bash -n output.
        # shellcheck disable=SC2086
        set +e
        output=$(check_syntax "$script" 2>&1)
        exit_code=$?
        set -e

        if [ "$exit_code" -eq 0 ]; then
            log_pass "bash -n syntax valid"
            TESTED_SCRIPTS="$TESTED_SCRIPTS
$script"
        else
            log_fail "bash -n failed: $output"
        fi
    done <<< "$ALL_SCRIPTS"
fi

echo ""
echo "--- Unit Tests ---"
echo ""

UNIT_TESTS=$(find_unit_tests)

if [ -z "$UNIT_TESTS" ]; then
    echo "  No unit tests found (*_test.sh) — skipping."
    SKIP_COUNT=$((SKIP_COUNT + 1))
else
    while IFS= read -r test_file; do
        [ -z "$test_file" ] && continue

        relative_path="${test_file#$REPO_ROOT/}"
        echo "[ $relative_path ]"

        # shellcheck disable=SC2086
        set +e
        bash "$test_file" 2>&1
        exit_code=$?
        set -e

        if [ "$exit_code" -eq 0 ]; then
            log_pass "unit test passed"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            log_fail "unit test failed (exit $exit_code)"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    done <<< "$UNIT_TESTS"
fi

echo ""
echo "--- Coverage ---"
echo ""

TOTAL=$(echo "$ALL_SCRIPTS" | grep -v "^$" | grep -v "tests/run-tests.sh\|tests/test-scripts.sh\|tests/test-skills.sh" | wc -l)
COVERED=$(echo "$TESTED_SCRIPTS" | grep -v "^$" | wc -l)

echo "  Scripts found : $TOTAL"
echo "  Syntax-checked: $COVERED"
if [ "$TOTAL" -gt 0 ]; then
    COVERAGE_PCT=$((COVERED * 100 / TOTAL))
    echo "  Coverage      : ${COVERAGE_PCT}%"
else
    echo "  Coverage      : N/A"
fi

echo ""
echo "---------------------"
echo "Results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  SKIP=$SKIP_COUNT"
echo "---------------------"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "RESULT: FAILED"
    exit 1
else
    echo "RESULT: PASSED"
    exit 0
fi
