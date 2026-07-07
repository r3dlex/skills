#!/bin/bash
#
# install-copilot.sh
# Installs skills/instructions to GitHub Copilot
#
# Copilot uses per-repository instruction files:
#   .github/copilot-instructions.md (root level)
#
# This script creates a consolidated instructions.md from skills
# and optionally sets up per-skill instruction files
#
# Usage: ./install-copilot.sh [--repo <path> | --consolidated | --all]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.."
TARGET_REPO="${2:-$SCRIPT_DIR/../..}"  # Default to parent of skills dir (assumes repo root)

# Shared discovery seam: list_skills, is_excluded_dir, frontmatter helpers.
. "$SCRIPT_DIR/lib-skill-discovery.sh"

# Parse args
MODE="${1:-}"
if [ -z "$MODE" ]; then
    MODE="--consolidated"
fi

create_consolidated_instructions() {
    local output_file="$TARGET_REPO/.github/copilot-instructions.md"
    local repo_name=$(basename "$TARGET_REPO")

    echo "Creating consolidated Copilot instructions at:"
    echo "  $output_file"
    echo ""

    mkdir -p "$(dirname "$output_file")"

    cat > "$output_file" << EOF
# Copilot Instructions — $repo_name

This file contains agent-facing instructions synthesized from the skills library.

EOF

    # Process each skill
    while IFS= read -r skill_name; do
        skill_dir="$SKILLS_DIR/$skill_name/"
        echo "## $skill_name" >> "$output_file"
        echo "" >> "$output_file"

        # Write skill content (frontmatter skipped), indented
        while IFS= read -r line; do
            echo "  $line" >> "$output_file"
        done < <(skill_body_without_frontmatter "${skill_dir}SKILL.md" 2>/dev/null)

        echo "" >> "$output_file"
    done < <(list_skills "$SKILLS_DIR")

    echo "✓ Created $output_file"
    echo ""
    echo "Copilot will automatically use this file for instructions"
    echo "in repositories where it exists at the root level"
}

create_per_skill_instructions() {
    local output_dir="$TARGET_REPO/.github/copilot-instructions/"
    mkdir -p "$output_dir"

    echo "Creating per-skill instruction files at:"
    echo "  $output_dir"
    echo ""

    while IFS= read -r skill_name; do
        skill_dir="$SKILLS_DIR/$skill_name/"
        local output_file="$output_dir/${skill_name}.md"

        # Extract description for header
        local description=$(skill_frontmatter_description "${skill_dir}SKILL.md" || echo "Skill: $skill_name")

        cat > "$output_file" << EOF
# $skill_name

$description

EOF

        # Append skill content (skip frontmatter)
        skill_body_without_frontmatter "${skill_dir}SKILL.md" >> "$output_file" 2>/dev/null

        echo "  ✓ $skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Per-skill instructions created. You can reference these"
    echo "in your main copilot-instructions.md or include them directly"
}

case "$MODE" in
    --repo)
        if [ -z "$2" ]; then
            echo "Usage: $0 --repo <path>"
            exit 1
        fi
        TARGET_REPO="$2"
        create_consolidated_instructions
        ;;
    --consolidated)
        create_consolidated_instructions
        ;;
    --per-skill)
        create_per_skill_instructions
        ;;
    --all)
        create_consolidated_instructions
        echo ""
        create_per_skill_instructions
        ;;
    *)
        echo "Usage: $0 [--consolidated | --per-skill | --all | --repo <path>]"
        echo "  --consolidated  Create single .github/copilot-instructions.md (default)"
        echo "  --per-skill     Create .github/copilot-instructions/<skill>.md files"
        echo "  --all           Create both consolidated and per-skill"
        echo "  --repo <path>   Install to specific repo path"
        exit 1
        ;;
esac
