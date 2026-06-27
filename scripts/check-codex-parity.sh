#!/bin/bash
#
# check-codex-parity.sh  (plan D5, P0-5)
#
# Greps a skill body (SKILL.md) for a denylist of Claude/OMC-only invocations
# that have no Codex equivalent. Exits non-zero on any UNMARKED real occurrence.
#
# Denylist (actual invocations):
#   - AskUserQuestion          (Claude interactive question tool)
#   - Task(subagent_type=      (Claude/OMC sub-agent spawn)
#   - subagent_type:           (sub-agent spawn, alternate form)
#   - Skill(                   (programmatic Skill tool invocation)
#   - OMC-only tool names      (TodoWrite, mcp__* MCP tool calls)
#
# CRITICAL — match ACTUAL INVOCATIONS ONLY (plan Minor-3):
#   The matcher MUST skip fenced code blocks (```), inline-code backtick spans,
#   and prose references. A skill body may legitimately *document* these strings
#   (e.g. `write-a-skill` teaching the marker convention) — such documented
#   mentions live in backticks or fenced blocks and MUST pass.
#
# Graceful-degradation marker:
#   A line carrying the marker `<!-- codex:optional -->` (on the construct line
#   or the line immediately preceding it) permits an annotated occurrence, on
#   the contract that a plain-markdown fallback is described adjacent to it.
#
# Usage:
#   check-codex-parity.sh <path-to-SKILL.md> [<path-to-SKILL.md> ...]
# Exit:
#   0  all given bodies pass
#   1  at least one unmarked denylisted construct found
#   2  usage / missing file
#

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: check-codex-parity.sh <SKILL.md> [<SKILL.md> ...]" >&2
  exit 2
fi

# Denylist as extended-regex alternatives, matched against prose-only text
# (after fenced blocks and inline-code spans have been stripped).
DENYLIST='AskUserQuestion|Task\(subagent_type=|subagent_type:|Skill\(|TodoWrite|mcp__[A-Za-z0-9_]+'
MARKER='<!-- codex:optional -->'

overall_rc=0

check_body() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "MISSING: $file" >&2
    overall_rc=2
    return
  fi

  local lineno=0
  local in_fence=0
  local prev_marked=0
  local found=0

  while IFS= read -r raw || [[ -n "$raw" ]]; do
    lineno=$((lineno + 1))

    # Toggle fenced-code state on lines whose first non-space chars are ``` (or ~~~).
    if [[ "$raw" =~ ^[[:space:]]*(\`\`\`|~~~) ]]; then
      in_fence=$((1 - in_fence))
      prev_marked=0
      continue
    fi

    # Inside a fenced code block: documented, not an invocation. Skip.
    if [[ "$in_fence" -eq 1 ]]; then
      prev_marked=0
      continue
    fi

    # Does THIS line carry the marker?
    local this_marked=0
    if [[ "$raw" == *"$MARKER"* ]]; then
      this_marked=1
    fi

    # Strip inline-code spans (text between backticks) so documented mentions
    # like `AskUserQuestion` are not treated as invocations.
    local stripped
    stripped="$(printf '%s' "$raw" | sed 's/`[^`]*`//g')"

    if printf '%s' "$stripped" | grep -Eq "$DENYLIST"; then
      # An occurrence is permitted if the construct line itself is marked OR the
      # immediately preceding (non-fence, non-blank-toggle) line was marked.
      if [[ "$this_marked" -eq 1 || "$prev_marked" -eq 1 ]]; then
        : # annotated occurrence with documented fallback — allowed
      else
        if [[ "$found" -eq 0 ]]; then
          echo "FAIL: $file"
          found=1
        fi
        local hit
        hit="$(printf '%s' "$stripped" | grep -Eo "$DENYLIST" | head -1)"
        echo "  line $lineno: unmarked Codex-incompatible construct: $hit"
        overall_rc=1
      fi
    fi

    prev_marked="$this_marked"
  done < "$file"

  if [[ "$found" -eq 0 ]]; then
    echo "PASS: $file"
  fi
}

for f in "$@"; do
  check_body "$f"
done

exit "$overall_rc"
