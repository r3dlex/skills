#!/usr/bin/env bash
# Execute the workflow's narrowly supported local command subset.
# This is supporting local evidence, not hosted-CI equivalence.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."

usage() { echo "local-ci: $1" >&2; exit 2; }
block() { echo "local-ci: BLOCKED — $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) [[ $# -ge 2 ]] || usage "--root needs a value"; ROOT="$2"; shift 2 ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"

CONTRACT_MODE=0
if [[ -e "$ROOT/.ai/ci/local-ci.json" || -L "$ROOT/.ai/ci/local-ci.json" ]]; then
  CONTRACT_MODE=1
  commands="$(python3 -B "$HERE/lib/local_ci_contract.py" "$ROOT")" \
    || block "explicit local CI contract failed; no workflow fallback"
else
  commands="$(bash "$HERE/ci-gate.sh" --derive-json --root "$ROOT")" \
    || block "no executable safe local command subset could be derived"
fi

record="$(mktemp "${TMPDIR:-/tmp}/autobahn-local-ci.XXXXXX")" \
  || block "could not create a temporary verification record"
cleanup() { rm -f "$record"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 600 "$record" || block "could not protect the temporary verification record"

CONTRACT_MODE="$CONTRACT_MODE" COMMANDS="$commands" RECORD="$record" python3 -B - <<'PY' \
  || block "structured local commands were malformed"
import json
import os
import re
from pathlib import Path

commands = json.loads(os.environ['COMMANDS'])
if not isinstance(commands, list) or not commands:
    raise SystemExit(1)
if os.environ['CONTRACT_MODE'] == '0' and any(not isinstance(command, str) or not command.strip() for command in commands):
    raise SystemExit(1)
# Workflow run values have shell semantics, whereas goal verification uses argv.
# Fail closed for shell comments/expansion rather than silently passing literals.
if os.environ['CONTRACT_MODE'] == '0' and any(re.search(r"[#*?\[\]{}~()]", command) for command in commands):
    raise SystemExit('unsupported workflow shell comment or expansion')
Path(os.environ['RECORD']).write_text(
    json.dumps({'id': 'local-ci-safe-subset', 'verification': commands}),
    encoding='utf-8',
)
PY

if [[ "$CONTRACT_MODE" == 1 ]]; then
  echo "local-ci: executing explicit supporting local CI contract (not hosted-CI equivalence)"
else
  echo "local-ci: executing safe local command subset (not hosted-CI equivalence)"
fi
bash "$HERE/ci-gate.sh" --verify --root "$ROOT" --goal-record "$record" \
  || block "safe local command subset did not pass"
echo "local-ci: supporting local checks passed (not hosted-CI equivalence)"
