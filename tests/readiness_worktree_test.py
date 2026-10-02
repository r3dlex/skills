"""Real linked worktrees; fixture authority never represents live approval."""
import os
import copy
import json
from argparse import Namespace
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from readiness_fixture import fixture, write, digest

REPO = Path(__file__).resolve().parents[1]
SURFACE = Path(os.environ.get('AUTOBAHN_TEST_ROOT', REPO)).resolve()
AUTO = SURFACE / '04-validate-handoff/autobahn' if (SURFACE / '04-validate-handoff').is_dir() else SURFACE / 'autobahn'
sys.path.insert(0, str(AUTO / 'lib'))
import readiness_contract as c


class WorktreeTests(unittest.TestCase):
    def git(self, root, *args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name).resolve()
        self.identity = self.home / 'primary'
        self.identity.mkdir()
        self.git(self.identity, 'init', '-b', 'main')
        self.git(self.identity, 'config', 'user.name', 'Fixture')
        self.git(self.identity, 'config', 'user.email', 'fixture@example.invalid')
        (self.identity / 'AGENTS.md').write_text('Fixture instructions\n')
        (self.identity / 'input.txt').write_text('original\n')
        self.bundle, self.context = fixture(self.identity)
        self.git(self.identity, 'add', '.')
        self.git(self.identity, 'commit', '-m', 'fixture base')
        self.base = self.git(self.identity, 'rev-parse', 'HEAD')
        self.git(self.identity, 'update-ref', 'refs/remotes/origin/main', self.base)
        self.files = self.home / 'execution'
        self.git(self.identity, 'worktree', 'add', '-b', 'feature', str(self.files), self.base)

    def observe(self, **kwargs):
        return c.worktree_observation(self.identity, self.files, self.base, **kwargs)

    def admission_fixture(self):
        self.policy = json.loads((self.files / c.POLICY).read_text())
        self.policy['worktree'] = c.worktree_binding(self.observe())
        write(self.files, c.POLICY, self.policy)
        self.direct = write(self.files, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        inputs = c.worktree_inputs(self.bundle, self.files) + ['direct.json']
        observation = c.worktree_observation(self.identity, self.files, self.base, inputs=inputs)
        self.context['policy']['sha256'] = digest(self.files / c.POLICY)
        self.context['worktree'] = observation
        self.context['authority'].update(worktree=observation, policy_sha256=self.context['policy']['sha256'],
                                         subject_sha256=digest(self.direct))
        self.context_path = write(self.home, 'independent-context.json', self.context)
        self.args = Namespace(root=str(self.identity), worktree_root=str(self.files), base_commit=self.base,
                              execution_root=None, stage='implementation', goal=str(self.direct),
                              goal_id=None, handoff=None, context=str(self.context_path), execution_record=None)
        return self.args

    def refresh_admission(self):
        write(self.files, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        inputs = c.worktree_inputs(self.bundle, self.files) + ['direct.json']
        observation = self.observe(inputs=inputs)
        self.context['worktree'] = observation
        self.context['authority'].update(worktree=observation, subject_sha256=digest(self.direct))
        write(self.home, 'independent-context.json', self.context)

    def test_object_verification_script_mutation_invalidates_admission(self):
        args = self.admission_fixture()
        script = self.files / 'tools/tests/check.sh'
        script.parent.mkdir(parents=True)
        script.write_text('echo original')
        (self.files / '.gitignore').write_text('tools/\n')
        self.bundle['goals'][0]['verification'] = [{'cwd': 'tools', 'command': 'bash tests/check.sh'}]
        self.refresh_admission()
        self.assertTrue(c.admit(args)['execution_ready'])
        script.write_text('echo changed')
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_ignored_script_and_parent_symlinks_are_rejected(self):
        self.admission_fixture()
        target = self.files / 'input.txt'
        directory = self.files / 'tools'
        directory.mkdir()
        (self.files / '.gitignore').write_text('tools/\n')
        script = directory / 'check.sh'
        script.symlink_to(target)
        self.bundle['goals'][0]['verification'] = [{'cwd': 'tools', 'command': 'bash check.sh'}]
        with self.assertRaises(c.Invalid):
            self.observe(inputs=c.worktree_inputs(self.bundle, self.files))
        self.bundle['goals'][0]['verification'] = ['echo fixture']
        write(self.files, 'package.json', {'scripts': {'lint': 'bash tools/check.sh'}})
        with self.assertRaises(c.Invalid):
            self.observe(inputs=c.worktree_inputs(self.bundle, self.files))
        (self.files / 'package.json').unlink()
        (self.files / 'prek.toml').write_text('entry = "bash tools/check.sh"')
        with self.assertRaises(c.Invalid):
            self.observe(inputs=c.worktree_inputs(self.bundle, self.files))
        (self.files / 'prek.toml').unlink()
        script.unlink()
        directory.rmdir()
        directory.symlink_to(self.files, target_is_directory=True)
        self.bundle['goals'][0]['verification'] = ['bash tools/input.txt']
        with self.assertRaises(c.Invalid):
            self.observe(inputs=c.worktree_inputs(self.bundle, self.files))

    def test_new_lint_and_ci_configuration_invalidate_admission(self):
        args = self.admission_fixture()
        for name, content in (
            ('package.json', '{"scripts":{"lint":"echo changed"}}'),
            ('prek.toml', 'repos = []'),
            ('.pre-commit-config.yaml', 'repos: []'),
            ('.ai/ci/local-ci.json', '{"verification":["echo changed"]}'),
            ('.github/workflows/new.yml', 'name: changed'),
        ):
            with self.subTest(configuration=name):
                self.refresh_admission()
                self.assertTrue(c.admit(args)['execution_ready'])
                path = self.files / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
                self.assertFalse(c.admit(args)['execution_ready'])
                path.unlink()

    def test_lint_and_ci_ignored_script_inputs_invalidate_admission(self):
        args = self.admission_fixture()
        script = self.files / 'tools/check.sh'
        script.parent.mkdir(parents=True)
        script.write_text('echo original')
        (self.files / '.gitignore').write_text('tools/\n')
        for name, content in (
            ('package.json', '{"scripts":{"lint":"bash tools/check.sh"}}'),
            ('prek.toml', 'entry = "bash tools/check.sh"'),
            ('.pre-commit-config.yaml', 'entry: bash tools/check.sh'),
            ('.ai/ci/local-ci.json', '{"verification":[{"cwd":"tools","command":"bash check.sh"}]}'),
            ('.github/workflows/new.yml', 'run: bash tools/check.sh'),
        ):
            with self.subTest(configuration=name):
                path = self.files / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
                self.refresh_admission()
                self.assertTrue(c.admit(args)['execution_ready'])
                script.write_text(script.read_text() + '\necho changed')
                self.assertFalse(c.admit(args)['execution_ready'])
                path.unlink()

    def test_arbitrary_ignored_names_and_context_location_fail_closed(self):
        args = self.admission_fixture()
        (self.files / '.gitignore').write_text('tools/\n')
        for name in ('check+v1.sh', 'check with spaces.sh'):
            script = self.files / 'tools' / name
            script.parent.mkdir(exist_ok=True)
            script.write_text('echo original')
            self.refresh_admission()
            self.assertTrue(c.admit(args)['execution_ready'])
            script.write_text('echo changed')
            self.assertFalse(c.admit(args)['execution_ready'])
        args.context = str(write(self.files, 'context.json', self.context))
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_unsupported_no_lazy_fetch_fails_closed_without_retry(self):
        failure = subprocess.CompletedProcess([], 129, stdout=b'', stderr=b'unknown option')
        with patch.object(c.subprocess, 'run', return_value=failure) as run:
            with self.assertRaises(c.Invalid):
                c.git_read(self.files, 'rev-parse', 'HEAD')
        self.assertEqual(run.call_count, 1)
        self.assertIn('--no-lazy-fetch', run.call_args.args[0])

    def test_git_proofs_never_lazy_fetch_missing_objects(self):
        marker = self.home / 'ssh-invoked'
        ssh = self.home / 'fake-ssh.sh'
        ssh.write_text('#!/bin/sh\nprintf invoked >> "' + str(marker) + '"\nexit 1\n')
        ssh.chmod(0o700)
        self.git(self.files, 'config', 'remote.origin.url', 'ssh://fixture.invalid/project')
        self.git(self.files, 'config', 'remote.origin.promisor', 'true')
        self.git(self.files, 'config', 'extensions.partialClone', 'origin')
        self.git(self.files, 'config', 'core.sshCommand', str(ssh))
        tree = self.git(self.files, 'rev-parse', 'HEAD^{tree}')
        (self.identity / '.git/objects' / tree[:2] / tree[2:]).unlink()
        with self.assertRaises(c.Invalid):
            c.git_read(self.files, 'ls-tree', '-r', '-z', self.base)
        self.assertFalse(marker.exists(), 'Git proofs must not invoke promisor transport')

    def test_observation_never_executes_clean_or_process_filters(self):
        (self.files / '.gitattributes').write_text('input.txt filter=probe\n')
        self.git(self.files, 'add', '.gitattributes')
        self.git(self.files, 'commit', '-m', 'declare inert filter fixture')
        (self.files / 'input.txt').write_bytes(b'ORIGINAL\n')
        for kind in ('clean', 'process'):
            for clean in (False, True):
                with self.subTest(kind=kind, merge=clean):
                    marker = self.home / 'filter-invoked'
                    command = 'printf invoked >> ' + str(marker) + ('; cat' if kind == 'clean' else '; exit 1')
                    self.git(self.files, 'config', 'filter.probe.' + kind, command)
                    observation = None
                    try:
                        observation = self.observe(clean=clean)
                    except c.Invalid:
                        pass
                    invoked = marker.exists()
                    marker.unlink(missing_ok=True)
                    self.git(self.files, 'config', '--unset', 'filter.probe.' + kind)
                    self.assertFalse(invoked, 'observer must never invoke repository filters')
                    if not clean:
                        self.assertIsNotNone(observation)

    def test_merge_rejects_staged_blob_mode_and_unmerged_index(self):
        original = self.git(self.files, 'rev-parse', 'HEAD:input.txt')
        different = self.git(self.files, 'rev-parse', 'HEAD:AGENTS.md')
        for mode, blob in (('100644', different), ('100755', original)):
            with self.subTest(mode=mode, blob=blob):
                self.git(self.files, 'update-index', '--cacheinfo', mode + ',' + blob + ',input.txt')
                with self.assertRaises(c.Invalid):
                    self.observe(clean=True)
                self.git(self.files, 'update-index', '--cacheinfo', '100644,' + original + ',input.txt')
        entries = '0 ' + '0' * 40 + '\tinput.txt\n100644 ' + original + ' 1\tinput.txt\n'
        subprocess.run(['git', '-C', str(self.files), 'update-index', '--index-info'], input=entries,
                       text=True, check=True, capture_output=True)
        with self.assertRaises(c.Invalid):
            self.observe(clean=True)

    def test_clean_merge_rejects_filter_normalized_disk_bytes(self):
        self.git(self.files, 'config', 'core.autocrlf', 'true')
        (self.files / 'input.txt').write_bytes(b'original\r\n')
        self.git(self.files, 'add', '--renormalize', 'input.txt')
        self.assertEqual(self.git(self.files, 'status', '--porcelain'), '')
        with self.assertRaises(c.Invalid):
            self.observe(clean=True)

    def test_clean_merge_rejects_executable_change_with_filemode_disabled(self):
        self.git(self.files, 'config', 'core.filemode', 'false')
        path = self.files / 'input.txt'
        path.chmod(path.stat().st_mode | 0o100)
        self.assertEqual(self.git(self.files, 'status', '--porcelain'), '')
        with self.assertRaises(c.Invalid):
            self.observe(clean=True)

    def test_clean_merge_rejects_index_flags_hiding_dirty_bytes(self):
        self.observe(clean=True)
        for flag in ('assume-unchanged', 'skip-worktree'):
            with self.subTest(flag=flag):
                self.git(self.files, 'update-index', '--' + flag, 'input.txt')
                (self.files / 'input.txt').write_text('hidden changed bytes')
                self.assertEqual(self.git(self.files, 'status', '--porcelain'), '')
                with self.assertRaises(c.Invalid):
                    self.observe(clean=True)
                self.git(self.files, 'update-index', '--no-' + flag, 'input.txt')
                self.git(self.files, 'checkout', '--', 'input.txt')
        self.observe(clean=True)

    def test_admission_keeps_canonical_identity_and_reads_only_worktree(self):
        args = self.admission_fixture()
        before = self.git(self.identity, 'status', '--porcelain')
        report = c.admit(args)
        self.assertTrue(report['execution_ready'], report)
        self.assertFalse(report['dispatch_authorized'])
        self.assertEqual(report['repository'], self.bundle['repository'])
        self.assertEqual(report['worktree'], self.context['worktree'])
        self.assertEqual(self.git(self.identity, 'status', '--porcelain'), before)
        (self.files / 'evidence.txt').write_text('bad worktree evidence')
        report = c.admit(args)
        self.assertFalse(report['execution_ready'], report)
        self.assertEqual((self.identity / 'evidence.txt').read_text(), 'observed fixture result')

    def test_context_observations_and_policy_cannot_assert_git_identity(self):
        args = self.admission_fixture()
        original = copy.deepcopy(self.context)
        for key in ('root', 'base_commit', 'head', 'state_sha256', 'common_dir', 'branch', 'target_revision'):
            with self.subTest(key=key):
                context = copy.deepcopy(original)
                context['worktree'][key] = 'incorrect'
                write(self.home, 'independent-context.json', context)
                self.assertFalse(c.admit(args)['execution_ready'])
        write(self.home, 'independent-context.json', original)
        self.policy['worktree']['root'] = str(self.identity)
        write(self.files, c.POLICY, self.policy)
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_new_nested_instruction_invalidates_context(self):
        args = self.admission_fixture()
        (self.files / 'tests/AGENTS.md').write_text('new instructions')
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_missing_bindings_mapped_mix_and_changed_record_block(self):
        args = self.admission_fixture()
        for key in ('worktree_root', 'base_commit'):
            bad = copy.copy(args)
            setattr(bad, key, None)
            self.assertFalse(c.admit(bad)['execution_ready'])
        bad = copy.copy(args)
        bad.execution_root = str(self.files)
        self.assertFalse(c.admit(bad)['execution_ready'])
        record = copy.deepcopy(self.bundle['goals'][0])
        record['scope'] = ['input.txt']
        args.execution_record = str(write(self.home, 'record.json', record))
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_glob_instruction_scope_fails_closed(self):
        args = self.admission_fixture()
        self.bundle['goals'][0]['scope'] = ['tests/**']
        write(self.files, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        self.assertFalse(c.admit(args)['execution_ready'])

    def test_publication_writes_only_isolated_generation_and_retains_identity(self):
        args = self.admission_fixture()
        primary_files = {p.relative_to(self.identity).as_posix(): p.read_bytes()
                         for p in self.identity.rglob('*') if p.is_file() and '.git' not in p.parts}
        candidate = write(self.files, 'candidate.json', self.bundle)
        args.bundle = str(candidate)
        published = c.publish(args)
        entry = published['published']
        immutable = self.files / entry['artifacts']['bundle']['path']
        self.assertEqual(json.loads(immutable.read_text())['repository'], self.bundle['repository'])
        original = immutable.read_bytes()
        self.bundle['extensions'] = {'annotation': 'new isolated generation'}
        write(self.files, 'candidate.json', self.bundle)
        c.publish(args)
        self.assertEqual(immutable.read_bytes(), original)
        for name, value in primary_files.items():
            self.assertEqual((self.identity / name).read_bytes(), value, name)
        self.assertFalse((self.identity / c.GEN).exists())

    def test_dependency_receipt_requires_integration_ancestor_not_current_head(self):
        observation = self.observe()
        now = datetime.now(timezone.utc)
        receipt = {'goal': 'G1', 'goal_sha256': c.goal_revision(self.bundle, 'G1'),
                   'status': 'complete', 'issuer': 'simulated-independent-review',
                   'evidence': ['fixture-only'], 'observed_at': (now - timedelta(minutes=1)).isoformat(),
                   'expires_at': (now + timedelta(hours=1)).isoformat(), 'integration_commit': self.base, 'execution_commit': self.base}
        self.assertTrue(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))
        receipt.pop('execution_commit')
        self.assertFalse(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))
        for value in (None, 'malformed'):
            receipt['execution_commit'] = value
            self.assertFalse(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))
        receipt['execution_commit'] = self.base
        receipt.pop('integration_commit')
        self.assertFalse(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))
        (self.files / 'input.txt').write_text('new successor commit')
        self.git(self.files, 'add', 'input.txt')
        self.git(self.files, 'commit', '-m', 'successor')
        observation = self.observe()
        receipt['integration_commit'] = self.base
        self.assertNotEqual(receipt['execution_commit'], observation['head'])
        self.assertTrue(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))
        receipt['integration_commit'] = observation['head']
        self.assertFalse(c.dependency_complete(self.bundle, 'G1', [receipt], worktree=observation))

    def test_worktree_gate_subject_binds_stage_goal_policy_and_observation(self):
        self.admission_fixture()
        gate = {'id': 'owners', 'kind': 'ownership', 'stage': 'implementation',
                'scope': {'goals': ['G1']}, 'binding': {'roles': ['owner']}}
        observed = self.context['worktree']
        original = c.gate_subject(self.bundle, gate, self.context['sources'], self.context['policy'], worktree=observed)
        for key in ('root', 'head', 'base_commit', 'state_sha256'):
            changed = dict(observed, **{key: 'different'})
            self.assertNotEqual(original, c.gate_subject(self.bundle, gate, self.context['sources'], self.context['policy'], worktree=changed))
        self.assertNotEqual(original, c.gate_subject(self.bundle, dict(gate, stage='merge'), self.context['sources'], self.context['policy'], worktree=observed))
        changed_policy = dict(self.context['policy'], sha256='0' * 64)
        self.assertNotEqual(original, c.gate_subject(self.bundle, gate, self.context['sources'], changed_policy, worktree=observed))

    def test_exact_linked_worktree_is_read_only_and_observed(self):
        before = self.git(self.files, 'status', '--porcelain')
        value = self.observe()
        self.assertEqual(value['schema'], 'git-worktree/1')
        self.assertEqual(value['root'], str(self.files))
        self.assertEqual(value['base_commit'], self.base)
        self.assertEqual(value['head'], self.base)
        self.assertEqual(value['branch'], 'refs/heads/feature')
        self.assertEqual(value['target_revision'], self.base)
        self.assertEqual(len(value['state_sha256']), 64)
        self.assertEqual(self.git(self.files, 'status', '--porcelain'), before)

    def test_dirty_bytes_modes_deletions_and_untracked_instructions_change_state(self):
        initial = self.observe()['state_sha256']
        path = self.files / 'input.txt'
        path.write_text('changed\n')
        changed = self.observe()['state_sha256']
        self.assertNotEqual(initial, changed)
        path.chmod(0o755)
        self.assertNotEqual(changed, self.observe()['state_sha256'])
        path.unlink()
        deleted = self.observe()['state_sha256']
        self.assertNotEqual(changed, deleted)
        nested = self.files / 'nested'
        nested.mkdir()
        (nested / 'AGENTS.md').write_text('New instruction\n')
        self.assertNotEqual(deleted, self.observe()['state_sha256'])
        with self.assertRaises(c.Invalid):
            self.observe(clean=True)

    def test_clone_is_not_a_linked_worktree(self):
        clone = self.home / 'clone'
        self.git(self.home, 'clone', str(self.identity), str(clone))
        with self.assertRaises(c.Invalid):
            c.worktree_observation(self.identity, clone, self.base)

    def test_alias_and_primary_and_wrong_base_rejected(self):
        alias = self.home / 'alias'
        alias.symlink_to(self.files, target_is_directory=True)
        for root in (alias, self.identity, self.files / 'nested/..'):
            with self.subTest(root=root), self.assertRaises(c.Invalid):
                c.worktree_observation(self.identity, root, self.base)
        with self.assertRaises(c.Invalid):
            c.worktree_observation(self.identity, self.files, '0' * 40)

    def test_git_selection_environment_does_not_redirect_observation(self):
        expected = self.observe()
        with patch.dict(os.environ, {'GIT_DIR': str(self.identity / '.git'),
                                     'GIT_WORK_TREE': str(self.identity),
                                     'GIT_INDEX_FILE': str(self.home / 'wrong-index')}):
            self.assertEqual(expected, self.observe())

    def test_detached_execution_rejected(self):
        self.git(self.files, 'checkout', '--detach')
        with self.assertRaises(c.Invalid):
            self.observe()


if __name__ == '__main__':
    unittest.main()
