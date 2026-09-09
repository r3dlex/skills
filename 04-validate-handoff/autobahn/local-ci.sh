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

commands="$(bash "$HERE/ci-gate.sh" --derive-json --root "$ROOT")" \
  || block "no executable safe local command subset could be derived"

record="$(mktemp "${TMPDIR:-/tmp}/autobahn-local-ci.XXXXXX")" \
  || block "could not create a temporary verification record"
cleanup() { rm -f "$record"; }
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 600 "$record" || block "could not protect the temporary verification record"

COMMANDS="$commands" RECORD="$record" python3 - <<'PY' \
  || block "structured local commands were malformed"
import json
import os
from pathlib import Path

commands = json.loads(os.environ['COMMANDS'])
if not isinstance(commands, list) or not commands:
    raise SystemExit(1)
if any(not isinstance(command, str) or not command.strip() for command in commands):
    raise SystemExit(1)
Path(os.environ['RECORD']).write_text(
    json.dumps({'id': 'local-ci-safe-subset', 'verification': commands}),
    encoding='utf-8',
)
PY

echo "local-ci: executing safe local command subset (not hosted-CI equivalence)"
bash "$HERE/ci-gate.sh" --verify --root "$ROOT" --goal-record "$record" \
  || block "safe local command subset did not pass"
echo "local-ci: safe local command subset passed"
