#!/bin/bash
#
# install-codex.sh
# Installs skills to OpenAI Codex
#
# Codex uses ~/.codex/skills/ with directory-based structure
# Each skill is a directory containing SKILL.md
#
# Usage: ./install-codex.sh [--skill <name> | --all]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.."
CODEX_SKILLS="$HOME/.codex/skills"

# Shared discovery seam: list_skills, is_excluded_dir, frontmatter helpers.
. "$SCRIPT_DIR/lib-skill-discovery.sh"

mkdir -p "$CODEX_SKILLS"

install_skill() {
    local skill_name="$1"
    local source_dir="$SKILLS_DIR/$skill_name"
    local dest_dir="$CODEX_SKILLS/$skill_name"

    if [ ! -d "$source_dir" ]; then
        echo "✗ Skill '$skill_name' not found in source directory"
        return 1
    fi

    if [ ! -f "$source_dir/SKILL.md" ]; then
        echo "✗ Skill '$skill_name' missing SKILL.md"
        return 1
    fi

    rm -rf "$dest_dir"
    mkdir -p "$(dirname "$dest_dir")"
    cp -r "$source_dir" "$dest_dir"
    echo "  ✓ $skill_name"
}

install_all() {
    echo "Installing all skills to Codex at $CODEX_SKILLS"

    while IFS= read -r skill_name; do
        install_skill "$skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Installed to: $CODEX_SKILLS"
    echo "Skills are auto-discovered by Codex on restart"
}

case "${1:-}" in
    --skill)
        if [ -z "$2" ]; then
            echo "Usage: $0 --skill <name>"
            exit 1
        fi
        echo "Installing skill '$2' to Codex"
        install_skill "$2"
        ;;
    --all|"")
        install_all
        ;;
    *)
        echo "Usage: $0 [--skill <name> | --all]"
        exit 1
        ;;
esac
