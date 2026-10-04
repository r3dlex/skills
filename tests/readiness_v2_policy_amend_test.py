"""Policy amendment (O9 amendment kind, K3 rule (d), K3b): a one-goal policy-amendment
generation carries a candidate bound by one new approval verified under the candidate's
anchor; its merge voids every other approval, and re-signing the same generation
recovers. Ephemeral keys, temporary anchors and disposable repositories only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import base64
import copy
import json
import os
import subprocess
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

import readiness_v2_core_test as core
from readiness_v2_core_test import (AUTO, NOW, POLICY, REGISTRY, Fixture, codes, git, sample_bundle, sample_sidecar, sha,
                                    ssh_sign, stamp, v2, observer, write_json)
from readiness_v2_certificate_test import gh_shim
from readiness_v2_approval_modes_test import ALL_FORMS, make_key, moded, public

AMEND = 'plan-amend'


def amendment_bundle(goal_id='PA'):
    bundle = sample_bundle([{'id': goal_id, 'scope': [POLICY], 'acceptance_criteria': ['the amended policy lands'],
                             'dependencies': [], 'verification': ['bash tests/check.sh']}])
    bundle['id'] = AMEND
    return bundle


def plan_bundle(plan_id):
    bundle = sample_bundle()
    bundle['id'] = plan_id
    return bundle


class Repository:
    """A Fixture (plan-a, live policy/2) plus helpers for further plans in the same repository."""

    def __init__(self, base, accept=('ssh-tag', 'in-session'), default_mode=None, extra_anchor=''):
        self.base = base
        keys = Path(tempfile.mkdtemp(prefix='more-keys-', dir=base))
        self.agent_key = make_key(keys, 'agentself')
        prefix = 'agentself@agent namespaces="%s" %s\n' % (v2.NS_AGENT_APPROVAL, public(self.agent_key)) + extra_anchor
        with mock.patch.object(core, 'sample_policy', moded(default_mode)):
            self.fixture = Fixture(base, accept=accept, anchor_prefix=prefix)
        self.fixture.keys.paths['agentself'] = self.agent_key
        self.work = self.fixture.work
        self.inputs = self.fixture.inputs
        self.anchor = self.fixture.keys.anchor

    def run(self, argv, anchor=None, key='certifier', adapter=None, env=None):
        return self.fixture.run(argv, anchor=anchor, key=key, adapter=adapter, env=env)

    def publish(self, bundle, candidate=None, message=None):
        bundle_path = write_json(self.inputs / (bundle['id'] + '-bundle.json'), bundle)
        sidecar_path = write_json(self.inputs / (bundle['id'] + '-sidecar.json'), sample_sidecar(bundle))
        argv = ['publish-v2', '--root', str(self.work), '--bundle', str(bundle_path), '--sidecar', str(sidecar_path)]
        if candidate is not None:
            argv += ['--policy-candidate', str(write_json(self.inputs / (bundle['id'] + '-candidate.json'), candidate))]
        exit_code, result = observer.run(argv, now=NOW)
        if exit_code == 0:
            self.fixture.commit_push(message or 'publish ' + bundle['id'])
        return exit_code, result

    def approve(self, plan_id, form, key='approver', anchor=None, signing_key='agentself'):
        """Request the approval through the driver, then create the single tag as the approver would."""
        argv = ['approval-request', '--root', str(self.work), '--handoff', 'northstar-plan-' + plan_id, '--owner',
                'Fixture Owner', '--reviewer-lane', 'independent review lane', '--days', '7']
        if form == 'agent-self':
            exit_code, request = self.run(argv + ['--assurance', 'agent-self'], anchor=anchor, key=signing_key)
            if exit_code:
                return exit_code, request
            message = request['message']
        else:
            exit_code, request = self.run(argv, anchor=anchor)
            if exit_code:
                return exit_code, request
            if form == 'ssh-tag':
                line = json.dumps(request['record'], sort_keys=True, separators=(',', ':'))
                signature = ssh_sign(self.fixture.keys.paths.get(key) or key, v2.NS_APPROVAL, line.encode(), self.base)
                message = line + '\nsignature: ' + base64.b64encode(signature.encode()).decode() + '\n'
            else:
                line = json.dumps(request['fallback']['record'], sort_keys=True, separators=(',', ':'))
                message = line + '\ndigest-echo: ' + request['fallback']['digest'] + '\n'
        self.tag(plan_id, request['publication_commit'] if 'publication_commit' in request else None, message,
                 request['tag'])
        return 0, request

    def tag(self, plan_id, publication, message, tag):
        if publication is None:
            entry = self.entry(plan_id)
            publication = git(self.work, 'log', '-1', '--format=%H', 'origin/main', '--',
                              '.ai/handoff/readiness-v2/%s/%s' % (plan_id, entry['generation']))
        path = self.inputs / (plan_id + '-approval.msg')
        path.write_text(message)
        git(self.work, 'tag', '-f', '-a', '--cleanup=verbatim', '-F', str(path), tag, publication)
        git(self.work, 'push', '-q', '-f', 'origin', 'refs/tags/' + tag)

    def entry(self, plan_id):
        registry = json.loads((self.work / REGISTRY).read_text())
        return next(p for p in registry['plans'] if p['plan_id'] == plan_id)

    def admit(self, plan_id, goal, stage='implementation', anchor=None, adapter=None):
        return self.run(['admit-v2', '--root', str(self.work), '--handoff', 'northstar-plan-' + plan_id, '--goal-id', goal,
                         '--stage', stage], anchor=anchor, adapter=adapter)

    def land(self, policy_bytes, message='merge the policy amendment'):
        git(self.work, 'checkout', '-q', 'main')
        (self.work / POLICY).write_bytes(policy_bytes)
        self.fixture.commit_push(message)

    def live(self):
        return json.loads((self.work / POLICY).read_text())


def anchor_file(base, name, text):
    path = Path(tempfile.mkdtemp(prefix=name + '-', dir=base)) / 'allowed_signers'
    path.write_text(text)
    return path, sha(path)


class AmendmentKindTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.repo = Repository(self.base)
        self.repo.approve('plan-a', 'in-session')
        self.assertEqual(self.repo.publish(plan_bundle('plan-b'))[0], 0)
        self.repo.approve('plan-b', 'in-session')
        for plan in ('plan-a', 'plan-b'):
            self.assertEqual(self.repo.admit(plan, 'G1')[0], 0)

    def amend(self, candidate, form='in-session', key='approver', anchor=None):
        exit_code, result = self.repo.publish(amendment_bundle(), candidate=candidate)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['published']['mode'], 'policy-amendment')
        exit_code, request = self.repo.approve(AMEND, form, key=key, anchor=anchor)
        self.assertEqual(exit_code, 0, json.dumps(request, indent=1))
        return result['published']

    def admitted(self, plan, goal, anchor=None):
        exit_code, context = self.repo.admit(plan, goal, anchor=anchor)
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        return context

    def voided_then_recovered(self, anchor=None, key='approver'):
        """Every other approval is voided on merge; re-signing the same generation restores admission."""
        for plan in ('plan-a', 'plan-b'):
            generation = self.repo.entry(plan)['generation']
            exit_code, context = self.repo.admit(plan, 'G1', anchor=anchor)
            self.assertNotEqual(exit_code, 0, plan)
            self.assertIn('approval_policy_mismatch', codes(context), json.dumps(context['gaps'], indent=1))
            self.assertEqual(self.repo.approve(plan, 'ssh-tag', key=key, anchor=anchor)[0], 0)
            context = self.admitted(plan, 'G1', anchor=anchor)
            self.assertEqual(context['generation'], generation)
            self.assertEqual(self.repo.entry(plan)['generation'], generation)

    def test_renamed_required_check(self):
        candidate = self.repo.live()
        candidate['required_checks'] = ['Unit Tests']
        self.amend(candidate)
        context = self.admitted(AMEND, 'PA')
        self.assertEqual(context['policy']['mode'], 'policy-amendment')
        self.assertEqual(context['policy']['sha256'], sha(json.dumps(candidate, indent=2, sort_keys=True).encode() + b'\n'))
        self.assertEqual(context['assurance'], 'in-session')
        self.repo.land((self.repo.inputs / (AMEND + '-candidate.json')).read_bytes())
        self.voided_then_recovered()

    def test_new_agent_principal_is_verified_under_the_candidate_anchor(self):
        newcomer = make_key(self.base, 'newagent')
        text = self.repo.anchor.read_text() + 'newagent@agent namespaces="%s,%s" %s\n' % (
            v2.NS_REVIEW, v2.NS_CERTIFICATE, public(newcomer))
        rotated, digest = anchor_file(self.base, 'new-agent', text)
        candidate = self.repo.live()
        candidate['approval']['anchor_sha256'] = digest
        self.amend(candidate, form='ssh-tag', anchor=rotated)
        self.assertIn('anchor_digest_mismatch', codes(self.repo.admit(AMEND, 'PA')[1]))
        self.admitted(AMEND, 'PA', anchor=rotated)
        self.repo.land((self.repo.inputs / (AMEND + '-candidate.json')).read_bytes())
        self.voided_then_recovered(anchor=rotated)

    def test_key_and_anchor_rotation(self):
        replacement = make_key(self.base, 'approver2')
        text = ''.join(line + '\n' for line in self.repo.anchor.read_text().splitlines() if not line.startswith('approver@'))
        text += 'approver2@human namespaces="%s" %s\n' % (v2.NS_APPROVAL, public(replacement))
        rotated, digest = anchor_file(self.base, 'rotated', text)
        candidate = self.repo.live()
        candidate['approval']['anchor_sha256'] = digest
        self.amend(candidate, form='ssh-tag', key=str(self.repo.fixture.keys.paths['approver']), anchor=rotated)
        self.assertIn('approval_signature_invalid', codes(self.repo.admit(AMEND, 'PA', anchor=rotated)[1]))
        self.assertEqual(self.repo.approve(AMEND, 'ssh-tag', key=str(replacement), anchor=rotated)[0], 0)
        self.admitted(AMEND, 'PA', anchor=rotated)
        self.repo.land((self.repo.inputs / (AMEND + '-candidate.json')).read_bytes())
        self.voided_then_recovered(anchor=rotated, key=str(replacement))

    def test_publication_shapes(self):
        candidate = self.repo.live()
        candidate['required_checks'] = ['Unit Tests']
        two = amendment_bundle()
        two['goals'].append({'id': 'G2', 'scope': ['src/app.txt'], 'acceptance_criteria': ['x'], 'dependencies': ['PA'],
                             'verification': ['bash tests/check.sh']})
        exit_code, result = self.repo.publish(two, candidate=candidate)
        self.assertNotEqual(exit_code, 0)
        self.assertIn('bootstrap_policy_live', codes(result))
        other = sample_bundle([{'id': 'X', 'scope': ['src/app.txt'], 'acceptance_criteria': ['x'], 'dependencies': [],
                                'verification': ['bash tests/check.sh']}])
        other['id'] = 'plan-x'
        self.assertIn('bootstrap_policy_live', codes(self.repo.publish(other, candidate=candidate)[1]))
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_amendment(amendment_bundle(), live_policy2=False)
        self.assertEqual(v2.code(raised.exception), 'amendment_requires_live_policy')
        self.assertEqual(v2.validate_amendment(amendment_bundle(), live_policy2=True), 'PA')


class RuleDTests(unittest.TestCase):
    """K3 rule (d): an amendment or bootstrap approval form must be in both accept lists."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def repository(self, name, accept, default_mode=None):
        base = self.base / name
        base.mkdir()
        return Repository(base, accept=accept, default_mode=default_mode)

    def amendment(self, repo, candidate_accept, default_mode=None, form='in-session'):
        candidate = repo.live()
        candidate['required_checks'] = ['Unit Tests']
        candidate['approval']['accept'] = list(candidate_accept)
        candidate['approval'].pop('default_mode', None)
        if default_mode:
            candidate['approval']['default_mode'] = default_mode
        exit_code, result = repo.publish(amendment_bundle(), candidate=candidate)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        return candidate

    def refused(self, repo, expected):
        exit_code, context = repo.admit(AMEND, 'PA')
        self.assertNotEqual(exit_code, 0)
        self.assertIn(expected, codes(context), json.dumps(context['gaps'], indent=1))
        return context

    def test_a_form_accepted_only_by_the_live_policy_is_refused(self):
        repo = self.repository('live-only', ('ssh-tag', 'in-session'))
        self.amendment(repo, ('ssh-tag',))
        repo.approve(AMEND, 'in-session')
        self.refused(repo, 'approval_form_not_accepted')
        repo.approve(AMEND, 'ssh-tag')
        self.assertEqual(repo.admit(AMEND, 'PA')[0], 0)

    def test_a_form_accepted_only_by_the_candidate_is_refused(self):
        repo = self.repository('candidate-only', ('ssh-tag',))
        self.amendment(repo, ('ssh-tag', 'in-session'))
        repo.approve(AMEND, 'in-session')
        self.refused(repo, 'approval_form_not_in_live_policy')
        repo.approve(AMEND, 'ssh-tag')
        self.assertEqual(repo.admit(AMEND, 'PA')[0], 0)

    def test_the_post_s06_amendment_to_agent_mode_needs_a_human_form(self):
        repo = self.repository('to-agent', ('ssh-tag', 'in-session'))
        self.amendment(repo, ALL_FORMS, default_mode='agent')
        self.assertIn('approval_form_not_in_live_policy', codes(repo.approve(AMEND, 'agent-self')[1]))
        message = agent_line(repo, AMEND)
        repo.tag(AMEND, None, message, 'approval/%s/%s' % (AMEND, repo.entry(AMEND)['generation'][:12]))
        self.refused(repo, 'approval_form_not_in_live_policy')
        repo.approve(AMEND, 'in-session')
        self.assertEqual(repo.admit(AMEND, 'PA')[0], 0)

    def test_agent_self_bootstrap_approval_is_refused(self):
        base = self.base / 'bootstrap'
        base.mkdir()
        keys = Path(tempfile.mkdtemp(prefix='agent-', dir=base))
        agent = make_key(keys, 'agentself')
        goals = [{'id': 'P', 'scope': [POLICY], 'acceptance_criteria': ['policy lands'], 'dependencies': [],
                  'verification': ['bash tests/check.sh']},
                 {'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['works'], 'dependencies': ['P'],
                  'verification': ['bash tests/check.sh']}]
        with mock.patch.object(core, 'sample_policy', moded('agent')):
            fixture = Fixture(base, bundle=sample_bundle(goals), candidate=True, live_policy=False, accept=ALL_FORMS,
                              anchor_prefix='agentself@agent namespaces="%s" %s\n' % (v2.NS_AGENT_APPROVAL, public(agent)))
        fixture.keys.paths['agentself'] = agent
        exit_code, request = fixture.run(['approval-request', '--root', str(fixture.work), '--handoff',
                                          'northstar-plan-plan-a', '--owner', 'O', '--reviewer-lane', 'independent review lane',
                                          '--assurance', 'agent-self'], key='agentself')
        self.assertNotEqual(exit_code, 0)
        self.assertIn('agent_self_bootstrap_refused', codes(request))
        record = fixture.record(assurance='agent-self')
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        signature = ssh_sign(agent, v2.NS_AGENT_APPROVAL, line.encode(), base)
        fixture.approve('agent-self', message=line + '\nagent-signature: ' + base64.b64encode(signature.encode()).decode() + '\n')
        exit_code, context = fixture.admit(goal='P')
        self.assertNotEqual(exit_code, 0)
        self.assertIn('agent_self_bootstrap_refused', codes(context), json.dumps(context['gaps'], indent=1))
        fixture.approve('in-session')
        self.assertEqual(fixture.admit(goal='P')[0], 0)


def agent_line(repo, plan_id):
    """A well-formed agent-signed approval for plan_id, built without the driver's guard."""
    exit_code, request = repo.run(['approval-request', '--root', str(repo.work), '--handoff', 'northstar-plan-' + plan_id,
                                   '--owner', 'Fixture Owner', '--reviewer-lane', 'independent review lane', '--days', '7'])
    assert exit_code == 0, request
    record = dict(request['record'], assurance='agent-self')
    line = json.dumps(record, sort_keys=True, separators=(',', ':'))
    signature = ssh_sign(repo.agent_key, v2.NS_AGENT_APPROVAL, line.encode(), repo.base)
    return line + '\nagent-signature: ' + base64.b64encode(signature.encode()).decode() + '\n'


class AgentSelfPolicyChangeTests(unittest.TestCase):
    """K3b: agent-self approves an amendment only when both accept lists hold agent-self;
    every such approval emits agent_self_policy_change and the merge bar is unchanged."""

    def test_agent_self_amendment_is_recorded_reported_and_audited(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            repo = Repository(base, accept=ALL_FORMS, default_mode='agent')
            candidate = repo.live()
            candidate['required_checks'] = ['Unit Tests']
            exit_code, result = repo.publish(amendment_bundle(), candidate=candidate)
            self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
            self.assertEqual(repo.approve(AMEND, 'agent-self')[0], 0)
            exit_code, context = repo.admit(AMEND, 'PA')
            self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
            self.assertEqual(context['assurance'], 'agent-self')
            self.assertIn('agent_self_policy_change', {n['code'] for n in context['notices']})
            self.assertIn('ASSURANCE: AGENT-SELF', context['assurance_notice'])
            # A candidate that drops agent-self cannot be approved by agent-self.
            narrowed = copy.deepcopy(candidate)
            narrowed['approval']['accept'] = ['ssh-tag', 'in-session']
            narrowed['approval']['default_mode'] = 'prompt'
            narrow_bundle = amendment_bundle('PB')
            narrow_bundle['id'] = 'plan-narrow'
            exit_code, _ = repo.publish(narrow_bundle, candidate=narrowed)
            self.assertEqual(exit_code, 0)
            message = agent_line(repo, 'plan-narrow')
            repo.tag('plan-narrow', None, message, 'approval/plan-narrow/' + repo.entry('plan-narrow')['generation'][:12])
            self.assertIn('agent_self_not_accepted', codes(repo.admit('plan-narrow', 'PB')[1]))
            # Merge reports and audit-merges: certify and merge the amendment goal at one exact head.
            work = repo.work
            branch = 'feat/%s-PA' % AMEND
            git(work, 'checkout', '-q', '-b', branch)
            (work / 'tests/flip.sh').write_text('#!/bin/sh\ntest -f src/amended.txt\n')
            (work / 'tests/flip.sh').chmod(0o755)
            evidence = AUTO / 'tdd-evidence.sh'
            subprocess.run(['bash', str(evidence), '--record-red', '--goal', 'PA', '--root', str(work), '--command',
                            'sh tests/flip.sh'], check=True, capture_output=True)
            (work / 'src/amended.txt').write_text('amended\n')
            (work / POLICY).write_bytes((repo.inputs / (AMEND + '-candidate.json')).read_bytes())
            subprocess.run(['bash', str(evidence), '--record-green', '--goal', 'PA', '--root', str(work), '--command',
                            'sh tests/flip.sh'], check=True, capture_output=True)
            head = repo.fixture.commit_push('feat: amend the policy', branch=branch)
            main = git(work, 'rev-parse', 'origin/main')
            state_path, log_path = base / 'gh-state.json', base / 'gh-log.jsonl'
            shim = gh_shim(base / 'bin', state_path, log_path)
            ok = {'name': 'Unit Tests', 'status': 'completed', 'conclusion': 'success',
                  'completed_at': stamp(NOW - timedelta(minutes=20))}
            write_json(state_path, {'pulls': {'12': {'head': {'sha': head, 'ref': branch}, 'base': {'sha': main, 'ref': 'main'}}},
                                    'checks': {head: [ok]}, 'threads': {'12': []}, 'protection': None, 'merged_prs': []})
            record = {'schema': 'review-lane/1', 'plan_id': AMEND, 'goal_id': 'PA', 'pr': 12, 'head': head,
                      'verdict': 'approve', 'lane': 'independent review lane', 'issued_at': stamp(NOW - timedelta(minutes=10))}
            review = base / 'review.json'
            review.write_text(json.dumps(record, sort_keys=True, separators=(',', ':')))
            Path(str(review) + '.sig').write_text(ssh_sign(repo.fixture.keys.paths['reviewer'], v2.NS_REVIEW,
                                                           review.read_bytes(), base))
            env = {'PATH': str(shim.parent) + os.pathsep + os.environ['PATH']}
            exit_code, issued = repo.run(['certify-v2', '--root', str(work), '--handoff', 'northstar-plan-' + AMEND,
                                          '--goal-id', 'PA', '--pr', '12', '--review-record', str(review)], env=env)
            self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
            self.assertEqual(issued['certificate']['assurance'], 'agent-self')
            self.assertIn('agent_self_policy_change', {n['code'] for n in issued['notices']})
            cwd = os.getcwd()
            os.chdir(work)
            try:
                exit_code, merged = repo.run(['merge-v2', '--pr', '12', '--admin'], env=env)
            finally:
                os.chdir(cwd)
            self.assertEqual(exit_code, 0, json.dumps(merged, indent=1))
            self.assertEqual(merged['assurance'], 'agent-self')
            self.assertIn('agent_self_policy_change', {n['code'] for n in merged['notices']})
            state = json.loads(state_path.read_text())
            state['merged_prs'] = [{'number': 12, 'headRefName': branch, 'headRefOid': head, 'mergeCommit': {'oid': 'c' * 40},
                                    'mergedAt': stamp(NOW)}]
            write_json(state_path, state)
            exit_code, audit = repo.run(['audit-merges', '--root', str(work), '--handoff', 'northstar-plan-' + AMEND], env=env)
            self.assertEqual(exit_code, 0, json.dumps(audit, indent=1))
            self.assertEqual(audit['prs'][0]['assurance'], 'agent-self')
            self.assertIn('agent_self_policy_change', {n['code'] for n in audit['notices']})
            self.assertNotIn('in-session', json.dumps(audit))


class ReviewRoundOneAmendmentTests(unittest.TestCase):
    """PR #102 review round 1: rule (d) against the live policy's whole form rule, concurrent
    amendments, and amendments that would move the branch namespace."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def repository(self, name, **kwargs):
        base = self.base / name
        base.mkdir()
        return Repository(base, **kwargs)

    def amendment(self, repo, change, plan_id=AMEND, goal='PA'):
        candidate = repo.live()
        change(candidate)
        bundle = amendment_bundle(goal)
        bundle['id'] = plan_id
        exit_code, result = repo.publish(bundle, candidate=candidate)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        return result['published']

    def test_prompt_mode_live_policy_refuses_an_agent_self_amendment_to_agent_mode(self):
        # The reviewers' configuration (prompt mode listing agent-self) is no longer a valid policy.
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_policy(dict(core.sample_policy('a' * 64), approval={
                'anchor_sha256': 'a' * 64, 'max_age_days': 14, 'accept': list(ALL_FORMS), 'default_mode': 'prompt'}))
        self.assertEqual(v2.code(raised.exception), 'policy_default_mode_inconsistent')
        repo = self.repository('prompt', accept=('in-session', 'ssh-tag'), default_mode='prompt')

        def to_agent(candidate):
            candidate['approval'].update(accept=list(ALL_FORMS), default_mode='agent')
            candidate['required_checks'] = ['Optional Smoke']
        self.amendment(repo, to_agent)
        exit_code, request = repo.approve(AMEND, 'agent-self')
        self.assertNotEqual(exit_code, 0)
        self.assertIn('approval_form_not_in_live_policy', codes(request))
        message = agent_line(repo, AMEND)
        repo.tag(AMEND, None, message, 'approval/%s/%s' % (AMEND, repo.entry(AMEND)['generation'][:12]))
        exit_code, context = repo.admit(AMEND, 'PA')
        self.assertNotEqual(exit_code, 0)
        self.assertIn('approval_form_not_in_live_policy', codes(context))
        # ssh-tag is in both accept lists but the live prompt mode admits only in-session.
        repo.approve(AMEND, 'ssh-tag')
        self.assertIn('approval_form_refused_by_mode', codes(repo.admit(AMEND, 'PA')[1]))
        repo.approve(AMEND, 'in-session')
        self.assertEqual(repo.admit(AMEND, 'PA')[0], 0)
        # Defense in depth: the live policy's mode rule applies even to an unvalidated live policy.
        with self.assertRaises(v2.Invalid) as raised:
            v2.check_form('agent-self', {'approval': {'accept': list(ALL_FORMS), 'default_mode': 'agent'}}, 'policy-amendment',
                          {'approval': {'accept': list(ALL_FORMS), 'default_mode': 'prompt'}})
        self.assertEqual(v2.code(raised.exception), 'agent_self_refused_by_mode')

    def test_a_concurrent_amendment_is_refused_once_another_lands(self):
        repo = self.repository('concurrent')
        live_sha = sha(repo.work / POLICY)
        loose = self.amendment(repo, lambda c: c.update(required_checks=['Optional Smoke']), plan_id='amend-loose', goal='PL')
        self.assertEqual(loose['amends_policy_sha256'], live_sha)
        self.amendment(repo, lambda c: c.update(required_checks=['Test Suite', 'Security Scan']), plan_id='amend-tight', goal='PT')
        for plan_id, goal in (('amend-loose', 'PL'), ('amend-tight', 'PT')):
            self.assertEqual(repo.approve(plan_id, 'ssh-tag')[0], 0)
            self.assertEqual(repo.admit(plan_id, goal)[0], 0)
        repo.land((repo.inputs / 'amend-tight-candidate.json').read_bytes(), 'merge the tightening amendment')
        exit_code, context = repo.admit('amend-loose', 'PL')
        self.assertNotEqual(exit_code, 0)
        self.assertIn('amendment_base_moved', codes(context))
        self.assertNotIn('amendment_base_moved', codes(repo.admit('amend-tight', 'PT')[1]))
        # The amends digest is part of the generation identity, so the approval binds it.
        entry = repo.entry('amend-loose')
        bundle = json.loads((repo.work / entry['artifacts']['bundle']['path']).read_text())
        digests = dict(bundle_sha256=v2.bundle_sha256(bundle), spec_sha256=entry['spec']['sha256'],
                       policy_sha256=entry['policy_sha256'], anchor_sha256=entry['anchor_sha256'])
        self.assertNotEqual(v2.generation_v2(**digests), entry['generation'])
        self.assertEqual(v2.generation_v2(amends_policy_sha256=live_sha, **digests), entry['generation'])

    def test_the_candidates_own_mode_never_governs_its_approval(self):
        repo = self.repository('ssh-to-prompt', accept=('ssh-tag', 'in-session'), default_mode='ssh-tag')

        def to_prompt(candidate):
            candidate['approval'].update(accept=['in-session', 'ssh-tag'], default_mode='prompt')
        self.amendment(repo, to_prompt)
        repo.approve(AMEND, 'ssh-tag')
        exit_code, context = repo.admit(AMEND, 'PA')
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        self.assertEqual(context['assurance'], 'key-held')
        repo.approve(AMEND, 'in-session')  # in both accept lists, but the live ssh-tag mode admits only ssh-tag
        self.assertIn('approval_form_refused_by_mode', codes(repo.admit(AMEND, 'PA')[1]))

    def test_an_amendment_may_not_move_the_branch_namespace(self):
        repo = self.repository('pattern')
        candidate = repo.live()
        candidate['branch_pattern'] = '^goal/<plan_id>/<goal_id>$'
        exit_code, result = repo.publish(amendment_bundle(), candidate=candidate)
        self.assertNotEqual(exit_code, 0)
        self.assertIn('branch_pattern_change_refused', codes(result))
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_amendment(amendment_bundle(), True, candidate, repo.live())
        self.assertEqual(v2.code(raised.exception), 'branch_pattern_change_refused')


if __name__ == '__main__':
    unittest.main()
