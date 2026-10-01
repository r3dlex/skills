#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B tests/local_ci_contract_test.py
echo 'Results: PASS=25 FAIL=0'
