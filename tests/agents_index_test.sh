#!/bin/bash
#
# agents_index_test.sh  (P0-5, upgraded to full parity in P1-7, decision D5)
#
# Asserts FULL index<->catalog parity: EVERY catalog skill (every top-level
# */SKILL.md) is present in the AGENTS.md `## Skills` table, so the table is a
# complete cross-tool discovery surface. NO exclusion allowlist (decision D5).
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

AGENTS="AGENTS.md"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Extract the `## Skills` table block (lines from `## Skills` up to the next
# top-level heading) so a skill name mentioned elsewhere does not falsely pass.
table="$(awk '
  /^## Skills/      {inblock=1; next}
  inblock && /^## / {inblock=0}
  inblock           {print}
' "$AGENTS")"

if [[ -z "$table" ]]; then
  bad "AGENTS.md has a '## Skills' table block"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
else
  ok "AGENTS.md has a '## Skills' table block"
fi

# Full catalog: every top-level */SKILL.md, discovered dynamically so this
# test stays consistent with the live catalog with no allowlist (decision D5).
catalog=()
while IFS=$'\t' read -r name source; do
  catalog+=("$name")
done < <(python3 scripts/catalog-query.py --host codex)

if [[ "${#catalog[@]}" -eq 0 ]]; then
  bad "catalog has at least one skill (*/SKILL.md)"
else
  ok "catalog discovered ${#catalog[@]} skills"
fi

for skill in "${catalog[@]}"; do
  # Match the skill as a code-fenced table cell entry: `| `skill` |`.
  if printf '%s\n' "$table" | grep -Eq "\`$skill\`"; then
    ok "AGENTS.md ## Skills table lists $skill"
  else
    bad "AGENTS.md ## Skills table lists $skill"
  fi
done

# Reverse direction: every first-column skill name in the table maps to a real
# */SKILL.md dir, so a stale row for a deleted/renamed skill is caught (no orphans).
while IFS= read -r row; do
  name="$(printf '%s' "$row" | sed -n 's/^| *`\([^`]*\)`.*/\1/p')"
  [[ -n "$name" ]] || continue
  if python3 scripts/catalog-query.py --host codex --skill "$name" >/dev/null 2>&1; then
    ok "AGENTS.md row '$name' maps to a real skill dir"
  else
    bad "AGENTS.md row '$name' maps to a real skill dir (orphan row?)"
  fi
done <<< "$table"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
