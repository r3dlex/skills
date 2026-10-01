#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B scripts/scan-secret-material.py
