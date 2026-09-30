"""Public CLI contract tests; disposable policy inputs are simulated, not authority."""
import copy
import hashlib
import shutil
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock
import sys
from argparse import Namespace
from readiness_fixture import fixture, write, digest

REPO = Path(__file__).resolve().parents[1]
AUTO = REPO / '04-validate-handoff/autobahn'
sys.path.insert(0, str(AUTO / 'lib'))
import readiness_contract as contract


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for name, value in {
            '.ai/matrix.json': {},
            '.ai/workflows/repo-workflow.json': {'optional_branches': [{'id': 'northstar-handoff-unrelated'}]},
            '.ai/traceability/graph.json': {'root_repo_id': 'fixture', 'nodes': [], 'edges': []},
        }.items():
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value))
        (self.root / '.ai/handoff').mkdir()
        (self.root / '.ai/handoff/northstar-unrelated.md').write_text('unrelated')

    def test_unselected_unrelated_handoff_never_admits(self):
        result = subprocess.run(['bash', str(AUTO / 'prereq-check.sh'), '--root', str(self.root)], capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn('selection_required', result.stdout + result.stderr)

    def test_exact_legacy_only_selection_requires_migration_without_writes(self):
        manifest = self.root / '.ai/workflows/repo-workflow.json'
        legacy = {'id': 'northstar-handoff-unrelated', 'status': 'available'}
        for entries, selector, expected in (
            ([legacy], legacy['id'], 'migration_required'),
            ([legacy], '.ai/handoff/northstar-unrelated.md', 'migration_required'),
            ([legacy], 'northstar-handoff-other', 'handoff_missing_or_ambiguous'),
            ([legacy, legacy], legacy['id'], 'handoff_missing_or_ambiguous'),
            ([legacy, legacy], '.ai/handoff/northstar-unrelated.md', 'handoff_missing_or_ambiguous'),
        ):
            with self.subTest(selector=selector, entries=len(entries)):
                manifest.write_text(json.dumps({'optional_branches': entries}))
                before = {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()}
                for script in ('prereq-check.sh', 'readiness-check.sh'):
                    result = subprocess.run(['bash', str(AUTO / script), '--root', str(self.root),
                                             '--handoff', selector, '--goal-id', 'G1'], capture_output=True, text=True)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn(expected, result.stdout + result.stderr)
                    self.assertFalse(json.loads(result.stdout)['dispatch_authorized'])
                self.assertEqual(before, {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()})


class VersionOneTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bundle, self.context = fixture(self.root)

    def command(self, script, *args):
        return subprocess.run(['bash', str(script), '--root', str(self.root), *args], capture_output=True, text=True)

    def publish(self):
        result = self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.entry = json.loads(result.stdout)['published']
        self.context['authority']['subject_sha256'] = self.entry['artifacts']['bundle']['sha256']
        write(self.root, 'context.json', self.context)
        return result

    def admit(self, *extra, script='prereq-check.sh', stage='implementation'):
        return self.command(AUTO / script, '--handoff', 'northstar-plan-chosen', '--goal-id', 'G1',
                            '--context', str(self.root / 'context.json'), '--stage', stage, *extra)

    def assert_blocked(self, result, text):
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn(text, result.stdout + result.stderr)

    def test_coverage_required_is_strict_boolean(self):
        for value in (None, 'false', 'true', 0, 1, 0.0, 1.0, [], {}):
            with self.subTest(value=value):
                goal = copy.deepcopy(self.bundle['goals'][0])
                goal['coverage_required'] = value
                gaps = []
                contract.coverage(goal, gaps, 'implementation')
                self.assertIn('invalid_coverage_required', [gap['code'] for gap in gaps])
        for value in (False, True):
            goal = copy.deepcopy(self.bundle['goals'][0])
            goal['coverage_required'] = value
            gaps = []
            contract.coverage(goal, gaps, 'implementation')
            self.assertNotIn('invalid_coverage_required', [gap['code'] for gap in gaps])

    def test_positive_read_only_exact_admission_and_no_dispatch_authority(self):
        self.publish()
        before = {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()}
        result = self.admit()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertTrue(report['execution_ready'])
        self.assertFalse(report['dispatch_authorized'])
        self.assertEqual(report['authority_verification'], 'external-required')
        self.assertEqual(report['goals'], ['G1'])
        self.assertFalse((self.root / 'SHOULD_NOT_RUN').exists())
        self.assertEqual(before, {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()})

    def test_planning_does_not_imply_implementation(self):
        self.bundle['goals'][0]['readiness']['implementation'] = 'unknown'
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        self.assertEqual(self.admit(stage='planning').returncode, 0)
        self.assert_blocked(self.admit(), 'goal_not_ready')

    def test_missing_wrong_duplicate_and_blocked_selection(self):
        self.publish()
        self.assert_blocked(self.command(AUTO / 'prereq-check.sh', '--handoff', 'wrong', '--goal-id', 'G1'), 'handoff_missing_or_ambiguous')
        self.assert_blocked(self.command(AUTO / 'prereq-check.sh', '--handoff', 'northstar-plan-chosen'), 'goal_selection_required')
        self.assert_blocked(self.admit('--goal-id', 'G1'), 'goal_selection_required')
        manifest = json.loads((self.root / '.ai/workflows/northstar-readiness-v1.json').read_text())
        manifest['plans'].append(copy.deepcopy(self.entry))
        write(self.root, '.ai/workflows/northstar-readiness-v1.json', manifest)
        self.assert_blocked(self.admit(), 'handoff_missing_or_ambiguous')
        manifest['plans'].pop()
        manifest['plans'][0]['status'] = 'blocked'
        write(self.root, '.ai/workflows/northstar-readiness-v1.json', manifest)
        self.assert_blocked(self.admit(), 'handoff_not_active')

    def test_spec_source_policy_and_artifact_staleness(self):
        self.publish()
        for name in ['spec.md', 'AGENTS.md', '.ai/policies/readiness-policy.json', self.entry['artifacts']['bundle']['path']]:
            with self.subTest(name=name):
                path = self.root / name
                old = path.read_bytes()
                path.write_bytes(old + b' ')
                self.assertNotEqual(self.admit().returncode, 0)
                path.write_bytes(old)

    def test_unsupported_policy_and_scope_aware_requirements(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['gates'].append({'id': 'coverage', 'stage': 'implementation', 'scope': {'repository': True}, 'kind': 'measured_coverage'})
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.bundle['goals'][0]['coverage_required'] = False
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        self.assert_blocked(self.admit(), 'measured_coverage_required')
        policy['gates'][-1]['kind'] = 'arbitrary_shell_predicate'
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        write(self.root, 'context.json', self.context)
        self.assert_blocked(self.admit(), 'unsupported_gate')

    def test_goal_requirement_cannot_be_silently_ignored(self):
        self.bundle['goals'][0]['requirements'] = [{'id': 'extra', 'kind': 'file_digest', 'path': 'missing'}]
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        self.assert_blocked(self.admit(), 'goal_requirement_invalid')

    def test_policy_empty_exclusions_do_not_silently_omit_required_dimensions(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['not_applicable'] = {}
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.publish()
        self.assert_blocked(self.admit(), 'policy_dimensions_required')

    def test_direct_nested_v1_same_policy(self):
        path = write(self.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        self.context['authority']['subject_sha256'] = digest(path)
        write(self.root, 'context.json', self.context)
        args = ('--goal', str(path), '--context', str(self.root / 'context.json'))
        for script in ('prereq-check.sh', 'readiness-check.sh'):
            result = self.command(AUTO / script, *args)
            self.assertEqual(result.returncode, 0, result.stdout)
        self.context['policy']['sha256'] = '0' * 64
        write(self.root, 'context.json', self.context)
        self.assert_blocked(self.command(AUTO / 'readiness-check.sh', *args), 'unapproved_policy_revision')

    def test_legacy_direct_is_migration_required(self):
        write(self.root, 'legacy.json', {'id': 'G1', 'implementation_ready': True})
        self.assert_blocked(self.command(AUTO / 'readiness-check.sh', '--goal', str(self.root / 'legacy.json')), 'migration_required')

    def test_verification_whole_list_is_never_executed(self):
        self.bundle['goals'][0]['verification'].append('bash -c dangerous')
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        self.assert_blocked(self.admit(), 'verification_invalid')
        self.assertFalse((self.root / 'SHOULD_NOT_RUN').exists())

    def test_regeneration_preserves_enrichment_and_other_registrations(self):
        self.bundle['extensions'] = {'review': {'note': 'keep me'}}
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        manifest_path = self.root / '.ai/workflows/northstar-readiness-v1.json'
        first = manifest_path.read_bytes()
        del self.bundle['extensions']
        write(self.root, 'plan.json', self.bundle)
        result = self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json'))
        self.assert_blocked(result, 'enrichment_loss')
        self.assertEqual(first, manifest_path.read_bytes())

    def test_lock_and_missing_generation_fail_closed(self):
        self.publish()
        lock = self.root / '.ai/workflows/.northstar-readiness-v1.lock'
        lock.mkdir()
        self.assert_blocked(self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json')), 'publication_locked')
        lock.rmdir()
        (self.root / self.entry['artifacts']['graph']['path']).unlink()
        self.assertNotEqual(self.admit().returncode, 0)

    def test_candidate_edit_and_unknown_enrichment_are_not_lost(self):
        self.bundle['user_notes'] = ['keep this rich content']
        write(self.root, 'plan.json', self.bundle)
        self.publish()
        original = contract.write_json
        def changed(path, value):
            original(path, value)
            if path.name == 'goals.json':
                candidate = copy.deepcopy(self.bundle)
                candidate['user_notes'].append('concurrent enrichment')
                write(self.root, 'plan.json', candidate)
        self.bundle['planning_complete'] = False
        write(self.root, 'plan.json', self.bundle)
        with mock.patch.object(contract, 'write_json', side_effect=changed):
            with self.assertRaisesRegex(contract.Invalid, 'candidate_changed'):
                contract.publish(Namespace(root=str(self.root), bundle=str(self.root / 'plan.json')))
        self.bundle['user_notes'] = []
        write(self.root, 'plan.json', self.bundle)
        self.assert_blocked(self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json')), 'enrichment_changed')

    def test_corrupt_orphan_generation_cannot_be_registered_on_retry(self):
        self.publish()
        write(self.root, '.ai/workflows/northstar-readiness-v1.json', {'schema': contract.VERSION, 'plans': []})
        path = self.root / self.entry['artifacts']['graph']['path']
        graph = json.loads(path.read_text())
        graph['goal_ids'] = []
        path.write_text(json.dumps(graph))
        self.assert_blocked(self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json')), 'generation_collision')

    def test_orphan_symlink_cannot_be_registered_on_retry(self):
        self.publish()
        write(self.root, '.ai/workflows/northstar-readiness-v1.json', {'schema': contract.VERSION, 'plans': []})
        path = self.root / self.entry['artifacts']['handoff']['path']
        outside = self.root / 'outside.md'
        outside.write_bytes(path.read_bytes())
        path.unlink()
        path.symlink_to(outside)
        self.assert_blocked(self.command(REPO / '02-govern-plan/northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json')), 'symlink_path')

    def test_fan_in_dag_validation_is_bounded(self):
        template = self.bundle['goals'][0]
        self.bundle['goals'] = []
        for index in range(40):
            goal = copy.deepcopy(template)
            goal['id'] = f'G{index}'
            goal['dependencies'] = [f'G{j}' for j in range(max(0, index - 2), index)]
            self.bundle['goals'].append(goal)
        write(self.root, 'plan.json', self.bundle)
        result = subprocess.run(['bash', str(REPO / '02-govern-plan/northstar/handoff-write.sh'), '--root', str(self.root), '--bundle', str(self.root / 'plan.json')], capture_output=True, text=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_live_graph_identity_change_blocks_selected_generation(self):
        self.publish()
        graph = json.loads((self.root / '.ai/traceability/graph.json').read_text())
        handoff = next(n for n in graph['nodes'] if n['type'] == 'handoff')
        handoff['path'] = 'unrelated.md'
        write(self.root, '.ai/traceability/graph.json', graph)
        self.assert_blocked(self.admit(), 'generation_graph_identity_mismatch')

    def test_registration_enrichment_survives_republication(self):
        self.publish()
        registry = json.loads((self.root / '.ai/workflows/northstar-readiness-v1.json').read_text())
        registry['plans'][0]['review_evidence'] = {'approval': 'keep me'}
        write(self.root, '.ai/workflows/northstar-readiness-v1.json', registry)
        self.publish()
        self.assertEqual(self.entry['review_evidence'], {'approval': 'keep me'})

    def test_executable_presence_is_observed_not_executed(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['gates'].append({'id': 'executable', 'stage': 'implementation', 'scope': {'repository': True}, 'kind': 'executable_presence', 'path': 'tests/check.sh'})
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.publish()
        self.assertNotEqual(self.admit().returncode, 0)
        (self.root / 'tests/check.sh').chmod(0o700)
        self.assertEqual(self.admit().returncode, 0)
        self.assertFalse((self.root / 'SHOULD_NOT_RUN').exists())

    def test_uncovered_existing_instruction_source_blocks(self):
        (self.root / '.rules.ts').write_text('authoritative extra rules')
        self.publish()
        self.assert_blocked(self.admit(), 'policy_source_set_incomplete')

    def test_consumer_requires_matching_northstar_peer_without_skill_tree_writes(self):
        flat = self.root / 'flat'
        shutil.copytree(AUTO, flat / 'autobahn', ignore=shutil.ignore_patterns('__pycache__'))
        self.assert_blocked(self.command(flat / 'autobahn/prereq-check.sh'), 'dependency_failed')
        shutil.copytree(REPO / '02-govern-plan/northstar', flat / 'northstar', ignore=shutil.ignore_patterns('__pycache__'))
        before = {str(p): digest(p) for p in flat.rglob('*') if p.is_file()}
        self.command(flat / 'autobahn/prereq-check.sh')
        self.assertEqual(before, {str(p): digest(p) for p in flat.rglob('*') if p.is_file()})
        (flat / 'northstar/readiness-dependency.json').write_text('{}')
        self.assert_blocked(self.command(flat / 'autobahn/prereq-check.sh'), 'fingerprint mismatch')

    def test_unsupported_policy_wide_semantics_are_not_ignored(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['freshness'] = {'max_age_seconds': 0}
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.publish()
        self.assert_blocked(self.admit(), 'unsupported_policy_fields')

    def test_unsupported_gate_predicate_and_freshness_are_not_ignored(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['gates'][0]['predicate'] = 'run arbitrary expression'
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.publish()
        self.assert_blocked(self.admit(), 'unsupported_gate_fields')

    def test_missing_v3_root_never_admits_direct(self):
        path = write(self.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        self.context['authority']['subject_sha256'] = digest(path)
        write(self.root, 'context.json', self.context)
        (self.root / '.ai/matrix.json').unlink()
        self.assert_blocked(self.command(AUTO / 'prereq-check.sh', '--goal', str(path), '--context', str(self.root / 'context.json')), 'v3_root_required')

    def test_publication_failure_boundaries_leave_only_complete_visibility(self):
        self.publish()
        manifest_path = self.root / '.ai/workflows/northstar-readiness-v1.json'
        old = manifest_path.read_bytes()
        self.bundle['extensions'] = {'note': 'new generation'}
        write(self.root, 'plan.json', self.bundle)
        args = Namespace(root=str(self.root), bundle=str(self.root / 'plan.json'))
        real_write, real_rename, real_replace = contract.write_json, Path.rename, contract.os.replace
        for boundary in ('write-before', 'rename-before', 'rename-after', 'graph-before', 'graph-after', 'register-before', 'register-after'):
            with self.subTest(boundary=boundary):
                manifest_path.write_bytes(old)
                # Retry a unique candidate so every boundary is actually exercised.
                self.bundle['extensions']['note'] = boundary
                write(self.root, 'plan.json', self.bundle)
                def rename(path, target):
                    if boundary == 'rename-before':
                        raise OSError('injected before generation rename')
                    result = real_rename(path, target)
                    if boundary == 'rename-after':
                        raise OSError('injected after generation rename')
                    return result
                def replace(source, target):
                    if boundary == ('register-before' if Path(target).name == 'northstar-readiness-v1.json' else 'graph-before'):
                        raise OSError('injected before registration')
                    result = real_replace(source, target)
                    if boundary == ('register-after' if Path(target).name == 'northstar-readiness-v1.json' else 'graph-after'):
                        raise OSError('injected after registration')
                    return result
                def write_json(path, value):
                    if boundary == 'write-before':
                        raise OSError('injected before payload')
                    return real_write(path, value)
                with mock.patch.object(contract, 'write_json', side_effect=write_json), mock.patch.object(Path, 'rename', rename), mock.patch.object(contract.os, 'replace', side_effect=replace):
                    with self.assertRaises(OSError):
                        contract.publish(args)
                if boundary != 'register-after':
                    self.assertEqual(manifest_path.read_bytes(), old)
                self.assertFalse((self.root / '.ai/workflows/.northstar-readiness-v1.lock').exists())
                # Previous generations persist; retry always yields one complete selected generation.
                self.assertTrue((self.root / self.entry['artifacts']['bundle']['path']).exists())
                result = contract.publish(args)
                entry = result['published']
                for ref in entry['artifacts'].values():
                    self.assertEqual(digest(self.root / ref['path']), ref['sha256'])

    def test_source_revalidation_refuses_to_register_changed_spec(self):
        self.publish()
        before = (self.root / '.ai/workflows/northstar-readiness-v1.json').read_bytes()
        self.bundle['extensions'] = {'note': 'source conflict'}
        write(self.root, 'plan.json', self.bundle)
        original = contract.write_json
        def changed(path, value):
            original(path, value)
            if path.name == 'goals.json':
                (self.root / 'spec.md').write_text('concurrent edit')
        with mock.patch.object(contract, 'write_json', side_effect=changed):
            with self.assertRaisesRegex(contract.Invalid, 'stale_file'):
                contract.publish(Namespace(root=str(self.root), bundle=str(self.root / 'plan.json')))
        self.assertEqual((self.root / '.ai/workflows/northstar-readiness-v1.json').read_bytes(), before)
        self.assertEqual((self.root / 'spec.md').read_text(), 'concurrent edit')

    def test_distinct_publishers_preserve_each_others_registration(self):
        other = copy.deepcopy(self.bundle)
        other['id'] = 'another'
        write(self.root, 'another.json', other)
        base = ['bash', str(REPO / '02-govern-plan/northstar/handoff-write.sh'), '--root', str(self.root), '--bundle']
        workers = [subprocess.Popen([*base, str(self.root / name)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for name in ('plan.json', 'another.json')]
        for worker in workers:
            stdout, stderr = worker.communicate()
            self.assertTrue(worker.returncode == 0 or 'publication_locked' in stdout + stderr)
        # Recover a losing writer explicitly; no process steals its peer's lock.
        for name in ('plan.json', 'another.json'):
            result = subprocess.run([*base, str(self.root / name)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        entries = json.loads((self.root / '.ai/workflows/northstar-readiness-v1.json').read_text())['plans']
        self.assertEqual({e['plan_id'] for e in entries}, {'chosen', 'another'})

    def test_goal_graph_links_are_complete_and_backlinked(self):
        self.publish()
        graph = json.loads((self.root / self.entry['artifacts']['graph']['path']).read_text())
        nodes = {n['id']: n for n in graph['nodes']}
        self.assertGreater(len(nodes), 1)
        for edge in graph['edges']:
            self.assertIn(edge['source'], nodes[edge['target']]['backlinks'])
            self.assertIn(edge['target'], nodes[edge['source']]['backlinks'])

    def test_two_publishers_never_register_partial_generation(self):
        command = ['bash', str(REPO / '02-govern-plan/northstar/handoff-write.sh'), '--root', str(self.root), '--bundle', str(self.root / 'plan.json')]
        workers = [subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
        results = [(p.communicate(), p.returncode) for p in workers]
        self.assertTrue(any(code == 0 for _, code in results), results)
        for (stdout, stderr), code in results:
            self.assertTrue(code == 0 or 'publication_locked' in stdout + stderr, results)
        self.publish()
        self.assertEqual(self.admit().returncode, 0)

    def test_migration_preserves_legacy_enrichment_and_resets_readiness(self):
        legacy = {'id': 'old', 'evidence': ['keep'], 'approvals': {'registration': 'historical-only'}}
        write(self.root, 'legacy.json', legacy)
        result = self.command(AUTO / 'migrate-handoff.sh', '--legacy', str(self.root / 'legacy.json'), '--bundle', str(self.root / 'plan.json'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        migrated = json.loads(result.stdout)['bundle']
        self.assertEqual(migrated['extensions']['legacy_original'], legacy)
        self.assertTrue(all(v == 'unknown' for v in migrated['goals'][0]['readiness'].values()))
        self.assertFalse((self.root / '.ai/handoff/readiness-v1').exists())

    def test_source_and_graph_change_cannot_reuse_generation(self):
        self.publish()
        graph = json.loads((self.root / '.ai/traceability/graph.json').read_text())
        graph['nodes'][0]['title'] = 'changed graph evidence'
        write(self.root, '.ai/traceability/graph.json', graph)
        # Retry preserves independently enriched live graph while reusing immutable payload.
        self.publish()
        self.assertEqual(json.loads((self.root / '.ai/traceability/graph.json').read_text())['nodes'][0]['title'], 'changed graph evidence')

    def test_invalid_scope_cannot_weaken_policy(self):
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        policy['gates'][0]['scope'] = {'goals': []}
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.publish()
        self.assert_blocked(self.admit(), 'explicit_gate_scope_required')

    def test_flat_install_helper_missing_and_mismatch_fail_closed(self):
        flat = self.root / 'flat'
        shutil.copytree(AUTO, flat / 'autobahn')
        shutil.copytree(REPO / '02-govern-plan/northstar', flat / 'northstar')
        result = self.command(flat / 'northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json'))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        helper = flat / 'autobahn/lib/readiness_contract.py'
        helper.write_text(helper.read_text() + '\n# mismatch\n')
        self.assert_blocked(self.command(flat / 'autobahn/prereq-check.sh'), 'fingerprint mismatch')
        helper.unlink()
        self.assert_blocked(self.command(flat / 'northstar/handoff-write.sh', '--bundle', str(self.root / 'plan.json')), 'dependency_failed')


if __name__ == '__main__':
    unittest.main()
