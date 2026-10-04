#!/usr/bin/env bash
# local_ci declaration contract for .ai/workflows/repo-workflow.json (af-06).
#
# The normative shape is documented in
# 03-configure-generate/ai-catapult-init/modules/workflow.md; the validator
# cases (well-formed accepted, malformed rejected with the offending path
# named, absent treated as absent) and the scaffold/fixture checks live in
# tests/local_ci_declaration_test.py.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -I -B tests/local_ci_declaration_test.py
