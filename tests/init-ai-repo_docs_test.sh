#!/bin/bash
#
# Regression tests for init-ai-repo canonical naming and deprecated alias docs.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if grep -Fq "$needle" "$file"; then ok "$label"; else bad "$label (missing: $needle)"; fi
}

assert_text_contains() {
  local text="$1" needle="$2" label="$3"
  if grep -Fq "$needle" <<< "$text"; then ok "$label"; else bad "$label (missing: $needle)"; fi
}

catalog_agents_content() {
  cd "$REPO_ROOT"
  local flag
  flag="$(git ls-files -v AGENTS.md 2>/dev/null | awk '{print $1}' || true)"
  if [[ "$flag" == "S" ]]; then
    git cat-file -p :AGENTS.md
  else
    cat AGENTS.md
  fi
}

cd "$REPO_ROOT"

assert_file_contains init-ai-repo/SKILL.md "name: init-ai-repo" "canonical skill frontmatter name"
assert_file_contains ai-sdlc-init/SKILL.md "name: ai-sdlc-init" "legacy shim frontmatter name"
assert_file_contains ai-sdlc-init/SKILL.md "../init-ai-repo/SKILL.md" "legacy shim points to canonical skill"
assert_file_contains ai-sdlc-init/README.md "../init-ai-repo/SKILL.md" "legacy shim README points to canonical skill"
assert_file_contains init-ai-repo/SKILL.md "Deprecated compatibility alias: ai-sdlc-init" "deprecated alias in skill description"
assert_file_contains README.md "[\`init-ai-repo\`](init-ai-repo/SKILL.md)" "README exposes canonical skill name"
assert_file_contains README.md "deprecated compatibility alias" "README documents deprecated alias"
assert_file_contains init-ai-repo/modules/README.md "canonical \`init-ai-repo\`" "module README uses canonical name"
assert_file_contains init-ai-repo/modules/README.md "deprecated compatibility path/alias" "module README documents compatibility path"
assert_file_contains init-ai-repo/SKILL.md "protected \`main\` and PR-only delivery" "skill requires protected main and PR-only delivery"
assert_file_contains init-ai-repo/SKILL.md "provider-specific branch-policy checklist/config artifacts" "skill emits branch-policy checklist/config by default"
assert_file_contains init-ai-repo/SKILL.md "host policy permits it" "skill documents admin self-approval boundary"
assert_file_contains init-ai-repo/SKILL.md "admin approve/admin bypass" "skill documents admin approval lane"
assert_file_contains init-ai-repo/SKILL.md "architect, reviewer, and executor" "skill documents architect/reviewer/executor review loop"
assert_file_contains init-ai-repo/SKILL.md "local CI plus host SCM CI" "skill requires local and host CI green"
assert_file_contains init-ai-repo/SKILL.md "do not merge or auto-merge" "skill gates merge and auto-merge"
assert_file_contains init-ai-repo/modules/ci-policy.md "protected \`main\` and PR-only delivery" "ci-policy assumes protected main and PR-only delivery"
assert_file_contains init-ai-repo/modules/ci-policy.md "provider-specific checklists/config templates" "ci-policy emits provider checklist/config artifacts by default"
assert_file_contains init-ai-repo/modules/ci-policy.md "hosted policy mutation remains opt-in and explicit" "ci-policy forbids hidden hosted mutation"
assert_file_contains init-ai-repo/modules/ci-policy.md "administrators may self-approve PRs" "ci-policy documents admin self-approval"
assert_file_contains init-ai-repo/modules/ci-policy.md "host/runtime explicitly supports admin approval" "ci-policy requires explicit host support for admin approval"
assert_file_contains init-ai-repo/modules/ci-policy.md "GitHub hosted PR review rejects same-actor approval" "ci-policy documents GitHub same-actor approval limit"
assert_file_contains init-ai-repo/modules/ci-policy.md "All actionable PR comments are resolved" "ci-policy requires actionable comments resolved"
assert_file_contains init-ai-repo/modules/ci-policy.md "Local CI and host SCM CI" "ci-policy requires local and host CI green"
assert_file_contains init-ai-repo/modules/ci-policy.md "Auto-merge may be enabled only after" "ci-policy gates auto-merge"
assert_file_contains docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md "4-Phase AI-SDLC" "active spec captures four-phase AI SDLC"
assert_file_contains docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md "admin approval mode" "active spec captures admin approval mode"
assert_file_contains init-ai-repo/SKILL.md "### Phase 1 — Discover & Decide" "skill exposes phase 1"
assert_file_contains init-ai-repo/SKILL.md "### Phase 2 — Govern & Plan" "skill exposes phase 2"
assert_file_contains init-ai-repo/SKILL.md "### Phase 3 — Configure & Generate" "skill exposes phase 3"
assert_file_contains init-ai-repo/SKILL.md "### Phase 4 — Validate & Handoff" "skill exposes phase 4"
assert_file_contains init-ai-repo/SKILL.md "### Internal checkpoints" "skill preserves internal checkpoints"
assert_file_contains init-ai-repo/SKILL.md "1. Detect repo state" "skill preserves checkpoint 1"
assert_file_contains init-ai-repo/modules/README.md "phases/01-discover-decide.md" "module README links phase 1 module"
assert_file_contains init-ai-repo/modules/phases/README.md "Eight internal checkpoints" "phase README preserves checkpoint mapping"
assert_file_contains init-ai-repo/modules/phases/01-discover-decide.md ".ai/phases/01-discover-decide/" "phase 1 module emits phase state folder"
assert_file_contains init-ai-repo/SKILL.md '`modules/cascade.md` — read when generating multi-repo cascade plans' 'skill module map names active cascade module after PR 6D'
assert_file_contains init-ai-repo/modules/README.md "workflow.md" "module README names active workflow module"
assert_file_contains init-ai-repo/modules/README.md "traceability.md" "module README names active traceability module"
assert_file_contains init-ai-repo/modules/README.md "cascade.md" "module README names active cascade module"
assert_file_contains init-ai-repo/modules/README.md "skill-modernization.md" "module README names active skill modernization module"
assert_file_contains init-ai-repo/REFERENCE.md "/init-ai-repo" "reference uses canonical invocation"
assert_file_contains init-ai-repo/REFERENCE.md "four-phase workflow" "reference documents four-phase workflow"
assert_file_contains init-ai-repo/REFERENCE.md 'Legacy `/ai-sdlc-init` remains an alias/path only' "reference preserves legacy alias"

agents_content="$(catalog_agents_content)"
assert_text_contains "$agents_content" "\`init-ai-repo\`" "AGENTS catalog exposes canonical skill"
assert_text_contains "$agents_content" "deprecated alias: \`ai-sdlc-init\`" "AGENTS catalog preserves deprecated alias"

if grep -F "only supported" init-ai-repo/SKILL.md README.md init-ai-repo/modules/README.md ai-sdlc-init/SKILL.md ai-sdlc-init/README.md >/dev/null; then
  bad "catalog docs must not imply ai-sdlc-init is the only supported name"
else
  ok "catalog docs do not imply ai-sdlc-init is the only supported name"
fi

if grep -F "repository path remains" README.md AGENTS.md init-ai-repo/SKILL.md init-ai-repo/modules/README.md >/dev/null; then
  bad "catalog docs must not claim ai-sdlc-init remains the canonical repository path"
else
  ok "catalog docs use init-ai-repo as canonical repository path"
fi

# --- P0-2: this repo's CLAUDE.md is a thin pointer to AGENTS.md (ADR-0004) ---
assert_file_contains CLAUDE.md "AGENTS.md" "repo CLAUDE.md points to AGENTS.md"
if grep -Eq '^## ' CLAUDE.md; then
  bad "repo CLAUDE.md is a pointer (no '^##' content sections)"
else
  ok "repo CLAUDE.md is a pointer (no '^##' content sections)"
fi
if grep -Fq "docs/adr/" CLAUDE.md; then
  bad "repo CLAUDE.md contains no stale docs/adr/ link"
else
  ok "repo CLAUDE.md contains no stale docs/adr/ link"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
