#!/bin/bash
#
# lib-skill-discovery.sh
# Shared skill-discovery seam for the tool installers.
#
# A "skill" is a top-level directory of the repo root that contains a
# SKILL.md and is not on the internal-dir exclusion list. The five
# installers (install-claude-code.sh, install-codex.sh, install-copilot.sh,
# install-gemini.sh, install-auggie.sh) source this file so that discovery
# and filtering live in exactly one place; each installer keeps only its
# tool-specific install step.
#
# Usage (from an installer):
#   . "$SCRIPT_DIR/lib-skill-discovery.sh"
#   while IFS= read -r skill_name; do ... done < <(list_skills "$SKILLS_DIR")
#

# Centralized exclusion list: internal dirs that are never skills, even if
# a SKILL.md ever appears in them. (Dotdirs are also skipped by the */ glob
# in list_skills; they are listed here so intent is explicit in one place.)
SKILL_DISCOVERY_EXCLUDES=(
    ".claude"
    ".omc"
    ".agents"
    ".ai"
    ".memory"
    ".github"
    "scripts"
    "raw"
    "tests"
    "docs"
    "reference"
)

# is_excluded_dir <name>
# Returns 0 if <name> is on the exclusion list, 1 otherwise.
is_excluded_dir() {
    local name="$1"
    local excluded
    for excluded in "${SKILL_DISCOVERY_EXCLUDES[@]}"; do
        if [ "$name" = "$excluded" ]; then
            return 0
        fi
    done
    return 1
}

# list_skills <root>
# Emits the discovered skill names (one per line, glob order): top-level
# directories of <root> that contain a SKILL.md and are not excluded.
list_skills() {
    local root="$1"
    local skill_dir skill_name
    for skill_dir in "$root"/*/; do
        skill_name=$(basename "$skill_dir")
        if is_excluded_dir "$skill_name"; then
            continue
        fi
        if [ -f "${skill_dir}SKILL.md" ]; then
            printf '%s\n' "$skill_name"
        fi
    done
}

# skill_frontmatter_description <skill-md-path>
# Prints the frontmatter `description:` value of a SKILL.md (the shared
# grep/tail/sed pipeline the installers previously inlined). Prints nothing
# if the field or file is missing.
skill_frontmatter_description() {
    grep -A1 '^description:' "$1" 2>/dev/null | tail -1 | sed 's/^ *//'
}

# skill_body_without_frontmatter <skill-md-path>
# Prints the SKILL.md body with the leading YAML frontmatter block removed.
skill_body_without_frontmatter() {
    sed -n '/^---$/,/^---$/d;p' "$1"
}
