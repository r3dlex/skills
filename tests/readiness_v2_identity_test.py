"""ACH-S-03 observed identity (AC-6, P6, G3, G5, AC-2, AC-3). A repository is its policy
repository.id plus the observed git common directory: the primary checkout and every registered
linked worktree of one common directory admit against one unchanged readiness-policy/2. The merge
certificate binds that common directory, identity aliases are refused with their own codes, and
the worktree is snapshotted around every gate run. v2 never reads policy.worktree, and #92's v1
worktree mode stays byte-identical. Disposable repositories and ephemeral keys only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import ast
import json
import os
import shutil
import subprocess
import tempfile
import unittest

from readiness_v2_core_test import AUTO, NORTH, POLICY, Fixture, codes, git, sha, v2, observer, write_json
from readiness_v2_certificate_test import BRANCH, PR, CertificateFixture

REPO = Path(__file__).resolve().parents[1]
HANDOFF = 'northstar-plan-plan-a'

# #92's v1 worktree mode and its three tests, byte-identical to skills origin/main d72d7cb.
V1_WORKTREE_PINS = {
    'tests/readiness_worktree_test.py': '310aad2a904a6508ecb3f257bd6eee97e41ba4a653762c465c40b9afecc1ea20',
    'tests/readiness_worktree_test.sh': '44da71e3bb405cf7c45ede68e6ee6aae3e657b1169294931ea0e8cacefed5e81',
    'tests/autobahn_worktree_run_gates_test.sh': '778e939dce02e51bbe2f6b258388286616d19105cd60cd6b799a616d4233846f',
    'tests/autobahn_worktree_driver_integration_test.py': 'f25547edf4971aae10f2f27786d05571f655db0d44c123bdcb6aaea0b4340b50',
    'tests/autobahn_worktree_driver_integration_test.sh': '90ab35eb0357581331a9060811cf0ddd2f2007890bb5f490d369334ee67c4d79',
}


def common_dir(root):
    return str(Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve())


def admit(fixture, root, stage='implementation', env=None):
    return fixture.run(['admit-v2', '--root', str(root), '--handoff', HANDOFF, '--goal-id', 'G1', '--stage', stage],
                       env=env)


def driver_copy(base, anchor):
    """A copy of the autobahn and northstar driver whose observer reads the fixture anchor, with
    the copy's manifests re-pinned to it: the only way a subprocess run reaches a disposable anchor."""
    flat = base / 'driver'
    shutil.copytree(AUTO, flat / 'autobahn', ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copytree(NORTH, flat / 'northstar', ignore=shutil.ignore_patterns('__pycache__'))
    copy = flat / 'autobahn/lib/observer.py'
    needle = "Path(passwd_home()) / '.config/ai-catapult/allowed_signers'"
    text = copy.read_text()
    assert needle in text, 'the observer anchor locator moved'
    copy.write_text(text.replace(needle, 'Path(%r)' % str(anchor)))
    manifest = json.loads((flat / 'autobahn/readiness-dependency-v2.json').read_text())
    for name in manifest['files']:
        path = flat / 'northstar/handoff-write.sh' if name == 'northstar/handoff-write.sh' else flat / 'autobahn' / name
        manifest['files'][name] = sha(path)
    for directory in ('autobahn', 'northstar'):
        (flat / directory / 'readiness-dependency-v2.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
    return flat / 'autobahn'


class LinkedWorktreeAdmissionTests(unittest.TestCase):
    """AC-6, P6: one unchanged policy/2 admits the primary checkout and two linked worktrees."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.fixture = Fixture(self.base)
        self.fixture.approve('in-session')
        self.linked = [self.base / 'linked-branch', self.base / 'linked-detached']
        git(self.fixture.work, 'worktree', 'add', '-q', '-b', 'feat/plan-a-G1', str(self.linked[0]), 'origin/main')
        git(self.fixture.work, 'worktree', 'add', '-q', '--detach', str(self.linked[1]), 'origin/main')

    def test_primary_and_two_linked_worktrees_admit_against_one_unchanged_policy(self):
        policy = git(self.fixture.work, 'rev-parse', 'origin/main:' + POLICY)
        contexts = []
        for root in [self.fixture.work, *self.linked]:
            exit_code, context = admit(self.fixture, root)
            self.assertEqual(exit_code, 0, json.dumps(context, indent=1))
            self.assertTrue(context['admitted'])
            contexts.append(context)
        identities = [c['observation']['facts']['repository']['value'] for c in contexts]
        # Identity is repository.id plus the observed common directory; the root path is informational.
        self.assertEqual({(i['id'], i['common_dir']) for i in identities}, {('fixture', common_dir(self.fixture.work))})
        self.assertEqual([i['root'] for i in identities], [str(r) for r in [self.fixture.work, *self.linked]])
        self.assertEqual(len({json.dumps(c['policy'], sort_keys=True) for c in contexts}), 1)
        self.assertEqual(git(self.fixture.work, 'rev-parse', 'origin/main:' + POLICY), policy)
        for root in [self.fixture.work, *self.linked]:
            self.assertEqual(git(root, 'status', '--porcelain'), '', root)


class IdentityRefusalTests(unittest.TestCase):
    """P6, G3, AC-2: identity aliases are refused, each with its own code."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.fixture = Fixture(self.base)
        self.fixture.approve('in-session')
        self.linked = self.base / 'linked'
        git(self.fixture.work, 'worktree', 'add', '-q', '-b', 'feat/plan-a-G1', str(self.linked), 'origin/main')
        self.assertEqual(admit(self.fixture, self.linked)[0], 0)

    def refused(self, result, expected):
        exit_code, value = result
        self.assertNotEqual(exit_code, 0, json.dumps(value, indent=1))
        self.assertIn(expected, codes(value), json.dumps(value, indent=1))

    def test_an_unregistered_worktree_is_refused(self):
        copied = self.base / 'copied-worktree'
        shutil.copytree(self.linked, copied, symlinks=True)
        self.assertEqual(common_dir(copied), common_dir(self.fixture.work))
        self.refused(admit(self.fixture, copied), 'identity_worktree_unregistered')

    def test_a_bare_repository_is_refused(self):
        bare = self.base / 'mirror.git'
        git(self.base, 'clone', '-q', '--mirror', str(self.fixture.origin), str(bare))
        git(bare, 'update-ref', 'refs/remotes/origin/main', git(self.fixture.work, 'rev-parse', 'origin/main'))
        self.refused(admit(self.fixture, bare), 'identity_bare_repository')

    def test_a_symlinked_root_is_refused(self):
        link = self.base / 'link-to-linked'
        link.symlink_to(self.linked, target_is_directory=True)
        self.refused(admit(self.fixture, link), 'identity_root_symlinked')
        parent = self.base / 'link-to-base'
        parent.symlink_to(self.base, target_is_directory=True)
        self.refused(admit(self.fixture, parent / 'work'), 'identity_root_symlinked')

    def test_a_subdirectory_root_is_refused(self):
        self.refused(admit(self.fixture, self.fixture.work / 'src'), 'identity_root_not_toplevel')

    def test_git_dir_and_git_common_dir_injection_are_refused(self):
        other = self.base / 'other'
        git(self.base, 'init', '-q', str(other))
        for name, value in (('GIT_DIR', other / '.git'), ('GIT_COMMON_DIR', other / '.git')):
            with self.subTest(name=name):
                self.refused(admit(self.fixture, self.linked, env={name: str(value)}), 'identity_git_env_injected')
        # Through the pinned shell entry point the variables reach the observer only to be refused.
        result = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), 'admit-v2', '--root', str(self.linked),
                                 '--handoff', HANDOFF, '--goal-id', 'G1'], capture_output=True, text=True,
                                env=dict(os.environ, GIT_DIR=str(other / '.git')), stdin=subprocess.DEVNULL)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('identity_git_env_injected', codes(json.loads(result.stdout)), result.stdout + result.stderr)


class CertificateIdentityTests(unittest.TestCase):
    """P6, G3: the certificate binds the observed common directory; a merge in another one refuses."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.c = CertificateFixture(self.base)

    def merge_in(self, root, *extra):
        cwd = os.getcwd()
        os.chdir(root)
        try:
            return self.c.fixture.run(['merge-v2', '--pr', PR, *extra], env=self.c.env())
        finally:
            os.chdir(cwd)

    def test_a_linked_worktree_certificate_merges_from_the_primary_checkout(self):
        linked = self.base / 'certify-here'
        git(self.c.fixture.work, 'worktree', 'add', '-q', '--detach', str(linked), self.c.head)
        exit_code, issued = self.c.fixture.run(
            ['certify-v2', '--root', str(linked), '--handoff', HANDOFF, '--goal-id', 'G1', '--pr', PR,
             '--review-record', str(self.c.review)], env=self.c.env())
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        self.assertEqual(issued['certificate']['repository'], {'id': 'fixture', 'common_dir': common_dir(self.c.fixture.work)})
        git(self.c.fixture.work, 'checkout', '-q', '--detach', self.c.head)
        exit_code, result = self.merge_in(self.c.fixture.work)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(len(self.c.merged()), 1)

    def test_merge_refuses_when_the_merge_time_common_dir_differs(self):
        exit_code, issued = self.c.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        self.assertEqual(issued['certificate']['repository']['common_dir'], common_dir(self.c.fixture.work))
        other = self.base / 'other-clone'
        git(self.base, 'clone', '-q', str(self.c.fixture.origin), str(other))
        git(other, 'checkout', '-q', '-b', BRANCH, 'origin/' + BRANCH)
        self.assertEqual(git(other, 'rev-parse', 'HEAD'), self.c.head)
        shutil.copytree(self.c.fixture.state_dir(), Path(common_dir(other)) / 'ai-catapult/observer')
        exit_code, result = self.merge_in(other)
        self.assertEqual(exit_code, 4, json.dumps(result, indent=1))
        self.assertIn('certificate_common_dir_mismatch', codes(result), json.dumps(result, indent=1))
        self.assertEqual(self.c.merged(), [])

    def test_merge_refuses_git_environment_injection(self):
        exit_code, issued = self.c.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        cwd = os.getcwd()
        os.chdir(self.c.fixture.work)
        try:
            exit_code, result = self.c.fixture.run(['merge-v2', '--pr', PR],
                                                   env=self.c.env({'GIT_COMMON_DIR': str(self.base / 'elsewhere')}))
        finally:
            os.chdir(cwd)
        self.assertEqual(exit_code, 4, json.dumps(result, indent=1))
        self.assertIn('identity_git_env_injected', codes(result))
        self.assertEqual(self.c.merged(), [])


class WorktreeSnapshotTests(unittest.TestCase):
    """G3: the observer snapshots the worktree before and after gate commands; merge needs HEAD's tree."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.c = CertificateFixture(self.base)

    def gate_writes_into_the_tree(self, work):
        (work / 'tests/check.sh').write_text('#!/bin/sh\necho ran >> gate.log\nexit 0\n')

    def test_the_snapshot_reuses_the_v1_worktree_observation_and_agrees_across_roots(self):
        from readiness_contract import worktree_observation
        work = self.c.fixture.work
        linked = self.base / 'linked'
        git(work, 'worktree', 'add', '-q', '-b', 'feat/plan-a-snapshot', str(linked), self.c.head)
        base = git(work, 'merge-base', 'HEAD', 'origin/main')
        primary, secondary = observer.worktree_snapshot(work), observer.worktree_snapshot(linked)
        self.assertEqual(secondary['state_sha256'], worktree_observation(work, linked, base)['state_sha256'])
        self.assertEqual(primary, secondary)
        (linked / 'untracked.txt').write_text('x\n')
        self.assertNotEqual(observer.worktree_snapshot(linked)['state_sha256'], secondary['state_sha256'])
        tree = ast.parse((AUTO / 'lib/observer.py').read_text())
        imported = {alias.name for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)
                    and node.module == 'readiness_contract' for alias in node.names}
        self.assertIn('worktree_observation', imported)

    def test_a_gate_that_changes_the_worktree_refuses_the_certificate(self):
        work = self.c.fixture.work
        (work / '.gitignore').write_text('gate.log\n')
        self.gate_writes_into_the_tree(work)
        self.c.head = self.c.fixture.commit_push('test: a gate that writes an ignored file', branch=BRANCH)
        self.c.host({})
        self.c.review = self.c.review_record()
        exit_code, result = self.c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('worktree_changed_during_gates', codes(result), json.dumps(result, indent=1))
        self.assertFalse(result['issued'])

    def test_merge_stage_requires_index_and_working_tree_to_equal_head(self):
        work = self.c.fixture.work
        cases = (lambda: git(work, 'update-index', '--chmod=+x', 'src/app.txt'),
                 lambda: (work / 'src/app.txt').write_text('edited\n'),
                 lambda: (work / 'ignored.log').write_text('x\n'))
        for change in cases:
            with self.subTest(change=change):
                change()
                exit_code, result = self.c.certify()
                self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
                self.assertIn('tree_not_clean', codes(result))
                git(work, 'reset', '-q', '--hard', self.c.head)
                git(work, 'clean', '-q', '-fdx')
        self.assertEqual(self.c.certify()[0], 0)

    def run_gates(self, driver, root, record):
        return subprocess.run(['bash', str(driver / 'run-gates.sh'), '--root', str(root), '--goal-record', str(record),
                               '--handoff', HANDOFF, '--phase', 'local-validation'], capture_output=True, text=True,
                              stdin=subprocess.DEVNULL)

    def test_run_gates_rechecks_the_worktree_snapshot_after_v2_gates(self):
        driver = driver_copy(self.base, self.c.fixture.keys.anchor)
        work = self.c.fixture.work
        record = write_json(self.base / 'record.json', self.c.fixture.bundle['goals'][0])
        linked = self.base / 'linked-gates'
        git(work, 'worktree', 'add', '-q', '-b', 'feat/plan-a-gates', str(linked), self.c.head)
        passed = self.run_gates(driver, linked, record)
        self.assertEqual(passed.returncode, 0, passed.stdout + passed.stderr)
        self.assertIn('v2 implementation admission passed', passed.stdout)
        self.assertIn('v2 worktree recheck passed', passed.stdout)
        self.gate_writes_into_the_tree(linked)
        git(linked, 'add', '-A')
        git(linked, 'commit', '-q', '-m', 'test: a gate that writes into the worktree')
        changed = self.run_gates(driver, linked, record)
        self.assertEqual(changed.returncode, 1, changed.stdout + changed.stderr)
        self.assertIn('worktree_changed_during_gates', changed.stderr)
        self.assertTrue((linked / 'gate.log').is_file())


class SupersedesV1WorktreeTests(unittest.TestCase):
    """G5: v2 never reads policy.worktree, and #92's v1 worktree mode stays byte-identical."""

    def test_a_policy2_carrying_worktree_is_refused_as_unknown(self):
        with tempfile.TemporaryDirectory() as tmp:
            fixture = Fixture(Path(tmp).resolve())
            fixture.approve('in-session')
            policy = json.loads((fixture.work / POLICY).read_text())
            policy['worktree'] = {'schema': 'git-worktree/1', 'root': str(fixture.work), 'base_commit': 'a' * 40,
                                  'target_ref': 'refs/remotes/origin/main'}
            with self.assertRaises(v2.Invalid) as raised:
                v2.validate_policy(policy)
            self.assertEqual(v2.code(raised.exception), 'policy_unknown_field')
            write_json(fixture.work / POLICY, policy)
            fixture.commit_push('a live policy/2 carrying a v1 worktree binding')
            exit_code, context = admit(fixture, fixture.work)
            self.assertNotEqual(exit_code, 0)
            self.assertIn('policy_unknown_field', codes(context), json.dumps(context['gaps'], indent=1))

    def test_v2_sources_never_read_a_policy_worktree_binding(self):
        for name in ('lib/observer.py', 'lib/readiness_contract_v2.py'):
            source = (AUTO / name).read_text()
            for pattern in ("['worktree']", ".get('worktree'", 'policy.worktree', '"worktree"'):
                self.assertNotIn(pattern, source, name)
        tree = ast.parse((AUTO / 'lib/observer.py').read_text())
        imported = {alias.name for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)
                    and node.module == 'readiness_contract' for alias in node.names}
        self.assertLessEqual(imported, {'Invalid', 'canonical', 'read', 'worktree_observation'})
        gates = (AUTO / 'run-gates.sh').read_text()
        self.assertIn('a v2 selection takes no --context, --worktree-root, --base-commit', gates)

    def test_v1_worktree_mode_and_its_three_tests_are_unmodified(self):
        for name, digest in V1_WORKTREE_PINS.items():
            self.assertEqual(sha(REPO / name), digest, name)


class ReleaseSurfaceTests(unittest.TestCase):
    """AC-3: re-pinned manifests and local CI contract, and the v2 section of worktree-execution.md."""

    def test_local_ci_contract_pins_are_current(self):
        import local_ci_contract
        local_ci_contract.read_contract(REPO)  # a stale pin raises ValueError
        contract = json.loads((REPO / '.ai/ci/local-ci.json').read_text())
        for name in ('tests/readiness_v2_identity_test.py', 'tests/readiness_v2_identity_test.sh',
                     'tests/readiness_v2_gate_shadowing_test.py', 'tests/readiness_v2_gate_shadowing_test.sh',
                     '04-validate-handoff/autobahn/lib/observer.py', '04-validate-handoff/autobahn/run-gates.sh',
                     '04-validate-handoff/autobahn/readiness-dependency-v2.json'):
            self.assertEqual(contract['sources'].get(name), sha(REPO / name), name)

    def test_worktree_execution_documents_the_v2_observed_identity(self):
        text = (AUTO / 'modules/worktree-execution.md').read_text()
        self.assertTrue('## readiness-contract/2: observed identity' in text, 'worktree-execution.md has no v2 section')
        for code in ('identity_worktree_unregistered', 'identity_bare_repository', 'identity_root_symlinked',
                     'identity_git_env_injected', 'identity_root_not_toplevel', 'certificate_common_dir_mismatch',
                     'worktree_changed_during_gates', 'policy_unknown_field'):
            self.assertIn(code, text, code)


if __name__ == '__main__':
    unittest.main()
