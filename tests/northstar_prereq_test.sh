#!/bin/bash
#
# northstar_prereq_test.sh  (PR-1, N3)
#
# Proves 02-govern-plan/northstar/prereq-check.sh is a read-only, fail-closed presence gate:
#   (a) against the standalone fixture (real .ai/) -> PASS (exit 0).
#   (b) against a non-initialized temp dir         -> FAIL closed (non-zero)
#       with actionable guidance on stderr.
#
# The repo root has NO .ai/, so the script always operates on --root.
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="02-govern-plan/northstar/prereq-check.sh"
FIXTURE="reference/fixtures/v3/standalone"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$SCRIPT" ]]; then
  bad "prereq-check.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# (a) initialized fixture -> exit 0
set +e
out_ok="$(bash "$SCRIPT" --root "$FIXTURE" 2>&1)"
rc_ok=$?
set -e 2>/dev/null || true
if [[ "$rc_ok" -eq 0 ]]; then
  ok "prereq passes against initialized fixture"
else
  bad "prereq passes against initialized fixture (got exit $rc_ok: $out_ok)"
fi

# (b) non-initialized temp dir -> non-zero + guidance
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
set +e
out_bad="$(bash "$SCRIPT" --root "$tmp" 2>&1)"
rc_bad=$?
set -e 2>/dev/null || true
if [[ "$rc_bad" -ne 0 ]]; then
  ok "prereq fails closed against non-initialized dir (exit $rc_bad)"
else
  bad "prereq fails closed against non-initialized dir (got exit 0)"
fi
if printf '%s' "$out_bad" | grep -qi "ai-catapult-init"; then
  ok "fail-closed output names ai-catapult-init guidance"
else
  bad "fail-closed output names ai-catapult-init guidance"
fi

# read-only: the temp dir must remain empty (no mutation).
if [[ -z "$(ls -A "$tmp")" ]]; then
  ok "prereq-check is read-only (no mutation of target)"
else
  bad "prereq-check is read-only (target was mutated)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
