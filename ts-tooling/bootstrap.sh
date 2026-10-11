#!/usr/bin/env bash
# Gate-workspace bootstrap. Stays bash: local-ci/2 runs `bash <pinned source>`
# and the observer's sanitized environment (including npm_config_*) must reach npm.
set -euo pipefail
cd -- "$(dirname -- "$0")"
exec npm ci --ignore-scripts
