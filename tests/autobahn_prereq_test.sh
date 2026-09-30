#!/bin/bash
# Offline public CLI regression using disposable, simulated v1 policy inputs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/tests:$REPO_ROOT/scripts${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PYTEST'
import json
from pathlib import Path
import subprocess
import tempfile
from readiness_fixture import fixture, write, digest

REPO = Path.cwd()
WRITER = REPO / '02-govern-plan/northstar/handoff-write.sh'
AUTO = REPO / '04-validate-handoff/autobahn'

def run(script, root, *args):
    return subprocess.run(['bash', str(script), '--root', str(root), *args],
                          capture_output=True, text=True, timeout=10)

def passed(result):
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)

def blocked(result, reason):
    assert result.returncode != 0, result.stdout
    assert reason in result.stdout + result.stderr, result.stdout + result.stderr

for flag in ('--root', '--goal', '--handoff', '--goal-id', '--context'):
    result = subprocess.run(['bash', str(AUTO / 'prereq-check.sh'), flag],
                            capture_output=True, text=True, timeout=2)
    assert result.returncode == 2 and 'usage:' in result.stderr, result
print('PASS: missing CLI values return usage without hanging')

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp) / 'initialized'
    root.mkdir()
    bundle, context = fixture(root)
    args = ('--handoff', 'northstar-plan-chosen', '--goal-id', 'G1',
            '--context', str(root / 'context.json'))
    blocked(run(AUTO / 'prereq-check.sh', root, *args), 'handoff_missing_or_ambiguous')
    print('PASS: exact missing handoff fails closed')
    entry = passed(run(WRITER, root, '--bundle', str(root / 'plan.json')))['published']
    context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
    write(root, 'context.json', context)
    before = {str(p): digest(p) for p in root.rglob('*') if p.is_file()}
    report = passed(run(AUTO / 'prereq-check.sh', root, *args))
    assert report['execution_ready'] and not report['dispatch_authorized']
    assert report['goals'] == ['G1'] and report['plan_id'] == 'chosen'
    assert before == {str(p): digest(p) for p in root.rglob('*') if p.is_file()}
    assert not (root / 'SHOULD_NOT_RUN').exists()
    print('PASS: explicitly selected published handoff is admitted read-only')
    blocked(run(AUTO / 'prereq-check.sh', root), 'selection_required')
    print('PASS: registered handoff is never implicitly selected')

    empty = Path(tmp) / 'empty'
    empty.mkdir()
    result = run(AUTO / 'prereq-check.sh', empty, '--handoff', 'northstar-plan-chosen', '--goal-id', 'G1')
    assert result.returncode != 0, result.stdout
    report = json.loads(result.stdout)
    assert not report['execution_ready'] and not report['dispatch_authorized']
    assert report['gaps'][0]['scope'] == 'repository'
    assert report['gaps'][0]['detail'] == 'v3_root_required'
    assert list(empty.iterdir()) == []
    print('PASS: non-initialized target rejected without mutation')
PYTEST
