#!/bin/bash
#
# opencode_parity_test.sh  (SSCM-08)
#
# Mirrors codex_parity_test.sh for the opencode surface:
#   - EVERY catalog skill body PASSES scripts/check-opencode-parity.sh;
#   - a fixture body with an UNMARKED denylisted construct FAILS (non-zero);
#   - a fixture body with a MARKED construct PASSES;
#   - backtick/fenced-code exemptions preserved (documented mentions pass).
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

CHECK="scripts/check-opencode-parity.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# ---------------------------------------------------------------------------
# (1) EVERY catalog skill body passes opencode parity (full catalog, no
#     allowlist — discovered dynamically like codex_parity_test.sh).
# ---------------------------------------------------------------------------
catalog=()
while IFS=$'\t' read -r name source; do
  catalog+=("$source")
done < <(python3 scripts/catalog-query.py --host opencode)

if [[ "${#catalog[@]}" -eq 0 ]]; then
  bad "catalog has at least one skill (*/SKILL.md)"
else
  ok "catalog discovered ${#catalog[@]} skills"
fi

for skill in "${catalog[@]}"; do
  body="$skill/SKILL.md"
  if bash "$CHECK" "$body" >/dev/null 2>&1; then
    ok "$skill passes opencode parity"
  else
    bad "$skill passes opencode parity"
    bash "$CHECK" "$body" 2>&1 | sed 's/^/      /'
  fi
done

# ---------------------------------------------------------------------------
# (2) Self-reference guard: write-a-skill documents the marker convention and
#     must PASS.
# ---------------------------------------------------------------------------
if grep -Fq "opencode:optional" 03-configure-generate/write-a-skill/SKILL.md; then
  ok "write-a-skill body documents the opencode marker convention"
else
  bad "write-a-skill body documents the opencode marker convention"
fi

# ---------------------------------------------------------------------------
# (3) Negative + positive fixtures.
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

<!-- opencode:optional -->
Use AskUserQuestion to confirm the destination branch.
Fallback (opencode/plain markdown): print the options as a numbered list and
ask the user to reply with a number in prose.
EOF

if bash "$CHECK" "$tmpdir/unmarked.md" >/dev/null 2>&1; then
  bad "unmarked AskUserQuestion fixture fails opencode parity (got exit 0)"
else
  ok "unmarked AskUserQuestion fixture fails opencode parity (non-zero exit)"
fi

if bash "$CHECK" "$tmpdir/marked.md" >/dev/null 2>&1; then
  ok "marked AskUserQuestion fixture passes opencode parity"
else
  bad "marked AskUserQuestion fixture passes opencode parity"
fi

# ---------------------------------------------------------------------------
# (4) Backtick/fenced exemptions preserved: a documented mention inside
#     backticks or a fenced block must pass unmarked.
# ---------------------------------------------------------------------------
cat > "$tmpdir/documentary.md" <<'EOF'
# Fixture skill

## Process

- Documented mention: `AskUserQuestion`, `~/.claude/skills`.
- Path reference: `.claude-plugin/marketplace.json`.

```text
Task(subagent_type=executor) inside a fenced block is documentation, not invocation.
```
EOF

if bash "$CHECK" "$tmpdir/documentary.md" >/dev/null 2>&1; then
  ok "documented mentions in backticks/fences pass unmarked (exemption preserved)"
else
  bad "documented mentions in backticks/fences pass unmarked (exemption preserved)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1