#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
PASS=0
FAIL=0

ok() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

runner_dir="$TMPDIR/tests"
mkdir -p "$runner_dir"
cp "$REPO_ROOT/tests/run-tests.sh" "$runner_dir/run-tests.sh"

write_suite() {
  local path="$1" assertions="$2"
  printf '#!/bin/bash\necho "Results: PASS=%s FAIL=0"\nexit 0\n' "$assertions" > "$path"
  chmod +x "$path"
}

assert_runner_exit() {
  local scripts_assertions="$1" skills_assertions="$2" expected="$3" message="$4" actual
  write_suite "$runner_dir/test-scripts.sh" "$scripts_assertions"
  write_suite "$runner_dir/test-skills.sh" "$skills_assertions"
  set +e
  bash "$runner_dir/run-tests.sh" >/dev/null 2>&1
  actual=$?
  set -e
  if [[ "$actual" == "$expected" ]]; then ok "$message"; else bad "$message (exit $actual, want $expected)"; fi
}

assert_runner_exit 0 1 1 "aggregate runner rejects a zero-assertion shell suite"
assert_runner_exit 1 0 1 "aggregate runner rejects a zero-assertion skill suite"
assert_runner_exit 1 1 0 "aggregate runner accepts child suites with assertions"

echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
