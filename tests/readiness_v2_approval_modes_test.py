"""Approval modes (K3, K1, K2, U1 as amended by K3): agent, prompt and ssh-tag mode,
the agent-self form and assurance, and the rule that no code path renders agent-self
as another assurance level or another level as agent-self. Ephemeral keys, a
temporary anchor and disposable repositories only."""
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
from readiness_v2_core_test import (AUTO, NOW, REPO, Fixture, codes, git, sample_policy, sha, ssh_sign, stamp, v2,
                                    observer, write_json)
from readiness_v2_certificate_test import BRANCH, PR, CertificateFixture

ALL_FORMS = ('agent-self', 'ssh-tag', 'in-session')
LEVELS = ('user-presence', 'key-held', 'in-session', 'agent-self')


def make_key(directory, name):
    path = Path(directory) / name
    subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', name, '-f', str(path)], check=True,
                   capture_output=True)
    return path


def public(path):
    return ' '.join(Path(str(path) + '.pub').read_text().split()[:2])


def moded(default_mode):
    """sample_policy with an approval.default_mode (None keeps the field absent)."""
    def build(anchor_sha256, identity_model='single', accept=('ssh-tag', 'in-session')):
        policy = sample_policy(anchor_sha256, identity_model, accept)
        if default_mode is not None:
            policy['approval']['default_mode'] = default_mode
        return policy
    return build


def mode_fixture(base, default_mode, accept, **kwargs):
    """A published generation whose policy declares default_mode, with an agent-approval
    principal (agentself@agent) and a principal that wrongly holds both roles (mixed@agent)."""
    keys = Path(tempfile.mkdtemp(prefix='agent-keys-', dir=base))
    agent, mixed = make_key(keys, 'agentself'), make_key(keys, 'mixed')
    prefix = ('agentself@agent namespaces="%s" %s\n' % (v2.NS_AGENT_APPROVAL, public(agent)) +
              'mixed@agent namespaces="%s,%s" %s\n' % (v2.NS_AGENT_APPROVAL, v2.NS_APPROVAL, public(mixed)))
    with mock.patch.object(core, 'sample_policy', moded(default_mode)):
        fixture = Fixture(base, accept=accept, anchor_prefix=prefix, **kwargs)
    fixture.keys.paths.update(agentself=agent, mixed=mixed)
    return fixture


def agent_message(fixture, key, record=None, namespace=None, line_name='agent-signature'):
    record = record or fixture.record(assurance='agent-self')
    line = json.dumps(record, sort_keys=True, separators=(',', ':'))
    signature = ssh_sign(fixture.keys.paths[key], namespace or v2.NS_AGENT_APPROVAL, line.encode(), fixture.base)
    return line + '\n%s: %s\n' % (line_name, base64.b64encode(signature.encode()).decode())


def issue(fixture, key='agentself', extra=()):
    """Autobahn issues the agent-mode approval itself; the tag carries the printed message."""
    exit_code, request = fixture.run(['approval-request', '--root', str(fixture.work), '--handoff', 'northstar-plan-plan-a',
                                      '--owner', 'Fixture Owner', '--reviewer-lane', 'independent review lane',
                                      '--assurance', 'agent-self', *extra], key=key)
    if exit_code == 0:
        fixture.approve('agent-self', message=request['message'])
    return exit_code, request


class AgentSelfFormTests(unittest.TestCase):
    """U1 as amended by K3: the agent-approval namespace, the carrier and the distinct refusals."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.fixture = mode_fixture(self.base, 'agent', ALL_FORMS)

    def refused(self, expected, fixture=None):
        exit_code, context = (fixture or self.fixture).admit()
        self.assertNotEqual(exit_code, 0, json.dumps(context, indent=1))
        self.assertIn(expected, codes(context), json.dumps(context['gaps'], indent=1))
        return context

    def test_agent_mode_issues_a_signed_agent_self_approval_on_the_single_tag(self):
        exit_code, request = issue(self.fixture)
        self.assertEqual(exit_code, 0, json.dumps(request, indent=1))
        self.assertTrue(request['signs'])
        self.assertEqual(request['assurance'], 'agent-self')
        self.assertEqual(request['record']['assurance'], 'agent-self')
        self.assertEqual(request['tag'], 'approval/plan-a/' + self.fixture.generation[:12])
        line, carrier = request['message'].rstrip('\n').split('\n')
        self.assertEqual(line, json.dumps(request['record'], sort_keys=True, separators=(',', ':')))
        self.assertTrue(carrier.startswith('agent-signature: '))
        signature = self.base / 'agent.sig'
        signature.write_bytes(base64.b64decode(carrier[len('agent-signature: '):]))
        verify = lambda namespace: subprocess.run(
            ['ssh-keygen', '-Y', 'verify', '-f', str(self.fixture.keys.anchor), '-I', 'agentself@agent', '-n', namespace,
             '-s', str(signature)], input=line.encode(), capture_output=True).returncode
        self.assertEqual(verify(v2.NS_AGENT_APPROVAL), 0)
        self.assertNotEqual(verify(v2.NS_APPROVAL), 0)
        self.assertIn('AGENT-SELF', request['notice'])
        tags = git(self.fixture.work, 'ls-remote', '--tags', 'origin', 'refs/tags/approval/*').splitlines()
        self.assertEqual(len(tags), 1)
        exit_code, context = self.fixture.admit()
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        self.assertEqual(context['assurance'], 'agent-self')
        self.assertEqual(context['approval']['form'], 'agent-self')
        self.assertEqual(context['approval']['principal'], 'agentself@agent')
        self.assertIn('ASSURANCE: AGENT-SELF', context['assurance_notice'])

    def test_agent_signer_must_hold_only_the_agent_approval_role(self):
        self.fixture.approve('agent-self', message=agent_message(self.fixture, 'certifier'))
        self.refused('agent_approval_signer_not_agent')
        self.fixture.approve('agent-self', message=agent_message(self.fixture, 'mixed'))
        self.refused('agent_approval_signer_not_agent')
        self.assertEqual(issue(self.fixture, key='certifier')[0], 1)
        self.assertIn('agent_approval_signer_not_agent', codes(issue(self.fixture, key='mixed')[1]))

    def test_human_namespace_or_digest_echo_claiming_agent_self_is_refused(self):
        record = self.fixture.record(assurance='agent-self')
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        self.fixture.approve('ssh-tag', message=agent_message(self.fixture, 'approver', record, v2.NS_APPROVAL, 'signature'))
        self.refused('agent_self_claim_without_agent_signature')
        self.fixture.approve('in-session', message=line + '\ndigest-echo: ' + sha(line.encode()) + '\n')
        self.refused('agent_self_claim_without_agent_signature')
        self.fixture.approve('agent-self', message=agent_message(self.fixture, 'approver', record, v2.NS_APPROVAL))
        self.refused('agent_self_claim_without_agent_signature')
        # An agent-signed record claiming another level is never relabelled.
        self.fixture.approve('agent-self', message=agent_message(self.fixture, 'agentself',
                                                                 self.fixture.record(assurance='in-session')))
        self.refused('approval_assurance_mismatch')

    def test_agent_self_record_is_refused_when_accept_omits_agent_self(self):
        base = self.base / 'narrow'
        base.mkdir()
        narrow = mode_fixture(base, None, ('ssh-tag', 'in-session'))
        narrow.approve('agent-self', message=agent_message(narrow, 'agentself'))
        self.refused('agent_self_not_accepted', fixture=narrow)
        self.assertIn('agent_self_not_accepted', codes(issue(narrow)[1]))

    def test_distinct_codes(self):
        self.assertEqual(len({'agent_approval_signer_not_agent', 'agent_self_claim_without_agent_signature',
                              'agent_self_not_accepted', 'agent_self_bootstrap_refused', 'agent_self_refused_by_mode'}), 5)


class ModeTests(unittest.TestCase):
    """K3 modes: agent, prompt and ssh-tag, each accepted and refused, and no default_mode."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def fixture(self, name, default_mode, accept):
        base = self.base / name
        base.mkdir()
        return mode_fixture(base, default_mode, accept)

    def admitted(self, fixture, assurance):
        exit_code, context = fixture.admit()
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        self.assertEqual(context['assurance'], assurance)

    def refused(self, fixture, expected):
        exit_code, context = fixture.admit()
        self.assertNotEqual(exit_code, 0)
        self.assertIn(expected, codes(context), json.dumps(context['gaps'], indent=1))

    def test_agent_mode(self):
        agent = self.fixture('agent', 'agent', ALL_FORMS)
        self.assertEqual(issue(agent)[0], 0)
        self.admitted(agent, 'agent-self')
        agent.approve('agent-self', message=agent_message(agent, 'certifier'))
        self.refused(agent, 'agent_approval_signer_not_agent')
        agent.approve('in-session')
        self.admitted(agent, 'in-session')

    def test_prompt_mode_admits_only_an_explicit_in_session_confirmation(self):
        prompt = self.fixture('prompt', 'prompt', ('in-session', 'agent-self'))
        prompt.approve('in-session')
        self.admitted(prompt, 'in-session')
        prompt.approve('agent-self', message=agent_message(prompt, 'agentself'))
        self.refused(prompt, 'agent_self_refused_by_mode')
        self.assertIn('agent_self_refused_by_mode', codes(issue(prompt)[1]))

    def test_ssh_tag_mode_is_an_opt_in(self):
        signed = self.fixture('ssh', 'ssh-tag', ('ssh-tag',))
        signed.approve('ssh-tag')
        self.admitted(signed, 'key-held')
        signed.approve('in-session')
        self.refused(signed, 'approval_form_not_accepted')
        signed.approve('agent-self', message=agent_message(signed, 'agentself'))
        self.refused(signed, 'agent_self_not_accepted')
        wide = self.fixture('ssh-wide', 'ssh-tag', ('ssh-tag', 'agent-self'))
        wide.approve('agent-self', message=agent_message(wide, 'agentself'))
        self.refused(wide, 'agent_self_refused_by_mode')

    def test_policy_without_default_mode_keeps_its_semantics(self):
        plain = self.fixture('plain', None, ('ssh-tag', 'in-session'))
        self.assertNotIn('default_mode', json.loads((plain.work / core.POLICY).read_text())['approval'])
        plain.approve('in-session')
        self.admitted(plain, 'in-session')
        plain.approve('ssh-tag')
        self.admitted(plain, 'key-held')
        plain.approve('agent-self', message=agent_message(plain, 'agentself'))
        self.refused(plain, 'agent_self_not_accepted')


class PolicyModeValidationTests(unittest.TestCase):
    """K3, O2, O5: readiness-policy/2 gains agent-self and an optional default_mode."""

    def refused(self, policy, expected):
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_policy(policy)
        self.assertEqual(v2.code(raised.exception), expected, str(raised.exception))

    def test_default_mode_must_name_an_accepted_form(self):
        for mode, form in (('agent', 'agent-self'), ('prompt', 'in-session'), ('ssh-tag', 'ssh-tag')):
            policy = sample_policy('a' * 64, accept=ALL_FORMS)
            policy['approval']['default_mode'] = mode
            self.assertEqual(v2.validate_policy(copy.deepcopy(policy)), policy)
            policy['approval']['accept'] = [f for f in ALL_FORMS if f != form]
            self.refused(policy, 'policy_default_mode_not_accepted')
        bad = sample_policy('a' * 64, accept=ALL_FORMS)
        bad['approval']['default_mode'] = 'auto'
        self.refused(bad, 'policy_approval_invalid')
        unknown = sample_policy('a' * 64)
        unknown['approval']['mode'] = 'agent'
        self.refused(unknown, 'policy_approval_invalid')

    def test_policy_without_default_mode_and_the_skills_candidate_stay_valid(self):
        v2.validate_policy(sample_policy('a' * 64))
        registry = json.loads((REPO / core.REGISTRY).read_text())
        entry = next(p for p in registry['plans'] if p['plan_id'] == 'ach-skills-contract-v2')
        candidate = REPO / entry['artifacts']['policy_candidate']['path']
        policy = v2.validate_policy(json.loads(candidate.read_text()))
        self.assertNotIn('default_mode', policy['approval'])
        self.assertEqual(policy['approval']['accept'], ['ssh-tag', 'in-session'])
        self.assertEqual(sha(candidate), entry['policy_sha256'])

    def test_schema_vocabulary(self):
        schema = json.loads((AUTO / 'schemas/readiness-contract-v2.json').read_text())
        approval = schema['$defs']['policy']['properties']['approval']
        self.assertEqual(approval['properties']['accept']['items']['enum'], ['ssh-tag', 'in-session', 'agent-self'])
        self.assertEqual(approval['properties']['default_mode'], {'enum': ['agent', 'prompt', 'ssh-tag']})
        self.assertNotIn('default_mode', approval['required'])
        self.assertEqual(schema['$defs']['assurance']['enum'], list(LEVELS))


class AssuranceRenderingTests(unittest.TestCase):
    """K3, K1, K2: agent-self is computed, never upgraded, and rendered only as itself."""

    def test_no_level_renders_as_another(self):
        self.assertEqual(set(v2.ASSURANCE), set(LEVELS))
        labels = {'user-presence': ('user-presence', 'user presence'), 'key-held': ('key-held',),
                  'in-session': ('in-session',), 'agent-self': ('agent-self',)}
        for level in LEVELS:
            rendered = v2.render_assurance(level).lower()
            for other in LEVELS:
                if other != level:
                    for label in labels[other]:
                        self.assertNotIn(label, rendered, (level, other))
        self.assertIn('ASSURANCE: AGENT-SELF', v2.render_assurance('agent-self'))
        self.assertEqual(v2.assurance_for('agent-self', 'sk-ssh-ed25519@openssh.com', []), 'agent-self')
        for form in ('ssh-tag', 'in-session'):
            for key_type in ('sk-ssh-ed25519@openssh.com', 'ssh-ed25519'):
                self.assertNotEqual(v2.assurance_for(form, key_type, []), 'agent-self')


class AgentCertificateFixture(CertificateFixture):
    """CertificateFixture under an agent-mode policy, approved by the agent itself."""

    def __init__(self, base):
        self.base = base
        self.fixture = mode_fixture(base, 'agent', ALL_FORMS)
        exit_code, request = issue(self.fixture)
        if exit_code:
            raise AssertionError(json.dumps(request))
        work = self.fixture.work
        git(work, 'checkout', '-q', '-b', BRANCH)
        (work / 'tests/flip.sh').write_text('#!/bin/sh\ntest -f src/done.txt\n')
        (work / 'tests/flip.sh').chmod(0o755)
        evidence = AUTO / 'tdd-evidence.sh'
        subprocess.run(['bash', str(evidence), '--record-red', '--goal', 'G1', '--root', str(work),
                        '--command', 'sh tests/flip.sh'], check=True, capture_output=True)
        (work / 'src/done.txt').write_text('done\n')
        (work / 'src/app.txt').write_text('v1\n')
        subprocess.run(['bash', str(evidence), '--record-green', '--goal', 'G1', '--root', str(work),
                        '--command', 'sh tests/flip.sh'], check=True, capture_output=True)
        self.head = self.fixture.commit_push('feat: implement G1', branch=BRANCH)
        self.base_sha = git(work, 'rev-parse', 'origin/main')
        self.state = base / 'gh-state.json'
        self.log = base / 'gh-log.jsonl'
        from readiness_v2_certificate_test import gh_shim
        self.shim = gh_shim(base / 'bin', self.state, self.log)
        self.host({})
        self.review = self.review_record()


class AgentSelfReportTests(unittest.TestCase):
    """Every approval, admission report, certificate, merge decision, driver-log entry and
    audit-merges result carries agent-self and prints it prominently."""

    def test_agent_self_is_carried_and_printed_everywhere_and_never_relabelled(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            c = AgentCertificateFixture(base)
            exit_code, context = c.fixture.admit()
            self.assertEqual((exit_code, context['assurance']), (0, 'agent-self'), context['gaps'])
            exit_code, issued = c.certify()
            self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
            self.assertEqual(issued['certificate']['assurance'], 'agent-self')
            self.assertIn('ASSURANCE: AGENT-SELF', issued['assurance_notice'])
            exit_code, merged = c.merge('--admin')
            self.assertEqual(exit_code, 0, json.dumps(merged, indent=1))
            self.assertEqual(merged['assurance'], 'agent-self')
            self.assertIn('ASSURANCE: AGENT-SELF', merged['assurance_notice'])
            state = json.loads(c.state.read_text())
            state['merged_prs'] = [{'number': int(PR), 'headRefName': BRANCH, 'headRefOid': c.head,
                                    'mergeCommit': {'oid': 'c' * 40}, 'mergedAt': stamp(NOW)}]
            write_json(c.state, state)
            exit_code, audit = c.fixture.run(['audit-merges', '--root', str(c.fixture.work), '--handoff',
                                              'northstar-plan-plan-a'], env=c.env())
            self.assertEqual(exit_code, 0, json.dumps(audit, indent=1))
            self.assertEqual(audit['prs'][0]['assurance'], 'agent-self')
            self.assertIn('ASSURANCE: AGENT-SELF', audit['prs'][0]['assurance_notice'])
            log = [json.loads(line) for line in (c.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
            self.assertEqual({entry['assurance'] for entry in log if entry['exit'] == 0}, {'agent-self'})
            for report in (context, issued, merged, audit, log):
                text = json.dumps(report)
                for other in ('"in-session"', '"key-held"', '"user-presence"', 'IN-SESSION'):
                    self.assertNotIn(other, text)

    def test_an_in_session_flow_never_renders_as_agent_self(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            c = CertificateFixture(base, form='in-session')
            exit_code, issued = c.certify()
            self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
            exit_code, merged = c.merge('--admin')
            self.assertEqual(exit_code, 0)
            log = (c.fixture.state_dir() / 'driver-log.jsonl').read_text()
            for text in (json.dumps(issued), json.dumps(merged), log):
                self.assertNotIn('agent-self', text.lower())
                self.assertNotIn('AGENT-SELF', text)


class DocumentationTests(unittest.TestCase):
    """The decisions this goal must record in prose, checked phrase by phrase."""

    def text(self, relative):
        return ' '.join((REPO / relative).read_text().split())

    def assertMentions(self, relative, *phrases):
        text = self.text(relative)
        for phrase in phrases:
            self.assertIn(phrase, text, '%s does not state: %s' % (relative, phrase))

    def test_adr_0016_records_k3_and_k3b(self):
        self.assertMentions('docs/architecture/adr/0016-git-native-plan-approval.md',
                            'ai-catapult-agent-approval', 'agent-self', '`agent` mode', '`prompt` mode', '`ssh-tag` mode',
                            'The merge bar is unchanged', 'K3b', 'agent_self_policy_change',
                            'can add approver lines whose keys the agent holds', 'the same class of risk as K1',
                            'user-instructed exception to R2', '2026-10-04',
                            'rule (d) lets agent-self re-approve a later amendment only if both accept lists contain agent-self',
                            '`agent_self_bootstrap_refused` does not cover that case')

    def test_adr_0016_records_the_k3_follow_ups(self):
        self.assertMentions('docs/architecture/adr/0016-git-native-plan-approval.md',
                            'Only the user, or an agent on the user\'s explicit instruction',
                            'only before a generation binds it', '`reviewer@autobahn`', '`agent@autobahn`',
                            'Strictly after ACH-S-06 merges and before any XSKP P5 approval',
                            '`default_mode: agent`', 'approved in-session or by ssh-tag',
                            'republished against the amended policy', 'None of these is part of ACH-S-02')

    def test_merge_authority_states_the_per_plan_route_guard_and_reserved_paths(self):
        self.assertMentions('04-validate-handoff/autobahn/modules/merge-authority.md',
                            'per registered active plan', 're.escape(plan_id)', 'case-insensitive',
                            '`v2_branch_without_plan`', 'status is not `active`', '`plan_unloadable`',
                            '`v2_scope_outside_goal`', '`v2_sidecar_not_tightening`', '`v2_plan_entry_replaced`',
                            'merge-decision/1', 'gh pr merge --match-head-commit',
                            'the merge certificate is the host-policy audit record')

    def test_readiness_v2_documents_the_reserved_namespace_modes_and_inventory(self):
        self.assertMentions('04-validate-handoff/autobahn/modules/readiness-v2.md',
                            'Reserved branch namespace', 'active goal', '.ai/policies/readiness-policy.json',
                            '.ai/workflows/northstar-readiness-v2.json', '.ai/handoff/readiness-v2/**',
                            '.ai/traceability/graph.json', '.ai/ci/local-ci.json', 'never reserved through goal scope',
                            '`v2_scope_outside_goal`', 'publish-v2 replay', 'sidecar-tighten',
                            '`inventory-v1 --root R`', '`retired_v1[]`', 'agent-self', '`default_mode`',
                            'ai-catapult-agent-approval', 'policy-amendment', '`agent_self_bootstrap_refused`')
        reserved = self.text('04-validate-handoff/autobahn/modules/readiness-v2.md')
        self.assertNotIn('`context-build`, `inventory-v1` and `export-evidence` are reserved names', reserved)


if __name__ == '__main__':
    unittest.main()
