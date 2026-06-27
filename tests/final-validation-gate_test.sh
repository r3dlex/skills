#!/bin/bash
# Final PR 6F validation gate for init-ai-repo AI-SDLC fixtures and safety checks.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 scripts/validate-final-package.py
bash tests/init-ai-repo_docs_test.sh
bash tests/workflow-fixtures_test.sh
bash tests/traceability-fixtures_test.sh
bash tests/cascade-fixtures_test.sh
bash tests/skill-catalog_test.sh
bash tests/test-skills-validator_test.sh
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json >/tmp/init-ai-repo-final-archgate.json
python3 -m json.tool /tmp/init-ai-repo-final-archgate.json >/dev/null

base_ref="${BASE_REF:-${GITHUB_BASE_REF:-codex/init-ai-repo-catalog-modernization}}"
if git rev-parse --verify --quiet "$base_ref" >/dev/null; then
    git diff --check "$base_ref...HEAD"
elif git rev-parse --verify --quiet "origin/$base_ref" >/dev/null; then
    git diff --check "origin/$base_ref...HEAD"
else
    # Clean shallow CI checkouts may not have the PR base ref. Still check the
    # committed HEAD patch so whitespace errors are not silently ignored.
    git show --check --format= HEAD >/dev/null
fi

printf 'final validation gate passed\n'
