#!/bin/bash
#
# adr_path_test.sh
#
# P0-3 regression guard: the v3 layout stores ADRs under `docs/architecture/adr/`.
# Any tracked file that links to a BARE legacy `docs/adr/` path (i.e. not the v3
# `docs/architecture/adr/` path) is a stale reference and must be swept — UNLESS
# it is on the frozen exclusion allowlist baked into this script below.
#
# Scope rules:
#   - Operates on `git ls-files` only, so untracked operational artifacts
#     (e.g. `.omx/state/sessions/*`) are out of scope by construction.
#   - "Bare `docs/adr/`" is matched with a regex that does NOT match the v3
#     `docs/architecture/adr/` path (the leading `architecture/` disqualifies it).
#   - Files physically under `docs/architecture/` are exempt: that subtree is the
#     v3 ADR home, and its files (e.g. ADR-0004) legitimately quote the legacy
#     path while documenting the migration.
#
# The allowlist is intentionally a frozen, path-based set (not prose / not a
# heuristic). Each entry is justified inline. Only TRULY-LEGACY, intentional
# references are excluded:
#   - the legacy-source column of the migration mapping,
#   - the still-physical legacy `docs/adr/` directory in this repo and its golden
#     mirrors (these are content-diffed verbatim by scripts/verify-golden-dir.sh
#     against this repo's real `docs/adr/` tree, which has not yet been migrated),
#   - the legacy-migration fixture that intentionally models a legacy source,
#   - REFERENCE.md / foundation.md legacy template bodies that mirror that same
#     still-physical `docs/adr/` artifact set,
#   - the spec and this test, which quote the stale link as the thing they govern,
#   - generic skill prose that teaches the conventional `docs/adr/` location for
#     ARBITRARY target repos (not this repo's concrete v3 layout).
#
# Exit 0 when no un-allowlisted bare `docs/adr/` references remain; non-zero otherwise.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# -----------------------------------------------------------------------------
# Frozen exclusion allowlist (baked-in, path-based). See header for rationale.
# -----------------------------------------------------------------------------
is_allowlisted() {
  case "$1" in
    # Legacy-source column of the migration mapping table (docs/adr -> v3).
    ai-catapult-init/modules/migration.md) return 0 ;;
    # Blueprint defers `docs/adr/` legacy-artifact classification to migration.md.
    ai-catapult-init/modules/documentation-blueprint.md) return 0 ;;

    # Still-physical legacy ADR directory in this repo (not yet migrated) and its
    # verbatim golden mirrors — content-diffed by scripts/verify-golden-dir.sh.
    docs/adr/*) return 0 ;;
    reference/golden-root/docs/adr/*) return 0 ;;
    reference/golden-skills/docs/adr/*) return 0 ;;
    scripts/verify-golden-dir.sh) return 0 ;;

    # Legacy template bodies that mirror the still-physical `docs/adr/` artifacts.
    ai-catapult-init/REFERENCE.md) return 0 ;;
    ai-catapult-init/modules/foundation.md) return 0 ;;

    # Fixture that intentionally models a legacy `docs/adr/` SOURCE being copied to v3.
    reference/fixtures/v3/legacy-migration/README.md) return 0 ;;
    reference/fixtures/v3/legacy-migration/migration-manifest.json) return 0 ;;

    # Spec + tests quote the stale link as the subject they govern.
    docs/specifications/ACTIVE/init-ai-repo-agentic-engineering-end-state.md) return 0 ;;
    tests/init-ai-repo_docs_test.sh) return 0 ;;
    tests/adr_path_test.sh) return 0 ;;

    # Generic skill prose teaching the conventional ADR location for ARBITRARY repos.
    grill-with-docs/ADR-FORMAT.md) return 0 ;;
    grill-with-docs/SKILL.md) return 0 ;;
    setup-skills/SKILL.md) return 0 ;;
    setup-skills/domain.md) return 0 ;;
  esac
  return 1
}

# Match a BARE legacy `docs/adr/` reference but NOT the v3 `docs/architecture/adr/`.
BARE_ADR_RE='(^|[^/])docs/adr/'

echo "ADR Path Sweep Test (P0-3)"
echo "=========================="
echo ""

# -----------------------------------------------------------------------------
# 1) Repo-wide guard: no un-allowlisted bare `docs/adr/` in tracked files.
# -----------------------------------------------------------------------------
violations=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # Exempt the v3 ADR home subtree.
  case "$f" in
    docs/architecture/*) continue ;;
  esac
  if grep -aqE "$BARE_ADR_RE" "$f" 2>/dev/null; then
    if is_allowlisted "$f"; then
      continue
    fi
    echo "  STALE: $f still links to a bare 'docs/adr/' (expected 'docs/architecture/adr/')"
    grep -anE "$BARE_ADR_RE" "$f" 2>/dev/null | sed 's/^/    /'
    violations=$((violations + 1))
  fi
done < <(git ls-files)

if [ "$violations" -eq 0 ]; then
  ok "no un-allowlisted bare 'docs/adr/' references in tracked files"
else
  bad "$violations tracked file(s) carry a stale bare 'docs/adr/' reference"
fi

# -----------------------------------------------------------------------------
# 2) AGENTS.md: the AI SDLC Methodology / ADR section points at the v3 path,
#    not the bare legacy path. Located by content, not by line number.
# -----------------------------------------------------------------------------
adr_line="$(grep -nE 'Significant architectural decisions are recorded in' AGENTS.md | head -n1 | cut -d: -f1 || true)"
if [ -z "$adr_line" ]; then
  bad "AGENTS.md ADR section anchor ('Significant architectural decisions are recorded in') not found"
else
  adr_text="$(sed -n "${adr_line}p" AGENTS.md)"
  if grep -qF 'docs/architecture/adr/' <<< "$adr_text"; then
    ok "AGENTS.md ADR section links docs/architecture/adr/"
  else
    bad "AGENTS.md ADR section does not link docs/architecture/adr/"
  fi
  if grep -qE "$BARE_ADR_RE" <<< "$adr_text"; then
    bad "AGENTS.md ADR section still carries a bare docs/adr/ link"
  else
    ok "AGENTS.md ADR section has no bare docs/adr/ link"
  fi
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
