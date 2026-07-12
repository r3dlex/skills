#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="${SKILLS_CATALOG_ROOT:-$SCRIPT_DIR/..}"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
scope="${1:---user}"; [[ $# -le 1 ]] || { echo "Usage: $0 [--user | --project | --all] [--include-lifecycle <value>]" >&2; exit 1; }
install_to() { local dest="$1" rows projection; projection=$(mktemp); rows="$(catalog_rows claude-code --projection "$projection")" || { rm -f "$projection"; return $?; }; mkdir -p "$dest"; mv "$projection" "$dest/catalog.json"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; rm -rf "$dest/$name"; cp -R "$SKILLS_DIR/$source" "$dest/$name"; echo "  ✓ $name"; done <<< "$rows"; }
case "$scope" in --user) install_to "$HOME/.claude/skills/omc-learned";; --project) install_to "$SKILLS_DIR/.omc/skills";; --all) install_to "$HOME/.claude/skills/omc-learned"; install_to "$SKILLS_DIR/.omc/skills";; *) echo "Usage: $0 [--user | --project | --all] [--include-lifecycle <value>]" >&2; exit 1;; esac
