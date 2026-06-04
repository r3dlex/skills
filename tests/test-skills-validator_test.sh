#!/bin/bash
# Regression tests for tests/test-skills.sh frontmatter/body parsing.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_SCRIPT="$REPO_ROOT/tests/test-skills.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

write_skill() {
    local dir="$1"
    local body_lines="$2"
    mkdir -p "$dir"
    {
        echo '---'
        echo 'name: fixture'
        echo 'description: Fixture skill for validator regression tests.'
        echo '---'
        for i in $(seq 1 "$body_lines"); do
            echo "Body line $i"
        done
    } > "$dir/SKILL.md"
}

run_validator() {
    local fixture_root="$1"
    set +e
    SKILLS_REPO_ROOT="$fixture_root" bash "$TEST_SCRIPT" 2>&1
    local exit_code=$?
    set -e
    return "$exit_code"
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    if ! grep -Fq "$needle" <<< "$haystack"; then
        echo "Expected output to contain: $needle" >&2
        echo "Actual output:" >&2
        echo "$haystack" >&2
        exit 1
    fi
}

# Fixture A: YAML frontmatter plus 101 body lines must fail the body limit.
over_limit="$TMP_ROOT/over-limit"
write_skill "$over_limit/over" 101
set +e
over_output=$(SKILLS_REPO_ROOT="$over_limit" bash "$TEST_SCRIPT" 2>&1)
over_exit=$?
set -e
if [ "$over_exit" -eq 0 ]; then
    echo "Expected over-limit fixture to fail" >&2
    echo "$over_output" >&2
    exit 1
fi
assert_contains "$over_output" "line count: body has 101 lines (limit: 100)"

# Fixture B: YAML frontmatter plus exactly 100 body lines must pass.
at_limit="$TMP_ROOT/at-limit"
write_skill "$at_limit/at" 100
at_output=$(SKILLS_REPO_ROOT="$at_limit" bash "$TEST_SCRIPT" 2>&1)
assert_contains "$at_output" "line count 100 (under 100)"
assert_contains "$at_output" "RESULT: PASSED"

# Fixture C: Missing frontmatter must fail frontmatter validation.
missing_fm="$TMP_ROOT/missing-frontmatter"
mkdir -p "$missing_fm/no-frontmatter"
printf '# No frontmatter\n' > "$missing_fm/no-frontmatter/SKILL.md"
set +e
missing_output=$(SKILLS_REPO_ROOT="$missing_fm" bash "$TEST_SCRIPT" 2>&1)
missing_exit=$?
set -e
if [ "$missing_exit" -eq 0 ]; then
    echo "Expected missing-frontmatter fixture to fail" >&2
    echo "$missing_output" >&2
    exit 1
fi
assert_contains "$missing_output" "frontmatter: missing opening ---"

archgate_json=$(cd "$REPO_ROOT" && bash scripts/archgate.sh \
    --mode structural \
    --rules '.rules.ts' \
    --base 'refs/heads/feature"quote' \
    --head 'refs/heads/fix\slash' \
    --format json)

ARCHGATE_JSON="$archgate_json" python3 - <<'PY'
import os
import json

payload = json.loads(os.environ["ARCHGATE_JSON"])
assert payload["status"] == "pass"
assert payload["base"] == 'refs/heads/feature"quote'
assert payload["head"] == r"refs/heads/fix\slash"
assert payload["rulesFile"] == ".rules.ts"
PY

if grep -R "setup-matt-pocock-skills" "$REPO_ROOT" \
    --exclude-dir=.git \
    --exclude-dir=.omc \
    --exclude-dir=graphify-out \
    --exclude="test-skills-validator_test.sh" \
    >/dev/null; then
    echo "Found stale setup-matt-pocock-skills reference" >&2
    exit 1
fi

printf 'test-skills validator regression tests passed\n'
