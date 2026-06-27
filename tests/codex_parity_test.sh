#!/bin/bash
#
# codex_parity_test.sh  (P0-5)
#
# Asserts:
#   - the 8 SDLC-core skills PASS scripts/check-codex-parity.sh (exit 0);
#   - `write-a-skill` PASSES even though its body documents the denylisted
#     strings while teaching the marker convention (self-reference guard);
#   - a fixture body with an UNMARKED AskUserQuestion FAILS (non-zero);
#   - a fixture body with a MARKED AskUserQuestion PASSES.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

CHECK="scripts/check-codex-parity.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# (1) The 8 P0 SDLC-core skill bodies pass parity.
# ---------------------------------------------------------------------------
SDLC_CORE=(
  init-ai-repo
  write-a-skill
  to-prd
  to-issues
  triage
  tdd
  diagnose
  publish-semver
)

for skill in "${SDLC_CORE[@]}"; do
  body="$skill/SKILL.md"
  if bash "$CHECK" "$body" >/dev/null 2>&1; then
    ok "$skill passes codex parity"
  else
    bad "$skill passes codex parity"
    bash "$CHECK" "$body" 2>&1 | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------------
# (2) Self-reference guard: write-a-skill documents the denylist strings while
#     teaching the marker convention, yet must PASS (mentions are in
#     backticks / fenced blocks, not invocations).
# ---------------------------------------------------------------------------
if grep -Fq "AskUserQuestion" write-a-skill/SKILL.md \
   && grep -Fq "codex:optional" write-a-skill/SKILL.md; then
  ok "write-a-skill body documents the marker convention (mentions denylist strings)"
else
  bad "write-a-skill body documents the marker convention (mentions denylist strings)"
fi
if bash "$CHECK" write-a-skill/SKILL.md >/dev/null 2>&1; then
  ok "write-a-skill passes parity despite documenting denylist strings (self-reference guard)"
else
  bad "write-a-skill passes parity despite documenting denylist strings (self-reference guard)"
fi

# ---------------------------------------------------------------------------
# (3) Negative + positive fixtures: unmarked construct FAILS, marked PASSES.
# ---------------------------------------------------------------------------
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat > "$tmpdir/unmarked.md" <<'EOF'
# Fixture skill

## Process

Use AskUserQuestion to confirm the destination branch before pushing.
EOF

cat > "$tmpdir/marked.md" <<'EOF'
# Fixture skill

## Process

<!-- codex:optional -->
Use AskUserQuestion to confirm the destination branch.
Fallback (Codex/plain markdown): print the options as a numbered list and ask
the user to reply with a number in prose.
EOF

if bash "$CHECK" "$tmpdir/unmarked.md" >/dev/null 2>&1; then
  bad "unmarked AskUserQuestion fixture fails parity (got exit 0)"
else
  ok "unmarked AskUserQuestion fixture fails parity (non-zero exit)"
fi

if bash "$CHECK" "$tmpdir/marked.md" >/dev/null 2>&1; then
  ok "marked AskUserQuestion fixture passes parity"
else
  bad "marked AskUserQuestion fixture passes parity"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
