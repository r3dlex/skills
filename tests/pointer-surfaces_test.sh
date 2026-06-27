#!/bin/bash
#
# P0-2 regression: AGENTS.md is the single source; CLAUDE.md / GEMINI.md are
# thin pointers to AGENTS.md with no content-bearing sections. Workflow links
# live on AGENTS.md + README.md only (ADR-0004, plan D3).
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# (a) Generated/fixture CLAUDE.md and GEMINI.md are pointers to AGENTS.md and
#     contain zero `^##` content sections.
# ---------------------------------------------------------------------------
for variant in standalone umbrella; do
  for surface in CLAUDE.md GEMINI.md; do
    f="reference/fixtures/v3/$variant/$surface"
    if [[ -f "$f" ]]; then
      ok "fixture $variant/$surface exists"
    else
      bad "fixture $variant/$surface exists"
      continue
    fi
    if grep -Fq "AGENTS.md" "$f"; then
      ok "fixture $variant/$surface points to AGENTS.md"
    else
      bad "fixture $variant/$surface points to AGENTS.md"
    fi
    if grep -Eq '^## ' "$f"; then
      bad "fixture $variant/$surface has zero '^##' content sections"
    else
      ok "fixture $variant/$surface has zero '^##' content sections"
    fi
    # A thin pointer must not itself link the workflow files.
    if grep -Fq "repo-workflow" "$f"; then
      bad "fixture $variant/$surface is a pointer (no workflow links)"
    else
      ok "fixture $variant/$surface is a pointer (no workflow links)"
    fi
  done
done

# ---------------------------------------------------------------------------
# (b) Grep regression across the contradiction modules: CLAUDE.md must no
#     longer appear adjacent to "link"/"workflow"/"surface". Each module must
#     name only AGENTS.md + README.md as the workflow-linking surfaces.
# ---------------------------------------------------------------------------
modules=(
  "init-ai-repo/modules/validation.md"
  "init-ai-repo/modules/workflow.md"
  "init-ai-repo/modules/documentation-blueprint.md"
)

for m in "${modules[@]}"; do
  # Fail if CLAUDE.md is enumerated alongside AGENTS.md/README.md AS a
  # workflow-linking entry surface. The contradiction phrasing puts CLAUDE.md
  # between AGENTS.md and README.md inside the link enumeration
  # ("`AGENTS.md`, `CLAUDE.md`, and `README.md` ... link to ... workflow").
  # The legitimate "required entry files" enumeration
  # ("`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, ...") and the
  # explicit "CLAUDE.md is a thin pointer" disclaimers are allowed.
  if grep -Eq '`AGENTS\.md`, `CLAUDE\.md`,? and `README\.md`' "$m"; then
    bad "$m: CLAUDE.md not enumerated as a workflow-linking surface"
    grep -En '`AGENTS\.md`, `CLAUDE\.md`,? and `README\.md`' "$m" | sed 's/^/      offending: /'
  else
    ok "$m: CLAUDE.md not enumerated as a workflow-linking surface"
  fi
done

# Each module now names the AGENTS.md + README.md workflow-linking contract.
if grep -Fq 'generated `AGENTS.md` and `README.md` link to both workflow files.' init-ai-repo/modules/validation.md; then
  ok "validation.md names AGENTS.md + README.md as workflow surfaces"
else
  bad "validation.md names AGENTS.md + README.md as workflow surfaces"
fi
if grep -Fq 'Generated `AGENTS.md` and `README.md` surfaces must link to both the workflow doc and the manifest' init-ai-repo/modules/workflow.md; then
  ok "workflow.md names AGENTS.md + README.md as workflow surfaces"
else
  bad "workflow.md names AGENTS.md + README.md as workflow surfaces"
fi
if grep -Fq 'Generated `AGENTS.md` and `README.md` link to `.ai/workflows/repo-workflow.md`' init-ai-repo/modules/documentation-blueprint.md; then
  ok "documentation-blueprint.md names AGENTS.md + README.md as workflow surfaces"
else
  bad "documentation-blueprint.md names AGENTS.md + README.md as workflow surfaces"
fi

# GEMINI.md is introduced as a new pointer surface in the blueprint tree + rules.
if grep -Fq "GEMINI.md" init-ai-repo/modules/documentation-blueprint.md; then
  ok "documentation-blueprint.md introduces GEMINI.md pointer surface"
else
  bad "documentation-blueprint.md introduces GEMINI.md pointer surface"
fi

# Generated fixture workflow docs must not enumerate CLAUDE.md as a surface that
# links workflow files (the original contradiction phrasing).
for variant in standalone umbrella; do
  wf="reference/fixtures/v3/$variant/.ai/workflows/repo-workflow.md"
  if grep -Eq '`AGENTS\.md`, `CLAUDE\.md`,? and `README\.md`' "$wf"; then
    bad "fixture $variant workflow doc drops CLAUDE.md from entry-surface link list"
  else
    ok "fixture $variant workflow doc drops CLAUDE.md from entry-surface link list"
  fi
done

# entry_surfaces in fixture manifests no longer list CLAUDE.md.
for variant in standalone umbrella; do
  if python3 - "$variant" <<'PY'
import json, sys
variant = sys.argv[1]
m = json.load(open(f"reference/fixtures/v3/{variant}/.ai/workflows/repo-workflow.json"))
es = m["entry_surfaces"]
assert "CLAUDE.md" not in es, es
assert "AGENTS.md" in es and "README.md" in es, es
PY
  then
    ok "fixture $variant entry_surfaces drops CLAUDE.md (AGENTS.md + README.md only)"
  else
    bad "fixture $variant entry_surfaces drops CLAUDE.md (AGENTS.md + README.md only)"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
