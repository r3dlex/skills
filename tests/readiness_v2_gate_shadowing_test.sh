#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 -I -B tests/readiness_v2_gate_shadowing_test.py
