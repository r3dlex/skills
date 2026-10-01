"""Actual driver + shared validator regressions; fixture authority is simulated."""
import copy
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from readiness_fixture import fixture, write, digest

REPO = Path(__file__).resolve().parents[1]
AUTO = REPO / '04-validate-handoff/autobahn'


class MergeDriverTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bundle, self.context = fixture(self.root)
        self.context['authority']['stage'] = 'merge'
        self.bundle['goals'][0]['readiness']['merge'] = 'ready'
        policy = json.loads((self.root / '.ai/policies/readiness-policy.json').read_text())
        gate = copy.deepcopy(policy['gates'][0])
        gate.update(id='merge-evidence', stage='merge', path='merge-evidence.txt')
        (self.root / 'merge-evidence.txt').write_text((self.root / 'evidence.txt').read_text())
        policy['gates'].append(gate)
        write(self.root, '.ai/policies/readiness-policy.json', policy)
        self.context['policy']['sha256'] = digest(self.root / '.ai/policies/readiness-policy.json')
        self.bundle['goals'][0]['verification'] = ['bash tests/ok.sh']
        write(self.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        self.context['authority']['subject_sha256'] = digest(self.root / 'direct.json')
        write(self.root, 'record.json', self.bundle['goals'][0])
        write(self.root, 'context.json', self.context)
        workflow = self.root / '.github/workflows/test.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/ok.sh\n')
        (self.root / 'tests').mkdir(exist_ok=True)
        (self.root / 'tests/ok.sh').write_text('#!/bin/sh\ntouch VERIFIED\n')

    def run_driver(self, *args, select=True, phase='pre-merge'):
        selection = ['--goal', str(self.root / 'direct.json'), '--context', str(self.root / 'context.json')] if select else []
        return subprocess.run(['bash', str(AUTO / 'run-gates.sh'), '--root', str(self.root),
                               '--goal-record', str(self.root / 'record.json'), '--phase', phase,
                               *selection, *args], text=True, capture_output=True)

    def blocked(self, result):
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse((self.root / 'VERIFIED').exists(), result.stdout + result.stderr)

    def test_missing_selection_fails_before_verification(self):
        self.blocked(self.run_driver(select=False))

    def test_ready_exact_direct_goal_passes_without_granting_authority(self):
        result = self.run_driver()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('merge', result.stdout)
        self.assertIn('"dispatch_authorized": false', result.stdout)
        self.assertTrue((self.root / 'VERIFIED').exists())

    def test_implementation_ready_does_not_supply_missing_merge_evidence(self):
        (self.root / 'merge-evidence.txt').unlink()
        implementation = copy.deepcopy(self.context)
        implementation['authority']['stage'] = 'implementation'
        write(self.root, 'implementation-context.json', implementation)
        admitted = subprocess.run(['bash', str(AUTO / 'prereq-check.sh'), '--root', str(self.root),
                                   '--goal', str(self.root / 'direct.json'), '--stage', 'implementation',
                                   '--context', str(self.root / 'implementation-context.json')],
                                  text=True, capture_output=True)
        self.assertEqual(admitted.returncode, 0, admitted.stdout + admitted.stderr)
        self.blocked(self.run_driver())

    def test_missing_context_fails_before_verification(self):
        (self.root / 'context.json').unlink()
        self.blocked(self.run_driver())

    def test_context_wrong_subject_or_stage_cannot_admit(self):
        for field, value in [('subject_sha256', '0' * 64), ('stage', 'implementation')]:
            with self.subTest(field=field):
                context = copy.deepcopy(self.context)
                context['authority'][field] = value
                write(self.root, 'context.json', context)
                self.blocked(self.run_driver())

    def test_stale_context_source_cannot_admit(self):
        (self.root / 'AGENTS.md').write_text('changed policy source')
        self.blocked(self.run_driver())

    def test_changed_same_id_command_record_cannot_admit(self):
        record = copy.deepcopy(self.bundle['goals'][0])
        record['verification'] = ['bash tests/different.sh']
        write(self.root, 'record.json', record)
        result = self.run_driver()
        self.blocked(result)
        self.assertIn('execution_record_mismatch', result.stdout)

    def test_wrong_goal_record_id_cannot_admit(self):
        record = copy.deepcopy(self.bundle['goals'][0])
        record['id'] = 'OTHER'
        write(self.root, 'record.json', record)
        self.blocked(self.run_driver())

    def test_same_generation_handoff_passes_but_other_selection_fails(self):
        write(self.root, 'plan.json', self.bundle)
        result = subprocess.run(['bash', str(REPO / '02-govern-plan/northstar/handoff-write.sh'),
                                 '--root', str(self.root), '--bundle', str(self.root / 'plan.json')],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        entry = json.loads(result.stdout)['published']
        self.context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
        write(self.root, 'context.json', self.context)
        args = ['--handoff', entry['handoff_path'], '--context', str(self.root / 'context.json')]
        result = self.run_driver(*args, select=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.root / 'VERIFIED').unlink()
        args[1] = 'unrelated'
        self.blocked(self.run_driver(*args, select=False))

    def test_all_command_surfaces_explain_merge_stage_boundary(self):
        expected = 'Independent readiness-context/1 input for exact subject, goals and stage; verify live authority separately before dispatch. Before ordinary or admin merges, require fresh merge-stage context for the original exact handoff/direct subject and selected goal; local-validation is supporting evidence, not merge admission.'
        for surface in ['omc', 'omx', 'opencode']:
            command = json.loads((REPO / 'reference/fixtures/v3/standalone/.ai/commands' / surface / 'autobahn.json').read_text())
            context = next(arg for arg in command['args'] if arg['name'] == 'context')
            self.assertEqual(context['description'], expected)
        self.assertIn(expected, (AUTO / 'modules/command-surface.md').read_text())

    def test_local_validation_does_not_authorize_merge(self):
        script = self.root / 'tests/flip.sh'
        script.write_text('#!/bin/sh\ntest -f impl\n')
        for mode in ['red', 'green']:
            if mode == 'green':
                (self.root / 'impl').touch()
            result = subprocess.run(['bash', str(AUTO / 'tdd-evidence.sh'), f'--record-{mode}',
                                     '--goal', 'G1', '--root', str(self.root), '--command', 'sh tests/flip.sh'],
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        result = self.run_driver(select=False, phase='local-validation')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('not merge admission or authority', result.stdout)
        (self.root / 'VERIFIED').unlink()
        self.blocked(self.run_driver(select=False, phase='all'))


if __name__ == '__main__':
    unittest.main()
