"""Explicit local CI is supporting evidence, never workflow equivalence."""
import copy
import hashlib
import json
import os
import sys
import pathlib
import subprocess
import tempfile
import unittest

REPO = pathlib.Path(__file__).resolve().parents[1]
LOCAL = REPO / '04-validate-handoff/autobahn/local-ci.sh'


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        for directory in ('.ai/ci', '.github/workflows', 'tests'):
            (self.root / directory).mkdir(parents=True)
        # Actual workflow fixture: intentionally outside the executable subset.
        workflow = REPO / '.github/workflows/ci-prek.yml'
        (self.root / '.github/workflows/ci.yml').write_bytes(workflow.read_bytes())
        (self.root / 'tests/check.sh').write_text('echo ran >> ran\n')
        self.path = self.root / '.ai/ci/local-ci.json'
        self.contract = {'schema': 'local-ci/1', 'workflows': self.pins('.github/workflows/ci.yml'),
                         'sources': self.pins('tests/check.sh'),
                         'verification': ['bash tests/check.sh']}

    def pins(self, *names):
        return {name: hashlib.sha256((self.root / name).read_bytes()).hexdigest() for name in names}

    def run_contract(self, passed=False):
        self.path.write_text(json.dumps(self.contract))
        result = subprocess.run(['bash', str(LOCAL), '--root', str(self.root)], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, passed, result.stdout + result.stderr)
        self.assertEqual((self.root / 'ran').exists(), passed, result.stdout + result.stderr)
        return result

    def test_reviewed_contract_runs_with_real_unsupported_workflow(self):
        result = self.run_contract(True)
        self.assertIn('not hosted-CI equivalence', result.stdout)

    def test_unknown_schema_or_fields(self):
        for change in ({'schema': 'local-ci/2'}, {'approval': True}):
            original = copy.deepcopy(self.contract)
            self.contract.update(change)
            self.run_contract()
            self.contract = original

    def test_stale_workflow(self):
        (self.root / '.github/workflows/ci.yml').write_text('name: changed\n')
        self.run_contract()

    def test_missing_workflow_pin(self):
        self.contract['workflows'] = {}
        self.run_contract()

    def test_added_workflow_blocks(self):
        (self.root / '.github/workflows/extra.yaml').write_text('name: extra\n')
        self.run_contract()

    def test_hidden_azure_workflow_requires_pin(self):
        for name in ('.azure-pipelines.yml', '.azure-pipelines.yaml'):
            with self.subTest(name=name):
                path = self.root / name
                path.write_text('steps: []\n')
                self.run_contract()
                path.unlink()

    def test_hidden_azure_workflows_with_current_pins_run(self):
        for name in ('.azure-pipelines.yml', '.azure-pipelines.yaml'):
            (self.root / name).write_text('steps: []\n')
            self.contract['workflows'].update(self.pins(name))
        self.run_contract(True)

    def test_hidden_azure_workflow_stale_pin_blocks(self):
        for name in ('.azure-pipelines.yml', '.azure-pipelines.yaml'):
            with self.subTest(name=name):
                path = self.root / name
                path.write_text('steps: []\n')
                self.contract['workflows'].update(self.pins(name))
                path.write_text('steps: [changed]\n')
                self.run_contract()
                path.unlink()
                del self.contract['workflows'][name]

    def test_deleted_workflow_blocks(self):
        (self.root / '.github/workflows/ci.yml').unlink()
        self.run_contract()

    def test_stale_supporting_source(self):
        (self.root / 'tests/check.sh').write_text('echo changed\n')
        self.run_contract()

    def test_sources_must_include_command_script(self):
        self.contract['sources'] = {}
        self.run_contract()

    def test_rejects_unsafe_or_unpinned_source_paths(self):
        digest = next(iter(self.contract['sources'].values()))
        for path in ('../check.sh', '/tmp/check.sh', 'tests//check.sh', 'tests/./check.sh'):
            self.contract['sources'] = {path: digest}
            self.run_contract()

    def test_source_symlink_even_contained_blocks(self):
        (self.root / 'tests/real.sh').write_text('echo ran >> ran\n')
        (self.root / 'tests/check.sh').unlink()
        (self.root / 'tests/check.sh').symlink_to('real.sh')
        self.run_contract()

    def test_workflow_directory_symlink_blocks(self):
        directory = self.root / '.github/workflows'
        directory.rename(self.root / 'workflows')
        directory.symlink_to('../workflows')
        self.run_contract()

    def test_empty_or_unsafe_later_command_never_executes_first(self):
        for entries in ([], ['bash tests/check.sh', 'echo unsafe'],
                        ['bash tests/check.sh', 'bash tests/check.sh; echo unsafe']):
            self.contract['verification'] = entries
            self.run_contract()

    def test_failing_command_blocks(self):
        (self.root / 'tests/check.sh').write_text('exit 1\n')
        self.contract['sources'] = self.pins('tests/check.sh')
        self.run_contract()

    def test_contract_symlink_blocks(self):
        real = self.root / 'local-ci.json'
        real.write_text(json.dumps(self.contract))
        self.path.symlink_to(real)
        self.run_contract()

    def test_duplicate_json_fields_block(self):
        self.path.write_text(json.dumps(self.contract)[:-1] + ', "schema": "local-ci/1"}')
        result = subprocess.run(['bash', str(LOCAL), '--root', str(self.root)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / 'ran').exists())

    def test_invalid_explicit_contract_never_falls_back_to_safe_workflow(self):
        (self.root / '.github/workflows/ci.yml').write_text(
            'name: CI\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n'
            '    steps:\n      - run: bash tests/check.sh\n')
        self.run_contract()

    def test_duplicate_commands_preserve_order(self):
        self.contract['verification'] *= 2
        self.run_contract(True)
        self.assertEqual((self.root / 'ran').read_text(), 'ran\nran\n')

    def test_contained_command_cwd(self):
        (self.root / 'sub/tests').mkdir(parents=True)
        # Subdirectory command cwd is supported by the unchanged verification adapter.
        (self.root / 'sub/tests/check.sh').write_text('echo ran >> ../ran\n')
        self.contract['sources'] = self.pins('sub/tests/check.sh')
        self.contract['verification'] = [{'cwd': 'sub', 'command': 'bash tests/check.sh'}]
        self.run_contract(True)

    def test_invalid_hash_and_missing_source(self):
        self.contract['sources']['tests/check.sh'] = 'not-a-sha'
        self.run_contract()
        self.contract['sources'] = {'tests/absent.sh': '0' * 64}
        self.run_contract()

    def test_missing_contract_retains_safe_derive(self):
        (self.root / '.github/workflows/ci.yml').write_text(
            'name: CI\non: [push]\njobs:\n  test:\n    runs-on: ubuntu-latest\n'
            '    steps:\n      - run: bash tests/check.sh\n')
        result = subprocess.run(['bash', str(LOCAL), '--root', str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'ran').exists())

    def test_unavailable_executable_blocks(self):
        self.path.write_text(json.dumps(self.contract))
        helper = LOCAL.parent / 'lib/local_ci_contract.py'
        result = subprocess.run([sys.executable, '-B', str(helper), str(self.root)],
                                env={**os.environ, 'PATH': ''}, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'executable is unavailable', result.stderr)
        self.assertFalse((self.root / 'ran').exists())

    def test_authority_claim_fields_rejected(self):
        # A declaration is not an approval token or remote CI success.
        self.contract['remote_ci'] = 'passed'
        self.run_contract()


if __name__ == '__main__':
    unittest.main()
