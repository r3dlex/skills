#!/bin/bash
# Offline public CLI regression using disposable, simulated v1 policy inputs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/tests:$REPO_ROOT/scripts${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PYTEST'
import copy
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

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bundle, context = fixture(root)
    (root / '.ai/handoff').mkdir(exist_ok=True)
    result = run(REPO / '02-govern-plan/northstar/prereq-check.sh', root)
    assert result.returncode == 0, result.stdout + result.stderr
    print('PASS: Northstar prerequisites recognize initialized fixture')
    entry = passed(run(WRITER, root, '--bundle', str(root / 'plan.json')))['published']
    assert (root / entry['handoff_path']).is_file()
    context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
    write(root, 'context.json', context)
    args = ('--handoff', entry['id'], '--goal-id', 'G1', '--context', str(root / 'context.json'))
    report = passed(run(AUTO / 'prereq-check.sh', root, *args))
    assert report['plan_id'] == bundle['id']
    assert report['goals'] == [bundle['goals'][0]['id']]
    assert report['handoff'] == entry
    assert report['execution_ready'] and not report['dispatch_authorized']
    assert not (root / 'SHOULD_NOT_RUN').exists()
    print('PASS: Northstar publication and explicit Autobahn selection share exact identity')
    blocked(run(AUTO / 'prereq-check.sh', root), 'selection_required')
    registry = json.loads((root / '.ai/workflows/northstar-readiness-v1.json').read_text())
    registry['plans'] = []
    write(root, '.ai/workflows/northstar-readiness-v1.json', registry)
    blocked(run(AUTO / 'prereq-check.sh', root, *args), 'handoff_missing_or_ambiguous')
    print('PASS: omitted selection and missing registration fail closed')

    # This is a test-only adapter for modules/orchestration.md's declared
    # agent boundary, not a production dispatch loop. CLI reports cannot verify
    # live runtime authority; the separate callback below simulates that service.
    calls = []
    authority_checks = []

    def tdd_spy():
        calls.append('tdd')

    def engine_spy():
        calls.append('engine')

    def transition(admission, verify_live_authority):
        if admission.returncode != 0:
            return
        value = json.loads(admission.stdout)
        if value.get('stage') != 'implementation' or value.get('execution_ready') is not True:
            return
        # Subject, goal set and stage are all bound independently. Neither
        # context.authority.status nor a report issuer grants this permission.
        if not verify_live_authority(value['subject_sha256'], tuple(value['goals']), value['stage']):
            return
        tdd_spy()
        engine_spy()

    def absent_live_authority(subject, goals, stage):
        authority_checks.append((subject, goals, stage))
        return False

    failed = run(AUTO / 'prereq-check.sh', root, *args)
    blocked(failed, 'handoff_missing_or_ambiguous')
    transition(failed, absent_live_authority)
    assert calls == [] and authority_checks == []
    print('PASS: failed admission invokes neither TDD nor engine nor live-authority adapter')

    direct = root / 'direct.json'
    direct_args = ('--goal', str(direct), '--context', str(root / 'context.json'))

    def direct_admission(candidate, stage='implementation'):
        write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': candidate})
        context['authority']['subject_sha256'] = digest(direct)
        write(root, 'context.json', context)
        return run(AUTO / 'prereq-check.sh', root, *direct_args, '--stage', stage)

    unknown = copy.deepcopy(bundle)
    unknown['goals'][0]['readiness']['implementation'] = 'unknown'
    unknown_result = direct_admission(unknown)
    blocked(unknown_result, 'goal_not_ready')
    transition(unknown_result, absent_live_authority)
    assert calls == [] and authority_checks == []
    print('PASS: unknown implementation readiness invokes neither TDD nor engine')

    planning = direct_admission(bundle, stage='planning')
    planning_report = passed(planning)
    assert planning_report['planning_complete'] and not planning_report['dispatch_authorized']
    transition(planning, absent_live_authority)
    assert calls == [] and authority_checks == []
    print('PASS: successful planning-only admission invokes neither TDD nor engine')

    ready = direct_admission(bundle)
    ready_report = passed(ready)
    assert ready_report['execution_ready'] and not ready_report['dispatch_authorized']
    # The fixture context already says authority.status=pass. That is explicitly
    # insufficient when the separate live adapter cannot verify permission.
    assert context['authority']['status'] == 'pass'
    transition(ready, absent_live_authority)
    expected_binding = (ready_report['subject_sha256'], ('G1',), 'implementation')
    assert calls == [] and authority_checks == [expected_binding]
    print('PASS: structurally ready report without live authority invokes neither TDD nor engine')

    def simulated_verified_live_authority(subject, goals, stage):
        # Deliberately test-only external-service response; not read from JSON.
        authority_checks.append((subject, goals, stage))
        return (subject, goals, stage) == expected_binding

    transition(ready, simulated_verified_live_authority)
    assert calls == ['tdd', 'engine']
    assert authority_checks == [expected_binding, expected_binding]
    assert not (root / 'SHOULD_NOT_RUN').exists()
    print('PASS: ready admission plus separately simulated bound live authority invokes both spies once')

# Engine selection and merge authority remain separate from contract readiness.
for args, expected in [(('--qa-heavy', 'true'), 'ultraqa'), ((), 'team')]:
    result = subprocess.run(['bash', str(AUTO / 'engine-pick.sh'), *args], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip().splitlines()[-1] == expected, result
print('PASS: engine selector retains qa-heavy and default behavior')
verdict = REPO / 'reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json'
result = subprocess.run(['bash', str(AUTO / 'merge-authority.sh'), '--verdict', str(verdict)], capture_output=True, text=True)
assert result.returncode == 0, result.stdout + result.stderr
print('PASS: separate merge authority accepts its approved fixture verdict')
PYTEST
