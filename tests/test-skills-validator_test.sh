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

# Discovery controls exercise the public supplied-root interface. All fixtures
# remain under the cleanup-bound external TMP_ROOT; production suites are intact.
assert_equal() {
    if [ "$1" != "$2" ]; then
        printf 'Expected %s:\n%s\nActual:\n%s\n' "$3" "$2" "$1" >&2
        exit 1
    fi
}

capture_discovery() {
    if discovery_output=$(SKILLS_REPO_ROOT="$1" bash "$TEST_SCRIPT" 2>&1); then
        discovery_exit=0
    else
        discovery_exit=$?
    fi
}

zero_output=$(cat <<'TEXT'
Skill Structure Tests
=====================

WARNING: No SKILL.md files found.
TEXT
)

# Characterize default find behavior: file links are candidates, directory links
# (including a supplied-root link) are not traversed. Keep the link's own name.
link_root="$TMP_ROOT/link-tree"
write_skill "$link_root/real" 100
write_skill "$TMP_ROOT/external-file" 100
mkdir -p "$link_root/file-link" "$TMP_ROOT/external-directory"
printf 'invalid external skill\n' > "$TMP_ROOT/external-directory/SKILL.md"
ln -s "$TMP_ROOT/external-file/SKILL.md" "$link_root/file-link/SKILL.md"
ln -s real "$link_root/internal-directory-link"
ln -s "$TMP_ROOT/external-directory" "$link_root/external-directory-link"
capture_discovery "$link_root"
assert_equal "$discovery_exit" 0 'symlink candidate exit'
assert_equal "$(grep '^\[ ' <<< "$discovery_output" | LC_ALL=C sort)" \
    $'[ file-link/SKILL.md ]\n[ real/SKILL.md ]' 'original symlink candidate names'
assert_contains "$discovery_output" 'Results: PASS=8  FAIL=0  WARN=0  SKIP=0'
printf 'Default find symlink characterization:\n%s\n' "$discovery_output"
ln -s "$link_root" "$TMP_ROOT/supplied-root-link"
capture_discovery "$TMP_ROOT/supplied-root-link"
assert_equal "$discovery_exit" 0 'supplied symlink root exit'
assert_equal "$discovery_output" "$zero_output" 'supplied symlink root no-follow output'
printf 'Supplied symlink root characterization:\n%s\n' "$discovery_output"

# Literal root-prefix removal and line reads must preserve whitespace, backslashes
# and glob characters. Newline filenames retain the existing line-oriented limit.
special_root="$TMP_ROOT/"$'root space\tand\\backslash[?]*'
special_skill=$'skill space\tand\\backslash'
write_skill "$special_root/$special_skill" 100
capture_discovery "$special_root"
assert_equal "$discovery_exit" 0 'special-path valid exit'
assert_equal "$(grep '^\[ ' <<< "$discovery_output")" \
    "[ $special_skill/SKILL.md ]" 'literal special-path skill name'
assert_contains "$discovery_output" 'Results: PASS=4  FAIL=0  WARN=0  SKIP=0'
write_skill "$special_root/$special_skill" 101
capture_discovery "$special_root"
assert_equal "$discovery_exit" 1 'special-path invalid exit'
assert_equal "$(grep '^\[ ' <<< "$discovery_output")" \
    "[ $special_skill/SKILL.md ]" 'literal invalid special-path skill name'
assert_contains "$discovery_output" 'body has 101 lines (target: 100); not in exception manifest'
assert_contains "$discovery_output" 'Results: PASS=3  FAIL=1  WARN=0  SKIP=0'
printf 'Space/tab/backslash/glob path controls passed\n'

# Only the three internal namespaces are excluded, at any depth. Other hidden
# directories stay visible and differently cased filenames remain undiscovered.
internal_root="$TMP_ROOT/internal-namespaces"
write_skill "$internal_root/ordinary" 100
write_skill "$internal_root/.visible/skill" 100
printf 'invalid differently cased filename\n' > "$internal_root/skill.md"
for namespace in .omc .git .claude; do
    mkdir -p "$internal_root/$namespace" "$internal_root/nested/$namespace/deeper"
    printf 'invalid internal skill\n' > "$internal_root/$namespace/SKILL.md"
    printf 'invalid nested skill\n' > "$internal_root/nested/$namespace/deeper/SKILL.md"
done
capture_discovery "$internal_root"
assert_equal "$discovery_exit" 0 'internal exclusions exit'
assert_equal "$(grep '^\[ ' <<< "$discovery_output" | LC_ALL=C sort)" \
    $'[ .visible/skill/SKILL.md ]\n[ ordinary/SKILL.md ]' 'only visible candidate names'
assert_contains "$discovery_output" 'Results: PASS=8  FAIL=0  WARN=0  SKIP=0'
rm -rf "$internal_root/ordinary" "$internal_root/.visible"
empty_root="$TMP_ROOT/empty-tree"
mkdir -p "$empty_root"

# AC4's isolated positive shell-suite stand-in belongs only to this disposable
# unchanged runner copy. The real full suite still executes every production test.
runner_root="$TMP_ROOT/zero-runner"
mkdir -p "$runner_root/tests"
cp "$REPO_ROOT/tests/run-tests.sh" "$runner_root/tests/run-tests.sh"
cp "$TEST_SCRIPT" "$runner_root/tests/test-skills.sh"
printf '#!/bin/bash\nprintf "Results: PASS=1  FAIL=0  SKIP=0\\n"\n' \
    > "$runner_root/tests/test-scripts.sh"
for zero_root in "$empty_root" "$internal_root"; do
    capture_discovery "$zero_root"
    assert_equal "$discovery_exit" 0 'zero-skill direct exit'
    assert_equal "$discovery_output" "$zero_output" 'zero-skill direct warning'
    if runner_output=$(SKILLS_REPO_ROOT="$zero_root" bash "$runner_root/tests/run-tests.sh" 2>&1); then
        runner_exit=0
    else
        runner_exit=$?
    fi
    assert_equal "$runner_exit" 1 'zero-skill full-runner exit'
    assert_contains "$runner_output" 'PASSED: Shell Script Tests'
    assert_contains "$runner_output" 'FAILED: Skill Structure Tests (zero assertions reported)'
    assert_contains "$runner_output" 'OVERALL: FAILED'
done
printf 'Internal/nested exclusions and empty/internal-only fail-closed controls passed\n'

# Ordinary and enclosing-namespace roots contain identical valid/exception trees.
# Compare complete output, including relative names, diagnostics and exact counts.
valid_root="$TMP_ROOT/discovery-valid"
write_skill "$valid_root/fixture" 100
capture_discovery "$valid_root"
assert_equal "$discovery_exit" 0 'ordinary valid exit'
valid_output="$discovery_output"
assert_contains "$valid_output" '[ fixture/SKILL.md ]'
assert_contains "$valid_output" 'line count 100 (under 100)'
assert_contains "$valid_output" 'description length 45 (within target 160)'
assert_contains "$valid_output" 'Results: PASS=4  FAIL=0  WARN=0  SKIP=0'
assert_contains "$valid_output" 'RESULT: PASSED'

excepted_root="$TMP_ROOT/discovery-excepted"
write_skill "$excepted_root/fixture" 180
python3 - "$excepted_root/fixture/SKILL.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text().replace(
    'description: Fixture skill for validator regression tests.',
    'description: ' + 'x' * 161,
))
PY
mkdir -p "$excepted_root/.ai/skills"
for manifest in description-exceptions body-line-exceptions; do
    printf '%s\n' '{"schema_version":"1.0","exceptions":[{"skill":"fixture","owner":"test","reason":"discovery control","expires":"2099-01-01"}]}' \
        > "$excepted_root/.ai/skills/$manifest.json"
done
capture_discovery "$excepted_root"
assert_equal "$discovery_exit" 0 'ordinary excepted exit'
excepted_output="$discovery_output"
assert_contains "$excepted_output" '[ fixture/SKILL.md ]'
assert_contains "$excepted_output" 'line count 180 (audited exception; maximum 180)'
assert_contains "$excepted_output" 'description length 161 over target but audited (maximum 180)'
assert_contains "$excepted_output" 'Results: PASS=4  FAIL=0  WARN=0  SKIP=0'
assert_contains "$excepted_output" 'RESULT: PASSED'

for namespace in ordinary .omc .git .claude; do
    ancestor_root="$TMP_ROOT/$namespace/ai-catapult/gate-workspaces"
    mkdir -p "$ancestor_root"
    cp -R "$valid_root" "$ancestor_root/valid"
    capture_discovery "$ancestor_root/valid"
    assert_equal "$discovery_exit" 0 "$namespace ancestor valid exit"
    assert_equal "$discovery_output" "$valid_output" "$namespace ancestor exact valid output"
    cp -R "$excepted_root" "$ancestor_root/excepted"
    capture_discovery "$ancestor_root/excepted"
    assert_equal "$discovery_exit" 0 "$namespace ancestor excepted exit"
    assert_equal "$discovery_output" "$excepted_output" "$namespace ancestor exact excepted output"
    cp -R "$over_limit" "$ancestor_root/invalid"
    capture_discovery "$ancestor_root/invalid"
    assert_equal "$discovery_exit" "$over_exit" "$namespace ancestor invalid exit"
    assert_equal "$discovery_output" "$over_output" "$namespace ancestor exact invalid diagnostic"
    printf 'Root-relative %s ancestor: exact valid/exception outputs and invalid exit/diagnostic passed\n' "$namespace"
done

printf 'test-skills root-discovery regression tests passed\n'
