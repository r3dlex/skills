#!/bin/bash
#
# install-auggie.sh
# Installs skills/rules to Augment Code (Auggie)
#
# Auggie uses rules-based system via --rules flag
# Skills are converted to .md rule files in ~/.auggie/rules/
#
# Usage: ./install-auggie.sh [--rules | --all]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/.."
AUGGIE_RULES="$HOME/.auggie/rules"

# Shared discovery seam: list_skills, is_excluded_dir, frontmatter helpers.
. "$SCRIPT_DIR/lib-skill-discovery.sh"

mkdir -p "$AUGGIE_RULES"

# Convert a skill's SKILL.md to an Auggie rule format
# Auggie rules are markdown with special headers
convert_skill_to_rule() {
    local skill_name="$1"
    local source_dir="$SKILLS_DIR/$skill_name"
    local dest_file="$AUGGIE_RULES/${skill_name}.md"

    if [ ! -f "$source_dir/SKILL.md" ]; then
        echo "✗ Skill '$skill_name' missing SKILL.md"
        return 1
    fi

    # Extract description from frontmatter
    local description=$(skill_frontmatter_description "$source_dir/SKILL.md" || echo "")

    # Write rule file with Auggie format
    cat > "$dest_file" << EOF
---
name: $skill_name
description: $description
platform: auggie
---

EOF

    # Append the skill content (skipping YAML frontmatter)
    skill_body_without_frontmatter "$source_dir/SKILL.md" >> "$dest_file" 2>/dev/null || cat "$source_dir/SKILL.md" >> "$dest_file"

    echo "  ✓ $skill_name (as rule)"
}

install_all() {
    echo "Installing skills to Auggie as rules at $AUGGIE_RULES"
    echo "(Auggie uses --rules flag to load these)"
    echo ""

    while IFS= read -r skill_name; do
        convert_skill_to_rule "$skill_name"
    done < <(list_skills "$SKILLS_DIR")

    echo ""
    echo "Installed to: $AUGGIE_RULES"
    echo ""
    echo "Usage: auggie --rules $AUGGIE_RULES/*.md <instruction>"
    echo "Or add to your auggie config to auto-load rules"
}

install_all
echo ""
echo "Note: Auggie loads rules dynamically via --rules flag"
echo "There is no persistent skill installation - rules are loaded per-session"
