#!/bin/bash
#
# install_claude_code_test.sh
#
# Regression guard for scripts/install-claude-code.sh. A trailing slash on the
# glob source (cp -r "$skill_dir" "$dest/") makes macOS/BSD cp copy each skill's
# CONTENTS into the destination, flattening every skill into one merged blob
# instead of creating per-skill subdirectories. This test runs the installer into
# a throwaway HOME and asserts each catalog skill lands as its own proper subdir
# with its SKILL.md, and that NO flattening occurred.
#
# Offline, deterministic. Only exercises --user (with HOME overridden to a temp
# dir); never --project, which would write into the repo.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

INSTALLER="$REPO_ROOT/scripts/install-claude-code.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$INSTALLER" ]]; then
  bad "install-claude-code.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# Count catalog skills (first-class dirs with SKILL.md), excluding internal dirs.
expected=0
for d in "$REPO_ROOT"/*/; do
  s="$(basename "$d")"
  # Mirror the installer's exact skip-list (.claude/.omc never match the */ glob
  # but are listed for intent parity with install-claude-code.sh).
  case "$s" in .claude|.omc|scripts|raw) continue;; esac
  [[ -f "$d/SKILL.md" ]] && expected=$((expected + 1))
done

tmphome="$(mktemp -d)"
trap 'rm -rf "$tmphome"' EXIT

if HOME="$tmphome" bash "$INSTALLER" --user >/dev/null 2>&1; then
  ok "installer --user exits 0"
else
  bad "installer --user should exit 0"
fi

dest="$tmphome/.claude/skills/omc-learned"
if [[ -d "$dest" ]]; then
  ok "destination directory created"
else
  bad "destination directory created ($dest)"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# Every entry at the destination root must be a directory (a proper skill dir),
# and each must contain a SKILL.md. A flattened install would leave stray files
# (SKILL.md, *.sh, *.md) directly at the root.
stray="$(find "$dest" -maxdepth 1 -type f ! -name catalog.json | wc -l | tr -d ' ')"
if [[ "$stray" -eq 0 && -f "$dest/catalog.json" ]]; then
  ok "only the installed catalog projection is present at destination root"
else
  bad "destination root has $stray stray file(s) — install flattened the skills"
fi

subdirs="$(find "$dest" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')"
if [[ "$subdirs" -eq "$expected" ]]; then
  ok "each catalog skill installed as its own subdir ($subdirs == $expected)"
else
  bad "expected $expected skill subdirs, found $subdirs"
fi

# Spot-check representative skills resolve to <skill>/SKILL.md.
miss=0
for s in northstar autobahn init-ai-repo grill-me eval-a-skill; do
  [[ -f "$dest/$s/SKILL.md" ]] || { bad "$s/SKILL.md present after install"; miss=$((miss + 1)); }
done
[[ "$miss" -eq 0 ]] && ok "representative skills resolve to <skill>/SKILL.md"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
