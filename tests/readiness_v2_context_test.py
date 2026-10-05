"""ACH-S-04 contexts: context-build is the builder admission uses (P3), dependency completion is
transitive by ancestry (P4), two v2 plans admit concurrently against one policy/2 (AC-5), and a
blocked admission is one consolidated, deterministically ordered report that carries no
authority (proceed semantics). Ephemeral keys, temporary anchors and disposable repositories only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import concurrent.futures
import copy
import json
import os
import subprocess
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

import readiness_v2_core_test as core
from readiness_v2_core_test import (AUTO, NOW, POLICY, REGISTRY, Fixture, codes, gh_shim, git, sample_bundle,
                                    sample_policy, sample_sidecar, sha, v2, observer, write_json)
from readiness_v2_policy_amend_test import Repository, plan_bundle

HANDOFF = 'northstar-plan-plan-a'
GAP_KEYS = {'code', 'detail', 'goal', 'gate', 'fact', 'source', 'recovery'}
CHAIN = [{'id': 'G1', 'scope': ['src/one.txt'], 'acceptance_criteria': ['one'], 'dependencies': [],
          'verification': ['bash tests/check.sh']},
         {'id': 'G2', 'scope': ['src/two.txt'], 'acceptance_criteria': ['two'], 'dependencies': ['G1'],
          'verification': ['bash tests/check.sh']},
         {'id': 'G3', 'scope': ['src/three.txt'], 'acceptance_criteria': ['three'], 'dependencies': ['G2'],
          'verification': ['bash tests/check.sh']}]


def gap_key(gap):
    return (gap['code'], str(gap['goal']), str(gap['gate']), str(gap['fact']), gap['detail'], gap['source'])


def snapshot(root):
    """Every file outside .git, by digest."""
    root = Path(root)
    return {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob('*'))
            if p.is_file() and '.git' not in p.relative_to(root).parts}


class Case(unittest.TestCase):
    """A temporary base, and a temporary cwd: in-process usage refusals are logged against the cwd
    repository, so they never reach this checkout."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.tmp.name)


class ContextBuildTests(Case):
    """P3: contract-run.sh context-build exposes the same builder admission uses."""

    def build(self, fixture, *extra, goal='G1', stage='implementation', **kwargs):
        return fixture.run(['context-build', '--root', str(fixture.work), '--handoff', HANDOFF, '--goal-id', goal,
                            '--stage', stage, *extra], **kwargs)

    def test_context_build_is_the_admission_builder(self):
        fixture = Fixture(self.base)
        fixture.approve('in-session')
        exit_code, built = self.build(fixture)
        self.assertEqual(exit_code, 0, json.dumps(built, indent=1))
        self.assertEqual(built['schema'], 'readiness-context/2')
        self.assertTrue(built['admitted'])
        self.assertEqual(built['authority'], 'plan-approval/1')
        self.assertEqual(built['assurance'], 'in-session')
        self.assertEqual(v2.projection(built), v2.projection(fixture.admit()[1]))
        # One builder: the operation is the admission handler itself, never a second implementation.
        self.assertIs(observer.HANDLERS['context-build'], observer.HANDLERS['admit-v2'])
        self.assertNotIn('context-build', observer.RESERVED)
        log = [json.loads(line) for line in (fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        self.assertIn(('context-build', 0), {(entry['op'], entry['exit']) for entry in log})

    def test_without_a_valid_approval_the_context_states_no_authority(self):
        fixture = Fixture(self.base)
        exit_code, built = self.build(fixture)
        self.assertEqual(exit_code, 1, json.dumps(built, indent=1))
        self.assertFalse(built['admitted'])
        self.assertIsNone(built['approval'])
        self.assertEqual(built['authority'], v2.NO_AUTHORITY)
        self.assertIn('approval_tag_missing', codes(built))
        fixture.approve('in-session')
        exit_code, expired = self.build(fixture, now=NOW + timedelta(days=20))
        self.assertEqual(exit_code, 1, json.dumps(expired, indent=1))
        self.assertIn('approval_expired', codes(expired))
        self.assertIsNone(expired['approval'])
        self.assertEqual(expired['authority'], v2.NO_AUTHORITY)

    def test_a_supplied_context_that_differs_is_refused(self):
        fixture = Fixture(self.base)
        blocked = self.build(fixture)[1]
        fixture.approve('in-session')
        built = self.build(fixture)[1]
        supplied = self.base / 'supplied-context.json'
        write_json(supplied, built)
        self.assertEqual(self.build(fixture, '--context', str(supplied))[0], 0)
        variants = {'admitted flipped': dict(built, admitted=False), 'goals widened': dict(built, goals=['G1', 'G2']),
                    'authority edited': dict(built, authority='plan-approval/1 (supplied)'),
                    'blocked report with its gaps removed': dict(blocked, gaps=[], admitted=True)}
        fixture.commit_push('move the head and the target')
        variants['built at the previous head'] = built
        for name, value in variants.items():
            with self.subTest(variant=name):
                write_json(supplied, value)
                exit_code, result = self.build(fixture, '--context', str(supplied))
                self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
                self.assertIn('supplied_context_mismatch', codes(result))
                self.assertFalse(result['admitted'])
                self.assertNotEqual(result['authority'], 'plan-approval/1')

    def test_route_and_usage(self):
        for args in (['context-build', '--definitely-unknown'], ['context-build', 'proceed'], ['context-build', '--help'],
                     ['export-evidence']):
            result = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), *args], capture_output=True, text=True,
                                    cwd=self.tmp.name, stdin=subprocess.DEVNULL)
            self.assertEqual(result.returncode, 2, (args, result.stdout, result.stderr))
            self.assertIn('readiness-contract/2', result.stderr)
        exit_code, result = observer.run(['export-evidence'])
        self.assertEqual((exit_code, result['refusals'][0]['code']), (2, 'usage'))


class ContextDependencyTests(Case):
    """P4: a goal is refused until every ancestor goal's PR merge commit reaches origin/<target>,
    for merge-commit and squash merges, from hosted facts and git ancestry only."""

    def setUp(self):
        super().setUp()
        self.fixture = Fixture(self.base, bundle=sample_bundle(copy.deepcopy(CHAIN)))
        self.fixture.approve('in-session')
        self.state = write_json(self.base / 'gh-state.json', {'merged_prs': []})
        shim = gh_shim(self.base / 'bin', self.state, self.base / 'gh-log.jsonl')
        self.env = {'PATH': str(shim.parent) + os.pathsep + os.environ['PATH']}

    def admit(self, goal='G3', extra=()):
        return self.fixture.admit(goal=goal, extra=extra, env=self.env, adapter=observer.GhAdapter(self.fixture.work))

    def merged(self, number, goal, commit):
        state = json.loads(self.state.read_text())
        state['merged_prs'] = [p for p in state['merged_prs'] if p['number'] != number] + [
            {'number': number, 'headRefName': 'feat/plan-a-' + goal, 'mergeCommit': {'oid': commit},
             'mergedAt': '2026-10-03T10:00:00Z'}]
        write_json(self.state, state)

    def missing(self, context):
        return sorted((g['fact'], g['goal'], g['detail']) for g in context['gaps'] if g['code'] == 'dependency_incomplete')

    def test_transitive_completion_by_ancestry_for_merge_commit_and_squash(self):
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 1)
        self.assertEqual(self.missing(context), [('dependency:G1', 'G3', 'G1'), ('dependency:G2', 'G3', 'G2')])
        work = self.fixture.work
        # A hole in the chain: G2 is squash-merged and G1 is not, so G3 stays refused, naming G1.
        (work / 'src/two.txt').write_text('two\n')
        self.merged(2, 'G2', self.fixture.commit_push('squash merge of G2'))
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 1)
        self.assertEqual(self.missing(context), [('dependency:G1', 'G3', 'G1')])
        # G1 lands as a real merge commit of its goal branch.
        git(work, 'checkout', '-q', '-b', 'feat/plan-a-G1')
        (work / 'src/one.txt').write_text('one\n')
        self.fixture.commit_push('feat: G1', branch='feat/plan-a-G1')
        git(work, 'checkout', '-q', 'main')
        git(work, 'merge', '-q', '--no-ff', '-m', 'Merge pull request #1 from feat/plan-a-G1', 'feat/plan-a-G1')
        git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(work, 'fetch', '-q', 'origin')
        merge = git(work, 'rev-parse', 'HEAD')
        self.merged(1, 'G1', merge)
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        self.assertTrue(context['admitted'])
        self.assertEqual(context['authority'], 'plan-approval/1')
        facts = context['observation']['facts']
        self.assertEqual(facts['dependency:G1']['value'], {'prs': [1], 'merge_commit': merge, 'ancestor': True})
        self.assertEqual(facts['dependency:G2']['source'], 'hosted:production-gh+git')
        # A recorded merge commit that never reached the target completes nothing.
        self.merged(1, 'G1', 'f' * 40)
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 1)
        self.assertEqual(self.missing(context), [('dependency:G1', 'G3', 'G1')])

    def test_no_hand_written_receipt_completes_a_dependency(self):
        for extra in (('--receipt', 'G1.json'), ('--dependency', 'G1'), ('--completed-goal', 'G1')):
            self.assertEqual(self.admit(extra=extra)[0], 2, extra)
        work = self.fixture.work
        write_json(work / '.ai/evidence/G1.json', {'goal_id': 'G1', 'merged': True, 'merge_commit': 'a' * 40})
        write_json(work / '.ai/receipts/G1.json', {'goal': 'G1', 'status': 'merged', 'completed': True})
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 1)
        self.assertEqual(self.missing(context), [('dependency:G1', 'G3', 'G1'), ('dependency:G2', 'G3', 'G2')])
        for dependency in ('G1', 'G2'):
            fact = context['observation']['facts']['dependency:' + dependency]
            self.assertEqual((fact['source'], fact['value']['ancestor']), ('hosted:production-gh+git', False))


class ConcurrentPlansTests(Case):
    """AC-5: two v2 plans in one repository admit concurrently, interleaved, against one policy/2."""

    def setUp(self):
        super().setUp()
        self.repo = Repository(self.base)
        self.assertEqual(self.repo.approve('plan-a', 'in-session')[0], 0)
        self.assertEqual(self.repo.publish(plan_bundle('plan-b'))[0], 0)
        self.assertEqual(self.repo.approve('plan-b', 'in-session')[0], 0)
        self.policy_blob = git(self.repo.work, 'rev-parse', 'origin/main:' + POLICY)
        self.policy_sha = sha(self.repo.work / POLICY)

    def argv(self, plan, stage='implementation'):
        return ['admit-v2', '--root', str(self.repo.work), '--handoff', 'northstar-plan-' + plan, '--goal-id', 'G1',
                '--stage', stage]

    def test_two_plans_admit_interleaved_and_concurrently_against_one_policy(self):
        hooks = [mock.patch.object(observer, 'anchor_locator', lambda: Path(self.repo.anchor)),
                 mock.patch.object(observer, 'signing_key_locator', lambda: self.repo.fixture.keys.paths['certifier'])]
        for hook in hooks:
            hook.start()
        try:
            run = lambda argv: observer.run(argv, now=NOW)
            interleaved = [run(self.argv(plan, stage)) for plan, stage in (
                ('plan-a', 'implementation'), ('plan-b', 'implementation'), ('plan-a', 'planning'), ('plan-b', 'merge'),
                ('plan-b', 'implementation'), ('plan-a', 'implementation'))]
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                jobs = [pool.submit(lambda plans: [run(self.argv(plan)) for plan in plans], order)
                        for order in (('plan-a', 'plan-b', 'plan-a'), ('plan-b', 'plan-a', 'plan-b'))]
                concurrent_runs = [outcome for job in jobs for outcome in job.result()]
        finally:
            for hook in reversed(hooks):
                hook.stop()
        self.assertEqual([code for code, _ in interleaved], [0, 0, 1, 1, 0, 0],
                         json.dumps([c['gaps'] for _, c in interleaved], indent=1))
        self.assertEqual([c['stage'] for _, c in interleaved][2:4], ['planning', 'merge'])
        self.assertFalse(any(c['admitted'] for _, c in interleaved[2:4]))
        self.assertEqual(len(concurrent_runs), 6)
        for exit_code, context in concurrent_runs:
            self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
            self.assertTrue(context['admitted'])
        contexts = [c for _, c in interleaved + concurrent_runs]
        self.assertEqual({c['plan_id'] for c in contexts}, {'plan-a', 'plan-b'})
        self.assertEqual({c['policy']['sha256'] for c in contexts}, {self.policy_sha})
        self.assertEqual(git(self.repo.work, 'rev-parse', 'origin/main:' + POLICY), self.policy_blob)
        registry = json.loads(git(self.repo.work, 'show', 'origin/main:' + REGISTRY))
        self.assertEqual({(p['plan_id'], p['status']) for p in registry['plans']}, {('plan-a', 'active'), ('plan-b', 'active')})
        log = [json.loads(line) for line in (self.repo.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        admissions = [entry for entry in log if entry['op'] == 'admit-v2']
        self.assertGreaterEqual(len(admissions), 12)
        self.assertEqual({entry['plan_id'] for entry in admissions}, {'plan-a', 'plan-b'})

    def test_a_goal_branch_shared_across_plans_is_refused_at_publication(self):
        # plan "plan", goal "a-G1" and plan "plan-a", goal "G1" are both feat/plan-a-G1: a merged PR
        # on it would complete both goals, and routing could pick either plan.
        bundle = sample_bundle([{'id': 'a-G1', 'scope': ['src/other.txt'], 'acceptance_criteria': ['collides'],
                                 'dependencies': [], 'verification': ['bash tests/check.sh']}])
        bundle['id'] = 'plan'
        work = self.repo.work
        before = snapshot(work)
        exit_code, result = self.repo.run(['publish-v2', '--root', str(work), '--bundle',
                                           str(write_json(self.base / 'collide-bundle.json', bundle)), '--sidecar',
                                           str(write_json(self.base / 'collide-sidecar.json', sample_sidecar(bundle))),
                                           '--admit-planning'])
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('goal_branch_collision', codes(result))
        self.assertIn('feat/plan-a-G1', json.dumps(result['refusals']))
        self.assertEqual(snapshot(work), before)


def blocked_policy(anchor_sha256, identity_model='single', accept=('ssh-tag', 'in-session')):
    """sample_policy with a missing tool, an absent fixture and an untrusted harness commit."""
    policy = sample_policy(anchor_sha256, identity_model, accept)
    policy['tools'] = policy['tools'] + ['definitely-missing-tool-xyz']
    for gate in policy['gates']:
        if gate['kind'] == 'fixture':
            gate.pop('not_applicable')
            gate['binding'] = {'path': 'tools/missing.sh'}
        elif gate['kind'] == 'harness_trust':
            gate.pop('not_applicable')
            gate['binding'] = {'commit': '0' * 40}
    return policy


class ConsolidatedReportTests(Case):
    """Proceed semantics: one consolidated, deterministically ordered report naming gate, fact,
    source and recovery for every missing input; non-zero exit; no partial authority."""

    def setUp(self):
        super().setUp()
        with mock.patch.object(core, 'sample_policy', blocked_policy):
            self.fixture = Fixture(self.base, bundle=sample_bundle(copy.deepcopy(CHAIN[:2])))
        self.fixture.approve('in-session')
        state = write_json(self.base / 'gh-state.json', {'merged_prs': []})
        shim = gh_shim(self.base / 'bin', state, self.base / 'gh-log.jsonl')
        self.env = {'PATH': str(shim.parent) + os.pathsep + os.environ['PATH']}

    def admit(self):
        return self.fixture.admit(goal='G2', env=self.env, adapter=observer.GhAdapter(self.fixture.work))

    def test_one_consolidated_deterministic_report_without_partial_authority(self):
        exit_code, context = self.admit()
        self.assertEqual(exit_code, 1)
        self.assertFalse(context['admitted'])
        self.assertIsNotNone(context['approval'], 'the approval itself verified')
        self.assertEqual(context['authority'], v2.BLOCKED_AUTHORITY)
        gaps = context['gaps']
        for gap in gaps:
            self.assertEqual(set(gap), GAP_KEYS, gap)
            self.assertTrue(gap['source'] and gap['recovery'] and gap['fact'], gap)
        expected = {'tool_missing': ('tools', 'tool:definitely-missing-tool-xyz'),
                    'fixture_unavailable': ('fixtures', 'fixture:tools/missing.sh'),
                    'harness_untrusted': ('harness', 'ancestor:' + '0' * 40),
                    'dependency_incomplete': (None, 'dependency:G1')}
        for name, (gate, fact) in expected.items():
            (gap,) = [g for g in gaps if g['code'] == name]
            self.assertEqual((gap['gate'], gap['fact']), (gate, fact), gap)
            self.assertNotEqual(gap['recovery'], v2.RECOVERY['policy'], gap)
        self.assertEqual(gaps, sorted(gaps, key=gap_key))
        self.assertEqual(len({json.dumps(g, sort_keys=True) for g in gaps}), len(gaps))
        again = self.admit()[1]
        self.assertEqual(json.dumps(v2.projection(again), sort_keys=True), json.dumps(v2.projection(context), sort_keys=True))

    def test_the_pure_validator_names_the_fact_and_withholds_authority(self):
        policy, bundle = sample_policy('4' * 64), sample_bundle()
        inputs = core.admission_inputs(policy, bundle, sample_sidecar(bundle))
        self.assertTrue(v2.admission(copy.deepcopy(inputs))['admitted'])
        inputs['observation']['facts']['tool:git']['value'] = None
        context = v2.admission(inputs)
        self.assertFalse(context['admitted'])
        self.assertIsNotNone(context['approval'])
        self.assertEqual(context['authority'], v2.BLOCKED_AUTHORITY)
        (gap,) = context['gaps']
        self.assertEqual((gap['code'], gap['detail'], gap['gate'], gap['fact'], gap['source']),
                         ('tool_missing', 'git', 'tools', 'tool:git', 'observation/1'))
        (line,) = v2.render_gaps(context['gaps'])
        self.assertTrue(line.startswith('1. tool_missing [gate tools | fact tool:git | source observation/1] git -> '), line)
        self.assertTrue(line.endswith(gap['recovery']), line)

    def test_the_entry_point_prints_one_consolidated_block(self):
        result = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), 'admit-v2', '--root', str(self.fixture.work),
                                 '--handoff', HANDOFF, '--goal-id', 'G1'], capture_output=True, text=True,
                                cwd=self.tmp.name, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        context = json.loads(result.stdout)
        self.assertFalse(context['admitted'])
        self.assertEqual(result.stderr.count('blocked - '), 1, result.stderr)
        self.assertIn('readiness-contract/2: blocked - %d missing inputs (no authority)' % len(context['gaps']), result.stderr)
        for number, gap in enumerate(context['gaps'], 1):
            self.assertIn('\n%d. %s [' % (number, gap['code']), result.stderr)


if __name__ == '__main__':
    unittest.main()
