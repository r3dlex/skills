#!/bin/bash
# Old/new reader compatibility matrix; real baseline scripts, never substitutes.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/tests${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PY'
import json
from pathlib import Path
import subprocess
import tempfile
from readiness_fixture import fixture, write, digest

REPO = Path.cwd()
BASELINE = '597393a73d82218010615282e6871b57700f2613'
AUTO = REPO / '04-validate-handoff/autobahn'
WRITER = REPO / '02-govern-plan/northstar/handoff-write.sh'
checks = 0


def passed(label):
    global checks
    checks += 1
    print('PASS: ' + label)


def run(script, *args):
    return subprocess.run(['bash', str(script), *args], capture_output=True, text=True, timeout=10)


def rejected(result, reason, code=1):
    assert result.returncode == code, result.stdout + result.stderr
    assert reason in result.stdout + result.stderr, result.stdout + result.stderr


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / 'repo'
    root.mkdir()
    old = Path(tmp) / 'baseline-readers'
    old.mkdir()
    for name in ('prereq-check.sh', 'readiness-check.sh'):
        # check=True makes unavailable baseline objects an explicit test error.
        extracted = subprocess.run(
            ['git', 'show', f'{BASELINE}:04-validate-handoff/autobahn/{name}'],
            cwd=REPO, capture_output=True, check=True)
        assert extracted.stdout.startswith(b'#!/bin/bash'), 'Unexpected baseline script'
        (old / name).write_bytes(extracted.stdout)
    passed('both sibling legacy readers extracted from the exact Git baseline')

    bundle, context = fixture(root)
    publication = run(WRITER, '--root', str(root), '--bundle', str(root / 'plan.json'))
    assert publication.returncode == 0, publication.stdout + publication.stderr
    entry = json.loads(publication.stdout)['published']
    context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
    write(root, 'context.json', context)
    selected = ('--root', str(root), '--handoff', entry['id'], '--goal-id', 'G1',
                '--context', str(root / 'context.json'))
    admitted = run(AUTO / 'prereq-check.sh', *selected)
    assert admitted.returncode == 0, admitted.stdout + admitted.stderr
    assert json.loads(admitted.stdout)['plan_id'] == bundle['id']
    assert (root / entry['handoff_path']).is_file()
    rejected(run(old / 'prereq-check.sh', '--root', str(root)), 'no valid northstar handoff')
    passed('old generic discovery cannot see the separately registered valid v1 publication')

    for flag, value in (('--handoff', entry['id']), ('--goal-id', 'G1')):
        rejected(run(old / 'prereq-check.sh', '--root', str(root), flag, value), 'usage:', code=2)
    passed('old reader rejects each new explicit selector as unsupported')

    direct = write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
    rejected(run(old / 'readiness-check.sh', '--goal', str(direct)), 'implementation_ready must be true')
    rejected(run(old / 'prereq-check.sh', '--root', str(root), '--goal', str(direct)),
             'direct goal failed')
    passed('old direct checker and old prerequisite wrapper reject the nested v1 envelope')

    legacy = {'id': 'northstar-handoff-unrelated-legacy', 'status': 'available'}
    write(root, '.ai/workflows/repo-workflow.json', {'optional_branches': [legacy]})
    (root / '.ai/handoff/northstar-unrelated-legacy.md').write_text('# Unrelated legacy plan\n')
    result = run(old / 'prereq-check.sh', '--root', str(root))
    assert result.returncode == 0, result.stdout + result.stderr
    assert "handoff ('unrelated-legacy')" in result.stdout, result.stdout
    assert "handoff ('chosen')" not in result.stdout
    assert entry['id'] not in result.stdout
    passed('old generic success identifies ONLY unrelated legacy work; old discovery remains unsafe')

    rejected(run(old / 'prereq-check.sh', '--root', str(root), '--goal', str(direct)),
             'direct goal failed')
    rejected(run(AUTO / 'prereq-check.sh', '--root', str(root)), 'selection_required')
    passed('explicit old direct failure and new missing-selection failure never fall back')

    legacy_goal = write(root, 'legacy-goal.json', {'id': 'old', 'implementation_ready': True})
    for name in ('prereq-check.sh', 'readiness-check.sh'):
        rejected(run(AUTO / name, '--root', str(root), '--goal', str(legacy_goal),
                     '--context', str(root / 'context.json')), 'migration_required')
    passed('both new readers require migration for legacy direct records despite registered plans')

    # Even moving an old registration into the new index does not upgrade it.
    registry = json.loads((root / '.ai/workflows/northstar-readiness-v1.json').read_text())
    registry['plans'].append(legacy)
    write(root, '.ai/workflows/northstar-readiness-v1.json', registry)
    rejected(run(AUTO / 'prereq-check.sh', '--root', str(root), '--handoff', legacy['id'],
                 '--goal-id', 'G1', '--context', str(root / 'context.json')), 'migration_required')
    passed('new explicit legacy registration rejects migration instead of selecting the valid v1 plan')

    assert not (root / 'SHOULD_NOT_RUN').exists()
    assert digest(old / 'prereq-check.sh') != digest(AUTO / 'prereq-check.sh')

assert checks == 8
print(f'Results: PASS={checks} FAIL=0')
PY
