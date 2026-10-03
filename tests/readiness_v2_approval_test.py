"""plan-approval/1 (U1, R2, R2b, K1, K2, O2): both approval forms, the trust anchor and
every refusal of AC-2 that concerns approvals. Ephemeral keys, a temporary anchor and
disposable repositories only; no real anchor, key or tag is read or written."""
import base64
import copy
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

from readiness_v2_core_test import (AUTO, NOW, POLICY, Fixture, codes, git, sha, ssh_sign, stamp, v2, observer,
                                    write_json)


class ApprovalTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.fixture = Fixture(self.base)

    def refused(self, expected, **kwargs):
        exit_code, context = self.fixture.admit(**kwargs)
        self.assertNotEqual(exit_code, 0, json.dumps(context, indent=1))
        self.assertFalse(context['admitted'])
        self.assertIn(expected, codes(context), json.dumps(context['gaps'], indent=1))
        return context

    def test_ssh_tag_approval_admits_with_key_held_assurance(self):
        self.fixture.approve('ssh-tag')
        exit_code, context = self.fixture.admit()
        self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))
        self.assertEqual(context['assurance'], 'key-held')
        self.assertEqual(context['approval']['form'], 'ssh-tag')
        self.assertEqual(context['approval']['principal'], 'approver@human')
        self.assertEqual(context['approval']['tag'], 'approval/plan-a/' + self.fixture.generation[:12])
        self.assertEqual(context['authority'], 'plan-approval/1')

    def test_forged_and_agent_role_signatures(self):
        record = self.fixture.approve('ssh-tag', key='outsider')
        self.refused('approval_signature_invalid')
        self.fixture.approve('ssh-tag', key='certifier', record=record)
        self.refused('approval_signer_not_approver')
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        signature = ssh_sign(self.fixture.keys.paths['approver'], v2.NS_APPROVAL, line.encode(), self.base)
        tampered = dict(record, owner='Someone Else')
        message = (json.dumps(tampered, sort_keys=True, separators=(',', ':')) + '\nsignature: ' +
                   base64.b64encode(signature.encode()).decode() + '\n')
        self.fixture.approve('ssh-tag', message=message)
        self.refused('approval_signature_invalid')
        wrong_namespace = ssh_sign(self.fixture.keys.paths['approver'], v2.NS_REVIEW, line.encode(), self.base)
        self.fixture.approve('ssh-tag', message=line + '\nsignature: ' + base64.b64encode(wrong_namespace.encode()).decode() + '\n')
        self.refused('approval_signature_invalid')

    def test_age_expiry_and_window(self):
        self.fixture.approve('ssh-tag', record=self.fixture.record(issued=NOW - timedelta(days=15), days=16))
        self.refused('approval_too_old')
        self.fixture.approve('ssh-tag', record=self.fixture.record(issued=NOW - timedelta(days=3), days=2))
        self.refused('approval_expired')
        self.fixture.approve('ssh-tag', record=self.fixture.record(issued=NOW - timedelta(hours=1), days=20))
        self.refused('approval_window_exceeds_max_age')
        self.fixture.approve('ssh-tag', record=self.fixture.record(issued=NOW + timedelta(days=1), days=2))
        self.refused('approval_not_yet_valid')

    def test_changed_generation_spec_policy_and_sidecar_digests(self):
        record = self.fixture.record()
        cases = [
            (dict(record, generation='0' * 64), 'approval_generation_mismatch'),
            (dict(record, sidecar_sha256='0' * 64), 'approval_sidecar_mismatch'),
            (dict(record, goals=['G1', 'G9']), 'approval_goals_mismatch'),
            (dict(record, stages=['implementation']), 'approval_record_invalid'),
            (dict(record, assurance='user-presence'), 'approval_assurance_mismatch'),
        ]
        for changed, expected in cases:
            with self.subTest(expected=expected):
                self.fixture.approve('ssh-tag', record=changed)
                self.refused(expected)
        self.fixture.approve('ssh-tag')
        self.assertEqual(self.fixture.admit()[0], 0)
        (self.fixture.work / 'spec.md').write_text('Specification changed after signing\n')
        self.fixture.commit_push('spec edit after signing')
        self.refused('approval_spec_mismatch')
        policy = json.loads((self.fixture.work / POLICY).read_text())
        policy['required_checks'].append('Late Check')
        (self.fixture.work / 'spec.md').write_text('Fixture specification\n')
        write_json(self.fixture.work / POLICY, policy)
        self.fixture.commit_push('policy edit after signing')
        self.refused('approval_policy_mismatch')

    def test_sidecar_tightening_admits_and_loosening_is_refused(self):
        self.fixture.approve('ssh-tag')
        path = self.fixture.work / '.ai/handoff/readiness-v2/plan-a' / self.fixture.generation / 'sidecar.json'
        sidecar = json.loads(path.read_text())
        sidecar['goals']['G1']['legacy_risk_reason'] += '; observed seam'
        write_json(path, sidecar)
        self.fixture.commit_push('tighten sidecar')
        self.assertEqual(self.fixture.admit()[0], 0)
        sidecar['goals']['G1']['readiness']['implementation'] = 'blocked'
        write_json(path, sidecar)
        self.fixture.commit_push('hold implementation')
        self.refused('readiness_hold')
        sidecar['goals']['G1']['legacy_safe_tdd'] = False
        sidecar['goals']['G1']['readiness']['implementation'] = 'unknown'
        write_json(path, sidecar)
        self.fixture.commit_push('loosen sidecar')
        self.refused('sidecar_loosened')

    def test_sidecar_v0_must_be_a_valid_sidecar(self):
        path = self.fixture.work / '.ai/handoff/readiness-v2/plan-a' / self.fixture.generation / 'sidecar.json'
        invalid = json.loads(path.read_text())
        invalid['goals']['G1']['owner'] = 'smuggled'
        write_json(path, invalid)
        self.fixture.commit_push('an invalid sidecar version enters history')
        self.fixture.approve('ssh-tag', record=self.fixture.record(sidecar_sha256=v2.canonical(invalid)))
        valid = json.loads(path.read_text())
        del valid['goals']['G1']['owner']
        write_json(path, valid)
        self.fixture.commit_push('restore a valid sidecar')
        self.refused('approval_sidecar_mismatch')

    def test_anchor_missing_inside_worktree_and_digest_mismatch(self):
        self.fixture.approve('ssh-tag')
        self.refused('anchor_missing', anchor=self.base / 'absent' / 'allowed_signers')
        inside = self.fixture.work / 'notes' / 'allowed_signers'
        inside.parent.mkdir()
        inside.write_bytes(self.fixture.keys.anchor.read_bytes())
        self.refused('anchor_inside_worktree', anchor=inside)
        inside.unlink()
        inside.parent.rmdir()
        nested_repo = self.base / 'dotfiles'
        git(self.base, 'init', '-q', str(nested_repo))
        (nested_repo / 'allowed_signers').write_bytes(self.fixture.keys.anchor.read_bytes())
        self.refused('anchor_inside_worktree', anchor=nested_repo / 'allowed_signers')
        other = self.base / 'other-anchor' / 'allowed_signers'
        other.parent.mkdir()
        other.write_text(self.fixture.keys.anchor.read_text() + '# changed\n')
        self.refused('anchor_digest_mismatch', anchor=other)

    def test_signing_key_line_decides_assurance_and_principals_are_unique(self):
        from readiness_v2_core_test import fake_sk_line
        signature = ssh_sign(self.fixture.keys.paths['approver'], v2.NS_APPROVAL, b'probe', self.base)
        self.assertEqual(' '.join(observer.signature_public_key(signature)), self.fixture.keys.public('approver'))
        base = self.base / 'two-lines'
        base.mkdir()
        doubled = Fixture(base, anchor_prefix=fake_sk_line('approver@human', v2.NS_APPROVAL))
        doubled.approve('ssh-tag', record=doubled.record(assurance='user-presence'))
        exit_code, context = doubled.admit()
        self.assertNotEqual(exit_code, 0)
        self.assertIn('anchor_principal_ambiguous', codes(context))
        self.assertNotEqual(context['assurance'], 'user-presence')
        doubled.approve('ssh-tag')
        self.assertIn('anchor_principal_ambiguous', codes(doubled.admit()[1]))

    def test_symlinked_or_resolved_inside_worktree_anchor_is_refused(self):
        self.fixture.approve('ssh-tag')
        link = self.base / 'linked' / 'allowed_signers'
        link.parent.mkdir()
        link.symlink_to(self.fixture.keys.anchor)
        self.refused('anchor_symlink', anchor=link)
        inside = self.fixture.work / 'vault'
        inside.mkdir()
        (inside / 'allowed_signers').write_bytes(self.fixture.keys.anchor.read_bytes())
        through = self.base / 'through'
        through.symlink_to(inside)
        self.refused('anchor_inside_worktree', anchor=through / 'allowed_signers')
        (inside / 'allowed_signers').unlink()
        inside.rmdir()
        self.assertEqual(self.fixture.admit()[0], 0)

    def test_anchor_locator_has_no_environment_or_flag_override(self):
        self.fixture.approve('ssh-tag')
        decoy = self.base / 'decoy' / 'allowed_signers'
        decoy.parent.mkdir()
        decoy.write_text('')
        env = {name: str(decoy) for name in ('AI_CATAPULT_ANCHOR', 'ALLOWED_SIGNERS', 'SSH_ALLOWED_SIGNERS')}
        env['HOME'] = str(decoy.parent)
        exit_code, context = self.fixture.admit(env=env)
        self.assertEqual(exit_code, 0, context['gaps'])
        self.assertEqual(self.fixture.admit(extra=('--anchor', str(decoy)))[0], 2)
        with mock.patch.dict(os.environ, {'HOME': '/nonexistent-home'}):
            self.assertEqual(observer.default_anchor_path(), Path(observer.passwd_home()) / '.config/ai-catapult/allowed_signers')

    def test_in_session_accepted_reported_and_narrowable(self):
        self.fixture.approve('in-session')
        exit_code, context = self.fixture.admit()
        self.assertEqual(exit_code, 0, context['gaps'])
        self.assertEqual(context['assurance'], 'in-session')
        self.assertIn('ASSURANCE: IN-SESSION', context['assurance_notice'])
        bad_echo = json.dumps(self.fixture.record('in-session'), sort_keys=True, separators=(',', ':')) + '\ndigest-echo: ' + '0' * 64 + '\n'
        self.fixture.approve('in-session', message=bad_echo)
        self.refused('approval_digest_echo_mismatch')
        narrowed_base = self.base / 'narrowed'
        narrowed_base.mkdir()
        narrowed = Fixture(narrowed_base, accept=('ssh-tag',))
        narrowed.approve('in-session')
        exit_code, context = narrowed.admit()
        self.assertNotEqual(exit_code, 0)
        self.assertIn('approval_form_not_accepted', codes(context))
        narrowed.approve('ssh-tag')
        self.assertEqual(narrowed.admit()[0], 0)

    def test_in_session_policy_bootstrap_is_accepted_and_reported(self):
        base = self.base / 'bootstrap'
        base.mkdir()
        goals = [{'id': 'P', 'scope': [POLICY], 'acceptance_criteria': ['policy lands'], 'dependencies': [],
                  'verification': ['bash tests/check.sh']},
                 {'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['works'], 'dependencies': ['P'],
                  'verification': ['bash tests/check.sh']}]
        from readiness_v2_core_test import sample_bundle
        bootstrap = Fixture(base, bundle=sample_bundle(goals), candidate=True, live_policy=False)
        bootstrap.approve('in-session')
        exit_code, context = bootstrap.admit(goal='P')
        self.assertEqual(exit_code, 0, context['gaps'])
        self.assertEqual(context['policy']['mode'], 'bootstrap')
        self.assertEqual(context['assurance'], 'in-session')
        exit_code, context = bootstrap.admit(goal='G1', adapter=observer.FixtureAdapter({'merged_prs': []}))
        self.assertIn('dependency_incomplete', codes(context))

    def test_tag_must_be_annotated_on_origin_and_point_at_the_generation(self):
        tag = 'approval/plan-a/' + self.fixture.generation[:12]
        git(self.fixture.work, 'tag', tag, self.fixture.publication_commit)
        self.refused('approval_tag_not_annotated')
        git(self.fixture.work, 'tag', '-d', tag)
        self.fixture.approve('ssh-tag', push=False)
        self.refused('approval_tag_not_on_origin')

    def test_assurance_rules_and_rendering_never_upgrade(self):
        self.assertEqual(v2.assurance_for('ssh-tag', 'sk-ssh-ed25519@openssh.com', []), 'user-presence')
        self.assertEqual(v2.assurance_for('ssh-tag', 'sk-ecdsa-sha2-nistp256@openssh.com', ['no-touch-required']), 'key-held')
        self.assertEqual(v2.assurance_for('ssh-tag', 'ssh-ed25519', []), 'key-held')
        self.assertEqual(v2.assurance_for('in-session', 'sk-ssh-ed25519@openssh.com', []), 'in-session')
        line = 'approver@human namespaces="ai-catapult-plan-approval",no-touch-required sk-ssh-ed25519@openssh.com AAAA comment'
        parsed = observer.parse_anchor_line(line)
        self.assertEqual(parsed['principals'], ['approver@human'])
        self.assertEqual(parsed['namespaces'], ['ai-catapult-plan-approval'])
        self.assertIn('no-touch-required', parsed['options'])
        self.assertEqual(parsed['key_type'], 'sk-ssh-ed25519@openssh.com')
        for assurance in ('in-session', 'key-held'):
            rendered = v2.render_assurance(assurance)
            self.assertNotIn('user-presence', rendered.lower())
            self.assertNotIn('user presence', rendered.lower())
        self.assertIn('ASSURANCE: IN-SESSION', v2.render_assurance('in-session'))
        with self.assertRaises(v2.Invalid):
            v2.render_assurance('user-presence-ish')

    def test_approval_request_prints_commands_and_never_signs(self):
        shim = self.base / 'bin'
        shim.mkdir()
        log = self.base / 'ssh-keygen.log'
        (shim / 'ssh-keygen').write_text('#!/bin/sh\necho "$@" >> %s\nexit 1\n' % log)
        (shim / 'ssh-keygen').chmod(0o755)
        before = {str(p): sha(p) for p in self.fixture.work.rglob('*') if p.is_file() and '.git' not in p.parts}
        refs = git(self.fixture.work, 'for-each-ref')
        env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ['PATH'])
        result = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), 'approval-request', '--root', str(self.fixture.work),
                                 '--handoff', 'northstar-plan-plan-a', '--owner', 'Fixture Owner',
                                 '--reviewer-lane', 'independent review lane'],
                                capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        request = json.loads(result.stdout)
        tag = 'approval/plan-a/' + self.fixture.generation[:12]
        self.assertEqual(request['tag'], tag)
        self.assertEqual(request['anchor_sha256'], self.fixture.anchor_sha256)
        self.assertEqual(request['digest'], sha(json.dumps(request['record'], sort_keys=True, separators=(',', ':')).encode()))
        joined = '\n'.join(request['commands']['ssh-tag'])
        self.assertIn('ssh-keygen -Y sign', joined)
        self.assertIn('-n ai-catapult-plan-approval', joined)
        self.assertIn('git tag -a --cleanup=verbatim', joined)
        self.assertIn(tag, joined)
        self.assertEqual(request['fallback']['assurance'], 'in-session')
        self.assertEqual(request['fallback']['record']['assurance'], 'in-session')
        self.assertIn('ASSURANCE: IN-SESSION', result.stderr)
        self.assertFalse(log.exists(), 'approval-request must never invoke ssh-keygen')
        self.assertEqual(before, {str(p): sha(p) for p in self.fixture.work.rglob('*') if p.is_file() and '.git' not in p.parts})
        self.assertEqual(refs, git(self.fixture.work, 'for-each-ref'))


if __name__ == '__main__':
    unittest.main()
