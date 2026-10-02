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
#   run-gates.sh --root <dir> --goal-record <path> [--phase pre-commit|pre-merge|all|local-validation] [--fail-fast]
#
# Exit codes: 0 every gate passed; 1 at least one gate blocked; 2 usage error.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="."
RECORD=""
PHASE="all"
FAIL_FAST=0
HANDOFF=""
DIRECT=""
CONTEXT=""
EXECUTION_ROOT=""
WORKTREE_ROOT=""
BASE_COMMIT=""

usage() { echo "run-gates: $1" >&2; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)        ROOT="${2:-}";   shift 2 || usage "--root needs a value" ;;
    --goal-record) RECORD="${2:-}"; shift 2 || usage "--goal-record needs a value" ;;
    --handoff)     HANDOFF="${2:-}"; shift 2 || usage "--handoff needs a value" ;;
    --goal)        DIRECT="${2:-}"; shift 2 || usage "--goal needs a value" ;;
    --execution-root) EXECUTION_ROOT="${2:-}"; shift 2 || usage "--execution-root needs a value" ;;
    --worktree-root) WORKTREE_ROOT="${2:-}"; shift 2 || usage "--worktree-root needs a value" ;;
    --base-commit) BASE_COMMIT="${2:-}"; shift 2 || usage "--base-commit needs a value" ;;
    --context)     CONTEXT="${2:-}"; shift 2 || usage "--context needs a value" ;;
    --phase)       PHASE="${2:-}";  shift 2 || usage "--phase needs a value" ;;
    --fail-fast)   FAIL_FAST=1;     shift ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"
[[ -n "$RECORD" ]] || usage "--goal-record is required"
case "$PHASE" in pre-commit|pre-merge|all|local-validation) : ;; *) usage "--phase must be pre-commit, pre-merge, all or local-validation" ;; esac

if [[ -n "$WORKTREE_ROOT" || -n "$BASE_COMMIT" ]]; then
  [[ -n "$WORKTREE_ROOT" && "$BASE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || usage "--worktree-root and full --base-commit are required together"
  [[ -z "$EXECUTION_ROOT" ]] || usage "worktree and mapped execution modes are mutually exclusive"
fi

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

# Same-repository worktree mode preserves the canonical identity root while
# every executable gate uses the independently admitted worktree. No phase can
# borrow primary-checkout green checks or omit exact-record admission.
if [[ -n "$WORKTREE_ROOT" ]]; then
  if [[ -z "$CONTEXT" || ( -z "$HANDOFF" && -z "$DIRECT" ) || ( -n "$HANDOFF" && -n "$DIRECT" ) ]]; then
    echo "run-gates: BLOCKED - worktree execution requires exact selection and current --context" >&2
    exit 1
  fi
  # Gate scripts invoke Git too: inherited repository-selection/configuration
  # overrides must not redirect their observations away from the admitted root.
  for git_variable in $(compgen -v GIT_); do
    unset "$git_variable" || exit 1
  done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0
  IDENTITY_ROOT="$ROOT"
  SELECTION=()
  if [[ -n "$HANDOFF" ]]; then
    SELECTION=(--handoff "$HANDOFF" --goal-id "$GOAL_ID")
  else
    SELECTION=(--goal "$DIRECT")
  fi
  STAGE="implementation"
  [[ "$PHASE" == "pre-merge" || "$PHASE" == "all" ]] && STAGE="merge"
  REPORT="$(mktemp)" || exit 1
  trap 'rm -f "$REPORT"' EXIT
  ADMISSION_SNAPSHOT=""
  worktree_admission() {
    if ! bash "$HERE/prereq-check.sh" --root "$IDENTITY_ROOT" "${SELECTION[@]}" \
        --worktree-root "$WORKTREE_ROOT" --base-commit "$BASE_COMMIT" \
        --context "$CONTEXT" --stage "$STAGE" --execution-record "$RECORD" > "$REPORT"; then
      cat "$REPORT"
      echo "run-gates: BLOCKED - worktree readiness" >&2
      return 1
    fi
    cat "$REPORT"
    local snapshot
    snapshot="$(python3 - "$REPORT" "$WORKTREE_ROOT" "$CONTEXT" "$RECORD" <<'PY_WORKTREE'
import hashlib, json, sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text())
if report.get('execution_ready') is not True or report.get('worktree', {}).get('root') != sys.argv[2]:
    raise SystemExit('worktree_root_mismatch')
if report.get('dispatch_authorized') is not False:
    raise SystemExit('worktree_authority_boundary_invalid')
payload = json.dumps(report['worktree'], sort_keys=True).encode()
for name in sys.argv[3:]:
    payload += hashlib.sha256(Path(name).read_bytes()).digest()
print(hashlib.sha256(payload).hexdigest())
PY_WORKTREE
)" || return 1
    if [[ -n "$ADMISSION_SNAPSHOT" && "$snapshot" != "$ADMISSION_SNAPSHOT" ]]; then
      echo "run-gates: BLOCKED - worktree admission changed during gates" >&2
      return 1
    fi
    ADMISSION_SNAPSHOT="$snapshot"
  }
  worktree_admission || exit 1
  ROOT="$WORKTREE_ROOT"
fi

# A foreign goal or mapped selector cannot borrow planning-root checks. This
# detection grants nothing; the pinned validator below admits the exact record.
MAPPED_RUN="no"
if [[ -z "$WORKTREE_ROOT" ]]; then
MAPPED_RUN="$(ROOT="$ROOT" RECORD="$RECORD" DIRECT="$DIRECT" HANDOFF="$HANDOFF" EXECUTION_ROOT="$EXECUTION_ROOT" python3 - <<'PY_DETECT'
import json, os
from pathlib import Path
root = Path(os.environ['ROOT']).resolve(strict=True)
record = json.loads(Path(os.environ['RECORD']).read_text())
foreign = record.get('repository', {}).get('root', str(root)) != str(root)
mapped = bool(os.environ['EXECUTION_ROOT']) or foreign
if os.environ['DIRECT']:
    envelope = json.loads(Path(os.environ['DIRECT']).read_text())
    mapped |= envelope.get('bundle', {}).get('schema') == 'mapped-handoff-goals/1'
if os.environ['HANDOFF']:
    registry = root / '.ai/workflows/northstar-readiness-v1.json'
    if registry.exists():
        for entry in json.loads(registry.read_text()).get('plans', []):
            if os.environ['HANDOFF'] in (entry.get('id'), entry.get('handoff_path')):
                path = root / entry['artifacts']['bundle']['path']
                if root not in path.resolve(strict=True).parents:
                    raise ValueError('unsafe bundle path')
                mapped |= json.loads(path.read_text()).get('schema') == 'mapped-handoff-goals/1'
print('yes' if mapped else 'no')
PY_DETECT
)" || { echo "run-gates: BLOCKED - unreadable execution selection" >&2; exit 1; }

fi

if [[ "$MAPPED_RUN" == "yes" ]]; then
  if [[ -z "$EXECUTION_ROOT" || -z "$CONTEXT" || ( -z "$HANDOFF" && -z "$DIRECT" ) || ( -n "$HANDOFF" && -n "$DIRECT" ) ]]; then
    echo "run-gates: BLOCKED - mapped execution requires --execution-root, exact selection and current --context" >&2
    exit 1
  fi
  SELECTION=()
  if [[ -n "$HANDOFF" ]]; then
    SELECTION=(--handoff "$HANDOFF" --goal-id "$GOAL_ID")
  else
    SELECTION=(--goal "$DIRECT")
  fi
  STAGE="implementation"
  [[ "$PHASE" == "pre-merge" || "$PHASE" == "all" ]] && STAGE="merge"
  REPORT="$(mktemp)" || exit 1
  trap 'rm -f "$REPORT"' EXIT
  if ! bash "$HERE/prereq-check.sh" --root "$ROOT" "${SELECTION[@]}" \
      --execution-root "$EXECUTION_ROOT" --context "$CONTEXT" --stage "$STAGE" \
      --execution-record "$RECORD" > "$REPORT"; then
    cat "$REPORT"
    echo "run-gates: BLOCKED - mapped readiness" >&2
    exit 1
  fi
  cat "$REPORT"
  if ! python3 - "$REPORT" "$EXECUTION_ROOT" <<'PY_ROUTE'
import json, sys
from pathlib import Path
report = json.loads(Path(sys.argv[1]).read_text())
execution = report.get('execution', {})
if not report.get('execution_ready') or execution.get('repository', {}).get('root') != sys.argv[2]:
    raise SystemExit('execution_root_mismatch')
if execution.get('validation') != 'local':
    raise SystemExit('external_validation_adapter_required')
PY_ROUTE
  then
    echo "run-gates: BLOCKED - mapped validation adapter" >&2
    exit 1
  fi
  ROOT="$EXECUTION_ROOT"
fi

# Merge admission is a prerequisite, not an optional report-all gate. Never
# execute verification under a different goal record or a stale/absent context.
if [[ -z "$WORKTREE_ROOT" && "$MAPPED_RUN" == "no" && ( "$PHASE" == "pre-merge" || "$PHASE" == "all" ) ]]; then
  if [[ -z "$CONTEXT" || ( -z "$HANDOFF" && -z "$DIRECT" ) || ( -n "$HANDOFF" && -n "$DIRECT" ) ]]; then
    echo "run-gates: BLOCKED — merge requires exact --handoff or --goal and fresh --context" >&2
    exit 1
  fi
  SELECTION=()
  if [[ -n "$HANDOFF" ]]; then
    SELECTION=(--handoff "$HANDOFF" --goal-id "$GOAL_ID")
  else
    SELECTION=(--goal "$DIRECT")
  fi
  gate "merge readiness" bash "$HERE/prereq-check.sh" --root "$ROOT" "${SELECTION[@]}" \
    --context "$CONTEXT" --stage merge --execution-record "$RECORD" || exit 1
fi

if [[ "$PHASE" == "pre-commit" || "$PHASE" == "all" || "$PHASE" == "local-validation" ]]; then
  gate "tdd-evidence" bash "$HERE/tdd-evidence.sh" --verify --goal "$GOAL_ID" --root "$ROOT"
  gate "lint-gate"    bash "$HERE/lint-gate.sh" --root "$ROOT"
fi

if [[ "$PHASE" == "pre-merge" || "$PHASE" == "all" || "$PHASE" == "local-validation" ]]; then
  gate "local safe CI subset" bash "$HERE/local-ci.sh" --root "$ROOT"
  gate "ci-gate --verify" bash "$HERE/ci-gate.sh" --verify --root "$ROOT" --goal-record "$RECORD"
fi

# Reobserve the exact context after commands: HEAD, working bytes, policy and
# instruction changes invalidate the run, even if the individual gates passed.
if [[ -n "$WORKTREE_ROOT" ]]; then
  gate "worktree readiness recheck" worktree_admission
fi

echo ""
if [[ "${#BLOCKED[@]}" -eq 0 ]]; then
  if [[ "$PHASE" == "local-validation" ]]; then
    echo "run-gates: local validation passed for $GOAL_ID — not merge admission or authority"
  else
    echo "run-gates: $PHASE gates passed for $GOAL_ID — host authority remains separately required"
  fi
  exit 0
fi

echo "run-gates: BLOCKED by ${#BLOCKED[@]} gate(s): ${BLOCKED[*]}" >&2
exit 1
