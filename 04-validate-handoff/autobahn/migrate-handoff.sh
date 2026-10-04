#!/usr/bin/env bash
# Emits a reviewable normalized candidate to stdout; does not publish or approve.
# With --to readiness-contract/2 the pinned v2 driver runs the migration (R1, O10);
# without a --to token the unchanged v1 legacy migration runs (AC-3: byte-identical).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for argument in "$@"; do
  if [[ "$argument" == "--to" || "$argument" == --to=* ]]; then
    exec bash "$HERE/contract-run-v2.sh" migrate-v2 "$@"
  fi
done
exec bash "$HERE/contract-run.sh" migrate "$@"
