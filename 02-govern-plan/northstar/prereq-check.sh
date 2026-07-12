#!/bin/bash
#
# northstar/prereq-check.sh  (PR-1, N3)
#
# Read-only, fail-closed presence gate: asserts the ai-catapult-init v3 .ai/
# structure exists under --root. The repo root in this catalog has no .ai/, so
# this script ALWAYS operates against an explicit --root.
#
# Usage:
#   prereq-check.sh --root <repo-root>
# Exit:
#   0  all required ai-catapult-init artifacts present
#   1  at least one required artifact missing (guidance on stderr)
#   2  usage error
#

set -uo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    *) echo "usage: prereq-check.sh --root <repo-root>" >&2; exit 2 ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "prereq-check: --root '$ROOT' is not a directory" >&2
  exit 2
fi

# Required ai-catapult-init v3 presence set (read-only assertions).
REQUIRED=(
  ".ai/matrix.json"
  ".ai/workflows/repo-workflow.json"
  ".ai/handoff"
  ".ai/traceability/graph.json"
)

missing=0
for rel in "${REQUIRED[@]}"; do
  if [[ ! -e "$ROOT/$rel" ]]; then
    echo "prereq-check: missing required ai-catapult-init artifact: $rel" >&2
    missing=$((missing + 1))
  fi
done

if [[ "$missing" -gt 0 ]]; then
  echo "prereq-check: $missing required ai-catapult-init artifact(s) absent under '$ROOT'." >&2
  echo "prereq-check: run the ai-catapult-init skill to initialize the repo, then retry." >&2
  exit 1
fi

echo "prereq-check: ai-catapult-init v3 structure present under '$ROOT'."
exit 0
