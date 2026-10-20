"""API-only defensive predicates and the original requirement exception seam."""
import copy
import importlib
import json
from pathlib import Path
import subprocess
import tempfile


def compare(parity, operation, args, function):
    try:
        value = parity.observe(function)
        expected, code = {'result': value}, 0
    except (ValueError, OSError) as error:
        expected, code = {'error': str(error), 'type': type(error).__name__, 'code': getattr(error, 'code', None)}, 1
    result = subprocess.run(['node', str(parity.REPO / 'tests/fixtures/e6-v1-port/bridge.mjs'), str(parity.REPO)], input=json.dumps({'operation': operation, 'args': args}), capture_output=True, text=True)
    parity.same('shipping-api-' + operation, (code, (json.dumps(expected, sort_keys=True)+'\n').encode(), b''), (result.returncode, (json.dumps(json.loads(result.stdout), sort_keys=True)+'\n').encode(), result.stderr.encode()))


def run(parity, lib):
    from readiness_fixture import fixture
    from readiness_worktree_test import WorktreeTests
    c = importlib.import_module('readiness_contract')
    assert Path(c.__file__).resolve().parent == lib.resolve()
    with tempfile.TemporaryDirectory(prefix='e6-api-') as temporary:
        root = Path(temporary).resolve()
        bundle, context = fixture(root)
        compare(parity, 'goal_revision', [bundle, 'absent'], lambda: c.goal_revision(bundle, 'absent'))
        mapped = copy.deepcopy(bundle)
        mapped.update(schema='mapped-handoff-goals/1', execution={'repository': {'id': 'application', 'root': str(root)}})
        gate = {'id': 'api-gate', 'kind': 'ownership', 'stage': 'implementation', 'scope': {'repository': True}, 'binding': {'roles': ['owner']}}
        compare(parity, 'gate_subject', [mapped, gate, context['sources'], context['policy'], None, None], lambda: c.gate_subject(mapped, gate, context['sources'], context['policy']))
        receipt = {'goal': 'G1', 'goal_sha256': c.goal_revision(bundle, 'G1'), 'status': 'complete', 'issuer': 'fixture', 'evidence': ['local:passed'], 'observed_at': '2000-01-01T00:00:00Z', 'expires_at': '2099-01-01T00:00:00Z'}
        for change in [dict(receipt, extra=True), dict(receipt, goal_sha256='0'*64), dict(receipt, observed_at='bad')]:
            compare(parity, 'dependency_complete', [bundle, 'G1', [change], None, None], lambda change=change: c.dependency_complete(bundle, 'G1', [change]))
        compare(parity, 'dependency_complete', [mapped, 'G1', [receipt], None, None], lambda: c.dependency_complete(mapped, 'G1', [receipt]))
        requirement = {'id': 'api-requirement', 'stage': 'implementation', 'kind': 'measured_coverage'}
        plain = copy.deepcopy(bundle)
        plain['goals'][0]['requirements'] = [requirement]
        class FaultyRequirement(dict):
            def __iter__(self): return iter(None)
        bundle['goals'][0]['requirements'] = [FaultyRequirement(requirement)]
        def runtime_requirement():
            resolved = []
            gaps = c.policy_admit(root, bundle, ['G1'], context, 'implementation', context['authority']['subject_sha256'], resolved)
            return {'gaps': gaps, 'resolved': resolved}
        compare(parity, 'requirement_runtime', [str(root), plain, context], runtime_requirement)
    case = WorktreeTests('test_exact_linked_worktree_is_read_only_and_observed')
    case.setUp()
    try:
        args = [str(case.identity), str(case.files), case.base, False, ['tests/*']]
        compare(parity, 'worktree_observation', args, lambda: c.worktree_observation(*args))
    finally: case.doCleanups()
