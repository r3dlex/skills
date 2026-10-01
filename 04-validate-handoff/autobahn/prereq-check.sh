#!/usr/bin/env bash
# Explicit v1 admission only. Legacy intake requires migration, never fallback.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$HERE/contract-run.sh" admit "$@"
