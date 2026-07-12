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

write_catalog() {
    local root="$1"
    local source_path="$2"
    python3 - "$root" "$source_path" <<'PY'
import json, re, sys
from pathlib import Path
root=Path(sys.argv[1]); source_path=sys.argv[2]; skill=root/source_path/'SKILL.md'
text=skill.read_text(); match=re.search(r'^name:\s*(\S+)', text, re.M); assert match
entries=[{'name':match.group(1),'source_path':source_path,'owner_phase':'test','applies_to_phases':['test'],'lifecycle':'stable','supported_hosts':['codex']}]
(root/'catalog.json').write_text(json.dumps({'schema_version':'1.0','phases':['test'],'skills':entries},indent=2)+'\n')
PY
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

# Fixture A: YAML frontmatter plus 101 body lines must fail without an exception.
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
assert_contains "$over_output" "body has 101 lines (target: 100); not in exception manifest"

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

# Fixture D: skill catalog validator hard-fails descriptions over 180 chars.
catalog_root="$TMP_ROOT/catalog-hard-fail"
mkdir -p "$catalog_root/too-long"
{
    echo '---'
    echo 'name: too-long'
    printf 'description: '
    python3 - <<'PY'
print('x' * 181)
PY
    echo '---'
    echo 'Body'
} > "$catalog_root/too-long/SKILL.md"
write_catalog "$catalog_root" too-long
set +e
catalog_output=$(python3 "$REPO_ROOT/scripts/validate-skill-catalog.py" --root "$catalog_root" 2>&1)
catalog_exit=$?
set -e
if [ "$catalog_exit" -eq 0 ]; then
    echo "Expected catalog hard-fail fixture to fail" >&2
    echo "$catalog_output" >&2
    exit 1
fi
assert_contains "$catalog_output" "exceeds maximum 180"

# Fixture E: over-target descriptions require an audited exception and stay <=180.
catalog_warn="$TMP_ROOT/catalog-warn"
mkdir -p "$catalog_warn/warn-skill"
{
    echo '---'
    echo 'name: warn-skill'
    printf 'description: '
    python3 - <<'PY'
print('x' * 161)
PY
    echo '---'
    echo 'Body'
} > "$catalog_warn/warn-skill/SKILL.md"
write_catalog "$catalog_warn" warn-skill
set +e
warn_output=$(python3 "$REPO_ROOT/scripts/validate-skill-catalog.py" --root "$catalog_warn" 2>&1)
warn_exit=$?
set -e
if [ "$warn_exit" -eq 0 ]; then
    echo "Expected over-target description without exception to fail" >&2
    exit 1
fi
assert_contains "$warn_output" "exceeds target 160 without audited exception"

mkdir -p "$catalog_warn/.ai/skills"
cat > "$catalog_warn/.ai/skills/description-exceptions.json" <<'JSON'
{"schema_version":"1.0","exceptions":[{"skill":"warn-skill","owner":"test","reason":"routing clarity","expires":"2099-01-01"}]}
JSON
exception_output=$(python3 "$REPO_ROOT/scripts/validate-skill-catalog.py" --root "$catalog_warn" 2>&1)
assert_contains "$exception_output" "skill catalog validation passed"

# Fixture F: body exceptions permit 101..180 lines but never 181.
body_exception="$TMP_ROOT/body-exception"
write_skill "$body_exception/fixture" 180
write_catalog "$body_exception" fixture
mkdir -p "$body_exception/.ai/skills"
cat > "$body_exception/.ai/skills/body-line-exceptions.json" <<'JSON'
{"schema_version":"1.0","exceptions":[{"skill":"fixture","owner":"test","reason":"irreducible workflow","expires":"2099-01-01"}]}
JSON
body_exception_output=$(SKILLS_REPO_ROOT="$body_exception" bash "$TEST_SCRIPT" 2>&1)
assert_contains "$body_exception_output" "line count 180 (audited exception; maximum 180)"
catalog_body_output=$(python3 "$REPO_ROOT/scripts/validate-skill-catalog.py" --root "$body_exception" 2>&1)
assert_contains "$catalog_body_output" "skill catalog validation passed"

write_skill "$body_exception/fixture" 181
set +e
body_max_output=$(SKILLS_REPO_ROOT="$body_exception" bash "$TEST_SCRIPT" 2>&1)
body_max_exit=$?
set -e
if [ "$body_max_exit" -eq 0 ]; then
    echo "Expected 181-line body to fail even with exception" >&2
    exit 1
fi
assert_contains "$body_max_output" "body has 181 lines (maximum: 180)"
set +e
catalog_body_max=$(python3 "$REPO_ROOT/scripts/validate-skill-catalog.py" --root "$body_exception" 2>&1)
catalog_body_max_exit=$?
set -e
if [ "$catalog_body_max_exit" -eq 0 ]; then
    echo "Expected catalog validator to reject 181-line body" >&2
    exit 1
fi
assert_contains "$catalog_body_max" "body length 181 exceeds maximum 180"

printf 'test-skills validator regression tests passed\n'
