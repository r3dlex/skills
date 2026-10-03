"""merge-certificate/1 and re-observing merge authority (U2, U3, O4, O7, P7, K2, AC-2):
run-gates.sh --phase pre-merge issues the certificate; merge-authority.sh re-derives
every fact and refuses on any difference. Disposable repositories, a recording `gh`
stand-in found through PATH, and ephemeral agent keys only."""
import base64
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from datetime import timedelta

from readiness_v2_core_test import (AUTO, NORTH, NOW, POLICY, REGISTRY, Fixture, codes, gh_shim, git, sha, ssh_sign,
                                    stamp, v2, observer, write_json)

PR = '7'
BRANCH = 'feat/plan-a-G1'


class CertificateFixture:
    """A published, approved generation with goal G1 implemented on its branch and a host state."""

    def __init__(self, base, identity_model='single', form='ssh-tag'):
        self.base = base
        self.fixture = Fixture(base, identity_model=identity_model)
        self.fixture.approve(form)
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
        self.shim = gh_shim(base / 'bin', self.state, self.log)
        self.host({})
        self.review = self.review_record()

    def host(self, changes):
        state = {
            'pulls': {PR: {'head': {'sha': self.head, 'ref': BRANCH}, 'base': {'sha': self.base_sha, 'ref': 'main'}}},
            'checks': {self.head: [
                {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success', 'completed_at': stamp(NOW - timedelta(minutes=30))},
                {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success', 'completed_at': stamp(NOW - timedelta(minutes=20))},
                {'name': 'Optional Smoke', 'status': 'completed', 'conclusion': 'skipped', 'completed_at': stamp(NOW - timedelta(minutes=25))}]},
            'threads': {PR: [{'isResolved': True}]},
            'protection': None,
            'merged_prs': [],
        }
        for key, value in changes.items():
            state[key] = value
        write_json(self.state, state)

    def review_record(self, key='reviewer', head=None, **overrides):
        record = dict({'schema': 'review-lane/1', 'plan_id': 'plan-a', 'goal_id': 'G1', 'pr': int(PR),
                       'head': head or self.head, 'verdict': 'approve', 'issued_at': stamp(NOW - timedelta(minutes=10))},
                      **overrides)
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        path = Path(tempfile.mkdtemp(dir=self.base)) / 'review.json'
        path.write_text(line)
        Path(str(path) + '.sig').write_text(ssh_sign(self.fixture.keys.paths[key], v2.NS_REVIEW, line.encode(), self.base))
        return path

    def env(self, extra=None):
        return dict({'PATH': str(self.shim.parent) + os.pathsep + os.environ['PATH']}, **(extra or {}))

    def certify(self, review=None, now=NOW, key='certifier', env=None, adapter=None, extra=()):
        argv = ['certify-v2', '--root', str(self.fixture.work), '--handoff', 'northstar-plan-plan-a', '--goal-id', 'G1',
                '--pr', PR, *extra]
        review = self.review if review is None else review
        if review:
            argv += ['--review-record', str(review)]
        return self.fixture.run(argv, now=now, key=key, env=self.env(env), adapter=adapter)

    def merge(self, *extra, now=NOW, env=None, adapter=None):
        cwd = os.getcwd()
        os.chdir(self.fixture.work)
        try:
            return self.fixture.run(['merge-v2', '--pr', PR, *extra], now=now, env=self.env(env), adapter=adapter)
        finally:
            os.chdir(cwd)

    def merged(self):
        return json.loads(self.state.read_text()).get('merged', [])


class CertificateIssueTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.c = CertificateFixture(self.base)

    def refused(self, result, expected):
        exit_code, value = result
        self.assertNotEqual(exit_code, 0, json.dumps(value, indent=1))
        self.assertIn(expected, codes(value), json.dumps(value, indent=1))
        return value

    def test_certificate_binds_every_merge_fact_and_is_agent_signed(self):
        exit_code, result = self.c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        certificate = result['certificate']
        self.assertEqual(certificate['schema'], 'merge-certificate/1')
        self.assertEqual(certificate['pr'], int(PR))
        self.assertEqual((certificate['head'], certificate['base']), (self.c.head, self.c.base_sha))
        self.assertEqual(certificate['assurance'], 'key-held')
        self.assertEqual(certificate['lane_independence'], 'declared')
        self.assertEqual(certificate['review_lane']['principal'], 'reviewer@agent')
        self.assertEqual(certificate['certifier'], 'certifier@agent')
        self.assertTrue(certificate['admin'])
        self.assertEqual(certificate['adapter'], 'production-gh')
        self.assertEqual(certificate['unresolved_threads'], 0)
        self.assertEqual([c['name'] for c in certificate['required_checks']], ['Test Suite'])
        self.assertEqual(sorted(g['name'] for g in certificate['local_gates']),
                         ['ci-gate --verify', 'lint-gate', 'local safe CI subset', 'tdd-evidence'])
        self.assertTrue(all(g['exit'] == 0 for g in certificate['local_gates']))
        self.assertRegex(certificate['merge_admission_digest'], '^[0-9a-f]{64}$')
        self.assertEqual(certificate['approval_digest'], result['approval_digest'])
        stored = Path(result['path'])
        self.assertTrue(stored.is_relative_to(self.c.fixture.state_dir()))
        self.assertEqual(json.loads(stored.read_text()), certificate)
        verify = subprocess.run(['ssh-keygen', '-Y', 'verify', '-f', str(self.c.fixture.keys.anchor), '-I', 'certifier@agent',
                                 '-n', v2.NS_CERTIFICATE, '-s', str(stored) + '.sig'],
                                input=json.dumps(certificate, sort_keys=True, separators=(',', ':')).encode(), capture_output=True)
        self.assertEqual(verify.returncode, 0, verify.stderr)
        log = [json.loads(line) for line in (self.c.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        self.assertEqual(log[-1]['op'], 'certify-v2')
        self.assertEqual(log[-1]['exit'], 0)
        self.assertEqual(log[-1]['assurance'], 'key-held')
        self.assertFalse(any(path.name == 'driver-log.jsonl' for path in self.c.fixture.work.rglob('*') if '.git' not in path.parts))
        allowed = {'PATH', 'LANG', 'LC_ALL', 'TMPDIR', 'SSH_AUTH_SOCK', 'GH_TOKEN', 'HOME', 'GH_CONFIG_DIR', '__CF_USER_TEXT_ENCODING'}
        for call in (json.loads(line) for line in self.c.log.read_text().splitlines()):
            self.assertLessEqual(set(call['env']), allowed, call['args'])
            self.assertEqual(call['env']['HOME'], observer.passwd_home())

    def test_every_issue_refusal_and_driver_log(self):
        self.refused(self.c.certify(review=False), 'review_lane_missing')
        self.refused(self.c.certify(review=self.c.review_record(key='certifier')), 'review_lane_not_independent')
        self.refused(self.c.certify(review=self.c.review_record(key='outsider')), 'review_lane_signature_invalid')
        self.refused(self.c.certify(review=self.c.review_record(head='0' * 40)), 'review_lane_binding_mismatch')
        self.c.host({'threads': {PR: [{'isResolved': False}]}})
        self.refused(self.c.certify(), 'unresolved_threads')
        pending = {'name': 'Test Suite', 'status': 'in_progress', 'conclusion': None, 'completed_at': None}
        self.c.host({'checks': {self.c.head: [pending]}})
        self.refused(self.c.certify(), 'check_pending')
        skipped = {'name': 'Lint', 'status': 'completed', 'conclusion': 'skipped', 'completed_at': stamp(NOW - timedelta(minutes=5))}
        success = {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success', 'completed_at': stamp(NOW - timedelta(minutes=5))}
        self.c.host({'checks': {self.c.head: [success, skipped]}})
        self.refused(self.c.certify(), 'check_skipped_unlisted')
        self.c.host({'checks': {self.c.head: [dict(success, completed_at=stamp(NOW + timedelta(minutes=5)))]}})
        self.refused(self.c.certify(), 'check_completed_after_issue')
        self.c.host({'pulls': {PR: {'head': {'sha': '0' * 40, 'ref': BRANCH}, 'base': {'sha': self.c.base_sha, 'ref': 'main'}}}})
        self.refused(self.c.certify(), 'pr_head_mismatch')
        self.c.host({})
        (self.c.fixture.work / 'untracked.txt').write_text('dirty\n')
        self.refused(self.c.certify(), 'tree_not_clean')
        (self.c.fixture.work / 'untracked.txt').unlink()
        log = [json.loads(line) for line in (self.c.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        self.assertGreaterEqual(len(log), 10)
        self.assertTrue(all(entry['op'] == 'certify-v2' and entry['exit'] == 1 for entry in log))
        self.assertEqual(self.c.certify()[0], 0)

    def test_admin_flag_only_under_single_identity(self):
        base = self.base / 'multi'
        base.mkdir()
        multi = CertificateFixture(base, identity_model='multi')
        exit_code, result = multi.certify()
        self.assertEqual(exit_code, 0, result)
        self.assertFalse(result['certificate']['admin'])
        self.refused(multi.merge('--admin'), 'admin_requires_single_identity')
        self.assertEqual(multi.merged(), [])
        self.assertEqual(multi.merge()[0], 0)
        self.assertNotIn('--admin', multi.merged()[0]['args'])

    def test_proceed_text_flags_and_skip_variables_never_waive_a_gate(self):
        pending = {'name': 'Test Suite', 'status': 'queued', 'conclusion': None, 'completed_at': None}
        self.c.host({'checks': {self.c.head: [pending]}})
        skip = {'SKIP': 'all', 'SKIP_GATES': '1', 'SKIP_CHECKS': '1', 'AI_FACTORY_ALLOW_UNREACHABLE_UMBRELLA': '1'}
        self.refused(self.c.certify(env=skip), 'check_pending')
        for extra in (['proceed'], ['override'], ['--force'], ['--admin', 'if', 'necessary']):
            self.assertEqual(self.c.certify(extra=extra)[0], 2)
            self.assertEqual(self.c.merge(*extra)[0], 2)
            for operation in ('admit-v2', 'publish-v2', 'approval-request'):
                self.assertEqual(self.c.fixture.run([operation, *extra])[0], 2)
        self.refused(self.c.merge(env=skip), 'certificate_missing')
        self.assertEqual(self.c.merged(), [])


class MergeAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.c = CertificateFixture(self.base)
        exit_code, self.issued = self.c.certify()
        self.assertEqual(exit_code, 0, json.dumps(self.issued, indent=1))

    def refused(self, result, expected):
        exit_code, value = result
        self.assertEqual(exit_code, 4, json.dumps(value, indent=1))
        self.assertIn(expected, codes(value), json.dumps(value, indent=1))
        self.assertEqual(self.c.merged(), [])
        return value

    def test_reobserved_merge_uses_match_head_commit_and_records_assurance(self):
        exit_code, result = self.c.merge()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['decision'], 'merge')
        self.assertEqual(result['assurance'], 'key-held')
        merged = self.c.merged()
        self.assertEqual(len(merged), 1)
        args = merged[0]['args']
        self.assertEqual(args[args.index('--match-head-commit') + 1], self.c.head)
        self.assertNotIn('--admin', args)
        log = [json.loads(line) for line in (self.c.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        self.assertEqual((log[-1]['op'], log[-1]['exit'], log[-1]['assurance']), ('merge-v2', 0, 'key-held'))

    def test_admin_merge_with_independent_lane_under_single_identity(self):
        exit_code, result = self.c.merge('--admin')
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertIn('--admin', self.c.merged()[0]['args'])

    def test_in_session_approval_admin_merge_is_accepted_and_reported(self):
        base = self.base / 'in-session'
        base.mkdir()
        other = CertificateFixture(base, form='in-session')
        exit_code, issued = other.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        self.assertEqual(issued['certificate']['assurance'], 'in-session')
        self.assertIn('ASSURANCE: IN-SESSION', issued['assurance_notice'])
        exit_code, result = other.merge('--admin')
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['assurance'], 'in-session')
        self.assertIn('ASSURANCE: IN-SESSION', result['assurance_notice'])
        self.assertNotIn('user-presence', json.dumps(result))
        log = [json.loads(line) for line in (other.fixture.state_dir() / 'driver-log.jsonl').read_text().splitlines()]
        self.assertEqual({entry['assurance'] for entry in log}, {'in-session'})

    def test_refusals_on_any_difference(self):
        self.refused(self.c.merge('--verdict', str(self.base / 'any.json')), 'verdict_refused_for_v2')
        self.refused(self.c.merge(adapter=observer.FixtureAdapter(json.loads(self.c.state.read_text()))), 'adapter_not_production')
        self.refused(self.c.merge(now=NOW + timedelta(days=8)), 'approval_expired')
        self.c.host({'threads': {PR: [{'isResolved': False}]}})
        self.refused(self.c.merge(), 'certificate_claim_mismatch')
        failing = {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'failure', 'completed_at': stamp(NOW - timedelta(minutes=1))}
        self.c.host({'checks': {self.c.head: [failing]}})
        self.refused(self.c.merge(), 'certificate_claim_mismatch')
        self.c.host({})
        state = json.loads(self.c.state.read_text())
        state['pulls'][PR]['head_at_merge'] = '1' * 40
        write_json(self.c.state, state)
        self.refused(self.c.merge(), 'head_moved_at_merge')

    def test_moved_head_and_missing_certificate(self):
        work = self.c.fixture.work
        (work / 'src/app.txt').write_text('v2\n')
        moved = self.c.fixture.commit_push('feat: late change', branch=BRANCH)
        state = json.loads(self.c.state.read_text())
        state['pulls'][PR]['head']['sha'] = moved
        state['checks'][moved] = state['checks'][self.c.head]
        write_json(self.c.state, state)
        self.refused(self.c.merge(), 'head_moved')
        self.c.host({'pulls': {'8': {'head': {'sha': self.c.head, 'ref': BRANCH}, 'base': {'sha': self.c.base_sha, 'ref': 'main'}}}})
        exit_code, result = self.c.fixture.run(['merge-v2', '--pr', '8'], env=self.c.env())
        self.assertNotEqual(exit_code, 0)

    def test_self_review_only_admin_merge_is_refused(self):
        base = self.base / 'self-review'
        base.mkdir()
        other = CertificateFixture(base)
        self.assertIn('review_lane_not_independent', codes(other.certify(review=other.review_record(key='certifier'))[1]))
        self.refused_other(other, other.merge('--admin'), 'certificate_missing')
        # A certificate forged by a valid agent key, claiming an independent lane that never reviewed.
        exit_code, issued = other.certify()
        self.assertEqual(exit_code, 0)
        certificate = dict(issued['certificate'])
        certificate['review_lane'] = dict(certificate['review_lane'], principal='certifier@agent')
        self.forge(other, Path(issued['path']), certificate)
        self.refused_other(other, other.merge('--admin'), 'certificate_claim_mismatch')

    def refused_other(self, other, result, expected):
        exit_code, value = result
        self.assertEqual(exit_code, 4, json.dumps(value, indent=1))
        self.assertIn(expected, codes(value))
        self.assertEqual(other.merged(), [])

    def forge(self, fixture, path, certificate, key='certifier'):
        line = json.dumps(certificate, sort_keys=True, separators=(',', ':'))
        path.write_text(json.dumps(certificate, indent=2, sort_keys=True) + '\n')
        Path(str(path) + '.sig').write_text(ssh_sign(fixture.fixture.keys.paths[key], v2.NS_CERTIFICATE, line.encode(), self.base))

    def test_forged_certificate_with_false_claims_signed_by_a_valid_agent_key(self):
        path = Path(self.issued['path'])
        certificate = dict(self.issued['certificate'])
        self.c.host({'threads': {PR: [{'isResolved': False}]}})
        self.forge(self.c, path, certificate, key='reviewer')
        self.refused(self.c.merge(), 'certificate_claim_mismatch')
        self.forge(self.c, path, dict(certificate, unresolved_threads=0, pr=int(PR)), key='outsider')
        self.refused(self.c.merge(), 'certificate_signature_invalid')


class MergeAuthorityEntryTests(unittest.TestCase):
    """The shell adapter: --pr is mandatory once origin/<target> carries v2 artifacts."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.verdict = REPO_VERDICT

    def authority(self, cwd, *args, env=None):
        return subprocess.run(['bash', str(AUTO / 'merge-authority.sh'), *args], cwd=str(cwd), capture_output=True,
                              text=True, env=env or os.environ.copy(), stdin=subprocess.DEVNULL)

    def repository(self, name, files):
        origin, work = self.base / (name + '.git'), self.base / name
        git(self.base, 'init', '-q', '--bare', str(origin))
        git(self.base, 'clone', '-q', str(origin), str(work))
        for path, value in files.items():
            write_json(work / path, value)
        git(work, 'add', '-A')
        git(work, 'commit', '-q', '--allow-empty', '-m', 'fixture')
        git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(work, 'fetch', '-q', 'origin')
        return work

    def test_verdict_only_refused_with_v2_registry_or_policy2(self):
        plain = self.repository('plain', {})
        self.assertEqual(self.authority(plain, '--verdict', str(self.verdict)).returncode, 0)
        for name, files in (('registry', {REGISTRY: {'schema': 'readiness-contract/2', 'plans': []}}),
                            ('policy', {POLICY: {'schema': 'readiness-policy/2'}})):
            work = self.repository(name, files)
            result = self.authority(work, '--verdict', str(self.verdict))
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('pr_required', result.stdout + result.stderr)
        outside = self.base / 'not-a-repository'
        outside.mkdir()
        self.assertEqual(self.authority(outside, '--verdict', str(self.verdict)).returncode, 0)

    def test_module_shadowing_in_cwd_cannot_hijack_entry_points(self):
        work = self.repository('shadow', {REGISTRY: {'schema': 'readiness-contract/2', 'plans': []}})
        for name in ('json.py', 'pathlib.py', 'hashlib.py', 'pwd.py'):
            (work / name).write_text('import sys\nsys.exit(0)\n')
        result = self.authority(work, '--verdict', str(self.verdict))
        self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
        self.assertIn('pr_required', result.stdout + result.stderr)
        v1 = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), 'admit', '--root', str(self.base)], cwd=str(work),
                            capture_output=True, text=True, stdin=subprocess.DEVNULL)
        self.assertEqual(v1.returncode, 1, v1.stdout + v1.stderr)
        self.assertEqual(json.loads(v1.stdout)['schema'], 'readiness-contract/1')

    def test_v2_pr_with_verdict_refused_and_v1_pr_keeps_v1_path_and_environment_allowlist(self):
        c = CertificateFixture(self.base)
        env = dict(os.environ, PATH=str(c.shim.parent) + os.pathsep + os.environ['PATH'], GH_HOST='evil.example',
                   GH_REPO='evil/repo', GH_ENTERPRISE_TOKEN='x', GIT_DIR=str(self.base / 'nowhere'),
                   GIT_WORK_TREE=str(self.base), HOME=str(self.base / 'inherited-home'),
                   AI_FACTORY_ALLOW_UNREACHABLE_UMBRELLA='1', SKIP_GATES='1', SKIP='all')
        result = self.authority(c.fixture.work, '--pr', PR, '--verdict', str(self.verdict), env=env)
        self.assertEqual(result.returncode, 4, result.stdout + result.stderr)
        self.assertIn('verdict_refused_for_v2', result.stdout + result.stderr)
        calls = [json.loads(line) for line in c.log.read_text().splitlines()]
        self.assertTrue(calls, 'the production adapter ran gh')
        home = observer.passwd_home()
        for call in calls:
            names = set(call['env'])
            for dropped in ('GH_HOST', 'GH_REPO', 'GH_ENTERPRISE_TOKEN', 'GIT_DIR', 'GIT_WORK_TREE',
                            'AI_FACTORY_ALLOW_UNREACHABLE_UMBRELLA', 'SKIP_GATES', 'SKIP'):
                self.assertNotIn(dropped, names)
            self.assertEqual(call['env']['HOME'], home)
            self.assertEqual(call['env']['GH_CONFIG_DIR'], str(Path(home) / '.config/gh'))
            self.assertLessEqual(names - {'PATH', 'LANG', 'LC_ALL', 'TMPDIR', 'SSH_AUTH_SOCK', 'GH_TOKEN', 'HOME',
                                          'GH_CONFIG_DIR', '__CF_USER_TEXT_ENCODING'}, set(), names)
        for extra in (['proceed'], ['override'], ['--force'], ['--admin', 'if', 'necessary']):
            self.assertEqual(self.authority(c.fixture.work, '--pr', PR, *extra, env=env).returncode, 2, extra)
            gates = subprocess.run(['bash', str(AUTO / 'run-gates.sh'), '--root', str(c.fixture.work), '--goal-record',
                                    str(self.base / 'absent.json'), '--phase', 'pre-merge', *extra],
                                   capture_output=True, text=True, env=env, stdin=subprocess.DEVNULL)
            self.assertEqual(gates.returncode, 2, extra)
        state = json.loads(c.state.read_text())
        state['pulls']['9'] = {'head': {'sha': c.head, 'ref': 'docs/unrelated-change'}, 'base': state['pulls'][PR]['base']}
        write_json(c.state, state)
        v1 = self.authority(c.fixture.work, '--pr', '9', '--verdict', str(self.verdict), env=env)
        self.assertEqual(v1.returncode, 0, v1.stdout + v1.stderr)
        self.assertIn('host-policy authorized', v1.stdout)
        self.assertNotIn('merged', json.loads(c.state.read_text()))


class BaseCopyTests(unittest.TestCase):
    """P8: a PR that edits the pinned v2 files is admitted by the base copy, never its own head."""

    def test_driver_runs_only_from_the_base_commit_copy(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            fixture = Fixture(base)
            work = fixture.work
            shutil.copytree(AUTO, work / '04-validate-handoff/autobahn', ignore=shutil.ignore_patterns('__pycache__'))
            shutil.copytree(NORTH, work / '02-govern-plan/northstar', ignore=shutil.ignore_patterns('__pycache__'))
            fixture.commit_push('vendor the v2 driver on main')
            git(work, 'checkout', '-q', '-b', 'feat/plan-a-G1')
            observer_copy = work / '04-validate-handoff/autobahn/lib/observer.py'
            observer_copy.write_text(observer_copy.read_text() + '\n# head edit\n')
            manifest = {'schema': 'readiness-contract/2', 'files': {}}
            for name in json.loads((AUTO / 'readiness-dependency-v2.json').read_text())['files']:
                path = work / ('02-govern-plan/northstar/handoff-write.sh' if name == 'northstar/handoff-write.sh'
                               else '04-validate-handoff/autobahn/' + name)
                manifest['files'][name] = sha(path)
            for directory in ('04-validate-handoff/autobahn', '02-govern-plan/northstar'):
                (work / directory / 'readiness-dependency-v2.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
            fixture.commit_push('feat: edit the driver', branch='feat/plan-a-G1')
            command = lambda driver: subprocess.run(
                ['bash', str(driver / '04-validate-handoff/autobahn/contract-run.sh'), 'admit-v2', '--root', str(work),
                 '--handoff', 'northstar-plan-plan-a', '--goal-id', 'G1'], capture_output=True, text=True,
                stdin=subprocess.DEVNULL)
            head_run = command(work)
            self.assertNotEqual(head_run.returncode, 0)
            self.assertIn('driver_not_base_copy', head_run.stdout)
            detached = base / 'base-copy'
            git(work, 'worktree', 'add', '-q', '--detach', str(detached), 'origin/main')
            base_run = command(detached)
            self.assertNotIn('driver_not_base_copy', base_run.stdout + base_run.stderr)
            self.assertNotIn('dependency_failed', base_run.stdout)
            self.assertEqual(json.loads(base_run.stdout)['schema'], 'readiness-context/2')


REPO_VERDICT = Path(__file__).resolve().parents[1] / 'reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json'

if __name__ == '__main__':
    unittest.main()
