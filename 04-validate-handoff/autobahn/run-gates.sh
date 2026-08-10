#!/usr/bin/env bash
#
# run-gates.sh — run every autobahn gate for one goal, in order.
#
# The gates shipped as prose: the scripts existed and were unit-tested, but
# whether they ran depended on an agent reading SKILL.md and choosing to.
# Documented-but-unrun is the same failure mode as an inert test. This makes a
# skipped gate impossible rather than merely against the rules.
#
# It runs GATES, not the goal loop. Sequencing goals stays with `ultragoal` — a
# driver that took that over would be the reimplementation autobahn exists to
# avoid, and there is a test asserting this script has not grown one.
#
# Default is report-all: every gate runs and every block is listed, so one pass
# shows everything to fix instead of one thing per run. --fail-fast stops at the
# first block, for when later gates are expensive or meaningless without it.
#
# Usage:
#   run-gates.sh --root <dir> --goal-record <path> [--phase pre-commit|pre-merge|all] [--fail-fast]
#
# Exit codes: 0 every gate passed; 1 at least one gate blocked; 2 usage error.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="."
RECORD=""
PHASE="all"
FAIL_FAST=0

usage() { echo "run-gates: $1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)        ROOT="${2:-}";   shift 2 || usage "--root needs a value" ;;
    --goal-record) RECORD="${2:-}"; shift 2 || usage "--goal-record needs a value" ;;
    --phase)       PHASE="${2:-}";  shift 2 || usage "--phase needs a value" ;;
    --fail-fast)   FAIL_FAST=1;     shift ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"
[[ -n "$RECORD" ]] || usage "--goal-record is required"
case "$PHASE" in pre-commit|pre-merge|all) : ;; *) usage "--phase must be pre-commit, pre-merge or all" ;; esac

# The goal id addresses the evidence file. A record the driver cannot name is a
# record whose evidence it cannot find, which is a block rather than a skip.
GOAL_ID="$(RECORD="$RECORD" python3 - <<'PY' 2>/dev/null
import json, os, sys
from pathlib import Path
try:
    record = json.loads(Path(os.environ['RECORD']).read_text(encoding='utf-8'))
except Exception:
    raise SystemExit(1)
goal_id = record.get('id') if isinstance(record, dict) else None
if not isinstance(goal_id, str) or not goal_id.strip():
    raise SystemExit(1)
print(goal_id.strip())
PY
)"
if [[ -z "$GOAL_ID" ]]; then
  echo "run-gates: BLOCKED — goal record is unreadable or has no id: $RECORD" >&2
  exit 1
fi

echo "run-gates: goal=$GOAL_ID phase=$PHASE root=$ROOT"

BLOCKED=()

# gate <name> <command...> — run it, record a block, honour --fail-fast.
gate() {
  local name="$1"; shift
  echo ""
  echo "run-gates: === $name ==="
  if "$@"; then
    echo "run-gates: $name passed"
    return 0
  fi
  echo "run-gates: $name BLOCKED" >&2
  BLOCKED+=("$name")
  if [[ "$FAIL_FAST" -eq 1 ]]; then
    echo ""
    echo "run-gates: stopping at first block (--fail-fast): $name" >&2
    exit 1
  fi
  return 1
}

if [[ "$PHASE" == "pre-commit" || "$PHASE" == "all" ]]; then
  gate "tdd-evidence" bash "$HERE/tdd-evidence.sh" --verify --goal "$GOAL_ID" --root "$ROOT"
  gate "lint-gate"    bash "$HERE/lint-gate.sh" --root "$ROOT"
fi

if [[ "$PHASE" == "pre-merge" || "$PHASE" == "all" ]]; then
  gate "ci-gate --derive" bash "$HERE/ci-gate.sh" --derive --root "$ROOT"
  gate "ci-gate --verify" bash "$HERE/ci-gate.sh" --verify --root "$ROOT" --goal-record "$RECORD"
fi

echo ""
if [[ "${#BLOCKED[@]}" -eq 0 ]]; then
  echo "run-gates: all gates passed for $GOAL_ID"
  exit 0
fi

echo "run-gates: BLOCKED by ${#BLOCKED[@]} gate(s): ${BLOCKED[*]}" >&2
exit 1
