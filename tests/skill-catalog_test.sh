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
# catalog and is DATA-DRIVEN (derived from the count of top-level */SKILL.md),
# so adding a skill needs no manual edit and PRs stay order-independent. The v3
# fixtures model a frozen generated target repo and stay pinned.
expected_count = {
    Path('.'): len(json.loads(Path('catalog.json').read_text())['skills']),
    Path('reference/fixtures/v3/standalone'): 21,
    Path('reference/fixtures/v3/umbrella'): 21,
}

for root in [Path('.'), Path('reference/fixtures/v3/standalone'), Path('reference/fixtures/v3/umbrella')]:
    count = expected_count[root]
    audit_path = root / '.ai/skills/catalog-audit.json'
    exceptions_path = root / '.ai/skills/description-exceptions.json'
    body_exceptions_path = root / '.ai/skills/body-line-exceptions.json'
    report_path = root / '.ai/skills/modernization-report.md'
    assert audit_path.is_file(), f'missing {audit_path}'
    assert exceptions_path.is_file(), f'missing {exceptions_path}'
    assert body_exceptions_path.is_file(), f'missing {body_exceptions_path}'
    assert report_path.is_file(), f'missing {report_path}'
    audit = json.loads(audit_path.read_text())
    exceptions = json.loads(exceptions_path.read_text())
    body_exceptions = json.loads(body_exceptions_path.read_text())
    assert audit['schema_version'] == '1.0'
    assert audit['status'] == 'pass'
    assert audit['skill_count'] == count
    assert audit['policy']['target_description_chars'] == 160
    assert audit['policy']['max_description_chars'] == 180
    assert audit['policy']['target_body_lines'] == 100
    assert audit['policy']['max_body_lines_with_exception'] == 180
    assert not audit['failures']
    assert all(skill['description_chars'] <= 160 or skill['description_status'] == 'exception' for skill in audit['skills'])
    assert exceptions['schema_version'] == '1.0'
    assert exceptions['exceptions'] == []
    assert body_exceptions['schema_version'] == '1.0'
    assert body_exceptions['exceptions'] == []
    report = report_path.read_text()
    assert 'status: `pass`' in report
    assert f'skill_count: `{count}`' in report

# Membership parity: the catalog is the machine-readable Interface for the
# live skill set, so the filesystem and catalog.json must name exactly the
# same first-class skills. The validator derives its scan list FROM the
# catalog, so neither an orphaned skill directory nor a ghost entry would
# otherwise be visible to any guard.
catalog = json.loads(Path('catalog.json').read_text())
entries = {entry['name']: entry for entry in catalog['skills']}

on_disk = {}
for phase_dir in sorted(Path('.').glob('0[0-9]-*')):
    if not phase_dir.is_dir():
        continue
    for skill_dir in sorted(p for p in phase_dir.iterdir() if p.is_dir()):
        if (skill_dir / 'SKILL.md').is_file():
            on_disk[skill_dir.name] = skill_dir

orphans = sorted(set(on_disk) - set(entries))
assert not orphans, f'SKILL.md directories missing from catalog.json: {orphans}'
ghosts = sorted(set(entries) - set(on_disk))
assert not ghosts, f'catalog.json entries with no SKILL.md on disk: {ghosts}'
for name, skill_dir in on_disk.items():
    entry = entries[name]
    assert entry['source_path'] == f'{skill_dir.parent.name}/{name}', (
        f'{name}: source_path drift: {entry["source_path"]}'
    )
    assert entry['owner_phase'] == skill_dir.parent.name, (
        f'{name}: owner_phase drift: {entry["owner_phase"]}'
    )

workflow = Path('reference/fixtures/v3/standalone/.ai/workflows/repo-workflow.md').read_text()
handoff = Path('reference/fixtures/v3/standalone/.ai/handoff/init-ai-repo-handoff.md').read_text()
for linked in ['.ai/skills/catalog-audit.json', '.ai/skills/description-exceptions.json', '.ai/skills/body-line-exceptions.json', '.ai/skills/modernization-report.md']:
    assert linked in workflow
    assert linked in handoff
PY

printf 'skill catalog validation passed\n'
