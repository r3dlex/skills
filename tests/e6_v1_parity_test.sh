#!/usr/bin/env bash
# Differential proof for e6-sk-02-v1-port. The reference is the frozen Python
# at the commit-and-path anchor, never the working tree. The candidate is the
# TypeScript port. interpreter-diagnostic is the only masked class.
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
export PYTHONDONTWRITEBYTECODE=1
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
# datetime.fromisoformat changes acceptance across Python releases, not merely
# exception wording. Use the commissioned reference runtime on every host.
reference="${E6_V1_REFERENCE_PYTHON:-python3}"
if [[ "$("$reference" -c 'import platform; print(platform.python_version())' 2>/dev/null)" != 3.14.8 ]]; then
	if ! command -v uv >/dev/null 2>&1; then
		echo 'reference_python_required:3.14.8 (install uv or set E6_V1_REFERENCE_PYTHON)' >&2
		exit 1
	fi
	uv python install 3.14.8 >&2 || exit 1
	reference="$(uv python find 3.14.8)" || exit 1
fi
exec "$reference" -B "$REPO_ROOT/tests/fixtures/e6-v1-port/parity.py" "$REPO_ROOT"
