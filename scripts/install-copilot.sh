#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="$SCRIPT_DIR/.."
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
mode="${1:---consolidated}"; target="${2:-$SCRIPT_DIR/../..}"; [[ "$mode" != --repo ]] || { [[ $# -eq 2 ]] || exit 1; mode=--consolidated; }
case "$mode" in --consolidated|--per-skill|--all) ;; *) echo "Usage: $0 [--consolidated | --per-skill | --all | --repo <path>] [--include-lifecycle <value>]" >&2; exit 1;; esac
mkdir -p "$target/.github"; rows="$(catalog_rows copilot --projection "$target/.github/skills-catalog.json")" || exit $?
consolidated() { local out="$target/.github/copilot-instructions.md"; printf '# Copilot Instructions\n\n' > "$out"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; printf '## %s\n\n' "$name" >> "$out"; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md" >> "$out"; printf '\n' >> "$out"; done <<< "$rows"; }
per_skill() { local out="$target/.github/copilot-instructions"; mkdir -p "$out"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; sed -n '/^---$/,/^---$/d;p' "$SKILLS_DIR/$source/SKILL.md" > "$out/$name.md"; done <<< "$rows"; }
[[ "$mode" == --consolidated || "$mode" == --all ]] && consolidated
[[ "$mode" == --per-skill || "$mode" == --all ]] && per_skill
