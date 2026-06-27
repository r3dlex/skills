#!/bin/bash
# Validate init-ai-repo cascade fixtures and all configured host adapter contracts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 scripts/validate-cascade-fixtures.py
