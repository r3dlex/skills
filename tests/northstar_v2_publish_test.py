"""ACH-S-04 publication and approval: handoff-write.sh given a v2 bundle runs planning-stage admission
against the simulated post-merge target (AC-7, P5); the anchor role-capability gap (AC-7, U3, O7);
generation defaults and publish-time verification; the mode-aware approve.sh (U1, O2, K2, K3, G4);
and the release surface. Ephemeral keys, temporary anchors and disposable repositories only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import base64
import contextlib
import copy
import io
import json
import os
import pwd
import re
import shutil
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

import readiness_v2_core_test as core
from readiness_v2_core_test import (AUTO, NORTH, NOW, POLICY, REGISTRY, REPO, Fixture, codes, git, sample_bundle,
                                    sample_policy, sample_sidecar, sha, ssh_sign, v2, observer, write_json)
from readiness_v2_approval_modes_test import ALL_FORMS, mode_fixture
from readiness_fixture import fixture as v1_fixture

WRITER = NORTH / 'handoff-write.sh'
APPROVE = NORTH / 'approve.sh'
HANDOFF = 'northstar-plan-plan-a'
POLICY_GOAL = {'id': 'P', 'scope': [POLICY], 'acceptance_criteria': ['policy lands'], 'dependencies': [],
               'verification': ['bash tests/check.sh']}
SIBLING = {'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['works'], 'dependencies': ['P'],
           'verification': ['bash tests/check.sh']}
APPROVER = ('approver@human', v2.NS_APPROVAL, 'approver')
CERTIFIER = ('certifier@agent', v2.NS_REVIEW + ',' + v2.NS_CERTIFICATE, 'certifier')
REVIEWER = ('reviewer@agent', v2.NS_REVIEW, 'reviewer')


def plan_b():
    """A second plan for the fixture repository: G2 depends on G1, and its spec copy is new."""
    return {'schema': 'handoff-goals/2', 'id': 'plan-b', 'repository': {'id': 'fixture'},
            'spec': {'path': 'docs/plan-b-spec.md'},
            'goals': [{'id': 'G1', 'scope': ['src/b1.txt'], 'acceptance_criteria': ['b1'], 'dependencies': [],
                       'verification': ['bash tests/check.sh']},
                      {'id': 'G2', 'scope': ['src/b2.txt'], 'acceptance_criteria': ['b2'], 'dependencies': ['G1'],
                       'verification': ['bash tests/check.sh', 'git diff --check']}]}


def write_spec(fixture, bundle=None):
    """The planning PR's spec copy, in the working tree only (never committed)."""
    spec = fixture.work / (bundle or plan_b())['spec']['path']
    spec.parent.mkdir(parents=True, exist_ok=True)
    spec.write_text('Plan B specification\n')


def publish(fixture, bundle, sidecar=None, extra=(), **kwargs):
    inputs = Path(tempfile.mkdtemp(prefix='publication-', dir=fixture.base))
    argv = ['publish-v2', '--root', str(fixture.work), '--bundle', str(write_json(inputs / 'bundle.json', bundle)),
            '--sidecar', str(write_json(inputs / 'sidecar.json', sidecar or sample_sidecar(bundle))), '--admit-planning',
            *extra]
    return fixture.run(argv, **kwargs)


def snapshot(root):
    """Every file outside .git, by digest."""
    root = Path(root)
    return {p.relative_to(root).as_posix(): sha(p) for p in sorted(root.rglob('*'))
            if p.is_file() and '.git' not in p.relative_to(root).parts}


def git_state(root):
    """The refs and the object store of a repository."""
    return git(root, 'for-each-ref', '--format=%(refname) %(objectname)'), git(root, 'count-objects', '-v')


def named(gaps):
    return {gap['code'] for gap in gaps}


def gate(policy, kind):
    return next(g for g in policy['gates'] if g['kind'] == kind)


def bind(policy, kind, binding):
    found = gate(policy, kind)
    found.pop('not_applicable', None)
    found['binding'] = binding


def policy_with(change):
    def build(anchor_sha256, identity_model='single', accept=('ssh-tag', 'in-session')):
        policy = sample_policy(anchor_sha256, identity_model, accept)
        change(policy)
        return policy
    return build


def anchored(lines):
    """Fixture anchors holding exactly these (principal, namespaces, key) lines."""
    def write_anchor(self, approver_namespaces=v2.NS_APPROVAL):
        self.anchor.write_text(''.join('%s namespaces="%s" %s\n' % (principal, namespaces, self.public(key))
                                       for principal, namespaces, key in lines))
        return sha(self.anchor)
    return mock.patch.object(core.Keys, 'write_anchor', write_anchor)


def run_script(script, *args, cwd=None):
    return subprocess.run(['bash', str(script), *map(str, args)], capture_output=True, text=True, cwd=cwd,
                          stdin=subprocess.DEVNULL, timeout=300)


class Case(unittest.TestCase):
    """A temporary base, and a temporary cwd: in-process usage refusals are logged against the cwd
    repository, so they never reach this checkout."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.tmp.name)

    def sub(self, name):
        base = self.base / name
        base.mkdir()
        return base


class PlanningPublicationTests(Case):
    """AC-7, P5: v2 publication is planning-stage admission against origin/<target> plus this publication."""

    def test_only_the_approval_gap_publishes(self):
        fixture = Fixture(self.base)
        write_spec(fixture)
        replay = self.base / 'replay'
        shutil.copytree(fixture.work, replay, symlinks=True)
        before = git_state(fixture.work)
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['schema'], 'northstar-publication/2')
        self.assertTrue(result['planning_complete'])
        self.assertEqual(result['authority'], v2.NO_AUTHORITY)
        planning = result['planning']
        self.assertEqual(planning['blocking'], [])
        self.assertLessEqual({'approval_tag_missing', 'plan_approval_missing', 'ownership_unresolved'},
                             named(planning['approval']))
        self.assertLessEqual({'branch_target_mismatch', 'pr_required', 'review_lane_missing', 'threads_unobserved',
                              'dependency_incomplete'}, named(planning['deferred']))
        self.assertFalse({'spec_missing', 'planning_input_not_on_target', 'planning_input_not_in_head'}
                         & named(planning['approval'] + planning['deferred']))
        # Deferred gaps are listed, never hidden and never counted as passed.
        deferred_gates = {g['gate'] for g in planning['deferred'] if g['gate']}
        self.assertTrue(deferred_gates)
        for entry in result['gates']:
            if entry['id'] in deferred_gates:
                self.assertEqual(entry['status'], 'deferred', entry)
        entry = result['published']
        prefix = '.ai/handoff/readiness-v2/plan-b/' + entry['generation']
        self.assertEqual(sorted(p.name for p in (fixture.work / prefix).iterdir()),
                         ['goals.json', 'graph.json', 'handoff.md', 'sidecar.json'])
        registry = json.loads((fixture.work / REGISTRY).read_text())
        self.assertEqual([p['id'] for p in registry['plans']], ['northstar-plan-plan-a', 'northstar-plan-plan-b'])
        self.assertIn('approve.sh', result['next'])
        self.assertEqual(git_state(fixture.work), before, 'the simulation never writes the root object store or refs')
        # The generation bytes are exactly what the unflagged publish-v2 (the replay lane) writes.
        inputs = Path(tempfile.mkdtemp(dir=self.base))
        exit_code, plain = observer.run(['publish-v2', '--root', str(replay), '--bundle',
                                         str(write_json(inputs / 'b.json', plan_b())), '--sidecar',
                                         str(write_json(inputs / 's.json', sample_sidecar(plan_b())))], now=NOW)
        self.assertEqual(exit_code, 0, json.dumps(plain, indent=1))
        self.assertEqual(plain['published'], entry)
        for name in (REGISTRY, *('%s/%s' % (prefix, n) for n in ('goals.json', 'graph.json', 'handoff.md', 'sidecar.json'))):
            self.assertEqual(sha(fixture.work / name), sha(replay / name), name)
        # A rerun of the same publication is idempotent.
        exit_code, again = publish(fixture, plan_b())
        self.assertEqual((exit_code, again['published']), (0, entry), json.dumps(again, indent=1))

    def test_blocking_gaps_refuse_and_write_nothing(self):
        cases = {'tool_missing': lambda p: p['tools'].append('definitely-missing-tool-xyz'),
                 'fixture_unavailable': lambda p: bind(p, 'fixture', {'path': 'tools/missing.sh'}),
                 'harness_untrusted': lambda p: bind(p, 'harness_trust', {'commit': '0' * 40}),
                 'git_ancestor_missing': lambda p: bind(p, 'git_ancestor', {'commits': ['0' * 40]})}
        for name, change in cases.items():
            with self.subTest(code=name):
                with mock.patch.object(core, 'sample_policy', policy_with(change)):
                    fixture = Fixture(self.sub(name))
                write_spec(fixture)
                before = snapshot(fixture.work)
                exit_code, result = publish(fixture, plan_b())
                self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
                self.assertEqual(result['schema'], 'northstar-publication/2')
                self.assertFalse(result['planning_complete'])
                self.assertIsNone(result['published'])
                self.assertIn(name, named(result['planning']['blocking']))
                self.assertIn('planning_incomplete', codes(result))
                self.assertEqual(snapshot(fixture.work), before)

    def test_the_simulation_reads_origin_plus_this_publication(self):
        fixture = Fixture(self.base)
        write_spec(fixture)
        (fixture.work / 'AGENTS.md').unlink()  # a policy source deleted locally and never committed
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        everything = named(sum((result['planning'][k] for k in ('approval', 'deferred', 'blocking')), []))
        self.assertFalse({'policy_source_missing', 'spec_missing', 'planning_input_not_on_target',
                          'planning_input_not_in_head'} & everything)

    def test_a_commit_only_in_the_local_repository_is_not_on_the_target(self):
        fixture = Fixture(self.base)
        work = fixture.work
        git(work, 'checkout', '-q', '-b', 'local-only')
        (work / 'local.txt').write_text('local\n')
        git(work, 'add', '-A')
        git(work, 'commit', '-q', '-m', 'a commit that never reaches origin')
        local = git(work, 'rev-parse', 'HEAD')
        git(work, 'checkout', '-q', 'main')
        policy = json.loads((work / POLICY).read_text())
        bind(policy, 'harness_trust', {'commit': local})
        write_json(work / POLICY, policy)
        fixture.commit_push('policy: pin a harness commit that exists only locally')
        write_spec(fixture)
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertEqual([g['detail'] for g in result['planning']['blocking'] if g['code'] == 'harness_untrusted'], [local])

    def test_a_stale_local_target_ref_refuses(self):
        fixture = Fixture(self.base)
        old = git(fixture.work, 'rev-parse', 'origin/main')
        fixture.commit_push('another commit on main')
        git(fixture.work, 'update-ref', 'refs/remotes/origin/main', old)
        write_spec(fixture)
        before = snapshot(fixture.work)
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('target_ref_rewound', codes(result))
        self.assertEqual(snapshot(fixture.work), before)

    def test_the_publication_base_is_the_target_registry(self):
        fixture = Fixture(self.base)
        registry = json.loads((fixture.work / REGISTRY).read_text())
        registry['plans'].append(dict(registry['plans'][0], id='northstar-plan-not-on-origin'))
        write_json(fixture.work / REGISTRY, registry)
        write_spec(fixture)
        before = snapshot(fixture.work)
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('publication_base_mismatch', codes(result))
        self.assertEqual(snapshot(fixture.work), before)

    def test_a_v2_publication_carries_no_holds(self):
        fixture = Fixture(self.base)
        write_spec(fixture)
        held = sample_sidecar(plan_b())
        held['goals']['G2']['readiness']['merge'] = 'blocked'
        before = snapshot(fixture.work)
        exit_code, result = publish(fixture, plan_b(), held)
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('publication_hold_refused', codes(result))
        self.assertEqual(snapshot(fixture.work), before)

    def test_a_v1_bundle_takes_the_unchanged_v1_path(self):
        root = self.base / 'v1'
        outcomes = []
        for script, args in ((WRITER, ()), (AUTO / 'contract-run.sh', ('publish',))):
            shutil.rmtree(root, ignore_errors=True)
            root.mkdir()
            v1_fixture(root)
            outcomes.append(run_script(script, *args, '--root', root, '--bundle', root / 'plan.json', cwd=self.tmp.name))
        self.assertEqual(outcomes[0].returncode, 0, outcomes[0].stdout + outcomes[0].stderr)
        self.assertEqual((outcomes[0].returncode, outcomes[0].stdout), (outcomes[1].returncode, outcomes[1].stdout))
        self.assertIn('published', json.loads(outcomes[0].stdout))

    def test_handoff_write_dispatches_a_v2_bundle_to_planning_admission(self):
        fixture = Fixture(self.base)
        write_spec(fixture)
        inputs = Path(tempfile.mkdtemp(dir=self.base))
        bundle, sidecar = write_json(inputs / 'b.json', plan_b()), write_json(inputs / 's.json', sample_sidecar(plan_b()))
        before = snapshot(fixture.work)
        # No in-process hooks: the real passwd-home anchor never equals this fixture's ephemeral anchor.
        result = run_script(WRITER, '--root', fixture.work, '--bundle', bundle, '--sidecar', sidecar, cwd=self.tmp.name)
        output = json.loads(result.stdout)
        self.assertEqual(output['schema'], 'northstar-publication/2', result.stdout + result.stderr)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(output['planning_complete'])
        blocking = named(output['planning']['blocking'])
        self.assertTrue(blocking)
        self.assertLessEqual(blocking, {'anchor_missing', 'anchor_digest_mismatch', 'anchor_symlink'})
        self.assertIn('northstar: planning incomplete - blocking %d' % len(output['planning']['blocking']), result.stderr)
        self.assertEqual(snapshot(fixture.work), before)

    def test_gaps_are_classified_by_kind(self):
        table = {'approval_tag_missing': 'approval', 'approval_expired': 'approval', 'approval_signature_invalid': 'approval',
                 'plan_approval_missing': 'approval', 'ownership_unresolved': 'approval',
                 'branch_target_mismatch': 'deferred', 'pr_required': 'deferred', 'check_pending': 'deferred',
                 'check_missing': 'deferred', 'check_failed': 'deferred', 'protection_check_unsatisfied': 'deferred',
                 'review_lane_missing': 'deferred', 'threads_unobserved': 'deferred', 'dependency_incomplete': 'deferred',
                 'tool_missing': 'blocking', 'fixture_unavailable': 'blocking', 'git_ancestor_missing': 'blocking',
                 'harness_untrusted': 'blocking', 'planning_input_not_on_target': 'blocking', 'anchor_missing': 'blocking',
                 'anchor_role_capability_missing': 'blocking', 'agent_self_not_accepted': 'blocking',
                 'agent_self_bootstrap_refused': 'blocking', 'agent_self_refused_by_mode': 'blocking',
                 'generation_mismatch': 'blocking', 'unresolved_threads': 'blocking', 'review_lane_signature_invalid': 'blocking',
                 'readiness_hold': 'blocking', 'totally_new_code': 'blocking'}
        gaps = [v2.gap_entry(name, 'x') for name in table]
        classes = v2.planning_classes(gaps)
        for kind in ('approval', 'deferred', 'blocking'):
            self.assertEqual(sorted(named(classes[kind])), sorted(n for n, k in table.items() if k == kind), kind)
        self.assertFalse(classes['planning_complete'])
        self.assertTrue(v2.planning_classes([g for g in gaps if table[g['code']] != 'blocking'])['planning_complete'])
        self.assertTrue(v2.planning_classes([])['planning_complete'])


class AnchorCapabilityTests(Case):
    """AC-7, U3, O7: planning names an anchor that cannot approve or cannot staff two lanes."""

    def fixture(self, name, lines, **kwargs):
        with anchored(lines):
            return Fixture(self.sub(name), **kwargs)

    def planning(self, fixture, goal='G1'):
        exit_code, context = fixture.admit(stage='planning', goal=goal)
        self.assertEqual(exit_code, 1, 'planning is never admitted')
        return [g for g in context['gaps'] if g['code'] == 'anchor_role_capability_missing'], context

    def test_a_single_agent_principal_is_refused_at_planning(self):
        fixture = self.fixture('single', [APPROVER, CERTIFIER])
        gaps, context = self.planning(fixture)
        self.assertEqual(len(gaps), 1, gaps)
        self.assertTrue(gaps[0]['detail'].startswith('review_lane_not_independent'), gaps[0])
        self.assertEqual((gaps[0]['fact'], gaps[0]['source'], gaps[0]['recovery']),
                         ('anchor_roles', 'anchor', v2.RECOVERY['anchor']))
        self.assertFalse(context['planning']['planning_complete'])
        self.assertIn(gaps[0], context['planning']['blocking'])
        write_spec(fixture)
        exit_code, result = publish(fixture, plan_b())
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('anchor_role_capability_missing', named(result['planning']['blocking']))
        # A planning-stage report: implementation contexts are unchanged.
        self.assertNotIn('anchor_role_capability_missing', codes(fixture.admit()[1]))

    def test_an_agent_approval_principal_counts_only_when_agent_self_is_accepted(self):
        agent = ('agent@x', ','.join((v2.NS_REVIEW, v2.NS_CERTIFICATE, v2.NS_AGENT_APPROVAL)), 'certifier')
        reviewer = ('reviewer@x', v2.NS_REVIEW, 'reviewer')
        narrow = self.fixture('narrow', [agent, reviewer], accept=('ssh-tag',))
        gaps, _ = self.planning(narrow)
        self.assertEqual([g['detail'].split(':', 1)[0] for g in gaps], ['approval'], gaps)
        wide = self.fixture('wide', [agent, reviewer], accept=('ssh-tag', 'agent-self'))
        self.assertEqual(self.planning(wide)[0], [])
        # A bootstrap generation never takes agent-self (rule d), whatever its candidate accepts.
        bootstrap = self.fixture('bootstrap', [agent, reviewer], accept=('agent-self',), candidate=True, live_policy=False,
                                 bundle=sample_bundle([dict(POLICY_GOAL), dict(SIBLING)]))
        gaps, _ = self.planning(bootstrap, goal='P')
        self.assertEqual([g['detail'].split(':', 1)[0] for g in gaps], ['approval'], gaps)

    def test_in_session_needs_no_approval_principal(self):
        fixture = self.fixture('in-session', [CERTIFIER, REVIEWER], accept=('in-session',))
        self.assertEqual(self.planning(fixture)[0], [])

    def test_the_default_fixture_anchor_is_capable(self):
        fixture = Fixture(self.base)
        gaps, context = self.planning(fixture)
        self.assertEqual(gaps, [])
        roles = context['observation']['facts']['anchor_roles']['value']
        self.assertEqual(roles['sha256'], fixture.anchor_sha256)
        self.assertIn({'principal': 'certonly@agent', 'namespaces': [v2.NS_CERTIFICATE]}, roles['lines'])


class GenerationDefaultsTests(Case):
    """Generation defaults and publish-time verification."""

    def setUp(self):
        super().setUp()
        self.fixture = Fixture(self.base)
        write_spec(self.fixture)

    def partial(self, reasons):
        return {'schema': 'readiness-sidecar/1', 'plan_id': 'plan-b',
                'goals': {gid: ({} if reason is None else {'legacy_risk_reason': reason}) for gid, reason in reasons.items()}}

    def refused(self, expected, bundle=None, sidecar=None, **kwargs):
        before = snapshot(self.fixture.work)
        exit_code, result = publish(self.fixture, bundle or plan_b(), sidecar, **kwargs)
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn(expected, codes(result), json.dumps(result, indent=1))
        self.assertEqual(snapshot(self.fixture.work), before)

    def test_a_partial_sidecar_takes_the_generation_defaults(self):
        exit_code, result = publish(self.fixture, plan_b(), self.partial({'G1': 'unmeasured', 'G2': 'unmeasured too'}))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        written = json.loads((self.fixture.work / result['published']['artifacts']['sidecar']['path']).read_text())
        for gid, reason in (('G1', 'unmeasured'), ('G2', 'unmeasured too')):
            self.assertEqual(written['goals'][gid], {
                'readiness': {'preparation': 'unknown', 'implementation': 'unknown', 'merge': 'unknown'},
                'coverage_status': 'unknown', 'legacy_safe_tdd': True, 'legacy_risk_reason': reason})
        full = sample_sidecar(plan_b())
        self.assertEqual(v2.sidecar_defaults(plan_b(), copy.deepcopy(full)), full)

    def test_a_goal_without_a_legacy_risk_reason_is_refused(self):
        for reasons in ({'G1': 'fine', 'G2': ''}, {'G1': 'fine', 'G2': '   '}, {'G1': 'fine', 'G2': None}, {'G1': 'fine'}):
            with self.subTest(reasons=reasons):
                self.refused('legacy_risk_reason_missing', sidecar=self.partial(reasons))
        self.refused('sidecar_goals_mismatch', sidecar=self.partial({'G1': 'fine', 'G2': 'fine', 'G9': 'unknown goal'}))

    def test_bash_verification_scripts_exist_at_the_base_commit(self):
        script = self.fixture.work / 'tests/new_test.sh'
        script.write_text('#!/bin/sh\nexit 0\n')
        script.chmod(0o755)
        bundle = plan_b()
        bundle['goals'][1]['verification'] = ['bash tests/new_test.sh']
        self.refused('verification_not_at_base', bundle=bundle)
        self.fixture.commit_push('test: add the new test')
        exit_code, result = publish(self.fixture, bundle)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))

    def test_verification_scope_and_dependency_validation(self):
        def changed(change):
            bundle = plan_b()
            change(bundle['goals'][1])
            return bundle
        cases = [(lambda g: g.update(verification=['curl x']), 'verification_invalid', {}),
                 (lambda g: g.update(verification=['bash tests/missing.sh']), 'verification_invalid', {}),
                 (lambda g: g.update(verification=['poetry run pytest']), 'verification_invalid',
                  {'env': {'PATH': '/usr/bin:/bin'}}),
                 (lambda g: g.update(dependencies=['G9']), 'bundle_dependency_unknown', {})]
        for scope in ('../x', '/abs', 'a/*.py', 'a/./b', '.git/config', 'src/.GIT/hooks', ' src/x', 'src/x ', 'src/\x01x'):
            cases.append((lambda g, scope=scope: g.update(scope=[scope]), 'bundle_scope_unsafe', {}))
        for change, expected, kwargs in cases:
            with self.subTest(expected=expected, bundle=changed(change)['goals'][1]):
                self.refused(expected, bundle=changed(change), **kwargs)


class ApproveTests(Case):
    """U1, O2, K2, K3, G4: approve.sh records owner and reviewer lane once and is mode-aware. It never
    signs with an approver key, never writes the anchor or a tag, and never reads a terminal."""

    def request(self, fixture, *extra, key='agentself', owner=True, **kwargs):
        argv = ['approval-request', '--root', str(fixture.work), '--handoff', HANDOFF]
        if owner:
            argv += ['--owner', 'Fixture Owner', '--reviewer-lane', 'independent review lane']
        return fixture.run(argv + list(extra), key=key, **kwargs)

    def spy(self):
        calls, original = [], observer.sign

        def recording(key, namespace, data):
            calls.append((Path(key).name, namespace))
            return original(key, namespace, data)
        return calls, mock.patch.object(observer, 'sign', recording)

    def test_agent_mode_is_the_default(self):
        for name, default_mode in (('agent', 'agent'), ('unset', None)):
            with self.subTest(default_mode=default_mode):
                fixture = mode_fixture(self.sub(name), default_mode, ALL_FORMS)
                calls, spy = self.spy()
                with spy:
                    exit_code, result = self.request(fixture, '--mode', 'default')
                self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
                self.assertEqual((result['mode'], result['assurance'], result['human_action']), ('agent', 'agent-self', None))
                self.assertEqual(calls, [('agentself', v2.NS_AGENT_APPROVAL)])
                fixture.approve('agent-self', message=result['message'])
                exit_code, context = fixture.admit()
                self.assertEqual((exit_code, context['assurance']), (0, 'agent-self'), context['gaps'])
                # Never an approver key: the agent path refuses one before anything is signed.
                calls, spy = self.spy()
                with spy:
                    exit_code, result = self.request(fixture, '--mode', 'agent', key='approver')
                self.assertEqual(exit_code, 1)
                self.assertIn('agent_approval_signer_not_agent', codes(result))
                self.assertEqual(calls, [])

    def test_the_default_without_agent_self_is_refused_and_prompt_needs_an_explicit_request(self):
        fixture = Fixture(self.base)
        calls, spy = self.spy()
        with spy:
            exit_code, result = self.request(fixture, '--mode', 'default')
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('agent_self_not_accepted', codes(result))
        self.assertIn('--mode prompt', ' '.join(result['notes']))
        self.assertEqual(calls, [])

    def test_prompt_mode_records_the_explicit_confirmation_in_two_steps(self):
        fixture = Fixture(self.base)
        calls, spy = self.spy()
        with spy:
            exit_code, first = self.request(fixture, '--mode', 'prompt')
        self.assertEqual(exit_code, 0, json.dumps(first, indent=1))
        self.assertEqual((first['mode'], first['assurance']), ('prompt', 'in-session'))
        self.assertEqual(first['digest'], v2.canonical(first['record']))
        self.assertEqual(first['anchor_sha256'], fixture.anchor_sha256)
        self.assertIn(first['digest'], first['human_action'])
        self.assertIn('--confirm ' + first['digest'], first['human_action'])
        self.assertIn('ASSURANCE: IN-SESSION', first['notice'])
        self.assertNotIn('message', first)
        self.assertEqual(calls, [])
        self.assertEqual((git(fixture.work, 'tag', '-l'), git(fixture.work, 'ls-remote', '--tags', 'origin')), ('', ''))
        exit_code, second = self.request(fixture, '--confirm', first['digest'], owner=False)
        self.assertEqual(exit_code, 0, json.dumps(second, indent=1))
        line = json.dumps(first['record'], sort_keys=True, separators=(',', ':'))
        self.assertEqual(second['message'], line + '\ndigest-echo: ' + first['digest'] + '\n')
        self.assertEqual(second['assurance'], 'in-session')
        self.assertIn('git tag -a --cleanup=verbatim', '\n'.join(second['commands']['in-session']))
        fixture.approve('in-session', message=second['message'])
        exit_code, context = fixture.admit()
        self.assertEqual((exit_code, context['assurance']), (0, 'in-session'), context['gaps'])
        self.assertIn('approval_confirmation_unknown', codes(self.request(fixture, '--confirm', 'f' * 64, owner=False)[1]))
        stale = self.request(fixture, '--confirm', first['digest'], owner=False, now=NOW + timedelta(days=15))
        self.assertEqual(stale[0], 1)
        self.assertIn('approval_confirmation_stale', codes(stale[1]))

    def test_ssh_tag_mode_prints_the_commands_for_a_human_approver_key(self):
        fixture = Fixture(self.base)
        calls, spy = self.spy()
        with spy:
            exit_code, result = self.request(fixture, '--mode', 'ssh-tag')
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(calls, [])
        self.assertEqual((result['mode'], result['assurance'], result['human_action']), ('ssh-tag', 'key-held', 'sign'))
        self.assertNotIn('fallback', result)
        text = '\n'.join(result['commands']['ssh-tag'])
        for needed in ('-n ai-catapult-plan-approval', '<your approver key>', 'git tag -a --cleanup=verbatim', 'git push'):
            self.assertIn(needed, text)
        self.assertNotIn('git tag -s', text)
        line = json.dumps(result['record'], sort_keys=True, separators=(',', ':'))
        signature = ssh_sign(fixture.keys.paths['approver'], v2.NS_APPROVAL, line.encode(), self.base)
        fixture.approve('ssh-tag', message=line + '\nsignature: ' + base64.b64encode(signature.encode()).decode() + '\n')
        exit_code, context = fixture.admit()
        self.assertEqual((exit_code, context['assurance']), (0, 'key-held'), context['gaps'])

    def test_bootstrap_generations_need_in_session_or_ssh_tag(self):
        fixture = Fixture(self.base, bundle=sample_bundle([dict(POLICY_GOAL), dict(SIBLING)]), candidate=True,
                          live_policy=False, accept=ALL_FORMS)
        exit_code, result = self.request(fixture, '--mode', 'default')
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('agent_self_bootstrap_refused', codes(result))
        rule = 'need an in-session or ssh-tag approval (rule d)'
        self.assertIn(rule, ' '.join(result['notes']))
        exit_code, result = self.request(fixture, '--mode', 'prompt')
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertIn(rule, ' '.join(result['notes']))

    def test_without_an_anchor_it_prints_the_human_setup_steps(self):
        fixture = Fixture(self.base)
        missing = self.base / 'nope' / 'allowed_signers'
        exit_code, result = self.request(fixture, '--mode', 'prompt', anchor=missing)
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('anchor_missing', codes(result))
        setup = '\n'.join(result['setup'])
        for needed in ('ssh-keygen -t ed25519-sk', 'allowed_signers', 'namespaces="ai-catapult-plan-approval"',
                       'ai-catapult-review,ai-catapult-certificate', 'ai-catapult-agent-approval', 'shasum -a 256',
                       'agents never write it'):
            self.assertIn(needed, setup)
        self.assertFalse(missing.parent.exists())

    def test_no_mode_writes_the_anchor_or_a_tag(self):
        fixture = mode_fixture(self.base, 'agent', ALL_FORMS)
        anchor = fixture.keys.anchor
        before = (sha(anchor), anchor.stat().st_mtime_ns)
        for extra in (('--mode', 'default'), ('--mode', 'agent'), ('--mode', 'prompt'), ('--mode', 'ssh-tag')):
            self.assertEqual(self.request(fixture, *extra)[0], 0, extra)
        self.assertEqual((sha(anchor), anchor.stat().st_mtime_ns), before)
        self.assertEqual((git(fixture.work, 'tag', '-l'), git(fixture.work, 'ls-remote', '--tags', 'origin')), ('', ''))

    def test_mode_and_assurance_usage(self):
        fixture = Fixture(self.base)
        for extra in (('--mode', 'prompt', '--assurance', 'agent-self'), ('--mode', 'agent', '--assurance', 'key-held'),
                      ('--mode', 'bogus')):
            self.assertEqual(self.request(fixture, *extra)[0], 2, extra)
        self.assertEqual(self.request(fixture, '--mode', 'prompt', owner=False)[0], 2)

    def test_the_approve_script(self):
        for args in (['--mode', 'bogus'], ['--help'], ['proceed'], ['--root', '.', '--handoff', 'x', '--owner', 'o']):
            result = run_script(APPROVE, *args, cwd=self.tmp.name)
            self.assertEqual(result.returncode, 2, (args, result.stdout, result.stderr))
        fixture = Fixture(self.sub('fixture'))
        real = Path(pwd.getpwuid(os.getuid()).pw_dir) / '.config/ai-catapult/allowed_signers'
        observed = lambda: (sha(real), real.stat().st_mtime_ns) if real.is_file() else None
        before = observed()
        args = ['--root', fixture.work, '--handoff', HANDOFF, '--owner', 'o', '--reviewer-lane', 'l']
        # No in-process hooks: the real passwd-home anchor never equals this fixture's ephemeral anchor.
        process = subprocess.Popen(['bash', str(APPROVE), *map(str, args)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, cwd=self.tmp.name)
        try:
            stdout, stderr = process.communicate(timeout=300)  # stdin stays open: a terminal read would hang
        finally:
            process.kill()
        self.assertNotEqual(process.returncode, 0)
        output = json.loads(stdout)
        self.assertEqual(output['requested_mode'], 'default', stdout + stderr)
        self.assertTrue(codes(output) & {'anchor_missing', 'anchor_digest_mismatch', 'anchor_symlink'}, stdout)
        self.assertEqual(observed(), before)
        flat = self.sub('flat')
        shutil.copytree(AUTO, flat / 'autobahn', ignore=shutil.ignore_patterns('__pycache__'))
        shutil.copytree(NORTH, flat / 'northstar', ignore=shutil.ignore_patterns('__pycache__'))
        self.assertNotIn('dependency_failed', run_script(flat / 'northstar/approve.sh', *args, cwd=self.tmp.name).stdout)
        with (flat / 'northstar/approve.sh').open('a') as handle:
            handle.write('\n# drift\n')
        drifted = run_script(flat / 'northstar/approve.sh', *args, cwd=self.tmp.name)
        self.assertNotEqual(drifted.returncode, 0)
        self.assertIn('dependency_failed', drifted.stdout)

    def test_the_approval_module_defines_plan_approval(self):
        text = ' '.join((NORTH / 'modules/approval.md').read_text().split())
        for phrase in ('Plan approval', 'Spec approval', 'remains not a state', '`agent` mode', '`prompt` mode',
                       '`ssh-tag` mode', 'need an in-session or ssh-tag approval (rule d)', 'never signs with an approver key',
                       'never writes the anchor', 'approve.sh --root', '--confirm', 'ASSURANCE: IN-SESSION',
                       'ASSURANCE: AGENT-SELF', 'namespaces='):
            self.assertIn(phrase, text)
        handoff = (NORTH / 'modules/handoff.md').read_text()
        for phrase in ('(approval.md)', 'handoff-goals/2', 'northstar-publication/2', 'schema_version', 'optional_branches'):
            self.assertIn(phrase, handoff)
        parity = subprocess.run(['bash', str(REPO / 'scripts/check-codex-parity.sh'), str(NORTH / 'modules/approval.md')],
                                capture_output=True, text=True)
        self.assertEqual(parity.returncode, 0, parity.stdout)


class ReleaseSurfaceTests(unittest.TestCase):
    """Catalog and Codex parity: re-pinned manifests and local CI contract."""

    def test_manifests_and_local_ci_contract_are_re_pinned(self):
        manifest = json.loads((AUTO / 'readiness-dependency-v2.json').read_text())
        self.assertEqual(manifest['files']['northstar/approve.sh'], sha(APPROVE))
        self.assertEqual((AUTO / 'readiness-dependency-v2.json').read_bytes(),
                         (NORTH / 'readiness-dependency-v2.json').read_bytes())
        import local_ci_contract
        local_ci_contract.read_contract(REPO)  # a stale pin raises ValueError
        contract = json.loads((REPO / '.ai/ci/local-ci.json').read_text())
        for name in ('tests/readiness_v2_context_test.py', 'tests/readiness_v2_context_test.sh',
                     'tests/northstar_v2_publish_test.py', 'tests/northstar_v2_publish_test.sh',
                     '04-validate-handoff/autobahn/lib/observer.py', '04-validate-handoff/autobahn/lib/readiness_contract_v2.py',
                     '04-validate-handoff/autobahn/readiness-dependency-v2.json', 'tests/readiness_v2_core_test.py'):
            self.assertEqual(contract['sources'].get(name), sha(REPO / name), name)


# --- migrated own-script verification (the marked publication route) ------------------------------------
#
# New test code is strict-typed (the ledger ratchet pins this file's mypy count): the untyped fixture
# helpers are reached through these typed views.
from typing import Any, Callable  # noqa: E402 - the appended marked-route cases
from readiness_contract import Invalid  # noqa: E402 - the refusal every ingress raises
from readiness_v2_migrate_test import HOST_UNSTARTED, marked_plan  # noqa: E402 - the migrated, marked fixture plan

_fixture: Callable[..., Any] = Fixture
_sub: Callable[..., Any] = Case.sub
_code: Callable[..., str] = v2.code
_main: Callable[..., Any] = observer.main
_adapter: Callable[..., Any] = observer.FixtureAdapter
_run: Callable[..., Any] = observer.run
_publish: Callable[..., Any] = publish
_snapshot: Callable[..., Any] = snapshot
_write_json: Callable[..., Any] = write_json
_sha: Callable[..., str] = sha
_codes: Callable[..., Any] = codes
_git: Callable[..., str] = git
_bytes: Callable[..., bytes] = observer.publication_bytes
def forbidden(*args: Any, **kwargs: Any) -> Any:
    raise AssertionError('decision construction performed an observation')


def no_observation() -> list[Any]:
    """The spy of AC-4's capture contract: no subprocess, no environment read, no filesystem read, no clock
    and no temporary allocation between the seal and the single decision exit."""
    environment = mock.MagicMock()
    environment.__getitem__.side_effect = forbidden
    environment.get.side_effect = forbidden
    patches = [mock.patch('subprocess.run', forbidden), mock.patch('subprocess.Popen', forbidden),
               mock.patch('subprocess.check_output', forbidden), mock.patch('builtins.open', forbidden),
               mock.patch('pathlib.Path.read_bytes', forbidden), mock.patch('pathlib.Path.read_text', forbidden),
               mock.patch('pathlib.Path.is_file', forbidden), mock.patch('pathlib.Path.is_dir', forbidden),
               mock.patch('pathlib.Path.exists', forbidden), mock.patch('pathlib.Path.resolve', forbidden),
               mock.patch('pathlib.Path.iterdir', forbidden), mock.patch('pathlib.Path.write_bytes', forbidden),
               mock.patch('pathlib.Path.mkdir', forbidden), mock.patch('os.stat', forbidden), mock.patch('os.access', forbidden),
               mock.patch('os.listdir', forbidden), mock.patch('os.environ', environment),
               mock.patch('tempfile.mkdtemp', forbidden), mock.patch('tempfile.TemporaryDirectory', forbidden),
               mock.patch('time.time', forbidden), mock.patch.object(observer, 'datetime', mock.MagicMock(now=forbidden))]
    return patches


def spied(target: str, calls: list[Any]) -> Any:
    """Patch observer.<target> with a wrapper that binds the no-observation spy for exactly the call's
    duration and records that the exit serializer ran inside it."""
    original = getattr(observer, target)

    def wrapper(*args: Any, **kwargs: Any) -> Any:
        patches = no_observation()
        exits: list[Any] = []

        def exit_serializer(value: Any) -> bytes:
            exits.append(value)
            return _bytes(value)
        for patch in patches:
            patch.start()
        try:
            with mock.patch.object(observer, 'publication_bytes', side_effect=exit_serializer):
                result = original(*args, **kwargs)
        finally:
            for patch in reversed(patches):
                patch.stop()
        calls.append(len(exits))
        return result
    return mock.patch.object(observer, target, wrapper)


def stamps(data: bytes) -> set[str]:
    return {match.decode() for match in re.findall(rb'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z', data)}


def twin_of(fixture: Any, work: Any) -> Any:
    """The same keys and hooks over another checkout of the same repository: a fresh location or a linked worktree."""
    twin = mock.MagicMock()
    twin.work, twin.base, twin.keys, twin.run = work, work.parent, fixture.keys, fixture.run
    return twin


class MarkedPublicationTests(Case):
    """AC-1 to AC-4: a proved migration publishes with its own-script leaves deferred, every forged or
    unprovable marker refuses with zero publication writes, and the decision bytes are deterministic."""

    def setUp(self) -> None:
        super().setUp()  # type: ignore[no-untyped-call]
        self.fixture = _fixture(self.base)
        self.bundle, self.sidecar, self.legacy = marked_plan(self.fixture)
        self.before = _snapshot(self.fixture.work)

    def publish_marked(self, bundle: Any = None, sidecar: Any = None, **kwargs: Any) -> Any:
        kwargs.setdefault('adapter', _adapter(HOST_UNSTARTED))
        return _publish(self.fixture, bundle or self.bundle, sidecar or self.sidecar, **kwargs)

    def refused(self, bundle: Any, expected: str, **kwargs: Any) -> Any:
        exit_code, result = self.publish_marked(bundle, **kwargs)
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn(expected, _codes(result), json.dumps(result, indent=1))
        self.assertEqual(_snapshot(self.fixture.work), self.before, 'a refusal writes nothing')
        return result

    def test_a_proved_migration_publishes_with_its_own_script_deferred(self) -> None:
        exit_code, result = self.publish_marked()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertTrue(result['planning_complete'])
        self.assertEqual(result['authority'], v2.NO_AUTHORITY)
        record = result[v2.MARKER]
        self.assertEqual(record['schema'], v2.MARKER_RECORD_SCHEMA)
        self.assertEqual((record['authority'], record['readiness']), (v2.NO_AUTHORITY, 'unknown'))
        self.assertEqual([(d['goal'], d['verification_index'], d['path'], d['status']) for d in record['deferred']],
                         [('M1', 1, 'tests/M1_test.sh', 'deferred')])
        self.assertEqual(record['deferred'][0]['source']['registration'], 'northstar-plan-plan-m')
        self.assertEqual(record['deferred'][0]['recovery'], v2.DEFERRAL_RECOVERY)
        self.assertEqual(record['base'], _git(self.fixture.work, 'rev-parse', 'origin/main'))
        self.assertEqual(record['clock'], datetime.fromtimestamp(int(_git(self.fixture.work, 'show', '-s', '--format=%ct', 'origin/main')),
                                                                 timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'))
        self.assertEqual([row['script_readable'] for row in record['real_root_safety']], [False])
        self.assertEqual(record['fresh_eligibility']['fate']['fate'], 'unstarted')
        entry = result['published']
        prefix = self.fixture.work / entry['artifacts'][v2.MARKER]['path'].rsplit('/', 1)[0]
        self.assertEqual(sorted(p.name for p in prefix.iterdir()),
                         ['goals.json', 'graph.json', 'handoff.md', v2.MARKER_RECORD, 'sidecar.json'])
        self.assertEqual((prefix / v2.MARKER_RECORD).read_bytes(), _bytes(record))
        self.assertEqual(json.loads((prefix / 'goals.json').read_text())['attachments'][v2.MARKER], self.bundle['attachments'][v2.MARKER])
        # The deferral is a planning placeholder: no script was written anywhere in the tree.
        self.assertFalse((self.fixture.work / 'tests/M1_test.sh').exists())
        self.assertFalse(list(Path(tempfile.gettempdir()).glob('observer-view-*')), 'the validation view never survives')

    def test_an_ordinary_plan_keeps_both_missing_script_refusals(self) -> None:
        plain = copy.deepcopy(self.bundle)
        del plain['attachments'][v2.MARKER]
        self.refused(plain, 'verification_invalid')
        (self.fixture.work / 'tests/M1_test.sh').write_text('#!/bin/sh\nexit 0\n')
        self.before = _snapshot(self.fixture.work)
        self.refused(plain, 'verification_not_at_base')

    def test_forged_markers_refuse_before_any_write(self) -> None:
        def changed(change: Any) -> dict[str, Any]:
            bundle = copy.deepcopy(self.bundle)
            change(bundle)
            return bundle
        cases = [(lambda b: b['attachments'][v2.MARKER].update(registration='northstar-plan-plan-a'), 'migration_legacy_unregistered'),
                 (lambda b: b['attachments'][v2.MARKER].update(generation='e' * 64), 'bundle_field_invalid'),
                 (lambda b: b['attachments'][v2.MARKER].update(generation='e' * 64, legacy_bundle=dict(
                     b['attachments'][v2.MARKER]['legacy_bundle'], path='%s/plan-m/%s/goals.json' % (v2.V1_GEN, 'e' * 64))),
                  'migration_legacy_unregistered'),
                 (lambda b: b['attachments'][v2.MARKER]['legacy_bundle'].update(sha256='e' * 64), 'migration_legacy_unregistered'),
                 (lambda b: b['goals'][0].update(acceptance_criteria=['M1 works', 'and more']), 'migration_legacy_unsupported'),
                 (lambda b: b['goals'][0]['verification'].append('git diff --check'), 'migration_legacy_unsupported'),
                 (lambda b: b['attachments'].update(note='changed'), 'migration_legacy_unsupported'),
                 (lambda b: b['attachments'][v2.MARKER]['scripts'][0].update(verification_index=True), 'bundle_field_invalid'),
                 (lambda b: b['attachments'][v2.MARKER]['scripts'][0].update(verification_index=0), 'bundle_field_invalid'),
                 (lambda b: b['attachments'].update(nested={v2.MARKER: {}}), 'bundle_unknown_field'),
                 (lambda b: b['attachments'].__setitem__(v2.MARKER, True), 'bundle_field_invalid'),
                 (lambda b: b['attachments'].__setitem__(v2.MARKER, [b['attachments'][v2.MARKER]]), 'bundle_field_invalid')]
        for change, expected in cases:
            with self.subTest(expected=expected, change=changed(change)['attachments']):
                self.refused(changed(change), expected)

    def test_refusal_bytes_carry_the_code_only_and_never_a_path(self) -> None:
        bundle = copy.deepcopy(self.bundle)
        bundle['attachments'][v2.MARKER]['registration'] = 'northstar-plan-plan-a'
        result = self.refused(bundle, 'migration_legacy_unregistered')
        refusal = result[v2.MARKER]
        self.assertEqual(set(refusal), v2.MARKER_REFUSAL_FIELDS)
        self.assertEqual(refusal['refusals'], [{'code': 'migration_legacy_unregistered'}])
        self.assertEqual((refusal['authority'], refusal['readiness']), (v2.NO_AUTHORITY, 'unknown'))
        self.assertEqual(refusal['base'], _git(self.fixture.work, 'rev-parse', 'origin/main'))
        text = _bytes(refusal).decode()
        for leak in (str(self.base), 'Errno', 'Traceback', 'No such file', str(shutil.which('bash'))):
            self.assertNotIn(leak, text)
        self.assertEqual(stamps(_bytes(refusal)), {refusal['clock']})
        # Changing real-interpreter availability changes the sealed real-root safety: no bash on PATH refuses the
        # same way, with the code only and still no resolved path.
        gitonly = self.base / 'gitonly'
        gitonly.mkdir()
        (gitonly / 'git').symlink_to(str(shutil.which('git')))
        without = self.refused(self.bundle, 'verification_invalid', env={'PATH': str(gitonly)})
        self.assertEqual(without[v2.MARKER]['refusals'], [{'code': 'verification_invalid'}])
        self.assertNotIn(str(self.base), _bytes(without[v2.MARKER]).decode())

    def test_a_present_marker_is_validated_before_and_independently_of_any_missing_script(self) -> None:
        # Every selected script exists at the base and in the tree; a forged binding still refuses (AC-1).
        fixture = _fixture(_sub(self, 'present'))
        bundle, sidecar, _ = marked_plan(fixture, present=('M1',))
        before = _snapshot(fixture.work)
        forged = copy.deepcopy(bundle)
        forged['attachments'][v2.MARKER]['legacy_bundle']['sha256'] = 'e' * 64
        exit_code, result = _publish(fixture, forged, sidecar, adapter=_adapter(HOST_UNSTARTED))
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('migration_legacy_unregistered', _codes(result))
        self.assertEqual(_snapshot(fixture.work), before)
        # A valid marker over present scripts keeps the ordinary path: nothing is deferred, provenance is kept.
        exit_code, result = _publish(fixture, bundle, sidecar, adapter=_adapter(HOST_UNSTARTED))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result[v2.MARKER]['deferred'], [])
        self.assertEqual([row['script_readable'] for row in result[v2.MARKER]['real_root_safety']], [True])
        self.assertEqual(result['published']['artifacts'][v2.MARKER]['path'].rsplit('/', 1)[1], v2.MARKER_RECORD)

    def test_a_bare_publish_v2_cannot_rebuild_the_proof_and_refuses(self) -> None:
        inputs = Path(tempfile.mkdtemp(dir=self.base))
        exit_code, result = _run(['publish-v2', '--root', str(self.fixture.work), '--bundle',
                                  str(_write_json(inputs / 'b.json', self.bundle)), '--sidecar',
                                  str(_write_json(inputs / 's.json', self.sidecar))], now=NOW)
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertEqual([r['code'] for r in result['refusals']], ['target_ref_unobservable'])
        self.assertEqual(_snapshot(self.fixture.work), self.before)

    def test_fresh_eligibility_is_observed_at_publication_and_blocks_an_in_flight_legacy(self) -> None:
        head = _git(self.fixture.work, 'rev-parse', 'origin/main')
        in_flight = {'merged_prs': [], 'open_prs': [{'number': 9, 'headRefName': 'feat/plan-m-M1', 'headRefOid': head}], 'branches': []}
        result = self.refused(self.bundle, 'migration_fate_refused', adapter=_adapter(in_flight))
        self.assertEqual(result[v2.MARKER]['refusals'], [{'code': 'migration_fate_refused'}])
        unobservable = {'merged_prs': [{'number': n, 'headRefName': 'x%d' % n} for n in range(observer.ROUTE_LIMIT)],
                        'open_prs': [], 'branches': []}
        self.refused(self.bundle, 'migration_fate_refused', adapter=_adapter(unobservable))

    def test_a_partly_merged_legacy_publishes_only_its_unmerged_goals(self) -> None:
        fixture = _fixture(_sub(self, 'partly'))
        head = _git(fixture.work, 'rev-parse', 'origin/main')
        host = {'merged_prs': [{'number': 7, 'headRefName': 'feat/plan-p-P1', 'headRefOid': head, 'baseRefName': 'main',
                                'mergeCommit': {'oid': head}, 'mergedAt': '2026-10-01T00:00:00Z'}], 'open_prs': [], 'branches': []}
        bundle, sidecar, _ = marked_plan(fixture, plan_id='plan-p', goals=('P1', 'P2'), host=host)
        self.assertEqual([g['id'] for g in bundle['goals']], ['P2'])
        exit_code, result = _publish(fixture, bundle, sidecar, adapter=_adapter(host))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        record = result[v2.MARKER]
        self.assertEqual([d['goal'] for d in record['deferred']], ['P2'])
        self.assertEqual(record['fresh_eligibility']['fate']['fate'], 'partly-merged')
        self.assertEqual(v2.served_goals(record['fresh_eligibility']), ['P1'])
        # A forged observation whose served goal has no reached merge is not a derivation anyone can make.
        forged = copy.deepcopy(record['fresh_eligibility'])
        forged['merged'][0]['reached'] = False
        with self.assertRaises(Invalid) as raised:
            v2.served_goals(forged)
        self.assertEqual(_code(raised.exception), 'migration_b5_invalid')

    def test_the_decision_is_constructed_from_the_seal_alone(self) -> None:
        calls: list[Any] = []
        with spied('decide_marked_publication', calls):
            exit_code, result = self.publish_marked()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(len(calls), 1, 'the decision ran exactly once inside the spy')
        self.assertGreaterEqual(calls[0], 1, 'the single exit serializer ran inside the spy')
        # The same spy around observation trips: the seal is where the reads live, so a spy bound only at the
        # serializer would prove nothing.
        with spied('seal_marked_publication', calls):
            exit_code, result = self.publish_marked()
        self.assertEqual(exit_code, 1)
        self.assertIn('operation_failed', _codes(result))
        self.assertIn('performed an observation', result['refusals'][0]['detail'])

    def test_decision_and_refusal_bytes_are_identical_across_fresh_locations_paths_and_clocks(self) -> None:
        elsewhere = Path(tempfile.mkdtemp(prefix='elsewhere-')).resolve()
        self.addCleanup(shutil.rmtree, elsewhere, True)
        for name in ('origin.git', 'work'):
            shutil.copytree(self.base / name, elsewhere / name, symlinks=True)
        _git(elsewhere / 'work', 'remote', 'set-url', 'origin', str(elsewhere / 'origin.git'))
        twin = twin_of(self.fixture, elsewhere / 'work')
        reordered = os.pathsep.join(reversed(os.environ['PATH'].split(os.pathsep)))
        later = {'now': NOW + timedelta(days=3), 'env': {'PATH': reordered}}
        forged = copy.deepcopy(self.bundle)
        forged['attachments'][v2.MARKER]['legacy_bundle']['sha256'] = 'e' * 64
        exit_code, first = self.publish_marked()
        self.assertEqual(exit_code, 0, json.dumps(first, indent=1))
        exit_code, second = _publish(twin, self.bundle, self.sidecar, adapter=_adapter(HOST_UNSTARTED), **later)
        self.assertEqual(exit_code, 0, json.dumps(second, indent=1))
        self.assertEqual(_bytes(first[v2.MARKER]), _bytes(second[v2.MARKER]))
        prefix = first['published']['artifacts'][v2.MARKER]['path'].rsplit('/', 1)[0]
        for name in ('goals.json', 'sidecar.json', 'graph.json', 'handoff.md', v2.MARKER_RECORD):
            self.assertEqual(_sha(self.fixture.work / prefix / name), _sha(twin.work / prefix / name), name)
        exit_code, refused = self.publish_marked(forged)
        exit_code_twin, refused_twin = _publish(twin, forged, self.sidecar, adapter=_adapter(HOST_UNSTARTED), **later)
        self.assertEqual((exit_code, exit_code_twin), (1, 1))
        self.assertEqual(_bytes(refused[v2.MARKER]), _bytes(refused_twin[v2.MARKER]))
        text = _bytes(first[v2.MARKER]).decode() + _bytes(refused[v2.MARKER]).decode()
        for leak in (str(self.base), str(elsewhere), 'Errno', 'Traceback', str(shutil.which('bash'))):
            self.assertNotIn(leak, text)
        self.assertEqual(stamps(_bytes(first[v2.MARKER])), {first[v2.MARKER]['clock']})

    def test_the_idempotent_retry_and_the_linked_worktree_route_match_the_writer(self) -> None:
        exit_code, first = self.publish_marked()
        self.assertEqual(exit_code, 0, json.dumps(first, indent=1))
        exit_code, again = self.publish_marked()
        self.assertEqual((exit_code, again['published']), (0, first['published']), json.dumps(again, indent=1))
        self.assertEqual(_bytes(first[v2.MARKER]), _bytes(again[v2.MARKER]))
        linked = self.base / 'linked'
        _git(self.fixture.work, 'worktree', 'add', '-q', '--detach', str(linked), 'origin/main')
        self.assertTrue((linked / 'docs/plan-m-spec.md').is_file())
        twin = twin_of(self.fixture, linked)
        exit_code, third = _publish(twin, self.bundle, self.sidecar, adapter=_adapter(HOST_UNSTARTED))
        self.assertEqual(exit_code, 0, json.dumps(third, indent=1))
        self.assertEqual(_bytes(first[v2.MARKER]), _bytes(third[v2.MARKER]))
        self.assertEqual(third['published'], first['published'])
        prefix = first['published']['artifacts'][v2.MARKER]['path'].rsplit('/', 1)[0]
        for name in ('goals.json', 'sidecar.json', 'graph.json', 'handoff.md', v2.MARKER_RECORD):
            self.assertEqual(_sha(self.fixture.work / prefix / name), _sha(linked / prefix / name), name)

    def test_a_registered_marked_generation_loads_by_reconstruction_and_a_supplied_context_cannot_carry_the_name(self) -> None:
        exit_code, result = self.publish_marked()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.fixture.commit_push('publish the migrated plan-m generation')
        # Post-landing: the goal's own script lands on main; the proof stays a reconstruction from recorded bytes.
        (self.fixture.work / 'tests/M1_test.sh').write_text('#!/bin/sh\nexit 0\n')
        self.fixture.commit_push('feat: land the M1 script')
        exit_code, context = self.fixture.run(['admit-v2', '--root', str(self.fixture.work), '--handoff', 'northstar-plan-plan-m',
                                               '--goal-id', 'M1', '--stage', 'planning'], adapter=_adapter(HOST_UNSTARTED))
        self.assertEqual(exit_code, 1, 'planning is never admitted')
        self.assertFalse({'migration_legacy_unregistered', 'migration_legacy_unsupported', 'generation_artifact_mismatch',
                          'bundle_field_invalid', 'admission_failed'} & _codes(context), json.dumps(context['gaps'], indent=1))
        self.assertIn('approval_tag_missing', _codes(context))
        supplied = copy.deepcopy(context)
        supplied[v2.MARKER] = {'forged': True}
        path = _write_json(self.base / 'context.json', supplied)
        exit_code, again = self.fixture.run(['admit-v2', '--root', str(self.fixture.work), '--handoff', 'northstar-plan-plan-m',
                                             '--goal-id', 'M1', '--stage', 'planning', '--context', str(path)],
                                            adapter=_adapter(HOST_UNSTARTED))
        self.assertIn('supplied_context_mismatch', _codes(again))
        # A tampered record on main refuses the registered generation load for every route that loads it.
        record_path = self.fixture.work / result['published']['artifacts'][v2.MARKER]['path']
        tampered = json.loads(record_path.read_text())
        tampered['deferred'] = []
        _write_json(record_path, tampered)
        self.fixture.commit_push('tamper with the record')
        exit_code, context = self.fixture.run(['admit-v2', '--root', str(self.fixture.work), '--handoff', 'northstar-plan-plan-m',
                                               '--goal-id', 'M1', '--stage', 'planning'], adapter=_adapter(HOST_UNSTARTED))
        self.assertIn('generation_artifact_mismatch', _codes(context))

    def test_a_missing_cwd_is_a_sealed_fact_the_decision_refuses_on(self) -> None:
        work = self.fixture.work
        nested = v2.Selection('M1', 0, 1, 'sub/tests/M1_test.sh', 'sub', 'bash tests/M1_test.sh')
        row = observer.safety_row(work, nested)
        self.assertEqual((row['cwd_readable'], row['script_readable'], row['refusal_code']), (False, False, 'verification_invalid'))
        facts = observer.base_tree_facts(work, _git(work, 'rev-parse', 'origin/main'), [nested])
        self.assertEqual(facts, {'absent': {'sub/tests/M1_test.sh': True}, 'cwd_tree': {'sub': False}})
        (work / 'sub').mkdir()
        self.assertEqual(observer.safety_row(work, nested)['cwd_readable'], True, 'a cwd present at the root resolves')
        flat = v2.Selection('M1', 0, 1, 'tests/M1_test.sh', '.', 'bash tests/M1_test.sh')
        self.assertEqual(observer.safety_row(work, flat)['refusal_code'], 'verification_invalid', 'the missing leaf is what the validator sees')
        self.assertEqual(observer.safety_row(work, flat)['executable_available'], True)
        self.assertEqual(set(row), v2.SAFETY_FIELDS)

    def test_the_writer_reports_each_deferred_leaf_once_on_stderr(self) -> None:
        exit_code, result = self.publish_marked()
        self.assertEqual(exit_code, 0)
        with mock.patch.object(observer, 'run', lambda argv: (0, result)), contextlib.redirect_stdout(io.StringIO()):
            with mock.patch('sys.stderr', new_callable=io.StringIO) as err:
                _main(['publish-v2'])
        lines = [line for line in err.getvalue().splitlines() if line.startswith('deferred own-script')]
        self.assertEqual(lines, ['deferred own-script M1 verification[1] tests/M1_test.sh (no authority; readiness unknown)'])


if __name__ == '__main__':
    unittest.main()
