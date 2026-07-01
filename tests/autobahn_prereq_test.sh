#!/bin/bash
#
# autobahn_prereq_test.sh  (PR-2, A3)
#
# Proves autobahn/prereq-check.sh is a read-only, fail-closed gate that requires
# BOTH init-ai-repo structure AND a valid northstar handoff. Also exercises the
# A->B contract end-to-end: the handoff this consumes is the one northstar's
# handoff-write.sh produces (shared fixture).
#
#   (a) fixture + valid northstar handoff (written by northstar) -> PASS (exit 0)
#   (b) initialized fixture with NO handoff                       -> FAIL closed
#   (c) non-initialized temp dir                                  -> FAIL closed
#
# The repo root has NO .ai/, so the script always operates on --root.
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="autobahn/prereq-check.sh"
NORTHSTAR_WRITE="northstar/handoff-write.sh"
FIXTURE="reference/fixtures/v3/standalone"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$SCRIPT" ]]; then
  bad "prereq-check.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

tmp_root="$(mktemp -d)"   # (a) initialized + handoff
tmp_noh="$(mktemp -d)"    # (b) initialized, no handoff
tmp_none="$(mktemp -d)"   # (c) non-initialized
trap 'rm -rf "$tmp_root" "$tmp_noh" "$tmp_none"' EXIT

cp -R "$FIXTURE/." "$tmp_root/"
cp -R "$FIXTURE/." "$tmp_noh/"

# (a) produce a valid northstar handoff into tmp_root via the A-side writer.
SLUG="ship-the-thing"
set +e
bash "$NORTHSTAR_WRITE" --root "$tmp_root" \
  --spec "docs/specifications/ACTIVE/intake-and-ship-skills.md" \
  --slug "$SLUG" >/dev/null 2>&1
wrc=$?
set -e 2>/dev/null || true
if [[ "$wrc" -ne 0 ]]; then
  bad "northstar handoff-write produced a fixture handoff (setup, exit $wrc)"
fi

set +e
out_a="$(bash "$SCRIPT" --root "$tmp_root" 2>&1)"; rc_a=$?
set -e 2>/dev/null || true
if [[ "$rc_a" -eq 0 ]]; then
  ok "(a) passes against init + valid northstar handoff"
else
  bad "(a) passes against init + valid northstar handoff (exit $rc_a: $out_a)"
fi

# (b) initialized but no handoff -> fail closed naming the handoff.
set +e
out_b="$(bash "$SCRIPT" --root "$tmp_noh" 2>&1)"; rc_b=$?
set -e 2>/dev/null || true
if [[ "$rc_b" -ne 0 ]]; then
  ok "(b) fails closed when initialized but no handoff (exit $rc_b)"
else
  bad "(b) fails closed when initialized but no handoff (got exit 0)"
fi
if printf '%s' "$out_b" | grep -qi "handoff"; then
  ok "(b) guidance names the missing handoff"
else
  bad "(b) guidance names the missing handoff"
fi

# (c) non-initialized -> fail closed naming ai-catapult-init.
set +e
out_c="$(bash "$SCRIPT" --root "$tmp_none" 2>&1)"; rc_c=$?
set -e 2>/dev/null || true
if [[ "$rc_c" -ne 0 ]]; then
  ok "(c) fails closed against non-initialized dir (exit $rc_c)"
else
  bad "(c) fails closed against non-initialized dir (got exit 0)"
fi
if printf '%s' "$out_c" | grep -qi "ai-catapult-init"; then
  ok "(c) guidance names ai-catapult-init"
else
  bad "(c) guidance names ai-catapult-init"
fi

# read-only: the non-initialized dir must remain empty.
if [[ -z "$(ls -A "$tmp_none")" ]]; then
  ok "prereq-check is read-only (no mutation of target)"
else
  bad "prereq-check is read-only (target was mutated)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
