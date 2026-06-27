#!/bin/bash
# Validate first-class skill catalog metadata budgets and audit artifacts.

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 scripts/validate-skill-catalog.py

python3 - <<'PY'
import json
from pathlib import Path

# Expected live-catalog skill count per root. The repo root tracks the live
# catalog (grows as skills are added); the v3 fixtures model a generated target
# repo and stay pinned.
expected_count = {
    Path('.'): 22,
    Path('reference/fixtures/v3/standalone'): 21,
    Path('reference/fixtures/v3/umbrella'): 21,
}

for root in [Path('.'), Path('reference/fixtures/v3/standalone'), Path('reference/fixtures/v3/umbrella')]:
    count = expected_count[root]
    audit_path = root / '.ai/skills/catalog-audit.json'
    exceptions_path = root / '.ai/skills/description-exceptions.json'
    report_path = root / '.ai/skills/modernization-report.md'
    assert audit_path.is_file(), f'missing {audit_path}'
    assert exceptions_path.is_file(), f'missing {exceptions_path}'
    assert report_path.is_file(), f'missing {report_path}'
    audit = json.loads(audit_path.read_text())
    exceptions = json.loads(exceptions_path.read_text())
    assert audit['schema_version'] == '1.0'
    assert audit['status'] == 'pass'
    assert audit['skill_count'] == count
    assert audit['policy']['target_description_chars'] == 180
    assert audit['policy']['hard_fail_description_chars'] == 280
    assert not audit['failures']
    assert all(skill['description_chars'] <= 180 for skill in audit['skills'])
    assert exceptions['schema_version'] == '1.0'
    assert exceptions['exceptions'] == []
    report = report_path.read_text()
    assert 'status: `pass`' in report
    assert f'skill_count: `{count}`' in report

workflow = Path('reference/fixtures/v3/standalone/.ai/workflows/repo-workflow.md').read_text()
handoff = Path('reference/fixtures/v3/standalone/.ai/handoff/init-ai-repo-handoff.md').read_text()
for linked in ['.ai/skills/catalog-audit.json', '.ai/skills/description-exceptions.json', '.ai/skills/modernization-report.md']:
    assert linked in workflow
    assert linked in handoff
PY

printf 'skill catalog validation passed\n'
