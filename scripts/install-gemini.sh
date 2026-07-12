#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="${SKILLS_CATALOG_ROOT:-$SCRIPT_DIR/..}"; DEST="$HOME/.gemini/skills"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
case "${1:-}" in --install|--link|--all|"") ;; *) echo "Usage: $0 [--install | --link | --all] [--include-lifecycle <value>]" >&2; exit 1;; esac
projection=$(mktemp); trap 'rm -f "$projection"' EXIT; rows="$(catalog_rows gemini --projection "$projection")" || exit $?; mkdir -p "$DEST"; mv "$projection" "$DEST/catalog.json"
while IFS=$'\t' read -r name source; do
 [[ -n "$name" ]] || continue; skill="$SKILLS_DIR/$source/SKILL.md"; description=$(grep -A1 '^description:' "$skill" 2>/dev/null | tail -1 | sed 's/^ *//' || echo "")
 { echo "# $name"; echo ""; echo "$description"; echo ""; echo "---"; echo ""; sed -n '/^---$/,/^---$/d;p' "$skill"; } > "$DEST/$name.md"; echo "  ✓ $name"
done <<< "$rows"
