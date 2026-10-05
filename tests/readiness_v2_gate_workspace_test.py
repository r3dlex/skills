"""ACH-S-07 (D1 gate workspace): certify-v2 and merge-v2 run the four local gates only in an
observer-built gate workspace — a disposable repository under the observed root's parent (a
sibling of the observed root, never inside it), borrowing the observed repository's objects
read-only through objects/info/alternates, with no remote and no hooks, checked out at the PR
head. The observed root keeps every existing check unchanged, the workspace's HEAD/index/files
are re-checked after every gate, a gate's git reaches only the workspace, the observed git
metadata is snapshotted around the gates, the target is resolved once before the gates, every
gate path is physical, digests are streamed, run-gates.sh's v2 branch turns bytecode off, and
the certificate gains exactly one field, gate_workspace. Disposable repositories, a recording
`gh` stand-in found through PATH, and ephemeral agent keys only."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
from readiness_v2_core_test import AUTO, Fixture, codes, git, sha, v2, observer, write_json
from readiness_v2_certificate_test import BRANCH, PR, CertificateFixture
from readiness_v2_identity_test import HANDOFF, driver_copy

REPO = Path(__file__).resolve().parents[1]


def metadata_bytes(common):
    """The observed common directory's config, hooks/, info/ and objects/info/alternates bytes."""
    snapshot = {}
    for rel in ('config', 'hooks', 'info', 'objects/info/alternates'):
        path = Path(common) / rel
        if path.is_dir():
            for entry in sorted(path.rglob('*')):
                if entry.is_file() or entry.is_symlink():
                    snapshot['%s/%s' % (rel, entry.relative_to(path).as_posix())] = entry.read_bytes()
        elif path.exists() or path.is_symlink():
            snapshot[rel] = path.read_bytes()
    return snapshot


def common_dir(root):
    return Path(git(root, 'rev-parse', '--path-format=absolute', '--git-common-dir'))


class GateWorkspaceFixture(CertificateFixture):
    """CertificateFixture whose committed gate is the case's check.sh; extra files and an
    ignore pattern are committed with it."""

    def __init__(self, base, check_text, extra_files=None, ignore=None):
        super().__init__(base)
        work = self.fixture.work
        if ignore:
            (work / '.gitignore').write_text(ignore)
        for name, text, mode in extra_files or []:
            path = work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            path.chmod(mode)
        (work / 'tests/check.sh').write_text(check_text)
        (work / 'tests/check.sh').chmod(0o755)
        self.head = self.fixture.commit_push('test: gate workspace case', branch=BRANCH)
        self.host({})
        self.review = self.review_record()

    def workspace(self):
        return Path(self.fixture.work.parent) / '.omc' / 'ai-catapult' / 'gate-workspaces' \
            / ('plan-a-G1-%s-%s' % (PR, self.head))

    def record(self):
        return self.fixture.state_dir() / 'gate-workspaces' / 'plan-a' / 'G1' / ('%s-%s-certify.json' % (PR, self.head))


class GateWorkspaceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def refused_details(self, result):
        return {r['detail'] for r in result.get('refusals', [])}


class WorkspaceLocationTests(GateWorkspaceTests):
    """AC-W1: the gates ran in a sibling workspace under the observed root's parent at the PR
    head, not in the observed root, and nothing remains afterwards."""

    def test_gates_run_in_a_sibling_workspace_at_the_pr_head_and_nothing_remains(self):
        dump = self.base / 'gate-observe.txt'
        check = '#!/bin/sh\nprintf "%%s\\n" "$(pwd -P)" "$(git rev-parse --show-toplevel)" "$(git rev-parse HEAD)" > %s\nexit 0\n' % dump
        c = GateWorkspaceFixture(self.base, check)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        recorded = dump.read_text().split()
        self.assertEqual(recorded, [str(c.workspace()), str(c.workspace()), c.head], recorded)
        self.assertNotEqual(recorded[0], str(c.fixture.work))
        self.assertFalse(c.workspace().exists(), 'the workspace must be removed when the derivation ends')
        gate_workspace = result['certificate']['gate_workspace']
        self.assertEqual(gate_workspace['workspace'], str(c.workspace()))
        record = Path(gate_workspace['record']['path'])
        self.assertTrue(record.is_file(), 'the certificate binds an existing gate-workspace/1 record')
        self.assertEqual(gate_workspace['record']['sha256'], sha(record.read_bytes()))
        data = json.loads(record.read_text())
        self.assertEqual(data['schema'], 'gate-workspace/1')
        self.assertEqual(data['head'], c.head)
        self.assertEqual(data['network'], 'bootstrap')
        self.assertEqual((data['bootstrap'], data['dependencies'], data['outputs']), ([], [], []))


class ObservedRootUnchangedTests(GateWorkspaceTests):
    """AC-W2: every observed-root check is unchanged; a gate writing an ignored file still
    refuses, the root stays byte-identical, and the detail code names the workspace path."""

    def test_a_gate_writing_an_ignored_file_keeps_the_root_untouched_and_refuses(self):
        c = GateWorkspaceFixture(self.base, '#!/bin/sh\necho ran >> gate.log\nexit 0\n', ignore='gate.log\n')
        before = observer.worktree_snapshot(c.fixture.work)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertFalse(result['issued'])
        self.assertIn('worktree_changed_during_gates', codes(result))
        self.assertIn('gate_workspace_undeclared_output:gate.log', self.refused_details(result))
        self.assertFalse((c.fixture.work / 'gate.log').exists(), 'the observed root never held the gate output')
        self.assertEqual(observer.worktree_snapshot(c.fixture.work), before)


class WorkspaceIntegrityTests(GateWorkspaceTests):
    """AC-W3: HEAD, index and tracked bytes are re-checked after every gate; undeclared paths
    refuse; a clean git-only gate is issued."""

    def test_a_gate_rewriting_a_tracked_file_is_refused(self):
        c = GateWorkspaceFixture(self.base, '#!/bin/sh\necho hacked > src/app.txt\nexit 0\n')
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('worktree_changed_during_gates', codes(result))
        self.assertIn('gate_workspace_tracked_changed:src/app.txt', self.refused_details(result))

    def test_a_gate_running_only_git_diff_check_and_ls_files_is_issued(self):
        c = GateWorkspaceFixture(self.base, '#!/bin/sh\ngit diff --check\ngit ls-files >/dev/null\nexit 0\n')
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))


class GitMetadataTests(GateWorkspaceTests):
    """AC-W4: a gate's git reaches only the workspace; the observed git metadata is snapshotted
    around the gates and a gate writing it by absolute path is refused."""

    def test_a_gate_configuring_hooks_and_refs_touches_only_the_workspace(self):
        c = GateWorkspaceFixture(self.base, '#!/bin/sh\ngit config --local gate.touched yes\n'
                                            'mkdir -p "$(git rev-parse --absolute-git-dir)/hooks"\n'
                                            'printf "#!/bin/sh\\nexit 0\\n" > "$(git rev-parse --absolute-git-dir)/hooks/post-checkout"\n'
                                            'git update-ref refs/heads/gw-moved HEAD\nexit 0\n')
        common = common_dir(c.fixture.work)
        before = metadata_bytes(common)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(metadata_bytes(common), before, 'the observed git metadata changed during the gates')
        self.assertNotIn('gate.touched', (common / 'config').read_text())

    def test_a_gate_writing_the_observed_git_metadata_by_absolute_path_is_refused(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        common = common_dir(work)
        (work / 'tests/check.sh').write_text('#!/bin/sh\nprintf "[gate]\\n\\ttouched = yes\\n" >> %s/config\nexit 0\n' % common)
        (work / 'tests/check.sh').chmod(0o755)
        c.head = c.fixture.commit_push('test: a gate that writes the observed config', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('git_metadata_changed_during_gates', codes(result))

    def test_the_target_is_resolved_once_before_the_gates(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        (work / 'spec.md').write_text('Fixture specification\ntouched outside the goal scope\n')
        root_commit = git(work, 'rev-list', '--max-parents=0', 'HEAD')
        common = common_dir(work)
        (work / 'tests/check.sh').write_text('#!/bin/sh\ngit --git-dir=%s update-ref refs/remotes/origin/main %s\nexit 0\n'
                                             % (common, root_commit))
        (work / 'tests/check.sh').chmod(0o755)
        c.head = c.fixture.commit_push('test: a reserved edit and a ref-moving gate', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('goal_reserved_path', codes(result), json.dumps(result, indent=1))


class PhysicalPathTests(GateWorkspaceTests):
    """AC-W5: every path the observer hands a gate (HOME, TMPDIR, --root as the working
    directory) is its physical path."""

    def test_home_tmpdir_and_the_workspace_are_physical(self):
        real = self.base / 'real-tmp'
        real.mkdir()
        link = self.base / 'tmp-link'
        link.symlink_to(real, target_is_directory=True)
        dump = self.base / 'env-observe.txt'
        check = '#!/bin/sh\nprintf "%%s\\n" "$HOME" "$TMPDIR" "$(pwd -P)" > %s\nexit 0\n' % dump
        c = GateWorkspaceFixture(self.base, check)
        exit_code, result = c.certify(env={'TMPDIR': str(link)})
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        home, tmpdir, pwd_p = dump.read_text().split()
        self.assertEqual(home, os.path.realpath(home))
        self.assertEqual(tmpdir, os.path.realpath(tmpdir))
        self.assertEqual(pwd_p, os.path.realpath(pwd_p))
        self.assertNotEqual(home, observer.passwd_home())
        self.assertEqual(result['certificate']['gate_workspace']['workspace'],
                         os.path.realpath(result['certificate']['gate_workspace']['workspace']))


class StreamingDigestTests(GateWorkspaceTests):
    """AC-W6: worktree_rows hashes file bytes in fixed-size chunks into hashlib, never
    whole-file."""

    def test_worktree_rows_streams_every_digest(self):
        from readiness_contract import canonical
        import hashlib
        import stat
        from unittest import mock
        repo = self.base / 'rows'
        repo.mkdir()
        git(self.base, 'init', '-q', str(repo))
        (repo / 'a.txt').write_text('a' * 300000 + '\n')
        (repo / 'b.sh').write_text('#!/bin/sh\nexit 0\n')
        (repo / 'b.sh').chmod(0o755)
        git(repo, 'add', '-A')
        git(repo, '-c', 'user.email=t@t', '-c', 'user.name=t', 'commit', '-q', '-m', 'rows')

        def chunked(path):
            digest = hashlib.sha256()
            with open(path, 'rb') as handle:
                for piece in iter(lambda: handle.read(65536), b''):
                    digest.update(piece)
            return digest.hexdigest()

        rows = [['a.txt', stat.S_IMODE(os.lstat(repo / 'a.txt').st_mode), chunked(repo / 'a.txt')],
                ['b.sh', stat.S_IMODE(os.lstat(repo / 'b.sh').st_mode), chunked(repo / 'b.sh')]]
        with mock.patch.object(Path, 'read_bytes', side_effect=AssertionError('whole-file read')):
            self.assertEqual(observer.worktree_rows(repo), canonical(rows))


class RunGatesBytecodeTests(GateWorkspaceTests):
    """AC-W7: run-gates.sh's readiness-contract/2 branch exports PYTHONDONTWRITEBYTECODE=1, so a
    v2 local-validation run whose gate imports a tracked module writes no bytecode."""

    def test_a_v2_local_validation_gate_importing_a_tracked_module_writes_no_bytecode(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        (work / 'tests/gate_helper.py').write_text('VALUE = 1\n')
        (work / 'tests/check.sh').write_text("#!/bin/sh\npython3 -c \"import sys; sys.path.insert(0, 'tests'); import gate_helper\"\nexit 0\n")
        c.head = c.fixture.commit_push('test: a gate that imports a tracked module', branch=BRANCH)
        c.host({})
        driver = driver_copy(self.base, c.fixture.keys.anchor)
        record = write_json(self.base / 'record.json', c.fixture.bundle['goals'][0])
        linked = self.base / 'linked-gates'
        git(work, 'worktree', 'add', '-q', '-b', 'feat/plan-a-gates', str(linked), c.head)
        # No PYTHON* variable from the caller: the v2 run-gates branch must turn bytecode off
        # itself, so this run writes bytecode without the export and refuses (red).
        env = {k: v for k, v in os.environ.items() if not k.startswith('PYTHON')}
        run = subprocess.run(['bash', str(driver / 'run-gates.sh'), '--root', str(linked), '--goal-record', str(record),
                              '--handoff', HANDOFF, '--phase', 'local-validation'], capture_output=True, text=True,
                             stdin=subprocess.DEVNULL, timeout=300, env=env)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertFalse(list(linked.rglob('__pycache__')), 'the v2 branch must turn bytecode off')


class CertificateFieldTests(GateWorkspaceTests):
    """AC-W8: the certificate adds exactly gate_workspace; local_gates stay {name, exit};
    pre-plan certificates keep validating; the merge re-derivation binds the same record."""

    def test_the_certificate_adds_only_the_gate_workspace_field(self):
        c = CertificateFixture(self.base)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        certificate = result['certificate']
        self.assertEqual(set(certificate), v2.CERTIFICATE_FIELDS)
        self.assertEqual(set(certificate['gate_workspace']), {'workspace', 'record'})
        self.assertEqual(set(certificate['gate_workspace']['record']), {'path', 'sha256'})
        self.assertEqual(sorted(g['name'] for g in certificate['local_gates']),
                         ['ci-gate --verify', 'lint-gate', 'local safe CI subset', 'tdd-evidence'])
        self.assertTrue(all(set(g) == {'name', 'exit'} for g in certificate['local_gates']))

    def test_a_pre_plan_certificate_without_the_field_keeps_validating(self):
        c = CertificateFixture(self.base)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        schema = json.loads((AUTO / 'schemas/readiness-contract-v2.json').read_text())
        self.assertIn('gate_workspace', schema['$defs']['certificate']['properties'])
        self.assertNotIn('gate_workspace', schema['$defs']['certificate']['required'])
        pre_plan = {k: v for k, v in result['certificate'].items() if k != 'gate_workspace'}
        self.assertNotIn('gate_workspace', pre_plan)
        # The stored pre-plan body still carries every field it used to, so nothing that reads
        # certificates (audit-merges, export-evidence) depends on the new field's presence.
        self.assertEqual(set(pre_plan), v2.CERTIFICATE_FIELDS - {'gate_workspace'})

    def test_merge_rederivation_binds_the_same_gate_workspace(self):
        c = CertificateFixture(self.base)
        exit_code, issued = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        exit_code, result = c.merge()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))

    def test_a_tampered_gate_workspace_record_refuses_the_merge(self):
        c = CertificateFixture(self.base)
        exit_code, issued = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        record = Path(issued['certificate']['gate_workspace']['record']['path'])
        record.write_text(record.read_text() + '\n# tampered\n')
        exit_code, result = c.merge()
        self.assertEqual(exit_code, 4, json.dumps(result, indent=1))
        self.assertIn('certificate_claim_mismatch', codes(result))


class DocumentationTests(GateWorkspaceTests):
    """The workspace codes are documented in readiness-v2.md, worktree-execution.md and the ADR."""

    def test_every_workspace_code_is_documented(self):
        texts = [(REPO / '04-validate-handoff/autobahn/modules/readiness-v2.md').read_text(),
                 (REPO / '04-validate-handoff/autobahn/modules/worktree-execution.md').read_text(),
                 (REPO / 'docs/architecture/adr/0017-isolated-gate-workspace.md').read_text()]
        for code in ('gate_workspace_unfaithful', 'gate_workspace_tracked_changed',
                     'gate_workspace_undeclared_output', 'git_metadata_changed_during_gates',
                     'gate_workspace_unavailable'):
            self.assertTrue(any(code in text for text in texts), code)


if __name__ == '__main__':
    unittest.main()
