#!/bin/bash
#
# run-tests.sh
# Main test runner for skills repository
#
# Runs all test suites and reports aggregate results.
# Exit 0 on all success, non-zero if any suite fails.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

TOTAL_FAILS=0
TOTAL_PASSES=0

run_suite() {
    local name="$1"
    local script="$2"
    local suite_fails

    echo ""
    echo "========================================"
    echo "  $name"
    echo "========================================"

    if [ ! -f "$script" ]; then
        echo "ERROR: test script not found: $script"
        TOTAL_FAILS=$((TOTAL_FAILS + 1))
        return
    fi

    # Run the suite; capture both stdout/stderr and exit code.
    # shellcheck disable=SC2086
    set +e
    bash "$script" 2>&1
    suite_exit=$?
    set -e

    if [ "$suite_exit" -ne 0 ]; then
        echo ""
        echo "FAILED: $name (exit $suite_exit)"
        TOTAL_FAILS=$((TOTAL_FAILS + 1))
    else
        echo ""
        echo "PASSED: $name"
        TOTAL_PASSES=$((TOTAL_PASSES + 1))
    fi
}

cd "$REPO_ROOT"

run_suite "Shell Script Tests"        "$SCRIPT_DIR/test-scripts.sh"
run_suite "Skill Structure Tests"    "$SCRIPT_DIR/test-skills.sh"

echo ""
echo "========================================"
echo "  SUMMARY"
echo "========================================"
echo "  Passed: $TOTAL_PASSES"
echo "  Failed: $TOTAL_FAILS"
echo "========================================"

if [ "$TOTAL_FAILS" -gt 0 ]; then
    echo "OVERALL: FAILED"
    exit 1
else
    echo "OVERALL: PASSED"
    exit 0
fi
