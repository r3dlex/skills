"""Real helper and gate scripts over disposable Git-linked worktrees only.

Fixture context simulates approval and is never live operation authority.
"""
import copy
import json
import os
import subprocess
import unittest

import readiness_worktree_test as fixture_module
from readiness_worktree_test import AUTO, c, write, digest


class WorktreeDriverTests(unittest.TestCase):
    setUp = fixture_module.WorktreeTests.setUp
    git = fixture_module.WorktreeTests.git
    observe = fixture_module.WorktreeTests.observe
    admission_fixture = fixture_module.WorktreeTests.admission_fixture

    def prepare(self, route, stage):
        self.bundle['goals'][0]['readiness']['merge'] = 'ready'
        self.log = self.home / 'executed.log'
        (self.files / 'tests/check.sh').write_text(
            '#!/bin/sh\nprintf "check:%s\\n" "$PWD" >> "$DRIVER_CALL_LOG"\n'
            'if [ "${DRIVER_MUTATE:-}" = yes ]; then printf changed > input.txt; fi\n')
        (self.files / 'tests/lint.sh').write_text(
            '#!/bin/sh\nprintf "lint:%s\\n" "$PWD" >> "$DRIVER_CALL_LOG"\n')
        write(self.files, 'package.json', {'scripts': {'lint': 'bash tests/lint.sh'}})
        workflow = self.files / '.github/workflows/ci.yml'
        workflow.parent.mkdir(parents=True)
        workflow.write_text('jobs:\n  test:\n    runs-on: ubuntu-latest\n'
                            '    steps:\n      - run: bash tests/check.sh\n')
        # Real observed red then green, confined to the disposable fixture.
        (self.files / 'tests/flip.sh').write_text('#!/bin/sh\ntest -f implementation\n')
        evidence = ['bash', str(AUTO / 'tdd-evidence.sh'), '--goal', 'G1',
                    '--root', str(self.files), '--command', 'sh tests/flip.sh']
        subprocess.run(evidence + ['--record-red'], check=True, capture_output=True)
        (self.files / 'implementation').touch()
        subprocess.run(evidence + ['--record-green'], check=True, capture_output=True)
        self.args = self.admission_fixture()
        subject = self.direct
        if route == 'handoff':
            self.args.bundle = str(write(self.files, 'candidate.json', self.bundle))
            entry = c.publish(self.args)['published']
            subject = self.files / entry['artifacts']['bundle']['path']
            self.args.goal = None
            self.args.handoff = entry['id']
            self.args.goal_id = ['G1']
        self.args.stage = stage
        self.record = write(self.home, 'goal-record.json', self.bundle['goals'][0])
        self.args.execution_record = str(self.record)
        self.git(self.files, 'add', '.')
        self.git(self.files, 'commit', '-m', 'complete isolated gate fixture')
        inputs = c.worktree_inputs(self.bundle, self.files)
        if route == 'direct':
            inputs.append('direct.json')
        observation = c.worktree_observation(self.identity, self.files, self.base,
                                             clean=stage == 'merge', inputs=inputs)
        self.context['worktree'] = observation
        self.context['authority'].update(stage=stage, worktree=observation,
                                          subject_sha256=digest(subject))
        write(self.home, 'independent-context.json', self.context)
        self.assertTrue(c.admit(self.args)['execution_ready'], c.admit(self.args))
        self.selection = ['--goal', str(self.direct)] if route == 'direct' else ['--handoff', entry['id']]
        self.primary_before = self.git(self.identity, 'status', '--porcelain')

    def run_driver(self, phase, mutate=False):
        self.log.unlink(missing_ok=True)
        result = subprocess.run(
            ['bash', str(AUTO / 'run-gates.sh'), '--root', str(self.identity),
             '--worktree-root', str(self.files), '--base-commit', self.base,
             '--goal-record', str(self.record), '--context', str(self.context_path),
             '--phase', phase] + self.selection,
            env=dict(os.environ, DRIVER_CALL_LOG=str(self.log),
                     DRIVER_MUTATE='yes' if mutate else ''),
            capture_output=True, text=True)
        self.assertEqual(self.git(self.identity, 'status', '--porcelain'), self.primary_before)
        return result

    def check_positive(self, route, stage, phase):
        self.prepare(route, stage)
        result = self.run_driver(phase)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.log.read_text().splitlines()
        self.assertIn('lint:' + str(self.files), calls)
        self.assertEqual(calls.count('check:' + str(self.files)), 2, calls)
        self.assertTrue(all(line.endswith(':' + str(self.files)) for line in calls), calls)
        self.assertEqual(self.git(self.files, 'status', '--porcelain'), '')
        self.assertIn('"dispatch_authorized": false', result.stdout)
        self.assertIn('worktree readiness recheck passed', result.stdout)
        # A context naming the primary must block before any executable gate.
        wrong = copy.deepcopy(self.context)
        wrong['worktree']['root'] = str(self.identity)
        write(self.home, 'independent-context.json', wrong)
        blocked = self.run_driver(phase)
        self.assertNotEqual(blocked.returncode, 0, blocked.stdout)
        self.assertFalse(self.log.exists(), blocked.stdout)
        write(self.home, 'independent-context.json', self.context)
        # A gate changing tracked bytes invalidates this exact admission.
        changed = self.run_driver(phase, mutate=True)
        self.assertNotEqual(changed.returncode, 0, changed.stdout)
        self.assertIn('worktree readiness recheck BLOCKED', changed.stderr)
        self.assertEqual((self.identity / 'input.txt').read_text(), 'original\n')

    def test_direct_implementation_gates(self):
        self.check_positive('direct', 'implementation', 'local-validation')

    def test_handoff_implementation_gates(self):
        self.check_positive('handoff', 'implementation', 'local-validation')

    def test_direct_clean_merge_all_gates(self):
        self.check_positive('direct', 'merge', 'all')

    def test_handoff_clean_merge_all_gates(self):
        self.check_positive('handoff', 'merge', 'all')


if __name__ == '__main__':
    unittest.main()
