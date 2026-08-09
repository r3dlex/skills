#!/bin/bash
#
# autobahn_tdd_evidence_test.sh  (northstar-autobahn-hardening, Slice 3)
#
# Unit-tests autobahn/tdd-evidence.sh, which turns "we did TDD" from a claim
# into an artifact: .ai/evidence/<goal-id>.json recording a test command, the
# non-zero exit it produced before the implementation, and the zero exit after.
#
# The script ships INERT this slice (decision 12) — nothing invokes it yet, so
# these unit tests are the only thing holding its contract. Slice 7 wires it.
#
# What fail-closed has to mean here: absent evidence, malformed evidence, a
# "red" run that actually passed, a "green" run that actually failed, and green
# recorded without a preceding red must all exit non-zero. An evidence gate that
# accepts missing evidence is worse than none — it certifies what it never saw.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="04-validate-handoff/autobahn/tdd-evidence.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -x "$SCRIPT" ]]; then
  bad "$SCRIPT exists and is executable"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "$SCRIPT exists and is executable"

if bash -n "$SCRIPT"; then
  ok "tdd-evidence.sh has no bash syntax errors"
else
  bad "tdd-evidence.sh has no bash syntax errors"
fi

run() { bash "$REPO_ROOT/$SCRIPT" "$@" >/dev/null 2>&1; }

# Each case gets a clean root so ordering between cases cannot leak.
new_root() { mktemp -d; }

# --- verify fails closed on absent evidence ---------------------------------
root="$(new_root)"
if run --verify --goal slice-1 --root "$root"; then
  bad "verify fails closed when no evidence file exists"
else
  ok "verify fails closed when no evidence file exists"
fi
rm -rf "$root"

# --- verify fails closed on malformed evidence ------------------------------
root="$(new_root)"
mkdir -p "$root/.ai/evidence"
printf '{not json' > "$root/.ai/evidence/slice-1.json"
if run --verify --goal slice-1 --root "$root"; then
  bad "verify fails closed on malformed evidence"
else
  ok "verify fails closed on malformed evidence"
fi
rm -rf "$root"

# --- record-red rejects a command that passes -------------------------------
# A "failing test" that exits 0 is the whole failure mode this gate exists for:
# it means the test does not actually cover the change.
root="$(new_root)"
if run --record-red --goal slice-1 --root "$root" --command "true"; then
  bad "record-red rejects a command that exits 0"
else
  ok "record-red rejects a command that exits 0"
fi
if [[ -f "$root/.ai/evidence/slice-1.json" ]]; then
  bad "record-red writes no evidence when the command passed"
else
  ok "record-red writes no evidence when the command passed"
fi
rm -rf "$root"

# --- record-red accepts a genuinely failing command -------------------------
# One command whose result flips, as in real TDD: it fails until the
# implementation lands, then passes. Using two different commands here would be
# testing something else entirely (see the mismatch case at the end).
root="$(new_root)"
FLIPPING="test -f impl"
if run --record-red --goal slice-1 --root "$root" --command "$FLIPPING"; then
  ok "record-red accepts a command that exits non-zero"
else
  bad "record-red accepts a command that exits non-zero"
fi
if [[ -f "$root/.ai/evidence/slice-1.json" ]]; then
  ok "record-red writes .ai/evidence/<goal-id>.json"
else
  bad "record-red writes .ai/evidence/<goal-id>.json"
fi

# red alone is not proof of TDD — the implementation still has to land.
if run --verify --goal slice-1 --root "$root"; then
  bad "verify fails closed with red recorded but no green"
else
  ok "verify fails closed with red recorded but no green"
fi

# --- record-green rejects a command that still fails ------------------------
# The implementation has not landed yet, so the same command is still red.
if run --record-green --goal slice-1 --root "$root" --command "$FLIPPING"; then
  bad "record-green rejects a command that exits non-zero"
else
  ok "record-green rejects a command that exits non-zero"
fi

# --- the happy path ---------------------------------------------------------
touch "$root/impl"   # the implementation lands; the same command now passes
if run --record-green --goal slice-1 --root "$root" --command "$FLIPPING"; then
  ok "record-green accepts a command that exits 0"
else
  bad "record-green accepts a command that exits 0"
fi
if run --verify --goal slice-1 --root "$root"; then
  ok "verify passes on recorded red-then-green"
else
  bad "verify passes on recorded red-then-green"
fi
rm -rf "$root"

# --- green without a preceding red fails closed -----------------------------
# Implementation-first work can still make a test pass; what it cannot produce
# is a red observation from before the code existed.
root="$(new_root)"
run --record-green --goal slice-1 --root "$root" --command "true"
if run --verify --goal slice-1 --root "$root"; then
  bad "verify fails closed when green was recorded with no red"
else
  ok "verify fails closed when green was recorded with no red"
fi
rm -rf "$root"

# --- the recorded command must be the same one on both legs -----------------
# Otherwise a red from an unrelated failing command certifies a green elsewhere.
root="$(new_root)"
run --record-red   --goal slice-1 --root "$root" --command "false"
run --record-green --goal slice-1 --root "$root" --command "true"
if run --verify --goal slice-1 --root "$root"; then
  bad "verify fails closed when red and green used different commands"
else
  ok "verify fails closed when red and green used different commands"
fi
rm -rf "$root"

# --- goal ids may not escape the evidence directory -------------------------
root="$(new_root)"
if run --record-red --goal "../escape" --root "$root" --command "false"; then
  bad "a traversing goal id is rejected"
else
  ok "a traversing goal id is rejected"
fi
rm -rf "$root"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
