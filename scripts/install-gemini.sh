#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="$SCRIPT_DIR/.."; DEST="$HOME/.gemini/skills"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
case "${1:-}" in --install|--link|--all|"") ;; *) echo "Usage: $0 [--install | --link | --all] [--include-lifecycle <value>]" >&2; exit 1;; esac
mkdir -p "$DEST"; rows="$(catalog_rows gemini --projection "$DEST/catalog.json")" || exit $?
while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; { echo "# $name"; echo; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md"; } > "$DEST/$name.md"; echo "  ✓ $name"; done <<< "$rows"
