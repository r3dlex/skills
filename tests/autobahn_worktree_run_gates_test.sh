#!/usr/bin/env bash
# Driver wiring tests; the real observer/admission tests cover Git and policy.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

source = Path(sys.argv[1]) / '04-validate-handoff/autobahn/run-gates.sh'
with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    driver = root / 'driver'
    driver.mkdir()
    shutil.copy(source, driver / source.name)
    identity = root / 'identity'
    worktree = root / 'worktree'
    identity.mkdir()
    worktree.mkdir()
    record = root / 'record.json'
    record.write_text(json.dumps({'id': 'goal-1'}))
    context = root / 'context.json'
    context.write_text('{}')
    direct = root / 'direct.json'
    direct.write_text('{}')
    log = root / 'calls.jsonl'
    script = '''#!/usr/bin/env bash
python3 - "$0" "$@" <<'STUB'
import json, os, sys
from pathlib import Path
assert 'GIT_DIR' not in os.environ and 'GIT_WORK_TREE' not in os.environ
assert os.environ.get('GIT_NO_REPLACE_OBJECTS') == '1'
name = Path(sys.argv[1]).name
args = sys.argv[2:]
log = Path(os.environ['CALL_LOG'])
previous = log.read_text().splitlines() if log.exists() else []
with log.open('a') as stream:
    stream.write(json.dumps({'name': name, 'args': args}) + '\\n')
if name == 'lint-gate.sh' and os.environ.get('MUTATE_CONTEXT'):
    Path(os.environ['MUTATE_CONTEXT']).write_text('{"changed": true}')
if name == 'prereq-check.sh':
    if os.environ.get('REJECT') == 'initial' or (os.environ.get('REJECT') == 'final' and previous):
        raise SystemExit(1)
    print(json.dumps({'execution_ready': True, 'dispatch_authorized': False,
                      'worktree': {'root': os.environ.get('REPORT_ROOT', os.environ['WORKTREE'])}}))
STUB
'''
    for name in ['prereq-check.sh', 'tdd-evidence.sh', 'lint-gate.sh', 'local-ci.sh', 'ci-gate.sh']:
        (driver / name).write_text(script)
    env = dict(os.environ, CALL_LOG=str(log), WORKTREE=str(worktree),
               GIT_DIR=str(identity / '.git'), GIT_WORK_TREE=str(identity))
    common = ['bash', str(driver / source.name), '--root', str(identity),
              '--goal-record', str(record), '--worktree-root', str(worktree),
              '--base-commit', 'a' * 40]
    def run(extra, overrides=None):
        log.unlink(missing_ok=True)
        result = subprocess.run(common + extra, env=dict(env, **(overrides or {})), capture_output=True, text=True)
        calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        return result, calls
    for phase, expected in [('pre-commit', 2), ('local-validation', 4), ('pre-merge', 2), ('all', 4)]:
        stage = 'merge' if phase in ('all', 'pre-merge') else 'implementation'
        for selection in [['--handoff', 'plan-1'], ['--goal', str(direct)]]:
            args = ['--phase', phase, '--context', str(context)] + selection
            result, calls = run(args)
            assert result.returncode == 0, (phase, result.stdout, result.stderr)
            assert len(calls) == expected + 2, calls
            assert calls[0]['name'] == calls[-1]['name'] == 'prereq-check.sh', calls
            for call in (calls[0], calls[-1]):
                argv = call['args']
                for flag, value in [('--root', str(identity)), ('--worktree-root', str(worktree)),
                                    ('--base-commit', 'a' * 40), ('--stage', stage),
                                    ('--execution-record', str(record)), ('--context', str(context))]:
                    assert argv[argv.index(flag) + 1] == value, call
            for call in calls[1:-1]:
                assert call['args'][call['args'].index('--root') + 1] == str(worktree), call
            result, calls = run(args, {'REJECT': 'initial'})
            assert result.returncode != 0 and len(calls) == 1, calls
            result, calls = run(args, {'REJECT': 'final'})
            assert result.returncode != 0 and len(calls) == expected + 2, calls
        for missing in [['--phase', phase], ['--phase', phase, '--handoff', 'plan-1'],
                        ['--phase', phase, '--context', str(context)]]:
            result, calls = run(missing)
            assert result.returncode != 0 and not calls, calls
    valid = ['--phase', 'local-validation', '--handoff', 'plan-1', '--context', str(context)]
    for extra in [['--execution-root', str(worktree)], ['--goal', str(direct)], ['--base-commit', 'short']]:
        result, calls = run(valid + extra)
        assert result.returncode != 0 and not calls, calls
    result, calls = run(valid, {'MUTATE_CONTEXT': str(context)})
    assert result.returncode != 0 and len(calls) == 6, calls
    result, calls = run(valid, {'REPORT_ROOT': str(identity)})
    assert result.returncode != 0 and len(calls) == 1, calls
print('PASS: all worktree phases route exact admission, revalidate, and fail closed')
PY
