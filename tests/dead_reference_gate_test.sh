#!/bin/bash
#
# dead_reference_gate_test.sh — grep gate for removed/dead skill references.
#
# Identity-aware: counts only references that name the skill as a catalog
# identity — backticked names, `$name` invocations, `--skill name`, and
# `name/SKILL.md` path-style links. Prose verbs (unbackticked) never count.
#
# Fails when:
#   1. an identity reference appears in a file NOT covered by the name's
#      allowlist, or
#   2. an allowlist entry matches ZERO files in the corpus (stale exclusion —
#      the content it once protected is gone; re-justify or drop it).
#
# Every allowlist entry carries a why-comment. Exclusions are reviewed with the
# same discipline as code; the zero-match check keeps them honest.
#
# Usage: dead_reference_gate_test.sh [corpus-root]
#   corpus-root defaults to the skills repo root. Consumers (e.g. ai-catapult's
#   wired gate) may pass their own root.
# Exit 0 on pass; 1 on any failure.

set -uo pipefail
CORPUS="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$CORPUS" || exit 1

FAIL=0
note() { echo "  $1"; }

# identity_matches <name> — grep for the name as a catalog identity:
#   `name` (backticked) | "name" (JSON/catalog string) | $name (shell
#   invocation) | name/SKILL.md (path link) | --skill name | --skill=name
identity_matches() {
  local name="$1"
  grep -rIE --exclude-dir=.git --exclude-dir=graphify-out --exclude-dir=node_modules \
    "(\\\`$name\\\`|\"$name\"|(name|triggers):[[:space:]]*$name\\b|^[[:space:]]*-[[:space:]]+$name[[:space:]]*$|\\\$$(echo "$name" | tr -d '-')\\b|$name/SKILL\\.md|--skill[= ]$name\\b)" \
    . 2>/dev/null | cut -d: -f1 | sort -u
}

# scan <name> [allowed-glob ...]
scan() {
  local name="$1"
  local -a allow=("${@:2}")
  local hits
  hits="$(identity_matches "$name")"
  local file allowed
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    allowed=0
    for allowed_path in "${allow[@]}"; do
      # shellcheck disable=SC2254
      case "$file" in
        $allowed_path) allowed=1; break ;;
      esac
    done
    if [[ "$allowed" -eq 0 ]]; then
      note "VIOLATION: '$name' referenced as skill identity (not allowlisted): $file"
      FAIL=1
    fi
  done <<< "$hits"
  # stale-exclusion check: every allowlist entry must match >=1 hit file — a
  # zero-match entry is a dead shield (its protected content is gone), so the
  # entry must be re-justified against the current tree or dropped.
  local any
  for allowed_path in "${allow[@]}"; do
    any=0
    while IFS= read -r file; do
      [[ -z "$file" ]] && continue
      # shellcheck disable=SC2254
      case "$file" in
        $allowed_path) any=1; break ;;
      esac
    done <<< "$hits"
    if [[ "$any" -eq 0 ]]; then
      note "VIOLATION: allowlist entry '$allowed_path' for '$name' matches zero files — re-justify or drop it"
      FAIL=1
    fi
  done
}

# --- denylist ----------------------------------------------------------------

# resolving-merge-conflicts: lifecycle deprecated (cleanup 2026-10-01); dropped
#   from default bundles. Allowed only in: its own deprecated SKILL.md (vendored-
#   pin-compat notice), generated all-lifecycle surfaces (README/AGENTS/phase
#   docs), the catalog, the ask-ai-catapult router inventory (generated), the
#   committed audit artifact, and the gate itself (its denylist declares the
#   name).
scan "resolving-merge-conflicts" \
  "./04-validate-handoff/resolving-merge-conflicts/*" \
  "./04-validate-handoff/README.md" \
  "./README.md" \
  "./AGENTS.md" \
  "./catalog.json" \
  "./01-discover-decide/ask-ai-catapult/*" \
  "./.ai/skills/*" \
  "./tests/dead_reference_gate_test.sh"

# diagnose: deprecated alias of diagnosing-bugs (cleanup 2026-10-01). Allowed
#   only in its own deprecated SKILL.md, generated all-lifecycle surfaces, the
#   router inventory (generated), readme-generate fixtures exercising the
#   generator with the name, migration/spec history, the audit artifact, and
#   the gate itself.
scan "diagnose" \
  "./04-validate-handoff/diagnose/*" \
  "./04-validate-handoff/README.md" \
  "./README.md" \
  "./AGENTS.md" \
  "./catalog.json" \
  "./01-discover-decide/ask-ai-catapult/*" \
  "./tests/readme-generate_test.sh" \
  "./docs/migration/*" \
  "./docs/specifications/*" \
  "./.ai/skills/*" \
  "./reference/fixtures/*" \
  "./tests/dead_reference_gate_test.sh"

# edit-article: supported_hosts [] (cleanup 2026-10-01) — retained as docs only.
#   Allowed in its own SKILL.md (frontmatter name/triggers), generated
#   all-lifecycle surfaces, the router inventory (generated), migration
#   history, the audit artifact, and the gate itself.
scan "edit-article" \
  "./03-configure-generate/edit-article/*" \
  "./03-configure-generate/README.md" \
  "./README.md" \
  "./AGENTS.md" \
  "./catalog.json" \
  "./01-discover-decide/ask-ai-catapult/*" \
  "./docs/migration/*" \
  "./.ai/skills/*" \
  "./reference/fixtures/*" \
  "./tests/dead_reference_gate_test.sh"

# ubiquitous-language: deleted outright (cleanup 2026-10-01). No live reference
#   allowed; only migration history (recorded before deletion), the pre-cleanup
#   audit snapshots inside reference fixtures, and the gate itself (denylist
#   declaration) may name it.
scan "ubiquitous-language" \
  "./docs/migration/*" \
  "./reference/fixtures/*" \
  "./tests/interview_decomposition_test.sh" \
  "./tests/dead_reference_gate_test.sh"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
  echo "dead_reference_gate_test: PASSED"
else
  echo "dead_reference_gate_test: FAILED"
fi
echo "Results: PASS=1 FAIL=$FAIL (gate verdict as a single assertion)"
exit "$FAIL"
