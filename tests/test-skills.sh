#!/bin/bash
#
# test-skills.sh
# Validates skill structure across all SKILL.md files in the repo.
#
# Checks:
#   - YAML frontmatter is present and well-formed
#   - Required frontmatter fields: name, description
#   - File body target <=100 lines; audited exceptions may reach 180
#   - Progressive disclosure compliance (no Overview/Background sections)
#   - Description target <=160 chars; audited exceptions may reach 180
#
# Exit 0 on all pass, non-zero on any failure.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SKILLS_REPO_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

FAIL_COUNT=0
PASS_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0

log_pass() {
    echo "  PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

log_fail() {
    echo "  FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
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
# Check the 100-line body target and audited 180-line exception ceiling.
# Returns 0 and prints "pass" when under limit; returns 1 and prints reason
# when over limit or parsing fails.
# -----------------------------------------------------------------------------
validate_line_count() {
    local file="$1"
    local body_line_count skill_name
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

    skill_name=$(awk '
        NR == 1 { next }
        $0 == "---" { exit }
        /^name:/ { sub(/^name:[[:space:]]*/, ""); gsub(/^["'\'']|["'\'']$/, ""); print; exit }
    ' "$file")

    if [ "$body_line_count" -gt 180 ]; then
        echo "body has $body_line_count lines (maximum: 180)"
        return 1
    fi
    if [ "$body_line_count" -gt 100 ]; then
        if is_body_excepted "$skill_name"; then
            echo "exception:$body_line_count"
            return 0
        fi
        echo "body has $body_line_count lines (target: 100); not in exception manifest"
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
# Description-length budget (compact Codex/Claude metadata policy).
# Target <=160 chars; audited exceptions may reach the absolute 180-char maximum.
#   .ai/skills/description-exceptions.json
# Pure-shell / offline, consistent with the other checks in this file.
#
# Prints one of:
#   pass:<len>           description within target
#   exception:<len>      over target but within 180 and listed in the manifest
#   ERROR:<reason>       parse failure (treated as failure by caller)
#   FAIL:<reason>        over target without exception, or over maximum
# Returns 0 for pass/exception, 1 for ERROR/FAIL.
# -----------------------------------------------------------------------------
DESCRIPTION_TARGET_CHARS=160
DESCRIPTION_MAX_CHARS=180
EXCEPTIONS_FILE="$REPO_ROOT/.ai/skills/description-exceptions.json"
BODY_EXCEPTIONS_FILE="$REPO_ROOT/.ai/skills/body-line-exceptions.json"

# Returns 0 if the given skill name is listed in the exception manifest.
is_description_excepted() {
    local skill_name="$1"
    [ -f "$EXCEPTIONS_FILE" ] || return 1
    # Match a JSON entry of the form: "skill": "<name>" (manifest is line-oriented).
    grep -Eq "\"skill\"[[:space:]]*:[[:space:]]*\"${skill_name}\"" "$EXCEPTIONS_FILE"
}

is_body_excepted() {
    local skill_name="$1"
    [ -f "$BODY_EXCEPTIONS_FILE" ] || return 1
    grep -Eq "\"skill\"[[:space:]]*:[[:space:]]*\"${skill_name}\"" "$BODY_EXCEPTIONS_FILE"
}

validate_description_budget() {
    local file="$1"
    local desc skill_name len

    # Extract the `description:` value from the frontmatter block. Handles both
    # single-line scalars and folded/literal block scalars (`>`, `>-`, `|`, `|-`)
    # by joining indented continuation lines into one space-separated string.
    desc=$(awk '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { in_fm = 1; next }
        in_fm && $0 == "---" { exit }
        collecting {
            # Continuation lines of a block scalar are indented; a non-indented
            # line (next key) ends the block.
            if ($0 ~ /^[[:space:]]+/ || $0 ~ /^$/) {
                line = $0
                sub(/^[[:space:]]+/, "", line)
                acc = (acc == "" ? line : acc " " line)
                next
            }
            collecting = 0
            print acc
            exit
        }
        in_fm && /^description:/ {
            val = $0
            sub(/^description:[[:space:]]*/, "", val)
            if (val ~ /^[>|][+-]?[[:space:]]*$/) {
                acc = ""
                collecting = 1
                next
            }
            gsub(/^["'\'']|["'\'']$/, "", val)
            print val
            exit
        }
        END { if (collecting) print acc }
    ' "$file")

    skill_name=$(awk '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { in_fm = 1; next }
        in_fm && $0 == "---" { exit }
        in_fm && /^name:/ {
            sub(/^name:[[:space:]]*/, "")
            gsub(/^["'\'']|["'\'']$/, "")
            print
            exit
        }
    ' "$file")

    if [ -z "$desc" ]; then
        echo "ERROR:no description found in frontmatter"
        return 1
    fi

    len=${#desc}

    if [ "$len" -gt "$DESCRIPTION_MAX_CHARS" ]; then
        echo "FAIL:description has $len chars (maximum: $DESCRIPTION_MAX_CHARS)"
        return 1
    fi

    if [ "$len" -gt "$DESCRIPTION_TARGET_CHARS" ]; then
        if is_description_excepted "$skill_name"; then
            echo "exception:$len"
            return 0
        fi
        echo "FAIL:description has $len chars (target: $DESCRIPTION_TARGET_CHARS); not in exception manifest"
        return 1
    fi

    echo "pass:$len"
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

    relative_path="${skill_file#"$REPO_ROOT"/}"
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
        case "$count_result" in
            exception:*) log_pass "line count ${count_result#exception:} (audited exception; maximum 180)" ;;
            *) lines=$(echo "$count_result" | cut -d: -f2); log_pass "line count $lines (under 100)" ;;
        esac
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

    set +e
    budget_result=$(validate_description_budget "$skill_file" 2>&1)
    budget_exit=$?
    set -e
    if [ "$budget_exit" -eq 0 ]; then
        case "$budget_result" in
            exception:*)
                log_pass "description length ${budget_result#exception:} over target but audited (maximum ${DESCRIPTION_MAX_CHARS})"
                ;;
            *)
                log_pass "description length ${budget_result#pass:} (within target ${DESCRIPTION_TARGET_CHARS})"
                ;;
        esac
    else
        log_fail "description budget: ${budget_result#*:}"
    fi

done <<< "$SKILLS"

echo ""
echo "---------------------"
echo "Results: PASS=$PASS_COUNT  FAIL=$FAIL_COUNT  WARN=$WARN_COUNT  SKIP=$SKIP_COUNT"
echo "---------------------"

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "RESULT: FAILED"
    exit 1
else
    echo "RESULT: PASSED"
    exit 0
fi
