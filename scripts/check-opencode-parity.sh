#!/bin/bash
#
# check-opencode-parity.sh  (SSCM-08, mirror-not-clone of check-codex-parity.sh)
#
# Greps a skill body (SKILL.md) for constructs that hard-depend on Claude/OMC
# and have no opencode equivalent. Exits non-zero on any UNMARKED real
# occurrence. Adapted, not imported: same fenced-block and backtick-span
# exemptions, own marker convention.
#
# Denylist (actual invocations and paths):
#   - AskUserQuestion          (Claude interactive question tool)
#   - Task(subagent_type=      (Claude/OMC sub-agent spawn)
#   - subagent_type:           (sub-agent spawn, alternate form)
#   - TodoWrite                (OMC tool name; opencode's tracker tooling is not this)
#   - mcp__*                   (OMC MCP tool naming form)
#   - ~/.claude/...            (Claude-only config paths)
#   - .claude-plugin/...       (Claude plugin layout)
#   - claude mcp|claude settings|claude -- (Claude CLI invocations)
#
# CRITICAL — match ACTUAL INVOCATIONS ONLY:
#   The matcher skips fenced code blocks (```), inline-code backtick spans, and
#   prose references. A skill body may legitimately *document* these strings —
#   such documented mentions live in backticks or fenced blocks and MUST pass.
#
# Graceful-degradation marker:
#   `<!-- opencode:optional -->` on the construct line or the line immediately
#   preceding it permits an annotated occurrence, on the contract that a
#   plain-markdown fallback is described adjacent to it.
#
# Usage:
#   check-opencode-parity.sh <path-to-SKILL.md> [<path-to-SKILL.md> ...]
# Exit:
#   0  all given bodies pass
#   1  at least one unmarked denylisted construct found
#   2  usage / missing file
#

set -uo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: check-opencode-parity.sh <SKILL.md> [<SKILL.md> ...]" >&2
  exit 2
fi

# Denylist as extended-regex alternatives, matched against prose-only text
# (after fenced blocks and inline-code spans have been stripped). Each entry is
# justified above; tighten the regex rather than growing an allowlist when a
# false positive appears.
DENYLIST='AskUserQuestion|Task\(subagent_type=|subagent_type:|TodoWrite|mcp__[A-Za-z0-9_]+|~/\.claude[^[:space:]]*|\.claude-plugin/[^[:space:]]*|claude (mcp|settings|--)[^[:space:]]*( [^[:space:]]+)*'
MARKER='<!-- opencode:optional -->'

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
        echo "  line $lineno: unmarked opencode-incompatible construct: $hit"
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