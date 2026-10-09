"""ACH-S-08 (D1-02): the declared bootstrap, the outputs and the gate-workspace/1 provenance
record. The observer reads .ai/ci/local-ci.json from the workspace (the head tree), validates it
with the pinned local CI contract lib, and refuses a declared dependency or output that is
tracked at the head, contains a tracked path, or is not ignored by the head's ignore rules, each
as gate_workspace_declaration_invalid:<reason>. A local-ci/1 contract or no contract declares
nothing, which is ACH-S-07's strict workspace. For a local-ci/2 head the observer runs each
bootstrap command in the workspace, in order, as argv with shell=False and stdin closed, under
the bootstrap environment (the gate environment plus GIT_CONFIG_NOSYSTEM=1,
GIT_CONFIG_GLOBAL=/dev/null, GIT_TERMINAL_PROMPT=0, npm_config_userconfig=/dev/null and a private
npm_config_cache inside the derivation's temporary directory); network access is permitted for
the bootstrap step only. A non-zero exit refuses with gate_workspace_bootstrap_failed:<command>
and no gate runs. During and after the gates untracked paths are allowed only under the declared
dependencies and outputs, and no observed-root check is relaxed. Every derivation writes one
gate-workspace/1 record holding the head and its tree, the contract's sha256 and schema, each
bootstrap command (resolved executable, --version output, and node for an npm form, exit code,
duration), the pinned input digests, a streaming digest of each dependency path, the outputs
present after the gates, network: bootstrap, and the workspace path. The certify-v2 and merge-v2
results and the driver-log entry carry the record's path and sha256. A local-ci/1 head behaves
exactly as after ACH-S-07. Disposable repositories, a recording `gh` stand-in and a recording
`npm` stand-in found through PATH, and ephemeral agent keys only; the bootstrap tests never
touch the network."""
import hashlib
import json
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
from readiness_v2_core_test import codes, git, sha, observer, write_json  # noqa: E402
from readiness_v2_certificate_test import BRANCH, CertificateFixture  # noqa: E402
from readiness_v2_gate_workspace_test import GateWorkspaceTests  # noqa: E402

REPO = Path(__file__).resolve().parents[1]


def npm_shim(directory, log, version='9.9.9', fail=False):
    """A recording `npm` stand-in on PATH: `--version` prints, every other invocation appends its
    argv and the bootstrap environment to the log and exits. It never reaches the network."""
    directory.mkdir(parents=True, exist_ok=True)
    (directory / 'npm').write_text('''#!/usr/bin/env python3
import json, os, sys
keys = ('GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_GLOBAL', 'GIT_TERMINAL_PROMPT', 'npm_config_userconfig',
        'npm_config_cache', 'GH_TOKEN', 'SSH_AUTH_SOCK', 'HOME')
if '--version' in sys.argv[1:]:
    print(%r); sys.exit(0)
with open(%r, 'a') as handle:
    handle.write(json.dumps({'argv': sys.argv[1:], 'env': {k: os.environ.get(k) for k in keys}}) + '\\n')
sys.exit(%d)
''' % (version, str(log), 1 if fail else 0))
    (directory / 'npm').chmod(0o755)
    (directory / 'node').write_text('#!/usr/bin/env python3\nprint("20.0.0")\n')
    (directory / 'node').chmod(0o755)
    return directory


class BootstrapFixture(CertificateFixture):
    """CertificateFixture whose head carries a local-ci/2 declaration, the case's gate as
    tests/check.sh, the case's pinned bootstrap scripts and optionally a pinned lockfile."""

    def __init__(self, base, bootstrap=('bash tests/bootstrap.sh',), dependencies=('vendor',),
                 outputs=('dist', 'dist-snapshot'), ignore='vendor/\ndist/\ndist-snapshot/\n',
                 bootstrap_scripts=None, check_text='#!/bin/sh\nexit 0\n', lock_text=None,
                 extra_sources=(), workspace=None):
        super().__init__(base)
        work = self.fixture.work
        (work / '.gitignore').write_text(ignore)
        (work / 'tests/check.sh').write_text(check_text)
        (work / 'tests/check.sh').chmod(0o755)
        scripts = dict(bootstrap_scripts or {
            'tests/bootstrap.sh': '#!/bin/sh\nmkdir -p vendor\nprintf "v1\\n" > vendor/app.js\nexit 0\n'})
        for name, text in scripts.items():
            path = work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
            path.chmod(0o755)
        if lock_text is not None:
            (work / 'package-lock.json').write_text(lock_text)
        sources = {'.github/workflows/ci.yml': sha(work / '.github/workflows/ci.yml'),
                   'tests/check.sh': sha(work / 'tests/check.sh'),
                   **{name: sha(work / name) for name in scripts},
                   **({} if lock_text is None else {'package-lock.json': sha(work / 'package-lock.json')}),
                   **{name: sha(work / name) for name in extra_sources}}
        self.contract = {'schema': 'local-ci/2', 'workflows': {'.github/workflows/ci.yml': sources['.github/workflows/ci.yml']},
                         'sources': sources, 'verification': ['bash tests/check.sh'],
                         'workspace': workspace or {'bootstrap': list(bootstrap),
                                                    'dependencies': list(dependencies),
                                                    'outputs': list(outputs)}}
        write_json(work / '.ai/ci/local-ci.json', self.contract)
        self.head = self.fixture.commit_push('test: gate bootstrap case', branch=BRANCH)
        self.host({})
        self.review = self.review_record()

    def record(self, result):
        return Path(result['certificate']['gate_workspace']['record']['path'])

    def record_data(self, result):
        return json.loads(self.record(result).read_text())


class DeclarationTests(GateWorkspaceTests):
    """The declaration is read from the workspace, so from the head tree, and every declared
    path must be untracked, contain no tracked path and be ignored by the head's ignore rules."""

    def test_a_local_ci_2_head_with_declared_bootstrap_dependencies_and_outputs_is_issued(self):
        c = BootstrapFixture(self.base, check_text='#!/bin/sh\nmkdir -p dist dist-snapshot\n'
                                                  'printf "o1\\n" > dist/out.txt\nprintf "o2\\n" > dist-snapshot/out.txt\nexit 0\n')
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        data = c.record_data(result)
        self.assertEqual(data['schema'], 'gate-workspace/1')
        self.assertEqual(data['head'], c.head)
        self.assertEqual(data['tree'], git(c.fixture.work, 'rev-parse', c.head + '^{tree}'))
        self.assertEqual(data['contract']['schema'], 'local-ci/2')
        self.assertEqual(data['contract']['sha256'], sha(c.fixture.work / '.ai/ci/local-ci.json'))
        self.assertEqual([b['command'] for b in data['bootstrap']], ['bash tests/bootstrap.sh'])
        self.assertEqual(data['network'], 'bootstrap')
        self.assertEqual(data['workspace'], result['certificate']['gate_workspace']['workspace'])
        self.assertEqual([d['path'] for d in data['dependencies']], ['vendor'])
        self.assertEqual([o['path'] for o in data['outputs']], ['dist', 'dist-snapshot'])

    def test_a_declared_dependency_tracked_at_the_head_is_refused(self):
        c = BootstrapFixture(self.base, dependencies=('src',))
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertFalse(result['issued'])
        self.assertIn('gate_workspace_declaration_invalid:tracked at the head: src',
                      {r['detail'] for r in result.get('refusals', [])})

    def test_a_declared_dependency_containing_a_tracked_path_is_refused(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        (work / 'vendor').mkdir()
        (work / 'vendor/keep.txt').write_text('keep\n')
        c.head = c.fixture.commit_push('test: a tracked file under the declared dependency', branch=BRANCH)
        (work / '.gitignore').write_text('vendor/\n')
        sources = {'.github/workflows/ci.yml': sha(work / '.github/workflows/ci.yml'),
                   'tests/check.sh': sha(work / 'tests/check.sh')}
        write_json(work / '.ai/ci/local-ci.json', {'schema': 'local-ci/2',
                                                   'workflows': {'.github/workflows/ci.yml': sources['.github/workflows/ci.yml']},
                                                   'sources': sources, 'verification': ['bash tests/check.sh'],
                                                   'workspace': {'bootstrap': [], 'dependencies': ['vendor'],
                                                                 'outputs': []}})
        c.head = c.fixture.commit_push('test: the declaration', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('gate_workspace_declaration_invalid:contains a tracked path: vendor',
                      {r['detail'] for r in result.get('refusals', [])})

    def test_a_declared_path_not_ignored_by_the_head_is_refused(self):
        c = BootstrapFixture(self.base, dependencies=('deps',), ignore='')
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('gate_workspace_declaration_invalid:not ignored by the head: deps',
                      {r['detail'] for r in result.get('refusals', [])})


class BootstrapTests(GateWorkspaceTests):
    """The bootstrap runs in the workspace, before the gates, in order, as argv with shell=False
    and stdin closed, under the bootstrap environment; a non-zero exit refuses and no gate runs;
    tracked files must still equal the head tree and untracked paths stay under the declared
    dependencies afterwards."""

    def tmp_env(self, c, extra=None):
        tmp = self.base / 'tmp'
        tmp.mkdir(exist_ok=True)
        return {'TMPDIR': str(tmp), 'PATH': str(c.shim.parent) + os.pathsep + os.environ['PATH'], **(extra or {})}

    def test_the_bootstrap_runs_before_the_gates_in_order_with_argv_and_closed_stdin(self):
        scripts = {'tests/one.sh': '#!/bin/sh\nprintf "one\\n" >> "$TMPDIR/order.txt"\n'
                                   'if read -r _; then echo open; else echo closed; fi >> "$TMPDIR/order.txt"\nexit 0\n',
                   'tests/two.sh': '#!/bin/sh\nprintf "two\\n" >> "$TMPDIR/order.txt"\nexit 0\n'}
        check = '#!/bin/sh\nprintf "gate\\n" >> "$TMPDIR/order.txt"\nexit 0\n'
        c = BootstrapFixture(self.base, bootstrap=('bash tests/one.sh', 'bash tests/two.sh'),
                             bootstrap_scripts=scripts, dependencies=(), outputs=(), check_text=check)
        exit_code, result = c.certify(env=self.tmp_env(c))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        order = (self.base / 'tmp' / 'order.txt').read_text().split()
        self.assertEqual(order[:4], ['one', 'closed', 'two', 'gate'], order)
        self.assertTrue(all(entry == 'gate' for entry in order[4:]), order)

    def test_the_bootstrap_environment_carries_no_credentials_and_a_private_npm_cache(self):
        script = ('#!/bin/sh\n[ -d "$npm_config_cache" ] || exit 1\n'
                  'printf "%s\\n%s\\n%s\\n%s\\n%s\\n%s\\n" "$GIT_CONFIG_NOSYSTEM" "$GIT_CONFIG_GLOBAL" '
                  '"$GIT_TERMINAL_PROMPT" "$npm_config_userconfig" "$npm_config_cache" "$HOME" > "$TMPDIR/bootstrap-env.txt"\n'
                  '[ -z "${GH_TOKEN:-}" ] || exit 1\n[ -z "${SSH_AUTH_SOCK:-}" ] || exit 1\n'
                  '[ -z "${GH_CONFIG_DIR:-}" ] || exit 1\nexit 0\n')
        c = BootstrapFixture(self.base, bootstrap_scripts={'tests/bootstrap.sh': script}, dependencies=(), outputs=())
        exit_code, result = c.certify(env=self.tmp_env(c))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        nosystem, global_config, prompt, userconfig, cache, home = (self.base / 'tmp' / 'bootstrap-env.txt').read_text().splitlines()
        self.assertEqual((nosystem, global_config, prompt, userconfig), ('1', '/dev/null', '0', '/dev/null'))
        self.assertIn('observer-', cache)
        self.assertNotIn(observer.passwd_home(), cache)
        self.assertNotEqual(home, observer.passwd_home())

    def test_an_npm_bootstrap_runs_the_recording_stand_in_and_never_the_network(self):
        log = self.base / 'npm-log.jsonl'
        shim = npm_shim(self.base / 'npm-bin', log)
        c = BootstrapFixture(self.base, bootstrap=('npm ci --ignore-scripts',), dependencies=(), outputs=(),
                             bootstrap_scripts={}, lock_text='{"lockfileVersion": 3}\n')
        exit_code, result = c.certify(env=self.tmp_env(c, {'PATH': str(shim) + os.pathsep + str(c.shim.parent)
                                                          + os.pathsep + os.environ['PATH']}))
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        calls = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
        installs = [call for call in calls if call['argv'] == ['ci', '--ignore-scripts']]
        self.assertEqual(len(installs), 1, calls)
        env = installs[0]['env']
        self.assertEqual((env['GIT_CONFIG_NOSYSTEM'], env['GIT_CONFIG_GLOBAL'], env['GIT_TERMINAL_PROMPT'],
                          env['npm_config_userconfig']), ('1', '/dev/null', '0', '/dev/null'))
        self.assertIn('observer-', env['npm_config_cache'])
        self.assertIsNone(env['GH_TOKEN'])
        self.assertIsNone(env['SSH_AUTH_SOCK'])
        entry = c.record_data(result)['bootstrap'][0]
        self.assertEqual(entry['command'], 'npm ci --ignore-scripts')
        self.assertEqual(entry['argv'], ['npm', 'ci', '--ignore-scripts'])
        self.assertTrue(entry['executable'].endswith('/npm'), entry)
        self.assertEqual(entry['version'], '9.9.9')
        self.assertEqual(entry['node_version'], '20.0.0')
        self.assertEqual(entry['exit'], 0)
        self.assertGreaterEqual(entry['duration'], 0)
        self.assertEqual(c.record_data(result)['inputs'],
                         [{'path': 'package-lock.json', 'sha256': c.contract['sources']['package-lock.json']}])

    def test_a_failing_bootstrap_refuses_and_no_gate_runs(self):
        c = BootstrapFixture(self.base, bootstrap_scripts={'tests/bootstrap.sh': '#!/bin/sh\nexit 1\n'},
                             check_text='#!/bin/sh\nprintf "gate\\n" >> "$TMPDIR/order.txt"\nexit 0\n')
        exit_code, result = c.certify(env=self.tmp_env(c))
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('gate_workspace_bootstrap_failed:bash tests/bootstrap.sh',
                      {r['detail'] for r in result.get('refusals', [])})
        self.assertFalse((self.base / 'tmp' / 'order.txt').exists(), 'no gate may run after a failed bootstrap')

    def test_a_bootstrap_that_changes_a_tracked_file_refuses(self):
        c = BootstrapFixture(self.base, bootstrap_scripts={'tests/bootstrap.sh': '#!/bin/sh\nprintf hacked > src/app.txt\nexit 0\n'})
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('worktree_changed_during_gates', codes(result))
        self.assertIn('gate_workspace_tracked_changed:src/app.txt', {r['detail'] for r in result.get('refusals', [])})

    def test_the_bootstrap_may_write_only_declared_dependencies(self):
        c = BootstrapFixture(self.base, bootstrap_scripts={'tests/bootstrap.sh': '#!/bin/sh\nmkdir -p vendor stray\n'
                                                                                 'printf "v\\n" > vendor/app.js\n'
                                                                                 'printf "s\\n" > stray/extra.txt\nexit 0\n'})
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('gate_workspace_undeclared_output:stray/extra.txt',
                      {r['detail'] for r in result.get('refusals', [])})


class OutputsTests(GateWorkspaceTests):
    """Untracked paths are allowed only under the declared dependencies and outputs; a
    declaration never relaxes a check on the observed root."""

    def test_a_gate_writing_declared_outputs_is_issued_and_an_undeclared_output_refuses(self):
        check = '#!/bin/sh\nmkdir -p dist dist-snapshot\nprintf "o1\\n" > dist/out.txt\nprintf "o2\\n" > dist-snapshot/out.txt\nexit 0\n'
        c = BootstrapFixture(self.base, check_text=check)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        data = c.record_data(result)
        dist = next(o for o in data['outputs'] if o['path'] == 'dist')
        self.assertEqual(dist['rows'][1][0], 'dist/out.txt')
        self.assertEqual(dist['rows'][1][2], hashlib.sha256(b'o1\n').hexdigest())
        base = self.base / 'undeclared'
        base.mkdir()
        c = BootstrapFixture(base, outputs=('dist',), check_text=check)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('gate_workspace_undeclared_output:dist-snapshot',
                      {r['detail'] for r in result.get('refusals', [])})

    def test_a_declaration_never_relaxes_the_observed_root(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        (work / '.gitignore').write_text('gate.log\n')
        (work / 'tests/check.sh').write_text('#!/bin/sh\nprintf "x\\n" >> %s/gate.log\nexit 0\n' % work)
        sources = {'.github/workflows/ci.yml': sha(work / '.github/workflows/ci.yml'),
                   'tests/check.sh': sha(work / 'tests/check.sh')}
        write_json(work / '.ai/ci/local-ci.json', {'schema': 'local-ci/2',
                                                   'workflows': {'.github/workflows/ci.yml': sources['.github/workflows/ci.yml']},
                                                   'sources': sources, 'verification': ['bash tests/check.sh'],
                                                   'workspace': {'bootstrap': [], 'dependencies': [], 'outputs': []}})
        c.head = c.fixture.commit_push('test: the declaration and a root-writing gate', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('worktree_changed_during_gates', codes(result))
        self.assertTrue((work / 'gate.log').exists(), 'the gate wrote the observed root')


class ProvenanceTests(GateWorkspaceTests):
    """The gate-workspace/1 record holds the head and tree, the contract's sha256 and schema,
    each bootstrap command's resolved executable, --version output (and node for an npm form),
    exit code and duration, the pinned input digests, a streaming digest of each dependency path
    and the outputs present after the gates; the certify-v2 and merge-v2 results and the
    driver-log entry carry the record's path and sha256."""

    def test_the_record_holds_bootstrap_inputs_dependencies_and_outputs(self):
        c = BootstrapFixture(self.base, check_text='#!/bin/sh\nmkdir -p dist dist-snapshot\n'
                                                  'printf "o1\\n" > dist/out.txt\nexit 0\n')
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        data = c.record_data(result)
        entry = data['bootstrap'][0]
        self.assertEqual(entry['command'], 'bash tests/bootstrap.sh')
        self.assertEqual(entry['argv'], ['bash', 'tests/bootstrap.sh'])
        self.assertTrue(entry['executable'].endswith('/bash'), entry)
        self.assertTrue(entry['version'].startswith('GNU bash'), entry)
        self.assertEqual(entry['exit'], 0)
        self.assertIsInstance(entry['duration'], float)
        self.assertNotIn('node_version', entry)
        self.assertEqual(data['inputs'], [{'path': 'tests/bootstrap.sh',
                                           'sha256': c.contract['sources']['tests/bootstrap.sh']}])
        vendor = data['dependencies'][0]
        self.assertEqual(vendor['path'], 'vendor')
        rows = {row[0]: row for row in vendor['rows']}
        self.assertEqual(rows['vendor/app.js'][2], hashlib.sha256(b'v1\n').hexdigest())
        self.assertEqual(rows['vendor'][1], 'directory')
        self.assertEqual(vendor['git_dirs'], [])
        self.assertEqual([o['path'] for o in data['outputs']], ['dist', 'dist-snapshot'])
        dist = next(o for o in data['outputs'] if o['path'] == 'dist')
        self.assertEqual({row[0]: row for row in dist['rows']}['dist/out.txt'][2],
                         hashlib.sha256(b'o1\n').hexdigest())

    def test_the_certify_result_and_the_driver_log_carry_the_record(self):
        c = BootstrapFixture(self.base)
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        record = Path(result['certificate']['gate_workspace']['record']['path'])
        self.assertEqual(result['gate_workspace_record'],
                         {'path': str(record), 'sha256': sha(record)})
        log = c.fixture.state_dir() / 'driver-log.jsonl'
        entries = [json.loads(line) for line in log.read_text().splitlines() if line.strip()]
        self.assertEqual(entries[-1]['gate_workspace_record'],
                         {'path': str(record), 'sha256': sha(record)})

    def test_the_merge_derivation_writes_the_merge_op_record(self):
        c = BootstrapFixture(self.base)
        exit_code, issued = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(issued, indent=1))
        exit_code, result = c.merge()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertTrue(str(result['gate_workspace_record']['path']).endswith(
            '%s-%s-merge.json' % (result['pr'], result['head'])), result)
        merge_record = Path(result['gate_workspace_record']['path'])
        self.assertEqual(result['gate_workspace_record']['sha256'], sha(merge_record))
        data = json.loads(merge_record.read_text())
        self.assertEqual(data['schema'], 'gate-workspace/1')
        self.assertEqual(data['head'], result['head'])
        self.assertEqual(data['bootstrap'][0]['command'], 'bash tests/bootstrap.sh')
        # The certificate keeps binding the certify-op record, so the merge re-derivation
        # compares against the record written at certify time.
        self.assertTrue(issued['certificate']['gate_workspace']['record']['path'].endswith('-certify.json'))


class CompatibilityTests(GateWorkspaceTests):
    """A repository with local-ci/1 or no local CI contract behaves exactly as after ACH-S-07:
    no bootstrap, no allowed untracked path."""

    def test_a_local_ci_1_head_behaves_exactly_as_after_ach_s_07(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        (work / '.gitignore').write_text('gate.log\n')
        sources = {'.github/workflows/ci.yml': sha(work / '.github/workflows/ci.yml'),
                   'tests/check.sh': sha(work / 'tests/check.sh')}
        write_json(work / '.ai/ci/local-ci.json', {'schema': 'local-ci/1',
                                                   'workflows': {'.github/workflows/ci.yml': sources['.github/workflows/ci.yml']},
                                                   'sources': sources, 'verification': ['bash tests/check.sh']})
        (work / 'tests/check.sh').write_text('#!/bin/sh\necho ran >> gate.log\nexit 0\n')
        c.head = c.fixture.commit_push('test: a local-ci/1 head', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertIn('worktree_changed_during_gates', codes(result))
        self.assertIn('gate_workspace_undeclared_output:gate.log',
                      {r['detail'] for r in result.get('refusals', [])})

    def test_an_issued_local_ci_1_certify_declares_nothing_and_carries_the_record(self):
        c = CertificateFixture(self.base)
        work = c.fixture.work
        sources = {'.github/workflows/ci.yml': sha(work / '.github/workflows/ci.yml'),
                   'tests/check.sh': sha(work / 'tests/check.sh')}
        write_json(work / '.ai/ci/local-ci.json', {'schema': 'local-ci/1',
                                                   'workflows': {'.github/workflows/ci.yml': sources['.github/workflows/ci.yml']},
                                                   'sources': sources, 'verification': ['bash tests/check.sh']})
        c.head = c.fixture.commit_push('test: a clean local-ci/1 head', branch=BRANCH)
        c.host({})
        c.review = c.review_record()
        exit_code, result = c.certify()
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        record = Path(result['certificate']['gate_workspace']['record']['path'])
        self.assertEqual(result['gate_workspace_record'], {'path': str(record), 'sha256': sha(record)})
        data = json.loads(record.read_text())
        self.assertEqual((data['bootstrap'], data['inputs'], data['dependencies'], data['outputs']),
                         ([], [], [], []))


class DocumentationTests(GateWorkspaceTests):
    """The declaration codes and the consumer shapes are documented."""

    def test_every_declaration_code_and_the_consumer_shapes_are_documented(self):
        readiness = (REPO / '04-validate-handoff/autobahn/modules/readiness-v2.md').read_text()
        adr = (REPO / 'docs/architecture/adr/0017-isolated-gate-workspace.md').read_text()
        ci_gate = (REPO / '04-validate-handoff/autobahn/modules/ci-gate.md').read_text()
        for code in ('gate_workspace_declaration_invalid', 'gate_workspace_bootstrap_failed'):
            self.assertTrue(code in readiness and code in adr, code)
        for needle in ('local-ci/2', 'setup.sh', 'skills.lock.json', 'vendor', 'dist', 'dist-snapshot',
                       'package-lock.json', 'node_modules', 're-pins the contract in the same change'):
            self.assertIn(needle, ci_gate, needle)


if __name__ == '__main__':
    unittest.main()
