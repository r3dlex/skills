#!/bin/bash
#
# autobahn_engine_pick_test.sh  (PR-2, A2/A3; M3)
#
# Feeds fixture goal-shapes to autobahn/engine-pick.sh and asserts the chosen
# engine for each signal, the precedence ties, and the --engine override path.
# The mapping is a pure function of the goal record — deterministic, offline.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="autobahn/engine-pick.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$SCRIPT" ]]; then
  bad "engine-pick.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# assert: "<expected>" <args...>
assert_pick() {
  local want="$1"; shift
  local got rc
  got="$(bash "$SCRIPT" "$@" 2>/dev/null)"; rc=$?
  if [[ "$rc" -eq 0 && "$got" == "$want" ]]; then
    ok "engine-pick($*) -> $got"
  else
    bad "engine-pick($*) -> '$got' (rc $rc), expected '$want'"
  fi
}

# --- single signals (inline flags) -------------------------------------------
assert_pick "ultraqa"   --qa-heavy true
assert_pick "ultraqa"   --kind qa
assert_pick "ultraqa"   --kind test
assert_pick "ultrawork" --parallelizable true
assert_pick "ralph"     --needs-persistence true
assert_pick "team"      # default (no signals)

# --- precedence ties: qa > parallel > persistence > default ------------------
assert_pick "ultraqa"   --qa-heavy true --parallelizable true --needs-persistence true
assert_pick "ultrawork" --parallelizable true --needs-persistence true
assert_pick "ralph"     --needs-persistence true   # over default

# --- override wins -----------------------------------------------------------
assert_pick "team"      --engine team --qa-heavy true           # override beats qa
assert_pick "ralph"     --engine ralph --parallelizable true
assert_pick "ultraqa"   --engine ultraqa
assert_pick "ultrawork" --engine ultrawork

# --- invalid override fails closed (non-zero) --------------------------------
set +e
bash "$SCRIPT" --engine bogus >/dev/null 2>&1; rc_bad=$?
set -e 2>/dev/null || true
if [[ "$rc_bad" -ne 0 ]]; then
  ok "invalid --engine override fails closed (exit $rc_bad)"
else
  bad "invalid --engine override fails closed (got exit 0)"
fi

# --- goal-record file path ---------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/qa.json"      <<'JSON'
{ "id": "g1", "qa_heavy": true }
JSON
cat > "$tmp/par.json"     <<'JSON'
{ "id": "g2", "parallelizable": true }
JSON
cat > "$tmp/persist.json" <<'JSON'
{ "id": "g3", "long_running": true }
JSON
cat > "$tmp/default.json" <<'JSON'
{ "id": "g4" }
JSON
cat > "$tmp/tie.json"     <<'JSON'
{ "id": "g5", "parallelizable": true, "needs_persistence": true }
JSON

assert_pick "ultraqa"   --goal "$tmp/qa.json"
assert_pick "ultrawork" --goal "$tmp/par.json"
assert_pick "ralph"     --goal "$tmp/persist.json"
assert_pick "team"      --goal "$tmp/default.json"
assert_pick "ultrawork" --goal "$tmp/tie.json"
# override beats the goal record
assert_pick "team"      --goal "$tmp/qa.json" --engine team

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
