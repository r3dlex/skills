#!/usr/bin/env bash
#
# tdd-evidence.sh — record and verify that a goal's test failed before it passed.
#
# Autobahn selected a TDD posture but had no way to tell red-then-green from
# tests written after the code. This turns the claim into an artifact at
# .ai/evidence/<goal-id>.json holding one test command and the exit code it
# produced on each leg.
#
# The script OBSERVES: --record-red and --record-green run the command and store
# the real exit code rather than accepting one as an argument. A caller can still
# lie by never running the script, which is why the gate is verification, not
# recording — no script can stop an agent from skipping it, but --verify can stop
# a goal that has no evidence from merging.
#
# Ships inert this slice: nothing invokes it yet. See modules/implementation.md.
#
# Usage:
#   tdd-evidence.sh --record-red   --goal <id> --root <dir> --command <cmd>
#   tdd-evidence.sh --record-green --goal <id> --root <dir> --command <cmd>
#   tdd-evidence.sh --verify       --goal <id> --root <dir>
#
# Exit codes: 0 success; 1 contract violation (fail closed); 2 usage error.
#
# The command is run through `bash -c` from the repo root. The allowlist
# contract that decision 9 defines for goal-record verification[] commands lands
# in slice 6a and applies here too once it exists.

set -uo pipefail

MODE=""
GOAL=""
ROOT="."
COMMAND=""

die()   { echo "tdd-evidence: $1" >&2; exit 1; }
usage() { echo "tdd-evidence: $1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --record-red|--record-green|--verify)
      [[ -n "$MODE" ]] && usage "only one mode may be given"
      MODE="${1#--}"; shift ;;
    --goal)    GOAL="${2:-}";    shift 2 || usage "--goal needs a value" ;;
    --root)    ROOT="${2:-}";    shift 2 || usage "--root needs a value" ;;
    --command) COMMAND="${2:-}"; shift 2 || usage "--command needs a value" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$MODE" ]] || usage "one of --record-red, --record-green, --verify is required"
[[ -n "$GOAL" ]] || usage "--goal is required"
[[ -d "$ROOT" ]] || usage "--root is not a directory: $ROOT"

# A goal id becomes a filename. Reject anything that could escape the evidence
# directory or collide with a path segment.
case "$GOAL" in
  ""|*/*|*\\*|.|..) die "goal id must be a single path-safe segment: $GOAL" ;;
esac

EVIDENCE_DIR="$ROOT/.ai/evidence"
EVIDENCE="$EVIDENCE_DIR/$GOAL.json"

record() {
  local leg="$1" want="$2"
  [[ -n "$COMMAND" ]] || usage "--command is required for --record-$leg"

  # Observe the real exit code. `|| true` keeps errexit from pre-empting the
  # comparison below, which is the whole point of the check.
  ( cd "$ROOT" && bash -c "$COMMAND" ) >/dev/null 2>&1 && actual=0 || actual=$?

  if [[ "$leg" == "red" && "$actual" -eq 0 ]]; then
    die "the test command passed, so there is no red leg to record: $COMMAND"
  fi
  if [[ "$leg" == "green" && "$actual" -ne 0 ]]; then
    die "the test command still fails (exit $actual), so there is no green leg: $COMMAND"
  fi

  mkdir -p "$EVIDENCE_DIR" || die "cannot create $EVIDENCE_DIR"

  EVIDENCE="$EVIDENCE" GOAL="$GOAL" LEG="$leg" COMMAND="$COMMAND" EXIT_CODE="$actual" \
  python3 - <<'PY' || die "could not write evidence"
import json, os
from pathlib import Path

path = Path(os.environ['EVIDENCE'])
data = {}
if path.exists():
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
    except json.JSONDecodeError:
        data = {}
    if not isinstance(data, dict):
        data = {}

data['goal_id'] = os.environ['GOAL']
data[os.environ['LEG']] = {
    'command': os.environ['COMMAND'],
    'exit_code': int(os.environ['EXIT_CODE']),
}
path.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n', encoding='utf-8')
PY

  echo "tdd-evidence: recorded $leg for $GOAL (exit $actual)"
  exit 0
}

case "$MODE" in
  record-red)   record red   1 ;;
  record-green) record green 0 ;;
esac

# --- verify -----------------------------------------------------------------
[[ -f "$EVIDENCE" ]] || die "no TDD evidence for goal '$GOAL' at $EVIDENCE"

EVIDENCE="$EVIDENCE" python3 - <<'PY'
import json, os, sys
from pathlib import Path

def fail(message):
    sys.stderr.write(f'tdd-evidence: {message}\n')
    raise SystemExit(1)

path = Path(os.environ['EVIDENCE'])
try:
    data = json.loads(path.read_text(encoding='utf-8'))
except json.JSONDecodeError as error:
    fail(f'evidence is malformed JSON: {error}')
if not isinstance(data, dict):
    fail('evidence must be a JSON object')

for leg in ('red', 'green'):
    entry = data.get(leg)
    if not isinstance(entry, dict):
        fail(f'evidence has no {leg} leg — a goal needs both a failing and a passing run')
    if not isinstance(entry.get('command'), str) or not entry['command']:
        fail(f'{leg} leg has no recorded command')
    if not isinstance(entry.get('exit_code'), int):
        fail(f'{leg} leg has no recorded exit code')

if data['red']['exit_code'] == 0:
    fail('the red leg exited 0 — that is not a failing test')
if data['green']['exit_code'] != 0:
    fail(f"the green leg exited {data['green']['exit_code']} — that is not a passing test")
if data['red']['command'] != data['green']['command']:
    fail(
        'red and green recorded different commands, so the red run is no evidence '
        f"for the green one: {data['red']['command']!r} vs {data['green']['command']!r}"
    )
PY
verify_status=$?
[[ "$verify_status" -eq 0 ]] || exit 1

echo "tdd-evidence: $GOAL has red-then-green evidence"
