#!/usr/bin/env bash
# Differential proof for e6-sk-02-v1-port. The reference is the frozen Python
# at the commit-and-path anchor, never the working tree. The candidate is the
# TypeScript port. interpreter-diagnostic is the only masked class.
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
export PYTHONDONTWRITEBYTECODE=1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
exec python3 -B "$REPO_ROOT/tests/fixtures/e6-v1-port/parity.py" "$REPO_ROOT"
