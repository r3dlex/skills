"""Mapped readiness uses disposable repositories and simulated authority only."""
import copy
import json
import os
import shutil
from argparse import Namespace
from datetime import datetime, timedelta, timezone
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from readiness_fixture import digest, fixture, write

REPO = Path(__file__).resolve().parents[1]
SURFACE = Path(os.environ.get('AUTOBAHN_TEST_ROOT', REPO)).resolve()
AUTO = SURFACE / '04-validate-handoff/autobahn' if (SURFACE / '04-validate-handoff').is_dir() else SURFACE / 'autobahn'
NORTH = SURFACE / '02-govern-plan/northstar' if (SURFACE / '02-govern-plan').is_dir() else SURFACE / 'northstar'
sys.path.insert(0, str(AUTO / 'lib'))
import readiness_contract as c


class MappedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.root = self.base / 'planning'
        self.execution = self.base / 'application'
        self.root.mkdir()
        self.execution.mkdir()
        self.bundle, self.context = fixture(self.root)
        (self.execution / 'AGENTS.md').write_text('Separate application instructions')
        (self.execution / 'tests').mkdir()
        (self.execution / 'tests/check.sh').write_text('#!/bin/sh\ntouch EXECUTED\n')
        self.binding = {'repository': {'id': 'application', 'root': str(self.execution)},
                        'target': 'master', 'source_revision': 'a' * 40,
                        'sources': [{'path': 'AGENTS.md', 'sha256': digest(self.execution / 'AGENTS.md')}],
                        'validation': 'external-only'}
        self.bundle.update(schema='mapped-handoff-goals/1', execution=copy.deepcopy(self.binding))
        self.bundle['goals'][0]['repository'] = copy.deepcopy(self.binding['repository'])
        self.policy = json.loads((self.root / c.POLICY).read_text())
        self.policy['execution'] = copy.deepcopy(self.binding)
        self.branch = {'id': 'mapped-target', 'stage': 'implementation', 'scope': {'goals': ['G1']},
                       'kind': 'branch_target', 'binding': {'target': 'master', 'branch': 'fix/DEV-1'}}
        self.policy['gates'].append(self.branch)
        self.policy['not_applicable'].pop('branch_target')
        self.context.update(execution=copy.deepcopy(self.binding), execution_revision='b' * 40)
        self.context['authority']['execution_revision'] = 'b' * 40

    def save(self, receipts=True):
        write(self.root, c.POLICY, self.policy)
        self.context['policy']['sha256'] = digest(self.root / c.POLICY)
        if receipts:
            now = datetime.now(timezone.utc)
            self.context['results'] = [{'gate': self.branch['id'], 'stage': self.branch['stage'],
                'scope': self.branch['scope'], 'status': 'pass', 'issuer': 'simulated-reviewer',
                'subject_sha256': c.gate_subject(self.bundle, self.branch, self.context['sources'],
                                                self.context['policy'], self.context['execution_revision']),
                'observed_at': (now - timedelta(minutes=1)).isoformat(),
                'expires_at': (now + timedelta(hours=1)).isoformat(),
                'evidence': ['local:fixture'], 'value': self.branch['binding']}]
        write(self.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        write(self.root, 'plan.json', self.bundle)
        self.context['authority']['subject_sha256'] = digest(self.root / 'direct.json')
        write(self.root, 'context.json', self.context)
        write(self.root, 'record.json', self.bundle['goals'][0])

    def admit(self, execution_root=None):
        return c.admit(Namespace(root=str(self.root), execution_root=str(execution_root or self.execution),
            goal=str(self.root / 'direct.json'), handoff=None, goal_id=None,
            context=str(self.root / 'context.json'), stage='implementation'))

    def rejected(self, report):
        self.assertFalse(report['execution_ready'], report)
        self.assertFalse(report['dispatch_authorized'], report)
        self.assertTrue(report['gaps'], report)

    def test_migration_preserves_legacy_and_resets_readiness(self):
        self.save(receipts=False)
        legacy = {'goals': ['original'], 'evidence': {'retained': True}}
        write(self.root, 'legacy.json', legacy)
        result = c.migrate(Namespace(root=str(self.root), legacy=str(self.root / 'legacy.json'),
                                     bundle=str(self.root / 'plan.json')))
        self.assertEqual(result['bundle']['extensions']['legacy_original'], legacy)
        self.assertEqual(result['bundle']['extensions']['legacy_sha256'], digest(self.root / 'legacy.json'))
        self.assertEqual(set(result['bundle']['goals'][0]['readiness'].values()), {'unknown'})
        self.assertFalse(result['dispatch_authorized'])
        self.assertFalse((self.execution / '.ai').exists())

    def test_mapped_admission_without_application_governance_is_read_only(self):
        self.save()
        before = {str(p): digest(p) for p in self.base.rglob('*') if p.is_file()}
        result = self.admit()
        self.assertTrue(result['execution_ready'], result)
        self.assertFalse(result['dispatch_authorized'])
        self.assertEqual(before, {str(p): digest(p) for p in self.base.rglob('*') if p.is_file()})
        self.assertFalse((self.execution / '.ai').exists())

    def test_absent_independent_authority_never_admits(self):
        self.context['authority'] = {}
        self.save()
        self.rejected(self.admit())

    def test_context_mapping_cannot_differ_from_fixed_policy(self):
        self.context['execution']['target'] = 'dev/26.1'
        self.save()
        self.rejected(self.admit())

    def test_gate_files_use_explicit_execution_root(self):
        self.policy['gates'][0].update(root='execution', path='AGENTS.md',
                                      sha256=digest(self.execution / 'AGENTS.md'))
        self.save()
        self.assertTrue(self.admit()['execution_ready'])
        self.policy['gates'][0]['root'] = 'planning'
        self.save()
        self.rejected(self.admit())

    def test_missing_policy_mapping_cannot_be_supplied_by_context(self):
        self.policy.pop('execution')
        self.save()
        self.rejected(self.admit())

    def test_each_policy_mapping_identity_mismatch_fails(self):
        for key, value in [('target', 'dev/26.1'), ('source_revision', 'c' * 40), ('validation', 'local'),
                           ('repository', {'id': 'other', 'root': str(self.execution)})]:
            with self.subTest(key=key):
                self.policy['execution'] = dict(copy.deepcopy(self.binding), **{key: value})
                self.save()
                self.rejected(self.admit())

    def test_explicit_wrong_execution_root_fails(self):
        self.save()
        self.rejected(self.admit(self.root))

    def test_context_cannot_select_an_alternate_policy(self):
        self.context['policy']['path'] = 'other-policy.json'
        write(self.root, 'other-policy.json', self.policy)
        self.save()
        self.rejected(self.admit())

    def test_current_revision_must_match_authority(self):
        self.context['authority']['execution_revision'] = 'c' * 40
        self.save()
        self.rejected(self.admit())

    def test_missing_current_revision_fails(self):
        self.save()
        del self.context['execution_revision']
        write(self.root, 'context.json', self.context)
        self.rejected(self.admit())

    def test_both_instruction_sets_are_digest_bound(self):
        self.save()
        for root in (self.root, self.execution):
            with self.subTest(root=root):
                source = root / 'AGENTS.md'
                old = source.read_bytes()
                source.write_text('Changed governing instructions')
                self.rejected(self.admit())
                source.write_bytes(old)

    def test_unbound_nested_execution_instructions_fail(self):
        (self.execution / 'tests/AGENTS.md').write_text('Additional applicable instructions')
        self.save()
        self.rejected(self.admit())

    def test_glob_scopes_cannot_bypass_nested_instructions(self):
        nested = self.execution / 'tests/nested'
        nested.mkdir()
        (nested / 'AGENTS.md').write_text('Nested execution instructions')
        for scope in ('tests/**', 'tests/*', 'tests/?', 'tests/[nested]', 'tests/nested]'):
            with self.subTest(scope=scope):
                self.bundle['goals'][0]['scope'] = [scope]
                self.save()
                result = self.admit()
                self.rejected(result)
                self.assertIn('execution_scope_must_be_literal', json.dumps(result['gaps']))

    def test_literal_directory_requires_recursive_instruction_binding(self):
        nested = self.execution / 'tests/nested'
        nested.mkdir()
        source = nested / 'AGENTS.md'
        source.write_text('Nested execution instructions')
        self.bundle['goals'][0]['scope'] = ['tests']
        self.save()
        result = self.admit()
        self.rejected(result)
        self.assertIn('execution_source_set_incomplete', json.dumps(result['gaps']))
        for binding in (self.bundle['execution'], self.policy['execution'], self.context['execution']):
            binding['sources'].append({'path': 'tests/nested/AGENTS.md', 'sha256': digest(source)})
        self.save()
        self.assertTrue(self.admit()['execution_ready'])

    def test_nonexistent_literal_file_scope_is_allowed(self):
        self.bundle['goals'][0]['scope'] = ['tests/new/nested/check.py']
        self.save()
        self.assertTrue(self.admit()['execution_ready'])

    def test_execution_source_traversal_and_symlink_rejected(self):
        (self.execution / 'alias.md').symlink_to(self.execution / 'AGENTS.md')
        for path in ('../application/AGENTS.md', 'alias.md'):
            with self.subTest(path=path):
                for value in (self.bundle['execution'], self.policy['execution'], self.context['execution']):
                    value['sources'][0]['path'] = path
                self.save()
                self.rejected(self.admit())

    def test_symlink_execution_root_rejected(self):
        alias = self.base / 'alias'
        alias.symlink_to(self.execution, target_is_directory=True)
        for value in (self.bundle['execution'], self.policy['execution'], self.context['execution']):
            value['repository']['root'] = str(alias)
        self.bundle['goals'][0]['repository']['root'] = str(alias)
        self.save()
        self.rejected(self.admit(alias))

    def test_binding_and_current_revision_invalidate_receipt(self):
        self.save()
        self.assertTrue(self.admit()['execution_ready'])
        self.context['execution_revision'] = 'c' * 40
        self.context['authority']['execution_revision'] = 'c' * 40
        self.save(receipts=False)
        self.rejected(self.admit())

    def test_goal_revision_changes_with_execution_binding(self):
        before = c.goal_revision(self.bundle, 'G1')
        self.bundle['execution']['target'] = 'dev/26.1'
        self.assertNotEqual(before, c.goal_revision(self.bundle, 'G1'))

    def test_v1_cannot_smuggle_execution_binding(self):
        self.bundle['schema'] = 'handoff-goals/1'
        self.bundle['goals'][0]['repository'] = self.bundle['repository']
        self.save(receipts=False)
        self.rejected(self.admit())

    def public_admit(self, auto=AUTO, selectors=None):
        return subprocess.run(['bash', str(auto / 'prereq-check.sh'), '--root', str(self.root),
            '--execution-root', str(self.execution), '--context', str(self.root / 'context.json'),
            *(selectors or ['--goal', str(self.root / 'direct.json')])], capture_output=True, text=True)

    def test_canonical_flat_and_handoff_direct_equivalence(self):
        self.save()
        flat = self.base / 'flat'
        shutil.copytree(AUTO, flat / 'autobahn')
        shutil.copytree(NORTH, flat / 'northstar')
        publish = subprocess.run(['bash', str(flat / 'northstar/handoff-write.sh'), '--root', str(self.root),
            '--bundle', str(self.root / 'plan.json')], capture_output=True, text=True)
        self.assertEqual(publish.returncode, 0, publish.stdout + publish.stderr)
        entry = json.loads(publish.stdout)['published']
        for auto in (AUTO, flat / 'autobahn'):
            for selectors in (['--goal', str(self.root / 'direct.json')], ['--handoff', entry['id'], '--goal-id', 'G1']):
                with self.subTest(auto=auto, selector=selectors[0]):
                    self.context['authority']['subject_sha256'] = digest(self.root / 'direct.json') if selectors[0] == '--goal' else entry['artifacts']['bundle']['sha256']
                    write(self.root, 'context.json', self.context)
                    run = self.public_admit(auto, selectors)
                    self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                    report = json.loads(run.stdout)
                    self.assertTrue(report['execution_ready'])
                    self.assertFalse(report['dispatch_authorized'])
        (flat / 'northstar/readiness-dependency.json').write_text('{}')
        run = self.public_admit(flat / 'autobahn')
        self.assertNotEqual(run.returncode, 0)
        self.assertIn('fingerprint mismatch', run.stdout + run.stderr)

    def test_missing_execution_root_public_cli_rejected(self):
        self.save()
        run = subprocess.run(['bash', str(AUTO / 'prereq-check.sh'), '--root', str(self.root),
            '--context', str(self.root / 'context.json'), '--goal', str(self.root / 'direct.json')],
            capture_output=True, text=True)
        self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertFalse(json.loads(run.stdout)['dispatch_authorized'])

    def test_distinct_repository_ids_required(self):
        for value in (self.bundle['execution'], self.policy['execution'], self.context['execution']):
            value['repository']['id'] = self.bundle['repository']['id']
        self.bundle['goals'][0]['repository']['id'] = self.bundle['repository']['id']
        self.save()
        self.rejected(self.admit())

    def test_missing_target_gate_cannot_be_waived(self):
        self.policy['gates'].remove(self.branch)
        self.policy['not_applicable']['branch_target'] = 'Caller claims no target check needed'
        self.save()
        self.rejected(self.admit())

    def test_local_driver_executes_only_in_execution_repository(self):
        for value in (self.bundle['execution'], self.policy['execution'], self.context['execution']):
            value['validation'] = 'local'
        self.branch['stage'] = 'merge'
        self.policy['gates'][0]['stage'] = 'merge'
        self.context['authority']['stage'] = 'merge'
        self.bundle['goals'][0]['readiness']['merge'] = 'ready'
        self.save()
        self.context['results'][0]['stage'] = 'merge'
        write(self.root, 'context.json', self.context)
        workflow = self.execution / '.github/workflows/test.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/check.sh\n')
        run = subprocess.run(['bash', str(AUTO / 'run-gates.sh'), '--root', str(self.root),
            '--execution-root', str(self.execution), '--goal', str(self.root / 'direct.json'),
            '--context', str(self.root / 'context.json'), '--goal-record', str(self.root / 'record.json'),
            '--phase', 'pre-merge'], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertTrue((self.execution / 'EXECUTED').exists())
        self.assertFalse((self.root / 'EXECUTED').exists())

    def test_external_only_driver_blocks_before_all_local_commands(self):
        for root in (self.root, self.execution):
            workflow = root / '.github/workflows/test.yml'
            workflow.parent.mkdir(parents=True)
            workflow.write_text('jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/check.sh\n')
        for phase in ('pre-commit', 'local-validation', 'pre-merge', 'all'):
            with self.subTest(phase=phase):
                stage = 'merge' if phase in ('pre-merge', 'all') else 'implementation'
                self.branch['stage'] = stage
                self.policy['gates'][0]['stage'] = stage
                self.context['authority']['stage'] = stage
                self.bundle['goals'][0]['readiness'][stage] = 'ready'
                self.save()
                before = {str(p): digest(p) for p in self.base.rglob('*') if p.is_file()}
                run = subprocess.run(['bash', str(AUTO / 'run-gates.sh'), '--root', str(self.root),
                    '--execution-root', str(self.execution), '--goal', str(self.root / 'direct.json'),
                    '--context', str(self.root / 'context.json'), '--goal-record', str(self.root / 'record.json'),
                    '--phase', phase], capture_output=True, text=True)
                self.assertNotEqual(run.returncode, 0, run.stdout + run.stderr)
                self.assertIn('"execution_ready": true', run.stdout)
                self.assertIn('external_validation_adapter_required', run.stderr.splitlines())
                self.assertFalse((self.execution / 'EXECUTED').exists())
                self.assertFalse((self.root / 'EXECUTED').exists())
                self.assertFalse((self.root / 'SHOULD_NOT_RUN').exists())
                self.assertEqual(before, {str(p): digest(p) for p in self.base.rglob('*') if p.is_file()})


if __name__ == '__main__':
    unittest.main()
