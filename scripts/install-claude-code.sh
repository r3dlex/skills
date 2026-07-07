#!/bin/bash
#
# install-claude-code.sh
# Installs skills to Claude Code via OMC skill system
#
# Skills are installed to ~/.claude/skills/omc-learned/ (user-level)
# Or use .omc/skills/ for project-level skills
#
# Usage: ./install-claude-code.sh [--user | --project | --all]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.."

# Shared discovery seam: list_skills, is_excluded_dir, frontmatter helpers.
. "$SCRIPT_DIR/lib-skill-discovery.sh"

# Default: install to user-level
SCOPE="${1:-user}"

install_to_user() {
    local dest="$HOME/.claude/skills/omc-learned"
    mkdir -p "$dest"

    echo "Installing skills to Claude Code (user-level) at $dest"

    # Copy all skill directories (each has SKILL.md and optional REFERENCE.md, scripts/)
    while IFS= read -r skill_name; do
        # Copy to an explicit destination path (no trailing slash on the
        # source). `cp -r "$skill_dir" "$dest/"` would copy the directory's
        # CONTENTS into $dest on macOS/BSD (the glob appends a trailing
        # slash), flattening every skill into one merged blob.
        rm -rf "${dest}/${skill_name}"
        cp -r "$SKILLS_DIR/$skill_name" "${dest}/${skill_name}"
        echo "  ✓ $skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Installed to: $dest"
    echo "Activate with: /oh-my-claudecode:<skill-name> or /skill <skill-name>"
}

install_to_project() {
    local dest="$SKILLS_DIR/.omc/skills"
    mkdir -p "$dest"

    echo "Installing skills to Claude Code (project-level) at $dest"

    while IFS= read -r skill_name; do
        # Copy to an explicit destination path (no trailing slash on the
        # source). `cp -r "$skill_dir" "$dest/"` would copy the directory's
        # CONTENTS into $dest on macOS/BSD (the glob appends a trailing
        # slash), flattening every skill into one merged blob.
        rm -rf "${dest}/${skill_name}"
        cp -r "$SKILLS_DIR/$skill_name" "${dest}/${skill_name}"
        echo "  ✓ $skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Installed to: $dest"
    echo "Activate with: /oh-my-claudecode:<skill-name> in this project"
}

case "$SCOPE" in
    --user)
        install_to_user
        ;;
    --project)
        install_to_project
        ;;
    --all)
        install_to_user
        echo ""
        install_to_project
        ;;
    *)
        echo "Usage: $0 [--user | --project | --all]"
        echo "  --user    Install to ~/.claude/skills/omc-learned/ (all projects)"
        echo "  --project Install to .omc/skills/ (this project only)"
        echo "  --all     Install to both locations"
        exit 1
        ;;
esac
