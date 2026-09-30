#!/usr/bin/env bash
# Emits a reviewable normalized candidate to stdout; does not publish or approve.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/contract-run.sh" migrate "$@"
