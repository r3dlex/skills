#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="${SKILLS_CATALOG_ROOT:-$SCRIPT_DIR/..}"; DEST="$HOME/.auggie/rules"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
case "${1:-}" in --rules|--all|"") ;; *) echo "Usage: $0 [--rules | --all] [--include-lifecycle <value>]" >&2; exit 1;; esac
projection=$(mktemp); trap 'rm -f "$projection"' EXIT; rows="$(catalog_rows auggie --projection "$projection")" || exit $?; mkdir -p "$DEST"; mv "$projection" "$DEST/catalog.json"
while IFS=$'\t' read -r name source; do
 [[ -n "$name" ]] || continue; skill="$SKILLS_DIR/$source/SKILL.md"; description=$(grep -A1 '^description:' "$skill" 2>/dev/null | tail -1 | sed 's/^ *//' || echo "")
 { echo '---'; echo "name: $name"; echo "description: $description"; echo 'platform: auggie'; echo '---'; echo ''; flattened_skill_body "$skill"; } > "$DEST/$name.md"; echo "  ✓ $name"
done <<< "$rows"
