#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."; fixture="$PWD/tests/fixtures/catalog-lifecycle"
run() { local home=$1; shift; HOME="$home" SKILLS_CATALOG_ROOT="$fixture" bash "$@" >/dev/null; }
assert_projection() { python3 - "$1" "$2" <<'PY'
import json,sys
assert [e['name'] for e in json.load(open(sys.argv[1]))['skills']] == sys.argv[2].split(',')
PY
}
for order in 'experimental deprecated' 'deprecated experimental'; do
 read -r first second <<< "$order"
 for host in codex claude gemini auggie copilot; do
  tmp=$(mktemp -d); args=(--include-lifecycle "$first" --include-lifecycle "$second")
  case $host in
   codex) run "$tmp" scripts/install-codex.sh --all "${args[@]}"; catpath="$tmp/.codex/skills/catalog.json";;
   claude) run "$tmp" scripts/install-claude-code.sh --user "${args[@]}"; catpath="$tmp/.claude/skills/omc-learned/catalog.json";;
   gemini) run "$tmp" scripts/install-gemini.sh --link "${args[@]}"; catpath="$tmp/.gemini/skills/catalog.json";;
   auggie) run "$tmp" scripts/install-auggie.sh --all "${args[@]}"; catpath="$tmp/.auggie/rules/catalog.json";;
   copilot) target="$tmp/repo"; run "$tmp" scripts/install-copilot.sh --repo "$target" "${args[@]}"; catpath="$target/.github/skills-catalog.json";;
  esac
  assert_projection "$catpath" 'deprecated-skill,experimental-skill,stable-skill'; rm -rf "$tmp"
 done
done
# Explicit installation is lifecycle-gated; failure is exit 2 before destination creation.
tmp=$(mktemp -d); set +e
HOME="$tmp" SKILLS_CATALOG_ROOT="$fixture" bash scripts/install-codex.sh --skill experimental-skill >/dev/null 2>&1; rc=$?
set -e; [[ $rc -eq 2 && ! -e "$tmp/.codex" ]]
run "$tmp" scripts/install-codex.sh --skill experimental-skill --include-lifecycle experimental
assert_projection "$tmp/.codex/skills/catalog.json" experimental-skill
# Unknown and missing lifecycle values fail before writes for every installer.
for script in install-codex.sh install-claude-code.sh install-gemini.sh install-auggie.sh install-copilot.sh; do
 for bad in unknown __missing__; do
  tmp=$(mktemp -d); set +e
  if [[ $bad == __missing__ ]]; then HOME="$tmp" SKILLS_CATALOG_ROOT="$fixture" bash "scripts/$script" --include-lifecycle >/dev/null 2>&1
  else HOME="$tmp" SKILLS_CATALOG_ROOT="$fixture" bash "scripts/$script" --include-lifecycle "$bad" >/dev/null 2>&1; fi
  rc=$?; set -e; [[ $rc -eq 2 ]]; [[ -z "$(find "$tmp" -mindepth 1 -print -quit)" ]]; rm -rf "$tmp"
 done
done
