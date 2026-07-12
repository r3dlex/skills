#!/bin/bash
#
# TDD check: assert post-rename invariants for ai-catapult-init.
#
# (a) ai-catapult-init exists and is the canonical skill (name: ai-catapult-init)
# (b) init-ai-repo is a deprecated alias pointing to ../ai-catapult-init/SKILL.md
# (c) ai-sdlc-init is a deprecated alias pointing to ../ai-catapult-init/SKILL.md
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if [[ -f "$file" ]] && grep -Fq "$needle" "$file"; then ok "$label"; else bad "$label (file=$file missing: $needle)"; fi
}

assert_file_exists() {
  local file="$1" label="$2"
  if [[ -f "$file" ]]; then ok "$label"; else bad "$label (missing: $file)"; fi
}

# (a) ai-catapult-init is the canonical skill
assert_file_exists  "03-configure-generate/ai-catapult-init/SKILL.md"              "03-configure-generate/ai-catapult-init/SKILL.md exists"
assert_file_contains "03-configure-generate/ai-catapult-init/SKILL.md" "name: ai-catapult-init" "ai-catapult-init canonical frontmatter name"

# Canonical skill mentions both deprecated aliases in its description
assert_file_contains "03-configure-generate/ai-catapult-init/SKILL.md" "init-ai-repo"   "ai-catapult-init description mentions init-ai-repo alias"
assert_file_contains "03-configure-generate/ai-catapult-init/SKILL.md" "ai-sdlc-init"   "ai-catapult-init description mentions ai-sdlc-init alias"

# (b) init-ai-repo is a deprecated alias -> ai-catapult-init
assert_file_exists  "03-configure-generate/init-ai-repo/SKILL.md"                   "03-configure-generate/init-ai-repo/SKILL.md exists (alias)"
assert_file_contains "03-configure-generate/init-ai-repo/SKILL.md" "name: init-ai-repo" "init-ai-repo alias frontmatter name preserved"
assert_file_contains "03-configure-generate/init-ai-repo/SKILL.md" "../ai-catapult-init/SKILL.md" "init-ai-repo alias points to ai-catapult-init"
assert_file_contains "03-configure-generate/init-ai-repo/README.md" "../ai-catapult-init/SKILL.md" "init-ai-repo README points to ai-catapult-init"

# (c) ai-sdlc-init is a deprecated alias -> ai-catapult-init
assert_file_exists  "03-configure-generate/ai-sdlc-init/SKILL.md"                   "03-configure-generate/ai-sdlc-init/SKILL.md exists (alias)"
assert_file_contains "03-configure-generate/ai-sdlc-init/SKILL.md" "name: ai-sdlc-init" "ai-sdlc-init alias frontmatter name preserved"
assert_file_contains "03-configure-generate/ai-sdlc-init/SKILL.md" "../ai-catapult-init/SKILL.md" "ai-sdlc-init alias points to ai-catapult-init"
assert_file_contains "03-configure-generate/ai-sdlc-init/README.md" "../ai-catapult-init/SKILL.md" "ai-sdlc-init README points to ai-catapult-init"

# Old canonical must NOT still claim to be canonical
if grep -Fq "name: init-ai-repo" "03-configure-generate/ai-catapult-init/SKILL.md" 2>/dev/null; then
  bad "03-configure-generate/ai-catapult-init/SKILL.md must not have name: init-ai-repo (it is the new canonical)"
else
  ok "03-configure-generate/ai-catapult-init/SKILL.md does not have stale name: init-ai-repo"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
