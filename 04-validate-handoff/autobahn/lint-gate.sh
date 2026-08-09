#!/usr/bin/env bash
#
# lint-gate.sh — run the repo's own lint policy, blocking on failure.
#
# autobahn had zero lint awareness: it could commit a goal, pass review and
# merge while the repo's own pre-commit policy would have rejected the diff.
#
# Detection order, most specific first:
#   1. prek.toml               -> prek run --all-files
#   2. .pre-commit-config.yaml -> pre-commit run --all-files
#   3. package.json .scripts.lint -> npm run lint
#
# A configured policy whose tool is not installed EXITS NON-ZERO. Nothing linted
# the diff, and reporting that as clean is the exact failure this gate exists to
# prevent — an uninstalled linter is indistinguishable from a passing one only
# if you never check.
#
# No policy at all exits 0 with status "none". A repo without a lint policy has
# not failed lint, and blocking it would make the gate unusable in the repos
# that most need the rest of autobahn.
#
# Ships inert this slice: nothing invokes it yet. See modules/lint-gate.md.
#
# Usage: lint-gate.sh --root <dir>
# Exit codes: 0 clean or no policy; 1 lint failed or could not be run; 2 usage.

set -uo pipefail

ROOT="."

usage() { echo "lint-gate: $1" >&2; exit 2; }
block() { echo "lint-gate: BLOCKED — $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 || usage "--root needs a value" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"

# require <tool> <policy-name> — a declared policy with no runner cannot pass.
require() {
  command -v "$1" >/dev/null 2>&1 \
    || block "$2 declares a lint policy but '$1' is not installed, so nothing linted this diff"
}

run_policy() {
  local name="$1"; shift
  echo "lint-gate: policy=$name"
  if ( cd "$ROOT" && "$@" ); then
    echo "lint-gate: clean ($name)"
    exit 0
  fi
  block "$name reported lint failures"
}

# --- 1. prek ----------------------------------------------------------------
# Wins over .pre-commit-config.yaml: prek is the configured runner, and running
# both would report the same policy twice.
if [[ -f "$ROOT/prek.toml" ]]; then
  require prek "prek.toml"
  run_policy prek prek run --all-files
fi

# --- 2. pre-commit ----------------------------------------------------------
if [[ -f "$ROOT/.pre-commit-config.yaml" ]]; then
  require pre-commit ".pre-commit-config.yaml"
  run_policy pre-commit pre-commit run --all-files
fi

# --- 3. package.json lint script -------------------------------------------
if [[ -f "$ROOT/package.json" ]]; then
  # Three outcomes: has a lint script, has none, or is unreadable. Only the
  # first two are answers; the third must not be read as "no policy".
  PKG="$ROOT/package.json" python3 - <<'PY'
import json, os, sys
from pathlib import Path
try:
    data = json.loads(Path(os.environ['PKG']).read_text(encoding='utf-8'))
except (json.JSONDecodeError, UnicodeDecodeError):
    sys.exit(2)
scripts = data.get('scripts') if isinstance(data, dict) else None
sys.exit(0 if isinstance(scripts, dict) and scripts.get('lint') else 1)
PY
  case $? in
    0)
      require npm "package.json"
      run_policy npm-lint npm run lint --silent
      ;;
    2)
      block "package.json is malformed, so its lint policy cannot be read"
      ;;
  esac
fi

echo "lint-gate: policy=none"
echo "lint-gate: no lint policy configured (prek.toml, .pre-commit-config.yaml, package.json lint)"
exit 0
