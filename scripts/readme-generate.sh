#!/bin/bash
# Repository convenience wrapper. The distributable skill owns the implementation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../03-configure-generate/ai-catapult-init/scripts/readme-generate.sh" "$@"
