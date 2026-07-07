#!/bin/bash
#
# install-gemini.sh
# Installs skills to Google Gemini CLI
#
# Gemini CLI has native skill management via 'gemini skills' commands:
#   gemini skills install <source>
#   gemini skills link <path>
#   gemini skills list
#
# Skills are installed to ~/.gemini/skills/ by default
#
# Usage: ./install-gemini.sh [--install | --link | --all]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.."
GEMINI_SKILLS="$HOME/.gemini/skills"

# Shared discovery seam: list_skills, is_excluded_dir, frontmatter helpers.
. "$SCRIPT_DIR/lib-skill-discovery.sh"

# Check if gemini CLI is available
GEMINI_BIN=""
if command -v gemini &> /dev/null; then
    GEMINI_BIN="gemini"
elif [ -f "$HOME/go/bin/gemini" ]; then
    GEMINI_BIN="$HOME/go/bin/gemini"
elif [ -f "/usr/local/bin/gemini" ]; then
    GEMINI_BIN="/usr/local/bin/gemini"
fi

# Convert OMC skill format to Gemini skill format
# Gemini uses simpler markdown without YAML frontmatter
convert_skill_for_gemini() {
    local skill_name="$1"
    local source_dir="$SKILLS_DIR/$skill_name"
    local dest_file="$GEMINI_SKILLS/${skill_name}.md"

    if [ ! -f "$source_dir/SKILL.md" ]; then
        echo "✗ Skill '$skill_name' missing SKILL.md"
        return 1
    fi

    # Extract description from frontmatter
    local description=$(skill_frontmatter_description "$source_dir/SKILL.md" || echo "")

    mkdir -p "$(dirname "$dest_file")"

    # Gemini skill format: Title line + description + content
    {
        echo "# $skill_name"
        echo ""
        echo "$description"
        echo ""
        echo "---"
        echo ""
        # Skip YAML frontmatter, output rest
        skill_body_without_frontmatter "$source_dir/SKILL.md"
    } > "$dest_file"

    echo "  ✓ $skill_name"
}

install_all_as_files() {
    echo "Installing skills to Gemini at $GEMINI_SKILLS"
    echo "(As native .md skill files)"
    echo ""

    mkdir -p "$GEMINI_SKILLS"

    while IFS= read -r skill_name; do
        convert_skill_for_gemini "$skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Installed to: $GEMINI_SKILLS"
    echo ""
    echo "Next steps:"
    echo "  gemini skills list"
    echo "  gemini skills link $GEMINI_SKILLS/<skill-name>.md"
}

gemini_skill_install() {
    if [ -z "$GEMINI_BIN" ]; then
        echo "✗ Gemini CLI not found. Please install from:"
        echo "  https://ai.google.dev/gemini-api/docs/gemini-cli"
        return 1
    fi

    echo "Installing skills via gemini skills CLI..."
    echo ""

    while IFS= read -r skill_name; do
        echo "  → Linking $skill_name..."
        # Create temp file with converted content
        convert_skill_for_gemini "$skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Skills are now linked. Verify with:"
    echo "  $GEMINI_BIN skills list"
}

case "${1:-}" in
    --install)
        gemini_skill_install
        ;;
    --link)
        install_all_as_files
        ;;
    --all)
        install_all_as_files
        echo ""
        echo "After linking, you can enable skills with:"
        echo "  gemini skills enable <skill-name>"
        ;;
    "")
        install_all_as_files
        ;;
    *)
        echo "Usage: $0 [--install | --link | --all]"
        echo "  --install  Use 'gemini skills install' (if gemini CLI available)"
        echo "  --link     Copy skills as .md files to ~/.gemini/skills/ (default)"
        echo "  --all      Run both methods"
        echo ""
        echo "Note: --install requires gemini CLI to be installed"
        exit 1
        ;;
esac
