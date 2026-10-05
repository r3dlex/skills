"""ACH-S-08 (D1-02, local-ci/2): the declared reproducible dependency install. The schema is
exactly the local-ci/1 fields plus a required workspace object with exactly bootstrap,
dependencies and outputs. Each bootstrap entry is exactly `npm ci`, `npm ci --ignore-scripts`
or `bash <path>` with <path> a pinned sources key; an npm form requires a pinned
package-lock.json or npm-shrinkwrap.json. dependencies and outputs are unique, normalized,
repository-relative literal paths with no glob character, no `..` and no .git component in any
letter case, and no entry equals, contains or lies inside another. local-ci/1 keeps its
behavior unchanged. Disposable repositories only."""
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
LOCAL = REPO / '04-validate-handoff/autobahn/local-ci.sh'
sys.path.insert(0, str(REPO / '04-validate-handoff/autobahn/lib'))  # python3 -I drops the script directory
import local_ci_contract as contract  # noqa: E402


class DeclarationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for directory in ('.ai/ci', '.github/workflows', 'tests'):
            (self.root / directory).mkdir(parents=True)
        (self.root / '.github/workflows/ci.yml').write_text('name: ci\n')
        (self.root / 'tests/check.sh').write_text('#!/bin/sh\necho ran >> ran\nexit 0\n')
        (self.root / 'tests/bootstrap.sh').write_text('#!/bin/sh\nmkdir -p vendor\nexit 0\n')
        (self.root / 'package-lock.json').write_text('{"lockfileVersion": 3}\n')
        (self.root / '.gitignore').write_text('vendor/\ndist/\ndist-snapshot/\n')
        self.path = self.root / '.ai/ci/local-ci.json'
        self.contract = {
            'schema': 'local-ci/2',
            'workflows': self.pins('.github/workflows/ci.yml'),
            'sources': self.pins('tests/check.sh', 'tests/bootstrap.sh', 'package-lock.json'),
            'verification': ['bash tests/check.sh'],
            'workspace': {'bootstrap': ['bash tests/bootstrap.sh'],
                          'dependencies': ['vendor'],
                          'outputs': ['dist', 'dist-snapshot']},
        }

    def pins(self, *names):
        return {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in names}

    def write(self):
        self.path.write_text(json.dumps(self.contract))

    def refused(self, reason):
        self.write()
        with self.assertRaises(ValueError) as raised:
            contract.read_declaration(self.root)
        self.assertIn(reason, str(raised.exception))
        return str(raised.exception)

    def test_valid_local_ci_2_declaration_is_accepted_and_runs_the_safe_subset(self):
        self.write()
        declaration = contract.read_declaration(self.root)
        self.assertEqual(declaration, self.contract['workspace'])
        result = subprocess.run(['bash', str(LOCAL), '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / 'ran').exists())

    def test_a_local_ci_2_record_without_workspace_is_refused(self):
        del self.contract['workspace']
        self.refused('workspace')

    def test_the_workspace_object_admits_exactly_bootstrap_dependencies_outputs(self):
        original = dict(self.contract['workspace'])
        for change in ({'missing': 'outputs'}, {'missing': 'bootstrap'}, {'extra': 'vendors'}):
            self.contract['workspace'] = dict(original)
            if change.get('missing'):
                del self.contract['workspace'][change['missing']]
            if change.get('extra'):
                self.contract['workspace'][change['extra']] = []
            self.refused('bootstrap, dependencies and outputs')
        self.contract['workspace'] = original

    def test_bootstrap_admits_only_the_three_allowlisted_forms(self):
        for entry in ('npm install', 'npm ci --extra', 'npm', 'npm ci ', 'npm ci; echo hi', 'bash ',
                      'bash tests/bootstrap.sh --flag', 'bash /abs.sh', 'bash ../escape.sh', '', 42):
            self.contract['workspace']['bootstrap'] = [entry]
            self.refused('bootstrap')

    def test_an_npm_form_requires_a_pinned_lockfile(self):
        self.contract['workspace']['bootstrap'] = ['npm ci']
        self.contract['sources'] = self.pins('tests/check.sh')
        self.refused('package-lock.json or npm-shrinkwrap.json')
        (self.root / 'npm-shrinkwrap.json').write_text('{"lockfileVersion": 3}\n')
        self.contract['sources'] = self.pins('tests/check.sh', 'npm-shrinkwrap.json')
        self.write()
        self.assertEqual(contract.read_declaration(self.root)['bootstrap'], ['npm ci'])

    def test_a_bash_form_must_name_a_pinned_sources_key(self):
        (self.root / 'tests/unpinned.sh').write_text('#!/bin/sh\nexit 0\n')
        self.contract['workspace']['bootstrap'] = ['bash tests/unpinned.sh']
        self.refused('not a pinned source')

    def test_declared_paths_are_unique_normalized_repository_relative_literal(self):
        for values in (['vendor', 'vendor'], ['a//b'], ['./a'], ['a/'], ['../a'], ['/abs'],
                       ['dist/*'], ['a?b'], ['a[b]'], ['a/.git/x'], ['x/.GIT'], [7]):
            self.contract['workspace']['dependencies'] = values
            self.refused('dependencies')

    def test_declared_paths_do_not_nest(self):
        for values in (['vendor', 'vendor/sub'], ['vendor/sub', 'vendor']):
            self.contract['workspace']['dependencies'] = values
            self.refused('nest')
        self.contract['workspace']['dependencies'] = ['vendor']
        for outputs in (['dist', 'dist'], ['dist', 'dist/sub']):
            self.contract['workspace']['outputs'] = outputs
            self.refused('nest')

    def test_declared_paths_do_not_nest_across_dependencies_and_outputs(self):
        self.contract['workspace']['dependencies'] = ['dist']
        self.contract['workspace']['outputs'] = ['dist/sub']
        self.refused('nest')
        self.contract['workspace']['dependencies'] = ['vendor']
        self.contract['workspace']['outputs'] = ['vendor']
        self.refused('unique')

    def test_local_ci_1_keeps_its_behavior(self):
        self.contract['schema'] = 'local-ci/1'
        del self.contract['workspace']
        self.write()
        self.assertIsNone(contract.read_declaration(self.root))
        result = subprocess.run(['bash', str(LOCAL), '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.root / 'ran').exists())

    def test_duplicate_or_unknown_fields_are_refused(self):
        self.write()
        duplicated = self.path.read_text()[:-1] + ', "workspace": {"bootstrap": [], "dependencies": [], "outputs": []}}'
        self.path.write_text(duplicated)
        with self.assertRaises(ValueError):
            contract.read_declaration(self.root)
        self.contract['authority'] = True
        self.refused('unknown or missing fields')


if __name__ == '__main__':
    unittest.main()
