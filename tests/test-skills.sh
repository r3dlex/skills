#!/bin/bash
#
# test-skills.sh
# Validates skill structure across all SKILL.md files in the repo.
#
# Checks:
#   - YAML frontmatter is present and well-formed
#   - Required frontmatter fields: name, description
#   - File body (after frontmatter) is under 100 lines
#   - Progressive disclosure compliance (no Overview/Background sections)
#
# Exit 0 on all pass, non-zero on any failure.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SKILLS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0

log_pass() {
    echo "  PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo "  FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

log_skip() {
    echo "  SKIP: $1"
    SKIP_COUNT=$((SKIP_COUNT + 1))
}

# -----------------------------------------------------------------------------
# Find all SKILL.md files, excluding .git/, hidden dirs, and .omc/ internal dirs.
# -----------------------------------------------------------------------------
find_skills() {
    find "$REPO_ROOT" \
        -name "SKILL.md" \
        -not -path "*/.git/*" \
        -not -path "*/.claude/*" \
        -not -path "*/.omc/*"
}

# -----------------------------------------------------------------------------
# Validate YAML frontmatter in a SKILL.md file.
# Returns 0 and prints "pass" on success; returns 1 on failure.
# -----------------------------------------------------------------------------
validate_frontmatter() {
    local file="$1"
    local first_line
    first_line=$(sed -n '1p' "$file")

    if [ "$first_line" != "---" ]; then
        echo "missing opening ---"
        return 1
    fi

    # Extract frontmatter between opening and closing delimiters.
    local fm
    fm=$(awk '
        NR == 1 && $0 == "---" { in_fm = 1; next }
        in_fm && $0 == "---" { found_close = 1; exit }
        in_fm { print }
        END { if (!found_close) exit 2 }
    ' "$file" 2>/dev/null)
    local awk_exit=$?

    if [ "$awk_exit" -ne 0 ]; then
        echo "missing closing ---"
        return 1
    fi

    # Required fields
    if ! echo "$fm" | grep -q '^name:'; then
        echo "missing required field 'name'"
        return 1
    fi
    if ! echo "$fm" | grep -q '^description:'; then
        echo "missing required field 'description'"
        return 1
    fi

    echo "pass"
    return 0
}

# -----------------------------------------------------------------------------
# Check that the body (after frontmatter) is under 100 lines.
# Returns 0 and prints "pass" when under limit; returns 1 and prints reason
# when over limit or parsing fails.
# -----------------------------------------------------------------------------
validate_line_count() {
    local file="$1"
    local body_line_count
    body_line_count=$(awk '
        NR == 1 && $0 == "---" { in_fm = 1; next }
        NR == 1 { parse_error = "missing opening ---"; exit }
        in_fm && $0 == "---" { in_body = 1; in_fm = 0; next }
        in_body { body_lines++ }
        END {
            if (parse_error) {
                print "ERROR:" parse_error
            } else if (!in_body) {
                print "ERROR:missing closing ---"
            } else {
                print body_lines + 0
            }
        }
    ' "$file")

    case "$body_line_count" in
        ERROR:*)
            echo "${body_line_count#ERROR:}"
            return 1
            ;;
    esac

    if [ "$body_line_count" -gt 100 ]; then
        echo "body has $body_line_count lines (limit: 100)"
        return 1
    fi
    echo "pass:$body_line_count"
    return 0
}

# -----------------------------------------------------------------------------
# Progressive disclosure compliance: body should not contain Overview,
# Background, or History sections.
# -----------------------------------------------------------------------------
validate_no_anti_patterns() {
    local file="$1"
    local bad_sections
    bad_sections=$(awk '
        /^##? .*/ {
            sect = substr($0, index($0, $2))
            if (sect ~ /^(Overview|Background|History)$/ ||
                sect ~ /^(Overview|Background|History)[[:space:]]/) {
                print sect
            }
        }
    ' "$file" 2>/dev/null || true)

    if [ -n "$bad_sections" ]; then
        echo "found anti-pattern sections: $bad_sections"
        return 1
    fi
    echo "pass"
    return 0
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
echo "Skill Structure Tests"
echo "====================="
echo ""

SKILLS=$(find_skills)

if [ -z "$SKILLS" ]; then
    echo "WARNING: No SKILL.md files found."
    exit 0
fi

while IFS= read -r skill_file; do
    [ -z "$skill_file" ] && continue

    relative_path="${skill_file#$REPO_ROOT/}"
    echo ""
    echo "[ $relative_path ]"

    set +e
    fm_result=$(validate_frontmatter "$skill_file" 2>&1)
    fm_exit=$?
    set -e
    if [ "$fm_exit" -eq 0 ]; then
        log_pass "frontmatter valid ($fm_result)"
    else
        log_fail "frontmatter: $fm_result"
    fi

    set +e
    count_result=$(validate_line_count "$skill_file" 2>&1)
    count_exit=$?
    set -e
    if [ "$count_exit" -eq 0 ]; then
        lines=$(echo "$count_result" | cut -d: -f2)
        log_pass "line count $lines (under 100)"
    else
        log_fail "line count: $count_result"
    fi

    set +e
    pd_result=$(validate_no_anti_patterns "$skill_file" 2>&1)
    pd_exit=$?
    set -e
    if [ "$pd_exit" -eq 0 ]; then
        log_pass "progressive disclosure compliant"
    else
        log_fail "progressive disclosure: $pd_result"
    fi

done <<< "$SKILLS"

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
