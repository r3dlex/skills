#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="autobahn/tdd-mode.sh"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_mode() {
  local want="$1"; shift
  local got rc
  got="$(bash "$SCRIPT" "$@" 2>/dev/null)"; rc=$?
  if [[ "$rc" -eq 0 && "$got" == "$want" ]]; then
    ok "tdd-mode($*) -> $got"
  else
    bad "tdd-mode($*) -> '$got' (rc $rc), expected '$want'"
  fi
}

assert_mode legacy-safe --coverage-percent 0
assert_mode legacy-safe --coverage-percent 29.99
assert_mode standard --coverage-percent 30
assert_mode standard --coverage-percent 85.4
assert_mode legacy-safe --coverage-percent 85.4 --legacy-risk true --legacy-risk-reason "High coupling at the change seam"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '%s\n' '{"coverage_percent": 12}' > "$tmp/legacy.json"
printf '%s\n' '{"coverage_percent": 72}' > "$tmp/covered.json"
printf '%s\n' '{"coverage_percent": 72, "legacy_safe_tdd": true, "legacy_risk_reason": "High coupling across an untested change seam."}' > "$tmp/complex.json"
assert_mode legacy-safe --goal "$tmp/legacy.json"
assert_mode standard --goal "$tmp/covered.json"
assert_mode legacy-safe --goal "$tmp/complex.json"

if bash "$SCRIPT" --coverage-percent unknown >/dev/null 2>&1; then
  bad "invalid coverage fails closed"
else
  ok "invalid coverage fails closed"
fi

if bash "$SCRIPT" --coverage-percent 80 --legacy-risk true >/dev/null 2>&1; then
  bad "agent-selected legacy risk requires an auditable reason"
else
  ok "agent-selected legacy risk requires an auditable reason"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
