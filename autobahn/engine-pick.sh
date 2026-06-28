#!/bin/bash
#
# autobahn/engine-pick.sh  (PR-2, A3; M3 deterministic engine-pick)
#
# Pure, deterministic mapping from a sliced-goal record's shape signals to one
# sub-engine. No model call, no network, no clock-dependence.
#
# Signals -> engine, with FIXED precedence qa > parallel > persistence > default:
#   qa_heavy:true (or kind=test|qa)        -> ultraqa
#   parallelizable:true                    -> ultrawork
#   needs_persistence:true (or long_running:true) -> ralph
#   (none)                                 -> team
#
# A --engine <name> override WINS over auto-pick for any of the four valid
# engines; an unknown override is rejected fail-closed (it never silently
# falls back).
#
# Signals are read from a goal-record JSON file (--goal <path>) and/or supplied
# inline as flags for testability; inline flags override the file's values.
#
# Usage:
#   engine-pick.sh [--goal <path>] [--engine <name>]
#                  [--qa-heavy true|false] [--parallelizable true|false]
#                  [--needs-persistence true|false] [--kind <kind>]
# Output:
#   prints the chosen engine name to stdout
# Exit:
#   0  an engine was chosen and printed
#   2  usage error / invalid --engine override
#

set -uo pipefail

VALID_ENGINES="ultraqa ultrawork ralph team"

GOAL="" ; OVERRIDE=""
QA="" ; PAR="" ; PERSIST="" ; KIND=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --goal)               GOAL="${2:-}";    shift 2 ;;
    --engine)             OVERRIDE="${2:-}"; shift 2 ;;
    --qa-heavy)           QA="${2:-}";      shift 2 ;;
    --parallelizable)     PAR="${2:-}";     shift 2 ;;
    --needs-persistence)  PERSIST="${2:-}"; shift 2 ;;
    --kind)               KIND="${2:-}";    shift 2 ;;
    *) echo "usage: engine-pick.sh [--goal <p>] [--engine <n>] [--qa-heavy b] [--parallelizable b] [--needs-persistence b] [--kind k]" >&2; exit 2 ;;
  esac
done

is_valid_engine() {
  local e="$1"
  for v in $VALID_ENGINES; do
    [[ "$e" == "$v" ]] && return 0
  done
  return 1
}

# --- override wins (fail-closed on unknown engine) ---------------------------
if [[ -n "$OVERRIDE" ]]; then
  if is_valid_engine "$OVERRIDE"; then
    echo "$OVERRIDE"
    exit 0
  fi
  echo "engine-pick: invalid --engine override '$OVERRIDE' (valid: $VALID_ENGINES)" >&2
  exit 2
fi

# --- resolve signals from the goal record, inline flags take precedence ------
if [[ -n "$GOAL" ]]; then
  if [[ ! -f "$GOAL" ]]; then
    echo "engine-pick: --goal '$GOAL' not found" >&2
    exit 2
  fi
  read -r g_qa g_par g_persist g_kind < <(python3 - "$GOAL" <<'PY'
import json, sys
try:
    g = json.load(open(sys.argv[1]))
except Exception as e:
    print("err err err err"); sys.exit(0)
def b(v): return "true" if v is True else ("false" if v is False else "")
qa = b(g.get("qa_heavy"))
par = b(g.get("parallelizable"))
persist = b(g.get("needs_persistence", g.get("long_running")))
kind = g.get("kind", "") or "-"
print(qa or "-", par or "-", persist or "-", kind)
PY
)
  [[ "$g_qa" == "err" ]] && { echo "engine-pick: could not parse --goal '$GOAL'" >&2; exit 2; }
  [[ -z "$QA"      && "$g_qa"      != "-" ]] && QA="$g_qa"
  [[ -z "$PAR"     && "$g_par"     != "-" ]] && PAR="$g_par"
  [[ -z "$PERSIST" && "$g_persist" != "-" ]] && PERSIST="$g_persist"
  [[ -z "$KIND"    && "$g_kind"    != "-" ]] && KIND="$g_kind"
fi

# --- deterministic mapping with fixed precedence -----------------------------
if [[ "$QA" == "true" || "$KIND" == "test" || "$KIND" == "qa" ]]; then
  echo "ultraqa"; exit 0
fi
if [[ "$PAR" == "true" ]]; then
  echo "ultrawork"; exit 0
fi
if [[ "$PERSIST" == "true" ]]; then
  echo "ralph"; exit 0
fi
echo "team"
exit 0
