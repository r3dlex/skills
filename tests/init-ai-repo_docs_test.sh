#!/bin/bash
#
# Regression tests for ai-catapult-init canonical naming and deprecated alias docs.
# Canonical skill: ai-catapult-init
# Deprecated aliases: init-ai-repo, ai-sdlc-init
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

# --- Canonical skill: ai-catapult-init ---
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "name: ai-catapult-init" "canonical skill frontmatter name"

# Deprecated aliases declared in canonical description
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "init-ai-repo" "canonical skill description mentions init-ai-repo alias"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "ai-sdlc-init" "canonical skill description mentions ai-sdlc-init alias"

# --- Deprecated alias: ai-sdlc-init ---
assert_file_contains 03-configure-generate/ai-sdlc-init/SKILL.md "name: ai-sdlc-init" "legacy shim frontmatter name"
assert_file_contains 03-configure-generate/ai-sdlc-init/SKILL.md "../ai-catapult-init/SKILL.md" "legacy shim points to canonical skill"
assert_file_contains 03-configure-generate/ai-sdlc-init/README.md "../ai-catapult-init/SKILL.md" "legacy shim README points to canonical skill"

# --- Deprecated alias: init-ai-repo ---
assert_file_contains 03-configure-generate/init-ai-repo/SKILL.md "name: init-ai-repo" "init-ai-repo shim frontmatter name"
assert_file_contains 03-configure-generate/init-ai-repo/SKILL.md "../ai-catapult-init/SKILL.md" "init-ai-repo shim points to canonical skill"
assert_file_contains 03-configure-generate/init-ai-repo/README.md "../ai-catapult-init/SKILL.md" "init-ai-repo shim README points to canonical skill"

# --- README catalog ---
assert_file_contains README.md "[\`ai-catapult-init\`](03-configure-generate/ai-catapult-init/SKILL.md)" "README exposes canonical skill name"
assert_file_contains README.md "deprecated compatibility alias" "README documents deprecated alias"

# --- modules/README.md ---
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "canonical \`ai-catapult-init\`" "module README uses canonical name"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "deprecated compatibility path/alias" "module README documents compatibility path"

# --- PR merge gate and CI policy in canonical SKILL.md ---
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "protected \`main\` and PR-only delivery" "skill requires protected main and PR-only delivery"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "provider-specific branch-policy checklist/config artifacts" "skill emits branch-policy checklist/config by default"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "host policy permits it" "skill documents admin self-approval boundary"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "admin approve/admin bypass" "skill documents admin approval lane"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "architect, reviewer, and executor" "skill documents architect/reviewer/executor review loop"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "local CI plus host SCM CI" "skill requires local and host CI green"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "do not merge or auto-merge" "skill gates merge and auto-merge"

# --- ci-policy module ---
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "protected \`main\` and PR-only delivery" "ci-policy assumes protected main and PR-only delivery"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "provider-specific checklists/config templates" "ci-policy emits provider checklist/config artifacts by default"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "hosted policy mutation remains opt-in and explicit" "ci-policy forbids hidden hosted mutation"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "administrators may self-approve PRs" "ci-policy documents admin self-approval"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "host/runtime explicitly supports admin approval" "ci-policy requires explicit host support for admin approval"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "GitHub hosted PR review rejects same-actor approval" "ci-policy documents GitHub same-actor approval limit"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "All actionable PR comments are resolved" "ci-policy requires actionable comments resolved"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "Local CI and host SCM CI" "ci-policy requires local and host CI green"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/ci-policy.md "Auto-merge may be enabled only after" "ci-policy gates auto-merge"

# --- active spec ---
assert_file_contains docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md "4-Phase AI-SDLC" "active spec captures four-phase AI SDLC"
assert_file_contains docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md "admin approval mode" "active spec captures admin approval mode"

# --- Four-phase workflow in canonical SKILL.md ---
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "### Phase 1 — Discover & Decide" "skill exposes phase 1"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "### Phase 2 — Govern & Plan" "skill exposes phase 2"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "### Phase 3 — Configure & Generate" "skill exposes phase 3"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "### Phase 4 — Validate & Handoff" "skill exposes phase 4"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "### Internal checkpoints" "skill preserves internal checkpoints"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md "1. Detect repo state" "skill preserves checkpoint 1"

# --- module README links ---
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "phases/01-discover-decide.md" "module README links phase 1 module"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/phases/README.md "Eight internal checkpoints" "phase README preserves checkpoint mapping"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/phases/01-discover-decide.md ".ai/phases/01-discover-decide/" "phase 1 module emits phase state folder"
assert_file_contains 03-configure-generate/ai-catapult-init/SKILL.md '`modules/cascade.md` — read when generating multi-repo cascade plans' 'skill module map names active cascade module after PR 6D'
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "workflow.md" "module README names active workflow module"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "traceability.md" "module README names active traceability module"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "cascade.md" "module README names active cascade module"
assert_file_contains 03-configure-generate/ai-catapult-init/modules/README.md "skill-modernization.md" "module README names active skill modernization module"

# --- REFERENCE.md ---
assert_file_contains 03-configure-generate/ai-catapult-init/REFERENCE.md "/init-ai-repo" "reference uses legacy invocation path (for reference completeness)"
assert_file_contains 03-configure-generate/ai-catapult-init/REFERENCE.md "four-phase workflow" "reference documents four-phase workflow"
assert_file_contains 03-configure-generate/ai-catapult-init/REFERENCE.md 'Legacy `/ai-sdlc-init` remains an alias/path only' "reference preserves legacy alias"

# --- AGENTS catalog ---
agents_content="$(catalog_agents_content)"
assert_text_contains "$agents_content" "\`ai-catapult-init\`" "AGENTS catalog exposes canonical skill"
assert_text_contains "$agents_content" "deprecated aliases:" "AGENTS catalog preserves deprecated aliases label"
assert_text_contains "$agents_content" "\`init-ai-repo\`" "AGENTS catalog lists init-ai-repo deprecated alias"
assert_text_contains "$agents_content" "\`ai-sdlc-init\`" "AGENTS catalog lists ai-sdlc-init deprecated alias"

if grep -F "only supported" 03-configure-generate/ai-catapult-init/SKILL.md README.md 03-configure-generate/ai-catapult-init/modules/README.md 03-configure-generate/ai-sdlc-init/SKILL.md 03-configure-generate/ai-sdlc-init/README.md 03-configure-generate/init-ai-repo/SKILL.md 03-configure-generate/init-ai-repo/README.md >/dev/null; then
  bad "catalog docs must not imply any alias is the only supported name"
else
  ok "catalog docs do not imply any alias is the only supported name"
fi

if grep -F "repository path remains" README.md AGENTS.md 03-configure-generate/ai-catapult-init/SKILL.md 03-configure-generate/ai-catapult-init/modules/README.md >/dev/null; then
  bad "catalog docs must not claim any deprecated path remains the canonical repository path"
else
  ok "catalog docs use ai-catapult-init as canonical repository path"
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
