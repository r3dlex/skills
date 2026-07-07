#!/bin/bash
#
# lib-skill-discovery_test.sh
#
# Unit tests for scripts/lib-skill-discovery.sh — the shared skill-discovery
# seam sourced by the five installers. Covers:
#   - is_excluded_dir membership against the centralized exclusion list
#   - list_skills skips dirs without SKILL.md
#   - list_skills skips excluded dirs (even when they contain a SKILL.md)
#   - list_skills emits the expected skill set for a fixture tree
#   - frontmatter helpers (description reader, frontmatter strip)
#   - parity: on the live repo, list_skills matches the legacy inline
#     skip-list logic the installers used before the extraction
#
# Offline, deterministic. Fixture tree lives in a mktemp dir, never the repo.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_ROOT/scripts/lib-skill-discovery.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$LIB" ]]; then
  bad "lib-skill-discovery.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# shellcheck source=/dev/null
. "$LIB"

# --- is_excluded_dir ---------------------------------------------------------
for name in .claude .omc .agents .ai .memory .github scripts raw tests docs reference; do
  if is_excluded_dir "$name"; then
    ok "is_excluded_dir excludes '$name'"
  else
    bad "is_excluded_dir should exclude '$name'"
  fi
done

for name in tdd northstar autobahn some-new-skill; do
  if is_excluded_dir "$name"; then
    bad "is_excluded_dir should NOT exclude '$name'"
  else
    ok "is_excluded_dir keeps '$name'"
  fi
done

# --- fixture tree ------------------------------------------------------------
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/skill-alpha" "$fixture/skill-beta" "$fixture/not-a-skill" \
         "$fixture/scripts" "$fixture/docs" "$fixture/raw" "$fixture/tests"

cat > "$fixture/skill-alpha/SKILL.md" << 'EOF'
---
name: skill-alpha
description: >-
  Alpha fixture skill description
---

# skill-alpha

Alpha body line.
EOF

cat > "$fixture/skill-beta/SKILL.md" << 'EOF'
---
name: skill-beta
description: >-
  Beta fixture skill description
---

# skill-beta
EOF

# Excluded dirs that DO contain a SKILL.md must still be skipped.
echo "# decoy" > "$fixture/scripts/SKILL.md"
echo "# decoy" > "$fixture/docs/SKILL.md"
echo "# decoy" > "$fixture/raw/SKILL.md"
echo "# decoy" > "$fixture/tests/SKILL.md"
# Dir without SKILL.md must be skipped.
echo "readme" > "$fixture/not-a-skill/README.md"
# Stray root-level file must be ignored (list_skills walks dirs only).
echo "stray" > "$fixture/stray-file.md"

expected=$'skill-alpha\nskill-beta'
actual="$(list_skills "$fixture")"
if [[ "$actual" == "$expected" ]]; then
  ok "list_skills emits expected skill set for fixture tree"
else
  bad "list_skills fixture set mismatch (got: $(echo "$actual" | tr '\n' ' '))"
fi

case "$actual" in
  *not-a-skill*) bad "list_skills should skip dirs without SKILL.md" ;;
  *) ok "list_skills skips dirs without SKILL.md" ;;
esac

for excluded in scripts docs raw tests; do
  case "$actual" in
    *"$excluded"*) bad "list_skills should skip excluded dir '$excluded' despite SKILL.md" ;;
    *) ok "list_skills skips excluded dir '$excluded' despite SKILL.md" ;;
  esac
done

# --- frontmatter helpers -----------------------------------------------------
desc="$(skill_frontmatter_description "$fixture/skill-alpha/SKILL.md")"
if [[ "$desc" == "Alpha fixture skill description" ]]; then
  ok "skill_frontmatter_description reads folded description value"
else
  bad "skill_frontmatter_description mismatch (got: '$desc')"
fi

desc_missing="$(skill_frontmatter_description "$fixture/not-a-skill/SKILL.md" || true)"
if [[ -z "$desc_missing" ]]; then
  ok "skill_frontmatter_description empty for missing file"
else
  bad "skill_frontmatter_description should be empty for missing file"
fi

body="$(skill_body_without_frontmatter "$fixture/skill-alpha/SKILL.md")"
case "$body" in
  *"name: skill-alpha"*) bad "skill_body_without_frontmatter should strip frontmatter" ;;
  *) ok "skill_body_without_frontmatter strips frontmatter" ;;
esac
case "$body" in
  *"Alpha body line."*) ok "skill_body_without_frontmatter keeps body" ;;
  *) bad "skill_body_without_frontmatter should keep body" ;;
esac

# --- live-repo parity with the legacy inline installer logic ------------------
legacy_inline_discovery() {
  local d s
  for d in "$REPO_ROOT"/*/; do
    s="$(basename "$d")"
    case "$s" in (.claude|.omc|scripts|raw) continue;; esac
    [[ -f "$d/SKILL.md" ]] && echo "$s"
  done
  return 0
}
legacy="$(legacy_inline_discovery)"
current="$(list_skills "$REPO_ROOT")"
if [[ "$current" == "$legacy" ]]; then
  ok "list_skills matches legacy inline skip-list on the live repo"
else
  bad "list_skills diverges from legacy inline skip-list on the live repo"
  diff <(echo "$legacy") <(echo "$current") | sed 's/^/    /'
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
