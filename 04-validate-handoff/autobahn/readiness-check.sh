#!/bin/bash
# Read-only gate for bypassing northstar with one evidence-complete goal record.

set -uo pipefail

command -v python3 >/dev/null 2>&1 || { echo "readiness-check: python3 is required" >&2; exit 2; }

GOAL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal)
      [[ $# -ge 2 ]] || { echo "usage: readiness-check.sh --goal <goal-record.json>" >&2; exit 2; }
      GOAL="$2"; shift 2
      ;;
    --goal=*) GOAL="${1#--goal=}"; shift ;;
    *) echo "usage: readiness-check.sh --goal <goal-record.json>" >&2; exit 2 ;;
  esac
done

if [[ -z "$GOAL" || ! -f "$GOAL" ]]; then
  echo "readiness-check: --goal must name an existing JSON goal record" >&2
  exit 2
fi

python3 - "$GOAL" <<'PY'
import json, re, sys
from pathlib import PurePosixPath

path = sys.argv[1]
try:
    goal = json.load(open(path))
except Exception as exc:
    print(f"readiness-check: invalid JSON: {exc}", file=sys.stderr)
    raise SystemExit(1)

errors = []
if goal.get("implementation_ready") is not True:
    errors.append("implementation_ready must be true")

for key in ("id", "context", "issue_ref"):
    if not isinstance(goal.get(key), str) or not goal[key].strip():
        errors.append(f"{key} must be a non-empty string")

for key in ("root_causes", "evidence", "solutions", "acceptance_criteria", "scope"):
    value = goal.get(key)
    if not isinstance(value, list) or not value or not all(isinstance(v, str) and v.strip() for v in value):
        errors.append(f"{key} must be a non-empty string array")

verification = goal.get("verification")
if not isinstance(verification, list) or not verification:
    errors.append("verification must be a non-empty array")
else:
    controls = re.compile(r"[\x00-\x1f\x7f]")
    for index, entry in enumerate(verification):
        if isinstance(entry, str):
            if not entry.strip():
                errors.append(f"verification[{index}] must be a non-empty string")
            continue
        if not isinstance(entry, dict) or set(entry) != {"cwd", "command"}:
            errors.append(f"verification[{index}] must be a string or exact cwd/command object")
            continue
        cwd = entry["cwd"]
        command = entry["command"]
        if not isinstance(cwd, str) or not cwd.strip():
            errors.append(f"verification[{index}].cwd must be a non-empty string")
            continue
        if not isinstance(command, str) or not command.strip():
            errors.append(f"verification[{index}].command must be a non-empty string")
        if controls.search(cwd) or (isinstance(command, str) and controls.search(command)):
            errors.append(f"verification[{index}] must not contain ASCII control characters")
        if cwd != cwd.strip() or "\\" in cwd:
            errors.append(f"verification[{index}].cwd must be normalized POSIX syntax")
            continue
        if cwd != ".":
            path = PurePosixPath(cwd)
            if (
                path.is_absolute()
                or path.as_posix() != cwd
                or any(part in ("", ".", "..") for part in cwd.split("/"))
            ):
                errors.append(f"verification[{index}].cwd must be a normalized relative descendant")

coverage = goal.get("coverage_percent")
if not isinstance(coverage, (int, float)) or isinstance(coverage, bool) or not 0 <= coverage <= 100:
    errors.append("coverage_percent must be a number from 0 through 100")

legacy_safe = goal.get("legacy_safe_tdd")
if legacy_safe not in (None, True, False):
    errors.append("legacy_safe_tdd must be boolean when present")
if legacy_safe is True and coverage is not None and coverage >= 30:
    reason = goal.get("legacy_risk_reason")
    if not isinstance(reason, str) or not reason.strip():
        errors.append("legacy_risk_reason is required when agent-selected legacy_safe_tdd is true at coverage >= 30")

if errors:
    for error in errors:
        print(f"readiness-check: {error}", file=sys.stderr)
    raise SystemExit(1)

print(f"readiness-check: implementation-ready goal '{goal['id']}'")
PY
