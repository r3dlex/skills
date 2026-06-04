#!/usr/bin/env bash
# archgate.sh — Stable AI SDLC governance command contract.
# Structural checks are default-on. Semantic/drift checks are opt-in.

set -euo pipefail

MODE="structural"
RULES_FILE=".rules.ts"
FORMAT="text"
BASE_REF=""
HEAD_REF=""

usage() {
  cat <<'USAGE'
Usage: bash scripts/archgate.sh [--mode structural|semantic|drift] [--rules .rules.ts] [--format text|json] [--base REF] [--head REF]

Modes:
  structural  Run fast .rules.ts structural validation (default).
  semantic    Opt-in placeholder contract for semantic rule checks.
  drift       Opt-in placeholder contract for BRD/PRD/ADR/Archgate drift checks.
USAGE
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

emit_json() {
  local status="$1"
  local mode="$2"
  local reason="$3"
  local exit_code="$4"
  local status_json mode_json rules_json base_json head_json check_id_json message_json
  status_json=$(printf '%s' "$status" | json_escape)
  mode_json=$(printf '%s' "$mode" | json_escape)
  rules_json=$(printf '%s' "$RULES_FILE" | json_escape)
  base_json=$(printf '%s' "$BASE_REF" | json_escape)
  head_json=$(printf '%s' "$HEAD_REF" | json_escape)
  check_id_json=$(printf '%s' "archgate-$mode" | json_escape)
  message_json=$(printf '%s' "$reason" | json_escape)
  cat <<JSON
{"status":$status_json,"mode":$mode_json,"rulesFile":$rules_json,"base":$base_json,"head":$head_json,"checks":[{"id":$check_id_json,"status":$status_json,"message":$message_json}],"exitCode":$exit_code}
JSON
}

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --rules) RULES_FILE="${2:-}"; shift 2 ;;
    --format) FORMAT="${2:-}"; shift 2 ;;
    --base) BASE_REF="${2:-}"; shift 2 ;;
    --head) HEAD_REF="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$MODE" in
  structural|semantic|drift) ;;
  *) echo "Unsupported mode: $MODE" >&2; exit 2 ;;
esac

case "$FORMAT" in
  text|json) ;;
  *) echo "Unsupported format: $FORMAT" >&2; exit 2 ;;
esac

if [ "$MODE" = "structural" ]; then
  set +e
  output=$(bash scripts/validate-rules.sh "$RULES_FILE" 2>&1)
  status_code=$?
  set -e
  if [ "$FORMAT" = "json" ]; then
    if [ "$status_code" -eq 0 ]; then
      emit_json "pass" "$MODE" "$output" 0
    else
      emit_json "fail" "$MODE" "$output" "$status_code"
    fi
  else
    printf '%s\n' "$output"
  fi
  exit "$status_code"
fi

if [ "${ARCHGATE_SEMANTIC:-0}" != "1" ]; then
  message="Optional $MODE checks are skipped. Set ARCHGATE_SEMANTIC=1 after configuring project-specific semantic/drift rules."
  if [ "$FORMAT" = "json" ]; then
    emit_json "skipped" "$MODE" "$message" 0
  else
    echo "$message"
  fi
  exit 0
fi

message="ARCHGATE_SEMANTIC=1 is set, but this repository has not configured a $MODE engine yet. Add the project-specific checker before requiring this mode in CI."
if [ "$FORMAT" = "json" ]; then
  emit_json "fail" "$MODE" "$message" 1
else
  echo "$message" >&2
fi
exit 1
