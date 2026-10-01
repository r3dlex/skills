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

import copy

result = subprocess.run(['bash', str(AUTO / 'readiness-check.sh'), '--goal'],
                        capture_output=True, text=True, timeout=2)
assert result.returncode == 2 and 'usage:' in result.stderr, result
print('PASS: missing direct-goal value returns usage without hanging')

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bundle, context = fixture(root)
    ready = write(root, 'ready.json', {'schema': 'direct-goal/1', 'bundle': bundle})
    context['authority']['subject_sha256'] = digest(ready)
    write(root, 'context.json', context)
    args = ('--goal', str(ready), '--context', str(root / 'context.json'))
    for name in ('readiness-check.sh', 'prereq-check.sh'):
        report = passed(run(AUTO / name, root, *args))
        assert report['execution_ready'] and not report['dispatch_authorized']
        assert report['goals'] == ['G1']
    assert not (root / 'SHOULD_NOT_RUN').exists()
    print('PASS: both public gates accept explicit nested v1 without a handoff')

    vague = copy.deepcopy(bundle)
    del vague['goals'][0]['verification']
    vague_path = write(root, 'vague.json', {'schema': 'direct-goal/1', 'bundle': vague})
    context['authority']['subject_sha256'] = digest(vague_path)
    write(root, 'context.json', context)
    for name in ('readiness-check.sh', 'prereq-check.sh'):
        result = run(AUTO / name, root, '--goal', str(vague_path), '--context', str(root / 'context.json'))
        assert result.returncode != 0, result.stdout
    print('PASS: incomplete nested v1 rejected by both gates')

    legacy = write(root, 'legacy.json', {'id': 'old', 'implementation_ready': True})
    blocked(run(AUTO / 'readiness-check.sh', root, '--goal', str(legacy)), 'migration_required')
    print('PASS: legacy direct readiness cannot bypass migration')

    # A valid unrelated registration must never rescue the explicit bad goal.
    entry = passed(run(WRITER, root, '--bundle', str(root / 'plan.json')))['published']
    result = run(AUTO / 'prereq-check.sh', root, '--goal', str(vague_path), '--context', str(root / 'context.json'))
    assert result.returncode != 0, result.stdout
    print('PASS: explicit incomplete goal never falls back to registered handoff')

    context['authority']['subject_sha256'] = digest(ready)
    context['policy']['sha256'] = '0' * 64
    write(root, 'context.json', context)
    for name in ('readiness-check.sh', 'prereq-check.sh'):
        blocked(run(AUTO / name, root, *args), 'unapproved_policy_revision')
    print('PASS: both direct gates enforce the independent policy binding')
PYTEST
