"""ACH-S-06 end-to-end tests: audit-merges re-observation and the detective control (AC1),
export-evidence (AC2), the dual-mode prompt-count measure (AC3), the negative list (AC4),
the edge cases (AC5) and the acceptance checks in the e2e context (AC6).

Everything runs offline through the in-process fixture (tests/readiness_v2_fixture.py):
no environment-selected adapter, no real `gh` execution, the stub's git remote is the
bare origin, and stdin is /dev/null everywhere. The counted measure is defined in the
fixture docstring (B3 ruling).
"""
import base64
import contextlib
import copy
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import readiness_v2_core_test as core  # noqa: E402
from readiness_v2_core_test import (AUTO, POLICY, REGISTRY, codes, git, observer, sha, ssh_sign, stamp, v2,  # noqa: E402
                                    write_json)
from readiness_v2_fixture import (E2ERepo, HANDOFF, HostStub, LANE, PLAN, e2e_bundle, sample_sidecar)  # noqa: E402

REPO = Path(__file__).resolve().parents[1]
NOW = core.NOW
GEN = '.ai/handoff/readiness-v2'


def offline():
    """No network and no real gh: socket raises in-process and any subprocess that would
    exec gh refuses."""
    stack = contextlib.ExitStack()
    stack.enter_context(mock.patch.object(socket, 'socket',
                                          mock.Mock(side_effect=AssertionError('no network in the e2e'))))
    real_run = subprocess.run

    def guarded_run(*args, **kwargs):
        if args and args[0] and str(args[0][0]) == 'gh':
            raise AssertionError('the e2e must never exec the real gh')
        return real_run(*args, **kwargs)

    stack.enter_context(mock.patch.object(subprocess, 'run', guarded_run))
    return stack


class Base(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='e2e-test-')
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def new_repo(self, mode, name):
        base = self.base / name
        base.mkdir()
        return E2ERepo(base, mode)

    def agent_repo(self, name='repo', chain='publication'):
        """An agent-mode repo through publication and approval; with chain='goal' also
        through G1's certified merge."""
        repo = self.new_repo('agent', name)
        repo.publication_chain()
        repo.approval_chain()
        if chain == 'goal':
            wt = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
            code, context, err = repo.admit(wt, 'G1')
            assert code == 0, json.dumps(context, indent=1)
            head = repo.implement_goal(wt, 'G1')
            review = repo.review_record('G1', 2, head)
            code, out, err = repo.certify(wt, 'G1', 2, review)
            assert code == 0, (out, err)
            code, out, err = repo.merge(wt, 2, ['--admin'])
            assert code == 0, (out, err)
            repo.fetch(repo.work, wt)
        return repo

    @staticmethod
    def verify_from(directory, signature, payload, principal, namespace):
        result = subprocess.run(['ssh-keygen', '-Y', 'verify', '-f', str(directory / 'allowed_signers'),
                                 '-I', principal, '-n', namespace, '-s', str(directory / signature)],
                                input=(directory / payload).read_bytes(), capture_output=True)
        return result.returncode


class DualModeEndToEndTests(Base):
    """AC3: the whole chain in both modes, with the AC-1 measure, the audit and the export."""

    modes = {}

    @classmethod
    def setUpClass(cls):
        cls.base = Path(tempfile.mkdtemp(prefix='e2e-dual-')).resolve()
        cls.environment_before = dict(os.environ)
        with offline():
            for mode in ('prompt', 'agent'):
                repo = E2ERepo(cls.base / mode, mode)
                repo.full_chain()
                cls.modes[mode] = repo

    def test_prompt_mode_counts_exactly_one(self):
        self.assert_mode('prompt')

    def test_agent_mode_counts_exactly_zero(self):
        self.assert_mode('agent')

    def test_audit_by_plan_reports_every_merged_goal(self):
        for mode in ('prompt', 'agent'):
            with self.subTest(mode=mode):
                self.assert_audit(mode)

    def test_export_after_each_mode_verifies_from_a_temporary_copy(self):
        for mode in ('prompt', 'agent'):
            with self.subTest(mode=mode):
                self.assert_export(mode)

    def assert_mode(self, mode):
        repo = self.modes[mode]
        expected = 1 if mode == 'prompt' else 0
        components = repo.counters.components()
        self.assertEqual(repo.counters.total(), expected, components)
        self.assertEqual(repo.counters.hook_calls, 0, components)
        # The sidecar is never edited after signing.
        sidecar_path = '%s/%s/%s/sidecar.json' % (GEN, PLAN, repo.generation)
        history = git(repo.work, 'log', '--format=%H', 'origin/main', '--', sidecar_path).split()
        self.assertEqual(history, [repo.publication], history)
        canonical_sidecar = json.loads((repo.work / sidecar_path).read_text())
        self.assertEqual(v2.canonical(canonical_sidecar), repo.approval['sidecar_sha256'])
        # Exactly one approval tag on origin.
        tags = git(repo.work, 'ls-remote', 'origin', 'refs/tags/approval/%s/*' % PLAN).split()
        self.assertEqual(len(tags), 1, tags)
        # The assurance is carried everywhere and never relabelled (K2).
        for context in repo.results['admissions']:
            self.assertEqual(context['assurance'], repo.assurance)
        for issued in repo.results['certificates']:
            self.assertEqual(issued['certificate']['assurance'], repo.assurance)
        for merged in repo.results['merges']:
            self.assertEqual(merged['assurance'], repo.assurance)
        log = repo.driver_log_lines()
        self.assertEqual({entry['assurance'] for entry in log if entry['exit'] == 0 and entry['op'] != 'audit-merges'},
                         {repo.assurance})
        self.assert_audit(mode)
        self.assert_export(mode)
        # The shared common dir bound every certificate; admissions ran from linked worktrees.
        common = str(Path(git(repo.work, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve())
        for issued in repo.results['certificates']:
            self.assertEqual(issued['certificate']['repository']['common_dir'], common)
        # No environment-selected adapter: the environment is exactly what it was before.
        self.assertEqual(set(os.environ), set(self.environment_before))

    def assert_audit(self, mode):
        repo = self.modes[mode]
        banned = ('"in-session"', '"key-held"', '"user-presence"', 'IN-SESSION') if mode == 'agent' \
            else ('"agent-self"', 'AGENT-SELF', '"key-held"', '"user-presence"')
        code, report, err = repo.audit()
        self.assertEqual(code, 0, json.dumps(report, indent=1))
        self.assertEqual([entry['pr'] for entry in report['prs']], [2, 3, 4])
        for entry in report['prs']:
            self.assertEqual(entry['assurance'], repo.assurance)
            self.assertEqual(entry['lane_independence'], 'declared')
            self.assertEqual(entry['flags'], [])
            self.assertIs(entry['merge_commit_reached'], True)
            self.assertIsNotNone(entry['merged_at'])
        self.assertEqual([c['attribution'] for c in report['changes']], ['goal', 'goal', 'goal'])
        self.assertEqual(report['publication_commit'], repo.publication)
        self.assertEqual(report['target_revision'], git(repo.work, 'rev-parse', 'origin/main'))
        self.assertEqual(report['findings'], [])
        for text in (json.dumps(report), json.dumps(repo.driver_log_lines())):
            for other in banned:
                self.assertNotIn(other, text)
        repo.results['audits'].append(report)

    def assert_export(self, mode):
        repo = self.modes[mode]
        code, result, err = repo.export()
        self.assertEqual(code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['assurance'], repo.assurance)
        self.assertEqual(result['tag'], 'approval/%s/%s' % (PLAN, repo.generation[:12]))
        self.assertEqual(result['unmerged'], [])
        directory = repo.work / '.ai/evidence/approvals' / PLAN
        files = {p.relative_to(directory).as_posix(): p.read_bytes() for p in directory.rglob('*') if p.is_file()}
        expected = {'approval.json', 'allowed_signers', 'driver-log.jsonl',
                    'certificates/G1.json', 'certificates/G1.json.sig', 'certificates/G2.json',
                    'certificates/G2.json.sig', 'certificates/G3.json', 'certificates/G3.json.sig'}
        if mode == 'agent':
            expected.add('approval.sig')
        self.assertEqual(set(files), expected)
        self.assertEqual(sha(files['allowed_signers']), repo.anchor_sha256)
        self.assertEqual(files['approval.json'], v2.canonical_bytes(repo.approval))
        # The driver log is the whole state log, byte for byte (B6).
        self.assertEqual(files['driver-log.jsonl'], (repo.state_dir() / 'driver-log.jsonl').read_bytes())
        for line in files['driver-log.jsonl'].splitlines():
            self.assertEqual(json.loads(line)['plan_id'], PLAN)
        # Verify everything from a temporary copy with ssh-keygen and a recomputed anchor_sha256.
        with tempfile.TemporaryDirectory(prefix='e2e-export-') as tmp:
            copy_dir = Path(tmp)
            for name, data in files.items():
                target = copy_dir / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            self.assertEqual(sha((copy_dir / 'allowed_signers').read_bytes()), repo.anchor_sha256)
            if mode == 'prompt':
                tag_message = git(repo.work, 'cat-file', 'tag', result['tag'])
                digest_echo = [line for line in tag_message.split('\n') if line.startswith('digest-echo: ')][0]
                self.assertEqual(sha((copy_dir / 'approval.json').read_bytes()),
                                 digest_echo[len('digest-echo: '):])
            else:
                self.assertEqual(self.verify_from(copy_dir, 'approval.sig', 'approval.json', 'certifier@agent',
                                                  'ai-catapult-agent-approval'), 0)
            for gid in ('G1', 'G2', 'G3'):
                self.assertEqual(self.verify_from(copy_dir, 'certificates/%s.json.sig' % gid,
                                                  'certificates/%s.json' % gid, 'certifier@agent',
                                                  'ai-catapult-certificate'), 0)
                certificate = json.loads((copy_dir / ('certificates/%s.json' % gid)).read_bytes())
                self.assertEqual(certificate['assurance'], repo.assurance)
        # Idempotent on equal bytes; a tampered copy refuses with evidence_conflict.
        code, again, err = repo.export()
        self.assertEqual(code, 0, json.dumps(again, indent=1))
        self.assertEqual(again['files'], result['files'])
        tampered = directory / 'driver-log.jsonl'
        original = tampered.read_bytes()
        tampered.write_bytes(original + b'{}\n')
        try:
            code, conflict, err = repo.export()
            self.assertEqual(code, 1, json.dumps(conflict, indent=1))
            self.assertIn('evidence_conflict', codes(conflict))
        finally:
            tampered.write_bytes(original)
        repo.results['exports'].append(result)


class AuditMergesTests(Base):
    """AC1: re-observation of every fact through the production adapter and the detective
    control over landed changes (the S-02 residual)."""

    def test_direct_gh_merge_with_pending_checks_and_a_later_certificate_is_flagged(self):
        repo = self.agent_repo(chain='goal')  # a certified G1 provides the certificate template
        wt = repo.add_worktree('G2', 'feat/%s-G2' % PLAN)
        head = repo.implement_goal(wt, 'G2')
        repo.stub.knobs['pending_checks'] = ['Test Suite']
        merged_at = repo.clock.stamp()
        repo.stub.pr_merge(['3', '--squash', '--match-head-commit', head])
        repo.clock.tick()
        completed_at = repo.clock.stamp()
        repo.stub.pulls[3]['checks'] = [{'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success',
                                         'completed_at': completed_at}]
        repo.clock.tick()
        issued_at = repo.clock.stamp()
        # A valid-looking certificate re-signed with the certifier key, bound to the merged head.
        template = repo.results['certificates'][0]['certificate']
        body = dict(template, goal_id='G2', pr=3, head=head, issued_at=issued_at,
                    approval_digest=v2.canonical(repo.approval), assurance=repo.assurance)
        line = v2.canonical_bytes(body)
        path = repo.state_dir() / 'certificates' / PLAN / 'G2' / ('3-%s.json' % head)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(line)
        Path(str(path) + '.sig').write_text(ssh_sign(repo.keys.paths['certifier'], v2.NS_CERTIFICATE, line, repo.base))
        repo.fetch(repo.work)
        code, report, err = repo.audit()
        self.assertEqual(code, 1, json.dumps(report, indent=1))
        flags = codes(report)
        self.assertIn('check_completed_after_merge', flags)
        self.assertIn('certificate_issued_after_merge', flags)
        entry = next(e for e in report['prs'] if e['pr'] == 3)
        self.assertEqual(entry['merged_at'], merged_at)

    def test_approval_expired_before_merge_is_flagged(self):
        repo = self.new_repo('agent', 'repo')
        repo.publication_chain()
        repo.approval_chain(days=1)
        wt = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
        code, context, err = repo.admit(wt, 'G1')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head = repo.implement_goal(wt, 'G1')
        review = repo.review_record('G1', 2, head)
        code, out, err = repo.certify(wt, 'G1', 2, review)
        self.assertEqual(code, 0, (out, err))
        repo.clock.tick(minutes=24 * 60 + 2)  # past expires_at; merge-v2 would refuse
        repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work)
        code, report, err = repo.audit()
        self.assertEqual(code, 1, json.dumps(report, indent=1))
        self.assertIn('approval_expired_at_merge', codes(report))
        entry = next(e for e in report['prs'] if e['pr'] == 2)
        self.assertEqual(entry['approval_expires_at'], repo.approval['expires_at'])

    def residual_repo(self):
        """plan-e2e approved, G1 merged, G2 still active."""
        return self.agent_repo(chain='goal')

    def tidy_head(self, repo, branch='docs/tidy'):
        wt = repo.add_worktree('tidy', branch)
        (wt / 'src/g2.txt').write_text('touched outside any goal\n')
        (wt / 'README.md').write_text('tidy\n')
        git(wt, 'add', '-A')
        git(wt, 'commit', '-q', '-m', 'tidy docs and touch g2')
        return wt, git(wt, 'rev-parse', 'HEAD')

    def assert_scope_finding(self, code, report):
        self.assertEqual(code, 1, json.dumps(report, indent=1))
        finding = next((f for f in report['findings'] if f['code'] == 'v2_scope_outside_goal'), None)
        self.assertIsNotNone(finding, json.dumps(report, indent=1))
        self.assertIn('plan-e2e G2', finding['detail'])
        self.assertIn('src/g2.txt', finding['detail'])

    def test_v1_lane_merge_that_touched_active_scope_is_caught_fetch_failure(self):
        repo = self.residual_repo()
        wt, head = self.tidy_head(repo)
        git(repo.base, 'init', '-q', '--bare', str(repo.base / 'fork.git'))
        git(wt, 'push', '-q', str(repo.base / 'fork.git'), 'HEAD:refs/heads/docs/tidy')
        base_sha = git(wt, 'rev-parse', 'origin/main')
        repo.stub.register(head=head, head_ref='docs/tidy', base=base_sha, base_ref='main',
                           files=[{'filename': 'README.md', 'status': 'modified'}])
        repo.stub.knobs['unfetchable'] = [2]
        code, out, err = repo.merge(wt, 2, [])
        self.assertEqual(code, 10, (out, err))
        self.assertEqual(json.loads(out)['lane'], 'v1')
        self.assertIsNone(json.loads(out)['diff_head'])
        repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work, wt)
        code, report, err = repo.audit()
        self.assert_scope_finding(code, report)

    def test_v1_lane_merge_that_touched_active_scope_is_caught_aba(self):
        repo = self.residual_repo()
        wt, head = self.tidy_head(repo)
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/tidy')
        base_sha = git(wt, 'rev-parse', 'origin/main')
        # The hosted list is served for another head: README.md only, while the local head
        # carries src/g2.txt too. The pull reads return the real head before and after.
        repo.stub.register(head=head, head_ref='docs/tidy', base=base_sha, base_ref='main',
                           files=[{'filename': 'README.md', 'status': 'modified'}])
        code, out, err = repo.merge(wt, 2, [])
        self.assertEqual(code, 10, (out, err))
        self.assertEqual(json.loads(out)['diff_head'], head)
        repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work, wt)
        code, report, err = repo.audit()
        self.assert_scope_finding(code, report)

    def test_the_same_pr_merged_after_g2_completed_is_not_flagged(self):
        repo = self.residual_repo()
        wt2 = repo.add_worktree('G2', 'feat/%s-G2' % PLAN)
        code, context, err = repo.admit(wt2, 'G2')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head = repo.implement_goal(wt2, 'G2')
        review = repo.review_record('G2', 2, head)
        code, out, err = repo.certify(wt2, 'G2', 2, review)
        self.assertEqual(code, 0, (out, err))
        code, out, err = repo.merge(wt2, 2, ['--admin'])
        self.assertEqual(code, 0, (out, err))
        repo.fetch(repo.work, wt2)
        wt, head = self.tidy_head(repo)
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/tidy')
        base_sha = git(wt, 'rev-parse', 'origin/main')
        repo.stub.register(head=head, head_ref='docs/tidy', base=base_sha, base_ref='main',
                           files=repo.stub.diff_files(base_sha, head))
        repo.stub.pr_merge(['3', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work, wt)
        code, report, err = repo.audit()
        self.assertEqual(code, 0, json.dumps(report, indent=1))
        self.assertEqual([c['attribution'] for c in report['changes']], ['goal', 'goal', 'non-goal'])

    def test_control_file_touches_and_exceptions(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        repo.publication_chain()
        repo.approval_chain()
        number = [2]

        def land(branch, work_fn, files=None):
            wt = repo.add_worktree(branch.replace('/', '-'), branch)
            work_fn(wt)
            git(wt, 'add', '-A')
            git(wt, 'commit', '-q', '-m', branch)
            git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/%s' % branch)
            head = git(wt, 'rev-parse', 'HEAD')
            repo.fetch(wt)
            base_sha = git(wt, 'rev-parse', 'origin/main')
            pr = number[0]
            number[0] += 1
            repo.stub.register(head=head, head_ref=branch, base=base_sha, base_ref='main',
                               files=files if files is not None else repo.stub.diff_files(base_sha, head))
            repo.stub.pr_merge([str(pr), '--squash', '--match-head-commit', head])
            repo.fetch(repo.work, wt)
            return pr

        # (d) a replay-equal second-plan publication.
        def publish_plan_b(wt):
            bundle = e2e_bundle('agent')
            bundle['id'] = 'plan-b'
            bundle_path = write_json(repo.inputs / 'b-bundle.json', bundle)
            sidecar_path = write_json(repo.inputs / 'b-sidecar.json', sample_sidecar(bundle))
            code, out, err = repo.run_op(['publish-v2', '--root', str(wt), '--bundle', str(bundle_path),
                                          '--sidecar', str(sidecar_path)], env=repo.env())
            assert code == 0, (out, err)
        pr_b = land('docs/plan-b-publication', publish_plan_b)
        # (c) a sidecar-tighten change.
        def tighten(wt):
            path = wt / ('%s/%s/%s/sidecar.json' % (GEN, PLAN, repo.generation))
            sidecar = json.loads(path.read_text())
            sidecar['goals']['G1']['coverage_status'] = 'measured'
            sidecar['goals']['G1']['coverage_percent'] = 40
            path.write_text(json.dumps(sidecar, indent=2, sort_keys=True) + '\n')
        pr_tighten = land('docs/sidecar-tighten', tighten)
        # (e) a case-variant reserved path, written through git plumbing only (the tree never
        # materializes the case variant on a case-insensitive filesystem).
        def case_variant(wt):
            result = subprocess.run(['git', '-C', str(wt), 'hash-object', '-w', '--stdin'], input=b'{}\n',
                                    capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            blob = result.stdout.decode().strip()
            git(wt, 'update-index', '--add', '--cacheinfo', '100644,%s,.AI/Workflows/Northstar-Readiness-V2.json' % blob)
            tree = git(wt, 'write-tree')
            commit = git(wt, 'commit-tree', tree, '-p', 'HEAD', '-m', 'case variant')
            git(wt, 'reset', '-q', '--hard', commit)
        pr_variant = land('docs/case-variant', case_variant)
        # (f) a symlink under readiness-v2/.
        def symlink(wt):
            os.symlink('.', str(wt / '.ai/handoff/readiness-v2/link'))
        pr_symlink = land('docs/symlink', symlink)
        # (b) a policy file edit.
        def policy_edit(wt):
            (wt / POLICY).write_text('{}\n')
        pr_policy = land('docs/policy-edit', policy_edit)
        # (a) a registry hand edit: a new bogus active entry the replay never produces.
        def registry_edit(wt):
            registry = json.loads((wt / REGISTRY).read_text())
            registry['plans'].append({'id': 'northstar-plan-bogus', 'plan_id': 'bogus',
                                      'generation': '0' * 64, 'status': 'active', 'artifacts': {}})
            (wt / REGISTRY).write_text(json.dumps(registry, indent=2, sort_keys=True) + '\n')
        pr_registry = land('docs/registry-edit', registry_edit)
        code, report, err = repo.audit()
        self.assertEqual(code, 1, json.dumps(report, indent=1))
        by_pr = {c['pr']: c for c in report['changes']}
        self.assertEqual(by_pr[pr_tighten]['lane'], 'sidecar-tighten')
        self.assertEqual(by_pr[pr_tighten]['flags'], [])
        self.assertEqual(by_pr[pr_b]['lane'], 'publish-v2-replay')
        self.assertEqual(by_pr[pr_b]['flags'], [])
        flagged = {f['code'] for f in report['findings']}
        self.assertEqual(flagged, {'v2_scope_outside_goal'})
        details = ' '.join(f['detail'] for f in report['findings'])
        self.assertIn('case-variant', details)
        self.assertIn('symlink', details)
        self.assertIn('policy-edit', details)
        self.assertIn('registry-edit', details)
        self.assertNotIn('sidecar-tighten', details)
        self.assertNotIn('plan-b-publication', details)

    def test_replacement_is_judged_as_of_the_replacing_merge(self):
        for open_before in (True, False):
            with self.subTest(open_before=open_before):
                base = self.base / ('repl-%s' % open_before)
                base.mkdir()
                repo = E2ERepo(base, 'agent')
                repo.publication_chain()
                repo.approval_chain()
                # Plan-b is published (a second plan in the same repo) and merged.
                bundle = e2e_bundle('agent')
                bundle['id'] = 'plan-b'
                sidecar = sample_sidecar(bundle)
                bundle_path = write_json(repo.inputs / 'b-bundle.json', bundle)
                sidecar_path = write_json(repo.inputs / 'b-sidecar.json', sidecar)
                wt = repo.add_worktree('bpub', 'docs/plan-b-publication')
                code, out, err = repo.run_op(['publish-v2', '--root', str(wt), '--bundle', str(bundle_path),
                                              '--sidecar', str(sidecar_path)], env=repo.env())
                self.assertEqual(code, 0, (out, err))
                git(wt, 'add', '-A')
                git(wt, 'commit', '-q', '-m', 'publish plan-b')
                git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/plan-b-publication')
                head = git(wt, 'rev-parse', 'HEAD')
                repo.fetch(wt)
                base_sha = git(wt, 'rev-parse', 'origin/main')
                repo.stub.register(head=head, head_ref='docs/plan-b-publication', base=base_sha, base_ref='main',
                                   files=repo.stub.diff_files(base_sha, head))
                repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
                repo.fetch(repo.work, wt)
                if open_before:
                    # Goal PR #b1 open from T1, before the replacement merges.
                    repo.stub.register(head=head, head_ref='feat/plan-b-B1',
                                       base=git(repo.work, 'rev-parse', 'origin/main'), base_ref='main',
                                       files=[{'filename': 'src/b1.txt', 'status': 'modified'}], state='open')
                # A replay PR replaces plan-b's entry at T2.
                edited = copy.deepcopy(bundle)
                edited['goals'][0]['acceptance_criteria'].append('an AC edit republishes the generation')
                bundle2_path = write_json(repo.inputs / 'b2-bundle.json', edited)
                sidecar2_path = write_json(repo.inputs / 'b2-sidecar.json', sample_sidecar(edited))
                wt2 = repo.add_worktree('brepl', 'docs/plan-b-republish')
                code, out, err = repo.run_op(['publish-v2', '--root', str(wt2), '--bundle', str(bundle2_path),
                                              '--sidecar', str(sidecar2_path)], env=repo.env())
                self.assertEqual(code, 0, (out, err))
                git(wt2, 'add', '-A')
                git(wt2, 'commit', '-q', '-m', 'republish plan-b')
                git(wt2, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/plan-b-republish')
                head2 = git(wt2, 'rev-parse', 'HEAD')
                repo.fetch(wt2)
                base2 = git(wt2, 'rev-parse', 'origin/main')
                repo.stub.register(head=head2, head_ref='docs/plan-b-republish', base=base2, base_ref='main',
                                   files=repo.stub.diff_files(base2, head2))
                repo.stub.pr_merge(['3', '--squash', '--match-head-commit', head2])
                repo.fetch(repo.work, wt2)
                if not open_before:
                    # #b1 opens only after T2: goal_branch_prs(open) is non-empty now, but the
                    # replacement was not busy as of its merge.
                    repo.stub.register(head=head, head_ref='feat/plan-b-B1',
                                       base=git(repo.work, 'rev-parse', 'origin/main'), base_ref='main',
                                       files=[{'filename': 'src/b1.txt', 'status': 'modified'}], state='open')
                code, report, err = repo.audit()
                findings = [f for f in report['findings'] if f['code'] == 'v2_scope_outside_goal']
                if open_before:
                    self.assertEqual(code, 1, json.dumps(report, indent=1))
                    self.assertTrue(findings, json.dumps(report, indent=1))
                    self.assertIn('plan-b', findings[0]['detail'])
                else:
                    self.assertEqual(code, 0, json.dumps(report, indent=1))
                    self.assertEqual(findings, [])

    def test_planning_inputs_and_audit_branch_not_flagged(self):
        repo = self.agent_repo()
        paths = ['.ai/traceability/graph.json', 'docs/specifications/ACTIVE/plan.md',
                 '.ai/ci/local-ci.json', '.ai/handoff/%s-plan-approval-request.json' % PLAN,
                 '.ai/handoff/%s-plan-approval.md' % PLAN, '.ai/host-policy/audit.jsonl']
        wt = repo.add_worktree('free', 'docs/free-paths')
        for name in paths:
            path = wt / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('{}\n' if name.endswith('.json') else 'x\n')
        git(wt, 'add', '-A')
        git(wt, 'commit', '-q', '-m', 'planning inputs and audit log')
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/free-paths')
        head = git(wt, 'rev-parse', 'HEAD')
        repo.fetch(wt)
        base_sha = git(wt, 'rev-parse', 'origin/main')
        repo.stub.register(head=head, head_ref='docs/free-paths', base=base_sha, base_ref='main',
                           files=repo.stub.diff_files(base_sha, head))
        repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work, wt)
        code, report, err = repo.audit()
        self.assertEqual(code, 0, json.dumps(report, indent=1))
        change = next(c for c in report['changes'] if c['pr'] == 2)
        self.assertEqual(change['flags'], [])
        self.assertEqual(change['lane'], 'none')

    def test_resign_noise_is_a_notice(self):
        repo = self.agent_repo()
        wt1 = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
        code, context, err = repo.admit(wt1, 'G1')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head1 = repo.implement_goal(wt1, 'G1')
        review = repo.review_record('G1', 2, head1)
        code, out, err = repo.certify(wt1, 'G1', 2, review)
        self.assertEqual(code, 0, (out, err))
        code, out, err = repo.merge(wt1, 2, ['--admin'])
        self.assertEqual(code, 0, (out, err))
        repo.fetch(repo.work, wt1)
        # G2 is certified under A but merged only after the re-sign B.
        wt2 = repo.add_worktree('G2', 'feat/%s-G2' % PLAN)
        code, context, err = repo.admit(wt2, 'G2')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head2 = repo.implement_goal(wt2, 'G2')
        review2 = repo.review_record('G2', 3, head2)
        code, out, err = repo.certify(wt2, 'G2', 3, review2)
        self.assertEqual(code, 0, (out, err))
        # Re-sign the same generation (B, later issued_at): the same tag, a new record.
        repo.clock.tick(minutes=30)
        code, out, err = repo.run_op(['approval-request', '--root', str(repo.work), '--handoff', HANDOFF,
                                      '--mode', 'default', '--owner', 'Fixture Owner', '--reviewer-lane', LANE],
                                     env=repo.env())
        self.assertEqual(code, 0, (out, err))
        message = json.loads(out)['message']
        repo.tag_and_push(message, 'approval/%s/%s' % (PLAN, repo.generation[:12]), repo.publication)
        code, out, err = repo.merge(wt2, 3, ['--admin'])
        self.assertEqual(code, 0, (out, err))
        repo.fetch(repo.work, wt2)
        code, report, err = repo.audit()
        self.assertEqual(code, 1, json.dumps(report, indent=1))
        by_pr = {entry['pr']: entry for entry in report['prs']}
        self.assertIn('approval_resigned', [n['code'] for n in by_pr[2]['notices']])
        self.assertNotIn('approval_digest_unobserved', by_pr[2]['flags'])
        self.assertIn('approval_digest_unobserved', by_pr[3]['flags'])
        self.assertEqual([f['code'] for f in report['findings']], ['approval_digest_unobserved'])

    def test_frozen_audit_cases_unchanged(self):
        result = subprocess.run(['python3', '-B', str(REPO / 'tests/readiness_v2_certificate_test.py'),
                                 'AuditReobservationTests'], capture_output=True, text=True, cwd=REPO,
                                stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


class ExportEvidenceTests(Base):
    """AC2 refusals: incomplete evidence and a wrong anchor fail closed."""

    def test_export_refuses_incomplete_and_wrong_anchor(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        repo.publication_chain()
        repo.approval_chain()
        wt = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
        code, context, err = repo.admit(wt, 'G1')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head = repo.implement_goal(wt, 'G1')
        review = repo.review_record('G1', 2, head)
        code, out, err = repo.certify(wt, 'G1', 2, review)
        self.assertEqual(code, 0, (out, err))
        code, out, err = repo.merge(wt, 2, ['--admin'])
        self.assertEqual(code, 0, (out, err))
        repo.fetch(repo.work, wt)
        # Delete the certificate signature: the merged goal lacks a verifying certificate.
        path = repo.state_dir() / 'certificates' / PLAN / 'G1' / ('2-%s.json.sig' % head)
        path.unlink()
        code, result, err = repo.export()
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('evidence_incomplete', codes(result))
        self.assertFalse((repo.work / '.ai/evidence/approvals' / PLAN).exists())
        # A different anchor refuses with anchor_digest_mismatch.
        foreign = repo.keys.dir / 'foreign-anchor'
        foreign.write_text('certifier@agent namespaces="ai-catapult-review,ai-catapult-certificate" %s\n'
                           % repo.keys.public('certifier'))
        code, result, err = repo.run_op(['export-evidence', '--root', str(repo.work), '--plan', PLAN],
                                        env=repo.env(), anchor=foreign)
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('anchor_digest_mismatch', codes(result))


class NegativeListTests(Base):
    """AC4: the full negative list, each refused with a distinct code."""

    fixtures = {}

    @classmethod
    def setUpClass(cls):
        cls.base = Path(tempfile.mkdtemp(prefix='e2e-negative-')).resolve()
        with offline():
            # Prompt pre-built: bootstrap published, approved, and G1 (the policy goal) merged.
            prompt = E2ERepo(cls.base / 'prompt', 'prompt')
            prompt.publication_chain()
            prompt.approval_chain()
            wt = prompt.add_worktree('G1', 'feat/%s-G1' % PLAN)
            code, context, err = prompt.admit(wt, 'G1')
            assert code == 0, json.dumps(context, indent=1)
            head = prompt.implement_goal(wt, 'G1')
            review = prompt.review_record('G1', 2, head)
            code, out, err = prompt.certify(wt, 'G1', 2, review)
            assert code == 0, (out, err)
            code, out, err = prompt.merge(wt, 2, ['--admin'])
            assert code == 0, (out, err)
            prompt.fetch(prompt.work, wt)
            cls.fixtures['prompt'] = prompt
            # Agent pre-built: live policy, published, approved, G1 implemented on its branch.
            agent = E2ERepo(cls.base / 'agent', 'agent')
            agent.publication_chain()
            agent.approval_chain()
            wt = agent.add_worktree('G1', 'feat/%s-G1' % PLAN)
            code, context, err = agent.admit(wt, 'G1')
            assert code == 0, json.dumps(context, indent=1)
            agent.head = agent.implement_goal(wt, 'G1')
            cls.fixtures['agent'] = agent

    def copy_of(self, mode, name):
        source = self.fixtures[mode]
        target = self.base / name
        shutil.copytree(str(source.base), str(target))
        work = target / 'work'
        git(work, 'remote', 'set-url', 'origin', str(target / 'origin.git'))
        git(work, 'fetch', '-q', '--tags', 'origin')
        repo = E2ERepo.__new__(E2ERepo)
        repo.base = target
        repo.mode = mode
        repo.keys = source.keys
        repo.anchor_sha256 = source.anchor_sha256
        repo.clock = source.clock
        repo.counters = source.counters
        repo.inputs = source.inputs
        repo.origin = target / 'origin.git'
        repo.work = work
        repo.bundle = source.bundle
        repo.sidecar = source.sidecar
        repo.policy = source.policy
        repo.candidate_path = source.candidate_path
        repo.bundle_path = source.bundle_path
        repo.sidecar_path = source.sidecar_path
        repo.bin = source.bin
        repo.generation = source.generation
        repo.publication = source.publication
        repo.approval = source.approval
        repo.assurance = source.assurance
        repo.results = {'admissions': [], 'certificates': [], 'merges': [], 'audits': [], 'exports': []}
        stub = HostStub(repo)
        stub.restore(source.stub.snapshot(), repo)
        repo.stub = stub
        return repo

    def record(self, repo, **overrides):
        return dict(repo.approval, **overrides)

    def ssh_tag(self, repo, record, key='approver', namespace=None):
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        signature = ssh_sign(repo.keys.paths[key], namespace or v2.NS_APPROVAL, line.encode(), repo.base)
        return line + '\nsignature: ' + base64.b64encode(signature.encode()).decode() + '\n'

    def in_session(self, record):
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        return line + '\ndigest-echo: ' + sha(line.encode()) + '\n'

    def cases(self):
        return [
            ('forged signature', 'prompt', self.case_forged_signature, 'approval_signature_invalid'),
            ('agent-namespace signature on a human approval', 'prompt', self.case_agent_namespace,
             'approval_signer_not_approver'),
            ('agent-self tag while accept omits agent-self', 'prompt', self.case_agent_self_not_accepted,
             'agent_self_not_accepted'),
            ('agent-self signed by a principal without the approval role', 'agent', self.case_agent_signer_role,
             'agent_approval_signer_not_agent'),
            ('agent-self of the bootstrap generation', 'prompt', self.case_bootstrap_agent_self,
             'agent_self_bootstrap_refused'),
            ('expired approval', 'prompt', self.case_expired, 'approval_expired'),
            ('digest-changed approval', 'prompt', self.case_digest_changed, 'approval_bundle_mismatch'),
            ('agent-written context', 'prompt', self.case_supplied_context, 'supplied_context_mismatch'),
            ('agent-written verdict', 'prompt', self.case_supplied_verdict, 'supplied_verdict_mismatch'),
            ('forged agent-signed certificate', 'agent', self.case_forged_certificate, 'certificate_claim_mismatch'),
            ('moved head', 'agent', self.case_moved_head, 'head_moved'),
            ('pending check', 'agent', self.case_pending_check, 'check_pending'),
            ('unlisted SKIPPED check', 'agent', self.case_skipped_unlisted, 'check_skipped_unlisted'),
            ('unresolved thread', 'agent', self.case_unresolved_thread, 'unresolved_threads'),
            ('missing review lane', 'agent', self.case_missing_review, 'review_lane_missing'),
            ('self-review-only admin merge', 'agent', self.case_self_review, 'review_lane_not_independent'),
            ('anchor inside a worktree', 'prompt', self.case_anchor_in_worktree, 'anchor_inside_worktree'),
            ('proceed text or flag', 'prompt', self.case_proceed, 'usage'),
        ]

    def test_each_negative_refuses_with_its_own_code(self):
        observed = {}
        for name, mode, case, expected in self.cases():
            with self.subTest(name=name):
                code_text = case(self.copy_of(mode, name.replace(' ', '-')))
                self.assertEqual(code_text, expected, (name, code_text))
                observed.setdefault(expected, []).append(name)
        self.assertEqual(len(observed), len(self.cases()), observed)

    def admit_g1(self, repo, extra=()):
        code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', HANDOFF, '--goal-id', 'G1',
                                      '--stage', 'implementation', *extra], env=repo.env())
        return codes(json.loads(out))

    def case_forged_signature(self, repo):
        record = self.record(repo, assurance='key-held')
        repo.tag_and_push(self.ssh_tag(repo, record, key='outsider'),
                          'approval/%s/%s' % (PLAN, repo.generation[:12]), repo.publication)
        self.assertIn('approval_signature_invalid', self.admit_g1(repo))
        return 'approval_signature_invalid'

    def case_agent_namespace(self, repo):
        record = self.record(repo, assurance='key-held')
        repo.tag_and_push(self.ssh_tag(repo, record, key='certifier'),
                          'approval/%s/%s' % (PLAN, repo.generation[:12]), repo.publication)
        self.assertIn('approval_signer_not_approver', self.admit_g1(repo))
        return 'approval_signer_not_approver'

    def case_agent_self_not_accepted(self, repo):
        # The bootstrap policy is live now (G1 merged): plan-b is a live-mode plan whose
        # policy omits agent-self; an agent-mode approval request refuses.
        bundle = e2e_bundle('agent')
        bundle['id'] = 'plan-b'
        bundle_path = write_json(repo.inputs / 'b-bundle.json', bundle)
        sidecar_path = write_json(repo.inputs / 'b-sidecar.json', sample_sidecar(bundle))
        code, out, err = repo.run_op(['publish-v2', '--root', str(repo.work), '--bundle', str(bundle_path),
                                      '--sidecar', str(sidecar_path)], env=repo.env())
        self.assertEqual(code, 0, (out, err))
        git(repo.work, 'add', '-A')
        git(repo.work, 'commit', '-q', '-m', 'publish plan-b')
        git(repo.work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(repo.work, 'fetch', '-q', 'origin')
        code, out, err = repo.run_op(['approval-request', '--root', str(repo.work), '--handoff', 'northstar-plan-plan-b',
                                      '--mode', 'default', '--owner', 'Owner', '--reviewer-lane', LANE], env=repo.env())
        self.assertEqual(code, 1, (out, err))
        self.assertIn('agent_self_not_accepted', codes(json.loads(out)))
        return 'agent_self_not_accepted'

    def case_agent_signer_role(self, repo):
        code, out, err = repo.run_op(['approval-request', '--root', str(repo.work), '--handoff', HANDOFF,
                                      '--mode', 'default', '--owner', 'Owner', '--reviewer-lane', LANE],
                                     env=repo.env(), key='reviewer')
        self.assertEqual(code, 1, (out, err))
        self.assertIn('agent_approval_signer_not_agent', codes(json.loads(out)))
        return 'agent_approval_signer_not_agent'

    def case_bootstrap_agent_self(self, repo):
        code, out, err = repo.run_op(['approval-request', '--root', str(repo.work), '--handoff', HANDOFF,
                                      '--mode', 'default', '--owner', 'Owner', '--reviewer-lane', LANE], env=repo.env())
        self.assertEqual(code, 1, (out, err))
        self.assertIn('agent_self_bootstrap_refused', codes(json.loads(out)))
        return 'agent_self_bootstrap_refused'

    def case_expired(self, repo):
        record = self.record(repo, issued_at=stamp(NOW - timedelta(days=2)),
                             expires_at=stamp(NOW - timedelta(days=1)))
        repo.tag_and_push(self.in_session(record), 'approval/%s/%s' % (PLAN, repo.generation[:12]),
                          repo.publication)
        self.assertIn('approval_expired', self.admit_g1(repo))
        return 'approval_expired'

    def case_digest_changed(self, repo):
        record = self.record(repo, bundle_sha256='0' * 64)
        repo.tag_and_push(self.in_session(record), 'approval/%s/%s' % (PLAN, repo.generation[:12]),
                          repo.publication)
        self.assertIn('approval_bundle_mismatch', self.admit_g1(repo))
        return 'approval_bundle_mismatch'

    def case_supplied_context(self, repo):
        forged = write_json(repo.inputs / 'forged-context.json', {'admitted': True, 'gaps': []})
        self.assertIn('supplied_context_mismatch', self.admit_g1(repo, ['--context', str(forged)]))
        return 'supplied_context_mismatch'

    def case_supplied_verdict(self, repo):
        forged = write_json(repo.inputs / 'forged-verdict.json', {'admitted': True, 'gaps': []})
        self.assertIn('supplied_verdict_mismatch', self.admit_g1(repo, ['--verdict', str(forged)]))
        return 'supplied_verdict_mismatch'

    def certify_on(self, repo, review=True, key='reviewer'):
        review_path = repo.review_record('G1', 2, repo.stub.pulls[2]['head']['sha'], key=key) if review else None
        code, out, err = repo.certify(repo.work, 'G1', 2, review_path)
        return code, json.loads(out)

    def case_forged_certificate(self, repo):
        code, issued = self.certify_on(repo)
        self.assertEqual(code, 0, json.dumps(issued, indent=1))
        repo.stub.pulls[2]['threads'] = [{'isResolved': False}]
        stored = Path(issued['path'])
        body = json.loads(stored.read_text())
        line = v2.canonical_bytes(body)
        Path(str(stored) + '.sig').write_text(ssh_sign(repo.keys.paths['certifier'], v2.NS_CERTIFICATE, line, repo.base))
        code, out, err = repo.merge(repo.work, 2, [])
        self.assertEqual(code, 4, (out, err))
        self.assertIn('certificate_claim_mismatch', codes(json.loads(out)))
        return 'certificate_claim_mismatch'

    def case_moved_head(self, repo):
        code, issued = self.certify_on(repo)
        self.assertEqual(code, 0, json.dumps(issued, indent=1))
        git(repo.work, 'commit', '-q', '--allow-empty', '-m', 'move the head')
        code, out, err = repo.merge(repo.work, 2, [])
        self.assertEqual(code, 4, (out, err))
        self.assertIn('head_moved', codes(json.loads(out)))
        return 'head_moved'

    def case_pending_check(self, repo):
        repo.stub.knobs['pending_checks'] = ['Test Suite']
        code, result = self.certify_on(repo)
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('check_pending', codes(result))
        return 'check_pending'

    def case_skipped_unlisted(self, repo):
        repo.stub.pulls[2]['checks'] = [{'name': 'Test Suite', 'status': 'completed', 'conclusion': 'skipped',
                                         'completed_at': repo.clock.stamp()}]
        code, result = self.certify_on(repo)
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('check_skipped_unlisted', codes(result))
        return 'check_skipped_unlisted'

    def case_unresolved_thread(self, repo):
        repo.stub.pulls[2]['threads'] = [{'isResolved': False}]
        code, result = self.certify_on(repo)
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('unresolved_threads', codes(result))
        return 'unresolved_threads'

    def case_missing_review(self, repo):
        code, result = self.certify_on(repo, review=False)
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('review_lane_missing', codes(result))
        return 'review_lane_missing'

    def case_self_review(self, repo):
        code, result = self.certify_on(repo, key='certifier')
        self.assertEqual(code, 1, json.dumps(result, indent=1))
        self.assertIn('review_lane_not_independent', codes(result))
        return 'review_lane_not_independent'

    def case_anchor_in_worktree(self, repo):
        inside = repo.work / 'anchor-inside'
        inside.write_text(repo.keys.anchor.read_text())
        code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', HANDOFF, '--goal-id', 'G1',
                                      '--stage', 'implementation'], env=repo.env(), anchor=inside)
        self.assertEqual(code, 1, (out, err))
        self.assertIn('anchor_inside_worktree', codes(json.loads(out)))
        return 'anchor_inside_worktree'

    def case_proceed(self, repo):
        operations = ('admit-v2', 'publish-v2', 'approval-request', 'certify-v2', 'merge-v2', 'audit-merges',
                      'export-evidence', 'context-build', 'inventory-v1')
        for operation in operations:
            for extra in (['proceed'], ['override'], ['--force'], ['--admin', 'if', 'necessary'], ['-h'], ['--help']):
                code, out, err = repo.run_op([operation, *extra], env=repo.env())
                self.assertEqual(code, 2, (operation, extra, out, err))
                self.assertIn('usage', codes(json.loads(out)))
        return 'usage'


class EdgeCaseTests(Base):
    """AC5: the 12-character generation prefix, and an approval expiring between issue and merge."""

    def test_shared_12_character_prefix_plans_get_distinct_approval_tags(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        real_generation = v2.generation_v2
        publications = {}

        def approve(plan_id):
            code, out, err = repo.run_op(['approval-request', '--root', str(repo.work),
                                          '--handoff', 'northstar-plan-' + plan_id, '--mode', 'ssh-tag',
                                          '--owner', 'Owner', '--reviewer-lane', LANE], env=repo.env())
            self.assertEqual(code, 0, (out, err))
            request = json.loads(out)
            self.assertEqual(request['tag'], 'approval/%s/abcdefabcdef' % plan_id)
            line = json.dumps(request['record'], sort_keys=True, separators=(',', ':'))
            signature = ssh_sign(repo.keys.paths['approver'], v2.NS_APPROVAL, line.encode(), repo.base)
            message = line + '\nsignature: ' + base64.b64encode(signature.encode()).decode() + '\n'
            repo.tag_and_push(message, request['tag'], publications[plan_id])
            return message

        with mock.patch.object(v2, 'generation_v2', lambda **kwargs: 'abcdefabcdef' + real_generation(**kwargs)[12:]):
            for plan_id in ('plan-x', 'plan-y'):
                bundle = e2e_bundle('agent')
                bundle['id'] = plan_id
                bundle_path = write_json(repo.inputs / ('%s-bundle.json' % plan_id), bundle)
                sidecar_path = write_json(repo.inputs / ('%s-sidecar.json' % plan_id), sample_sidecar(bundle))
                code, out, err = repo.run_op(['publish-v2', '--root', str(repo.work), '--bundle', str(bundle_path),
                                              '--sidecar', str(sidecar_path)], env=repo.env())
                self.assertEqual(code, 0, (out, err))
                git(repo.work, 'add', '-A')
                git(repo.work, 'commit', '-q', '-m', 'publish ' + plan_id)
                git(repo.work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
                git(repo.work, 'fetch', '-q', 'origin')
                publications[plan_id] = git(repo.work, 'log', '-1', '--format=%H', 'origin/main', '--',
                                            '%s/%s' % (GEN, plan_id))
            plan_x_message = approve('plan-x')
            # The tags share the 12-character prefix but are distinct refs.
            for plan_id in ('plan-x', 'plan-y'):
                ref = 'refs/tags/approval/%s/abcdefabcdef' % plan_id
                listed = git(repo.work, 'ls-remote', 'origin', ref).split()
                self.assertEqual(len(listed), 2, listed)
            # plan-y admits only with its own tag: plan-x's tag alone is missing.
            code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', 'northstar-plan-plan-y',
                                          '--goal-id', 'G1', '--stage', 'implementation'], env=repo.env())
            self.assertEqual(code, 1, (out, err))
            self.assertIn('approval_tag_missing', codes(json.loads(out)))
            # plan-y's own tag admits; plan-x's message pushed as plan-y's tag refuses.
            approve('plan-y')
            code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', 'northstar-plan-plan-y',
                                          '--goal-id', 'G1', '--stage', 'implementation'], env=repo.env())
            self.assertEqual(code, 0, json.dumps(json.loads(out), indent=1))
            repo.tag_and_push(plan_x_message, 'approval/plan-y/abcdefabcdef', publications['plan-y'])
            code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', 'northstar-plan-plan-y',
                                          '--goal-id', 'G1', '--stage', 'implementation'], env=repo.env())
            self.assertEqual(code, 1, (out, err))
            self.assertIn('approval_plan_mismatch', codes(json.loads(out)))

    def test_an_approval_expiring_between_certificate_issue_and_merge_is_refused_at_merge(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        repo.publication_chain()
        repo.approval_chain(days=1)
        wt = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
        code, context, err = repo.admit(wt, 'G1')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        head = repo.implement_goal(wt, 'G1')
        review = repo.review_record('G1', 2, head)
        repo.clock.tick(minutes=23 * 60)  # expires_at - 1h
        code, out, err = repo.certify(wt, 'G1', 2, review)
        self.assertEqual(code, 0, (out, err))
        repo.clock.tick(minutes=61)  # expires_at + 1m
        code, out, err = repo.merge(wt, 2, ['--admin'])
        self.assertEqual(code, 4, (out, err))
        self.assertIn('approval_expired', codes(json.loads(out)))


class AcceptanceInContextTests(Base):
    """AC6: the freeze test and the AC-3..AC-7 checks in the e2e context, offline, plus the O8 note."""

    def test_ac3_freeze_test_passes_offline(self):
        result = subprocess.run(['bash', str(REPO / 'tests/readiness_v1_freeze_test.sh')], capture_output=True,
                                text=True, cwd=REPO, stdin=subprocess.DEVNULL)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_ac4_sidecar_tighten_and_an_ac_edit_republish(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        repo.publication_chain()
        repo.approval_chain()
        # A sidecar-tighten PR merges through the v1 lane and admission stays green.
        wt = repo.add_worktree('tighten', 'docs/sidecar-tighten')
        sidecar_path = wt / ('%s/%s/%s/sidecar.json' % (GEN, PLAN, repo.generation))
        sidecar = json.loads(sidecar_path.read_text())
        sidecar['goals']['G1']['coverage_status'] = 'measured'
        sidecar['goals']['G1']['coverage_percent'] = 40
        sidecar_path.write_text(json.dumps(sidecar, indent=2, sort_keys=True) + '\n')
        git(wt, 'add', '-A')
        git(wt, 'commit', '-q', '-m', 'tighten the sidecar')
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/sidecar-tighten')
        head = git(wt, 'rev-parse', 'HEAD')
        repo.fetch(wt)
        base_sha = git(wt, 'rev-parse', 'origin/main')
        repo.stub.register(head=head, head_ref='docs/sidecar-tighten', base=base_sha, base_ref='main',
                           files=repo.stub.diff_files(base_sha, head))
        code, out, err = repo.merge(wt, 2, [])
        self.assertEqual(code, 10, (out, err))
        self.assertEqual(json.loads(out)['lane'], 'sidecar-tighten')
        repo.stub.pr_merge(['2', '--squash', '--match-head-commit', head])
        repo.fetch(repo.work, wt)
        wt1 = repo.add_worktree('G1', 'feat/%s-G1' % PLAN)
        code, context, err = repo.admit(wt1, 'G1')
        self.assertEqual(code, 0, json.dumps(context, indent=1))
        # An AC text edit republishes a new generation; the old tag no longer admits it.
        edited = copy.deepcopy(repo.bundle)
        edited['goals'][0]['acceptance_criteria'].append('an AC edit republishes the generation')
        bundle_path = write_json(repo.inputs / 'edited-bundle.json', edited)
        sidecar_path = write_json(repo.inputs / 'edited-sidecar.json', sample_sidecar(edited))
        code, out, err = repo.run_op(['publish-v2', '--root', str(repo.work), '--bundle', str(bundle_path),
                                      '--sidecar', str(sidecar_path)], env=repo.env())
        self.assertEqual(code, 0, (out, err))
        git(repo.work, 'add', '-A')
        git(repo.work, 'commit', '-q', '-m', 'republish after the AC edit')
        git(repo.work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(repo.work, 'fetch', '-q', 'origin')
        code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', HANDOFF, '--goal-id', 'G1',
                                      '--stage', 'implementation'], env=repo.env())
        self.assertEqual(code, 1, (out, err))
        self.assertIn('approval_tag_missing', codes(json.loads(out)))

    def test_ac5_a_second_plan_admits_interleaved_with_a_constant_policy(self):
        base = self.base / 'repo'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        repo.publication_chain()
        repo.approval_chain()
        bundle = e2e_bundle('agent')
        bundle['id'] = 'plan-b'
        bundle_path = write_json(repo.inputs / 'b-bundle.json', bundle)
        sidecar_path = write_json(repo.inputs / 'b-sidecar.json', sample_sidecar(bundle))
        code, out, err = repo.run_op(['publish-v2', '--root', str(repo.work), '--bundle', str(bundle_path),
                                      '--sidecar', str(sidecar_path)], env=repo.env())
        self.assertEqual(code, 0, (out, err))
        generation_b = json.loads(out)['published']['generation']
        git(repo.work, 'add', '-A')
        git(repo.work, 'commit', '-q', '-m', 'publish plan-b')
        git(repo.work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(repo.work, 'fetch', '-q', 'origin')
        code, out, err = repo.run_op(['approval-request', '--root', str(repo.work), '--handoff', 'northstar-plan-plan-b',
                                      '--mode', 'default', '--owner', 'Owner', '--reviewer-lane', LANE], env=repo.env())
        self.assertEqual(code, 0, (out, err))
        message = json.loads(out)['message']
        publication_b = git(repo.work, 'log', '-1', '--format=%H', 'origin/main', '--', '%s/plan-b' % GEN)
        repo.tag_and_push(message, 'approval/plan-b/' + generation_b[:12], publication_b)
        # Interleaved admissions of both plans; the live policy sha stays constant.
        policy_sha = sha(git(repo.work, 'show', 'origin/main:' + POLICY, check=False).encode())
        for handoff, goal, expected in (('northstar-plan-plan-e2e', 'G1', 0), ('northstar-plan-plan-b', 'G1', 0),
                                        ('northstar-plan-plan-e2e', 'G2', 1), ('northstar-plan-plan-b', 'G2', 1)):
            code, out, err = repo.run_op(['admit-v2', '--root', str(repo.work), '--handoff', handoff, '--goal-id', goal,
                                          '--stage', 'implementation'], env=repo.env())
            self.assertEqual(code, expected, (handoff, goal, out, err))
            self.assertEqual(sha(git(repo.work, 'show', 'origin/main:' + POLICY, check=False).encode()), policy_sha)

    def test_ac7_blocking_planning_refuses_when_a_tool_is_missing(self):
        base = self.base / 'blocked'
        base.mkdir()
        repo = E2ERepo(base, 'agent')
        wt = repo.add_worktree('pub', 'docs/%s-publication' % PLAN)
        argv = ['publish-v2', '--root', str(wt), '--bundle', str(repo.bundle_path), '--sidecar', str(repo.sidecar_path),
                '--admit-planning']
        code, out, err = repo.run_op(argv, env={})  # PATH without the e2e-tool stub
        self.assertEqual(code, 1, (out, err))
        result = json.loads(out)
        self.assertFalse(result['planning_complete'])
        self.assertIn('tool_missing', {g['code'] for g in result['planning']['blocking']})
        self.assertIn('planning_incomplete', codes(result))
        self.assertFalse((wt / REGISTRY).exists())

    def test_o8_release_is_documented(self):
        text = ' '.join((REPO / '04-validate-handoff/autobahn/modules/readiness-v2.md').read_text().split())
        self.assertIn("ACH-S-06's merge commit on skills main is the O8 release", text)
        self.assertIn('dependent plans check it by git merge-base --is-ancestor', text)


if __name__ == '__main__':
    unittest.main()
