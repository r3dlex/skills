#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SKILLS_DIR="${SKILLS_CATALOG_ROOT:-$SCRIPT_DIR/..}"
source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@" || exit $?; set -- "${CATALOG_REST[@]}"
mode="${1:---consolidated}"; target="${2:-$SCRIPT_DIR/../..}"; [[ "$mode" != --repo ]] || { [[ $# -eq 2 ]] || exit 1; mode=--consolidated; }
case "$mode" in --consolidated|--per-skill|--all) ;; *) echo "Usage: $0 [--consolidated | --per-skill | --all | --repo <path>] [--include-lifecycle <value>]" >&2; exit 1;; esac
projection=$(mktemp); trap 'rm -f "$projection"' EXIT; rows="$(catalog_rows copilot --projection "$projection")" || exit $?; mkdir -p "$target/.github"; mv "$projection" "$target/.github/skills-catalog.json"
consolidated() { local out="$target/.github/copilot-instructions.md" repo_name; repo_name=$(basename "$target"); cat > "$out" <<EOF
# Copilot Instructions — $repo_name

This file contains agent-facing instructions synthesized from the skills library.

EOF
 while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; printf '## %s\n\n' "$name" >> "$out"; while IFS= read -r line; do echo "  $line" >> "$out"; done < <(flattened_skill_body "$SKILLS_DIR/$source/SKILL.md"); echo "" >> "$out"; done <<< "$rows"; }
per_skill() { local out="$target/.github/copilot-instructions" description; mkdir -p "$out"; while IFS=$'\t' read -r name source; do [[ -n "$name" ]] || continue; description=$(skill_description "$SKILLS_DIR/$source/SKILL.md"); { echo "# $name"; echo ''; echo "$description"; echo ''; flattened_skill_body "$SKILLS_DIR/$source/SKILL.md"; } > "$out/$name.md"; done <<< "$rows"; }
if [[ "$mode" == --consolidated || "$mode" == --all ]]; then consolidated; fi
if [[ "$mode" == --per-skill || "$mode" == --all ]]; then per_skill; fi
