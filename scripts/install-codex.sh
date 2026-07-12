#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="$SCRIPT_DIR/.."; CODEX_SKILLS="$HOME/.codex/skills"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
mkdir -p "$CODEX_SKILLS"; skill=""
case "${1:-}" in --skill) [[ $# -eq 2 ]] || { echo "Usage: $0 [--skill <name> | --all] [--include-lifecycle <value>]" >&2; exit 1; }; skill="$2";; --all|"") ;; *) echo "Usage: $0 [--skill <name> | --all] [--include-lifecycle <value>]" >&2; exit 1;; esac
if [[ -n "$skill" ]]; then
  rows="$(catalog_rows codex --skill "$skill" --projection "$CODEX_SKILLS/catalog.json")" || exit $?
else
  rows="$(catalog_rows codex --projection "$CODEX_SKILLS/catalog.json")" || exit $?
fi
while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; rm -rf "$CODEX_SKILLS/$name"; cp -R "$SKILLS_DIR/$source" "$CODEX_SKILLS/$name"; echo "  ✓ $name"; done <<< "$rows"
