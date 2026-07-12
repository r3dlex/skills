#!/bin/bash
# Pure selection of standard vs legacy-safe TDD from coverage and recorded risk.

set -uo pipefail

command -v python3 >/dev/null 2>&1 || { echo "tdd-mode: python3 is required" >&2; exit 2; }

GOAL=""
COVERAGE=""
LEGACY_RISK=""
LEGACY_RISK_REASON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal|--coverage-percent|--legacy-risk|--legacy-risk-reason)
      [[ $# -ge 2 ]] || {
        echo "usage: tdd-mode.sh [--goal <json>] [--coverage-percent <0..100>] [--legacy-risk true|false] [--legacy-risk-reason <text>]" >&2
        exit 2
      }
      case "$1" in
        --goal) GOAL="$2" ;;
        --coverage-percent) COVERAGE="$2" ;;
        --legacy-risk) LEGACY_RISK="$2" ;;
        --legacy-risk-reason) LEGACY_RISK_REASON="$2" ;;
      esac
      shift 2
      ;;
    *) echo "usage: tdd-mode.sh [--goal <json>] [--coverage-percent <0..100>] [--legacy-risk true|false] [--legacy-risk-reason <text>]" >&2; exit 2 ;;
  esac
done

python3 - "$GOAL" "$COVERAGE" "$LEGACY_RISK" "$LEGACY_RISK_REASON" <<'PY'
import json, sys

goal_path, coverage_arg, risk_arg, risk_reason_arg = sys.argv[1:]
goal = {}
if goal_path:
    try:
        goal = json.load(open(goal_path))
    except Exception as exc:
        print(f"tdd-mode: invalid goal JSON: {exc}", file=sys.stderr)
        raise SystemExit(2)

coverage = coverage_arg if coverage_arg else goal.get("coverage_percent")
if isinstance(coverage, bool):
    print("tdd-mode: coverage_percent must be numeric, not boolean", file=sys.stderr)
    raise SystemExit(2)
try:
    coverage = float(coverage)
except (TypeError, ValueError):
    print("tdd-mode: coverage_percent must be supplied as a number from 0 through 100", file=sys.stderr)
    raise SystemExit(2)
if not 0 <= coverage <= 100:
    print("tdd-mode: coverage_percent must be from 0 through 100", file=sys.stderr)
    raise SystemExit(2)

if risk_arg:
    if risk_arg not in ("true", "false"):
        print("tdd-mode: --legacy-risk must be true or false", file=sys.stderr)
        raise SystemExit(2)
    legacy_risk = risk_arg == "true"
else:
    legacy_risk = goal.get("legacy_safe_tdd", False)
    if not isinstance(legacy_risk, bool):
        print("tdd-mode: legacy_safe_tdd must be boolean", file=sys.stderr)
        raise SystemExit(2)

risk_reason = risk_reason_arg if risk_reason_arg else goal.get("legacy_risk_reason", "")
if legacy_risk and coverage >= 30 and (not isinstance(risk_reason, str) or not risk_reason.strip()):
    print("tdd-mode: agent-selected legacy risk at coverage >= 30 requires legacy_risk_reason", file=sys.stderr)
    raise SystemExit(2)

print("legacy-safe" if coverage < 30 or legacy_risk else "standard")
PY
