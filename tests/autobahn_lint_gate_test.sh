#!/bin/bash
#
# autobahn_lint_gate_test.sh  (northstar-autobahn-hardening, Slice 5)
#
# Unit-tests autobahn/lint-gate.sh. autobahn had zero lint awareness: it could
# commit a goal, pass review and merge while the repo's own pre-commit policy
# would have rejected the diff.
#
# The gate detects a configured framework and runs it, or runs the repo's lint
# directly when none is configured. Ships INERT (decision 12) — slice 7 wires it.
#
# The three states that matter, and why:
#   - configured + passing  -> 0
#   - configured + failing  -> non-zero (the whole point)
#   - configured + tool missing -> non-zero. This is the subtle one: a repo that
#     declares a policy whose tool is absent has NOT been linted, and reporting
#     that as clean is the failure mode this gate exists to prevent.
#   - nothing configured    -> 0, reported as "none". A repo with no lint policy
#     is not a repo that failed lint, and blocking it would make the gate
#     unusable everywhere it is most needed.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="04-validate-handoff/autobahn/lint-gate.sh"

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
  ok "lint-gate.sh has no bash syntax errors"
else
  bad "lint-gate.sh has no bash syntax errors"
fi

ABS="$REPO_ROOT/$SCRIPT"
run()  { bash "$ABS" --root "$1" >/dev/null 2>&1; }
emit() { bash "$ABS" --root "$1" 2>/dev/null; }

# A fake bin dir lets a case decide whether the declared tool exists at all.
stub() {
  local dir="$1" name="$2" code="$3"
  mkdir -p "$dir/bin"
  printf '#!/bin/sh\nexit %s\n' "$code" > "$dir/bin/$name"
  chmod +x "$dir/bin/$name"
}

with_path() {
  # with_path <bindir> <root> — run the gate with only the stub dir prepended.
  local bindir="$1" root="$2"
  PATH="$bindir:$PATH" bash "$ABS" --root "$root" >/dev/null 2>&1
}

# --- nothing configured -----------------------------------------------------
root="$(mktemp -d)"
if run "$root"; then
  ok "a repo with no lint policy passes"
else
  bad "a repo with no lint policy passes"
fi
# Capture before grepping: under `pipefail`, `grep -q` closes the pipe on its
# first match and the producer's SIGPIPE becomes the pipeline's status, so a
# successful match reads as a failure.
report="$(emit "$root")"
if grep -q "none" <<<"$report"; then
  ok "a repo with no lint policy reports 'none'"
else
  bad "a repo with no lint policy reports 'none'"
fi
rm -rf "$root"

# --- prek.toml, tool passes -------------------------------------------------
root="$(mktemp -d)"
: > "$root/prek.toml"
stub "$root" prek 0
if with_path "$root/bin" "$root"; then
  ok "prek.toml with a passing prek exits 0"
else
  bad "prek.toml with a passing prek exits 0"
fi
report="$(PATH="$root/bin:$PATH" bash "$ABS" --root "$root" 2>/dev/null)"
if grep -q "prek" <<<"$report"; then
  ok "prek.toml is detected and named in the report"
else
  bad "prek.toml is detected and named in the report"
fi
rm -rf "$root"

# --- prek.toml, tool fails --------------------------------------------------
root="$(mktemp -d)"
: > "$root/prek.toml"
stub "$root" prek 1
if with_path "$root/bin" "$root"; then
  bad "a failing prek run blocks"
else
  ok "a failing prek run blocks"
fi
rm -rf "$root"

# --- configured but the tool is not installed -------------------------------
# Nothing linted the diff, so the gate must not report clean.
root="$(mktemp -d)"
: > "$root/.pre-commit-config.yaml"
empty="$(mktemp -d)"; mkdir -p "$empty/bin"
if PATH="$empty/bin" bash "$ABS" --root "$root" >/dev/null 2>&1; then
  bad "a configured framework with a missing tool blocks"
else
  ok "a configured framework with a missing tool blocks"
fi
rm -rf "$root" "$empty"

# --- package.json lint script ----------------------------------------------
root="$(mktemp -d)"
printf '{"scripts":{"lint":"exit 0"}}' > "$root/package.json"
stub "$root" npm 0
if with_path "$root/bin" "$root"; then
  ok "a package.json lint script is detected and run"
else
  bad "a package.json lint script is detected and run"
fi
rm -rf "$root"

root="$(mktemp -d)"
printf '{"scripts":{"lint":"exit 1"}}' > "$root/package.json"
stub "$root" npm 1
if with_path "$root/bin" "$root"; then
  bad "a failing package.json lint script blocks"
else
  ok "a failing package.json lint script blocks"
fi
rm -rf "$root"

# --- a package.json without a lint script is not a lint policy --------------
root="$(mktemp -d)"
printf '{"scripts":{"test":"exit 0"}}' > "$root/package.json"
if run "$root"; then
  ok "a package.json without a lint script reports no policy"
else
  bad "a package.json without a lint script reports no policy"
fi
rm -rf "$root"

# --- malformed package.json fails closed ------------------------------------
# It may well declare a lint script; the gate cannot tell, so it cannot pass.
root="$(mktemp -d)"
printf '{not json' > "$root/package.json"
if run "$root"; then
  bad "a malformed package.json fails closed"
else
  ok "a malformed package.json fails closed"
fi
rm -rf "$root"

# --- detection precedence ---------------------------------------------------
# prek.toml wins over .pre-commit-config.yaml: prek is the configured runner
# for this workspace, and running both would double-report the same policy.
root="$(mktemp -d)"
: > "$root/prek.toml"
: > "$root/.pre-commit-config.yaml"
stub "$root" prek 0
stub "$root" pre-commit 1
if with_path "$root/bin" "$root"; then
  ok "prek.toml takes precedence over .pre-commit-config.yaml"
else
  bad "prek.toml takes precedence over .pre-commit-config.yaml"
fi
rm -rf "$root"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
