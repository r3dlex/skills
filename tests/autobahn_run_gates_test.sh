#!/bin/bash
#
# autobahn_run_gates_test.sh  (northstar-autobahn-hardening, follow-up)
#
# Unit-tests autobahn/run-gates.sh — the driver that invokes every gate in
# order, so a skipped gate is impossible rather than merely against the rules.
#
# Before this, the gates were prose instructions: the scripts existed and were
# unit-tested, but whether they ran depended on an agent reading SKILL.md and
# choosing to. Documented-but-unrun is the same failure mode as an inert test.
#
# The driver runs GATES, not the goal loop. Sequencing goals stays with
# ultragoal — a driver that took that over would be the reimplementation
# autobahn exists to avoid.
#
# What must hold:
#   - every gate is invoked, and a gate that blocks makes the driver exit 1;
#   - all gates run by default and all failures are reported, so one pass shows
#     everything to fix rather than one thing at a time;
#   - --fail-fast stops at the first block, for the case where later gates are
#     expensive or meaningless;
#   - an unreadable goal record, or a goal record with no id, blocks. The driver
#     cannot address evidence to a goal it cannot name.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="04-validate-handoff/autobahn/run-gates.sh"

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
  ok "run-gates.sh has no bash syntax errors"
else
  bad "run-gates.sh has no bash syntax errors"
fi

ABS="$REPO_ROOT/$SCRIPT"
EVIDENCE="$REPO_ROOT/04-validate-handoff/autobahn/tdd-evidence.sh"

# A repo that passes every gate: derivable CI, an allowlisted verification
# command that succeeds, valid red-then-green evidence, and no lint policy.
green_repo() {
  local root; root="$(mktemp -d)"
  mkdir -p "$root/.github/workflows" "$root/tests"
  printf 'jobs:\n  t:\n    steps:\n      - run: npm test\n' > "$root/.github/workflows/ci.yml"
  printf '#!/bin/sh\nexit 0\n' > "$root/tests/goal_test.sh"
  chmod +x "$root/tests/goal_test.sh"
  python3 - "$root/goal.json" <<'PY'
import json, sys
json.dump({'id': 'slice-1', 'verification': ['bash tests/goal_test.sh']}, open(sys.argv[1], 'w'))
PY
  # Real red-then-green evidence: one command whose result flips.
  printf '#!/bin/sh\ntest -f impl\n' > "$root/tests/flip.sh"; chmod +x "$root/tests/flip.sh"
  bash "$EVIDENCE" --record-red --goal slice-1 --root "$root" --command "sh tests/flip.sh" >/dev/null 2>&1
  touch "$root/impl"
  bash "$EVIDENCE" --record-green --goal slice-1 --root "$root" --command "sh tests/flip.sh" >/dev/null 2>&1
  echo "$root"
}

run() { bash "$ABS" --root "$1" --goal-record "$1/goal.json" "${@:2}" 2>&1; }
rc()  { bash "$ABS" --root "$1" --goal-record "$1/goal.json" "${@:2}" >/dev/null 2>&1; }

# --- the happy path ---------------------------------------------------------
root="$(green_repo)"
if rc "$root"; then
  ok "a repo passing every gate exits 0"
else
  bad "a repo passing every gate exits 0"
fi

out="$(run "$root")"
for gate in tdd-evidence lint-gate ci-gate; do
  if grep -q "$gate" <<<"$out"; then
    ok "the driver reports running $gate"
  else
    bad "the driver reports running $gate"
  fi
done
rm -rf "$root"

# --- a blocking gate blocks the driver --------------------------------------
# Evidence removed: the goal can no longer show red-before-green.
root="$(green_repo)"
rm -f "$root/.ai/evidence/slice-1.json"
if rc "$root"; then
  bad "missing TDD evidence blocks the driver"
else
  ok "missing TDD evidence blocks the driver"
fi
rm -rf "$root"

# --- no derivable CI blocks -------------------------------------------------
root="$(green_repo)"
rm -rf "$root/.github"
if rc "$root"; then
  bad "no derivable CI blocks the driver"
else
  ok "no derivable CI blocks the driver"
fi
rm -rf "$root"

# --- a failing verification command blocks ----------------------------------
root="$(green_repo)"
printf '#!/bin/sh\nexit 1\n' > "$root/tests/goal_test.sh"
if rc "$root"; then
  bad "a failing verification[] command blocks the driver"
else
  ok "a failing verification[] command blocks the driver"
fi
rm -rf "$root"

# --- all gates run by default, so one pass shows everything to fix ----------
root="$(green_repo)"
rm -f "$root/.ai/evidence/slice-1.json"   # gate 1 blocks
rm -rf "$root/.github"                    # gate 3 blocks too
out="$(run "$root")"
if grep -qi "tdd-evidence" <<<"$out" && grep -qi "ci-gate" <<<"$out"; then
  ok "later gates still run after an earlier one blocks"
else
  bad "later gates still run after an earlier one blocks"
fi

# --fail-fast is the opposite contract and must stop early.
out="$(run "$root" --fail-fast)"
if grep -qi "ci-gate" <<<"$out"; then
  bad "--fail-fast stops at the first blocking gate"
else
  ok "--fail-fast stops at the first blocking gate"
fi
rm -rf "$root"

# --- a goal record the driver cannot name blocks ----------------------------
root="$(green_repo)"
printf '{not json' > "$root/goal.json"
if rc "$root"; then
  bad "an unreadable goal record blocks"
else
  ok "an unreadable goal record blocks"
fi

python3 -c "import json,sys; json.dump({'verification':['npm test']}, open(sys.argv[1],'w'))" "$root/goal.json"
if rc "$root"; then
  bad "a goal record with no id blocks"
else
  ok "a goal record with no id blocks"
fi
rm -rf "$root"

# --- a gate script that has gone missing blocks -----------------------------
# The worst outcome for a driver is reporting success because a gate was absent
# rather than passing. Nothing else in the repo detects a gate that stopped
# existing, so assert it here instead of trusting that `bash <missing>` exits
# non-zero and that the driver notices.
root="$(green_repo)"
broken="$(mktemp -d)/run-gates.sh"
mkdir -p "$(dirname "$broken")"
sed 's#\$HERE/lint-gate.sh#$HERE/deliberately-absent.sh#' "$ABS" > "$broken"
if bash "$broken" --root "$root" --goal-record "$root/goal.json" >/dev/null 2>&1; then
  bad "a missing gate script blocks rather than being skipped"
else
  ok "a missing gate script blocks rather than being skipped"
fi
rm -rf "$root" "$(dirname "$broken")"

# --- the empty-BLOCKED path is safe on bash 3.2 -----------------------------
# macOS ships bash 3.2 and this repo has already been bitten by its `set -u`
# behaviour. The success path expands an empty array, so run it under the system
# shell explicitly rather than only under whatever bash the suite happens to use.
if [[ -x /bin/bash ]]; then
  root="$(green_repo)"
  if /bin/bash "$ABS" --root "$root" --goal-record "$root/goal.json" >/dev/null 2>&1; then
    ok "the all-passed path works under /bin/bash ($(/bin/bash -c 'echo $BASH_VERSION'))"
  else
    bad "the all-passed path works under /bin/bash ($(/bin/bash -c 'echo $BASH_VERSION'))"
  fi
  rm -rf "$root"
fi

# --- the driver does not sequence goals -------------------------------------
# Guards the composition boundary: a driver that grew a goal loop would be the
# reimplementation autobahn exists to avoid.
# Scan code only. The script's header prose names ultragoal precisely to explain
# the boundary, and matching that would be checking for the wrong thing — the
# defect would be a goal LOOP, not a mention.
if grep -vE '^\s*#' "$SCRIPT" | grep -qE 'for +goal|while .*goal.*read|goals\[|--goals\b'; then
  bad "run-gates.sh does not reimplement the goal loop"
else
  ok "run-gates.sh does not reimplement the goal loop"
fi

# It must take exactly one goal record, which is what keeps it a gate runner.
if grep -qE '^\s*--goal-record\)' "$SCRIPT"; then
  ok "run-gates.sh takes a single goal record"
else
  bad "run-gates.sh takes a single goal record"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
