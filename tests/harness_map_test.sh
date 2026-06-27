#!/bin/bash
#
# harness_map_test.sh  (P1-3)
#
# Asserts the generated AGENTS.md fixtures carry a six-context **Harness Map**
# enumerating all six context types — Instructions, Knowledge, Memory,
# Examples, Tools, Guardrails — AND a documented static-vs-dynamic context
# boundary (ADR-0005, spec §4.B.5).
#
# Offline, deterministic, keyword + structural — no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

CONTEXT_TYPES=(Instructions Knowledge Memory Examples Tools Guardrails)

# ---------------------------------------------------------------------------
# (a) Both generated AGENTS.md fixtures carry a Harness Map block enumerating
#     all six context types and a documented static/dynamic boundary.
# ---------------------------------------------------------------------------
for variant in standalone umbrella; do
  f="reference/fixtures/v3/$variant/AGENTS.md"

  if [[ -f "$f" ]]; then
    ok "fixture $variant/AGENTS.md exists"
  else
    bad "fixture $variant/AGENTS.md exists"
    continue
  fi

  # Extract the `## Harness Map` section (from the heading up to the next
  # top-level `## ` heading) so a keyword mentioned elsewhere cannot pass.
  section="$(awk '
    /^## Harness Map/ {inblock=1; next}
    inblock && /^## /  {inblock=0}
    inblock            {print}
  ' "$f")"

  if [[ -n "$section" ]]; then
    ok "fixture $variant/AGENTS.md has a '## Harness Map' section"
  else
    bad "fixture $variant/AGENTS.md has a '## Harness Map' section"
    continue
  fi

  # All six context types must appear, code-fenced, inside the section.
  for ctx in "${CONTEXT_TYPES[@]}"; do
    if printf '%s\n' "$section" | grep -Eq "\`$ctx\`"; then
      ok "fixture $variant/AGENTS.md Harness Map enumerates $ctx"
    else
      bad "fixture $variant/AGENTS.md Harness Map enumerates $ctx"
    fi
  done

  # The static-vs-dynamic context boundary must be documented in the section.
  if printf '%s\n' "$section" | grep -Eiq 'static'; then
    ok "fixture $variant/AGENTS.md Harness Map documents 'static' context"
  else
    bad "fixture $variant/AGENTS.md Harness Map documents 'static' context"
  fi
  if printf '%s\n' "$section" | grep -Eiq 'dynamic'; then
    ok "fixture $variant/AGENTS.md Harness Map documents 'dynamic' context"
  else
    bad "fixture $variant/AGENTS.md Harness Map documents 'dynamic' context"
  fi
  # The boundary must be framed as an explicit boundary, not just two words.
  if printf '%s\n' "$section" | grep -Eiq 'boundary'; then
    ok "fixture $variant/AGENTS.md Harness Map frames a static/dynamic boundary"
  else
    bad "fixture $variant/AGENTS.md Harness Map frames a static/dynamic boundary"
  fi
done

# ---------------------------------------------------------------------------
# (b) The blueprint module carries the Harness Map generation rule, so the
#     generated AGENTS.md is guaranteed to emit it.
# ---------------------------------------------------------------------------
blueprint="init-ai-repo/modules/documentation-blueprint.md"
if grep -Fq "Harness Map" "$blueprint"; then
  ok "documentation-blueprint.md carries the Harness Map generation rule"
else
  bad "documentation-blueprint.md carries the Harness Map generation rule"
fi
for ctx in "${CONTEXT_TYPES[@]}"; do
  if grep -Eq "\`$ctx\`" "$blueprint"; then
    ok "documentation-blueprint.md Harness Map rule names $ctx"
  else
    bad "documentation-blueprint.md Harness Map rule names $ctx"
  fi
done
if grep -Eiq 'static.{0,40}dynamic|dynamic.{0,40}static' "$blueprint"; then
  ok "documentation-blueprint.md documents the static/dynamic boundary rule"
else
  bad "documentation-blueprint.md documents the static/dynamic boundary rule"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
