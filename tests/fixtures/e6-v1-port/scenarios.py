"""Execute every original v1 unittest assertion with TS-bound calls.

Read-only calls are also compared with the frozen module on identical inputs.
Publication fault seams mirror the original mocks in Node, before loading the
unchanged shipping CLI (including its normal fingerprints).
"""
import copy
import importlib
import io
import json
import os
import shutil
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


class Adapter:
    def __init__(self, parity, frozen):
        self.parity, self.frozen = parity, frozen
        self.case = None
        self.write_json = frozen.write_json
        self.os = types.SimpleNamespace(replace=frozen.os.replace)
        self.subprocess = types.SimpleNamespace(run=subprocess.run)
        self.calls = 0

    def __getattr__(self, name):
        return getattr(self.frozen, name)

    def bridge(self, name, args, fault=None):
        env = dict(os.environ, E6_V1_FAULT=json.dumps(fault or {}))
        base = self.parity.REPO / 'tests/fixtures/e6-v1-port'
        result = subprocess.run(['node', '--disable-proto=throw', '--import', str(base / 'faults.mjs'), str(base / 'bridge.mjs'), str(self.parity.REPO)], input=json.dumps({'operation': name, 'args': args}, default=str), capture_output=True, text=True, env=env)
        self.calls += 1
        data = json.loads(result.stdout)
        if 'error' in data:
            raise self.frozen.Invalid(data['error'])
        return data['result']

    def paired(self, name, args, pyargs=None, kwargs=None):
        expected_error = actual_error = None
        try: expected = self.parity.observe(getattr(self.frozen, name), *(args if pyargs is None else pyargs), **(kwargs or {}))
        except (ValueError, OSError) as error:
            expected_error, expected = error, {'error': str(error)}
        try: actual = self.bridge(name, args)
        except (ValueError, OSError) as error:
            actual_error, actual = error, {'error': str(error)}
        if isinstance(expected, set): expected = sorted(expected)
        if isinstance(expected, bytes): expected = expected.decode()
        if isinstance(expected, Path): expected = str(expected)
        self.parity.same(self.case.id() + ':' + name, (0, (json.dumps(expected, sort_keys=True, indent=2) + '\n').encode(), b''), (0, (json.dumps(actual, sort_keys=True, indent=2) + '\n').encode(), b''))
        if actual_error: raise actual_error
        if expected_error: raise AssertionError('TS accepted frozen refusal: ' + str(expected_error))
        return actual

    def cli(self, operation, args):
        flags = []
        for key, value in vars(args).items():
            if value is None or key == 'operation': continue
            for item in value if isinstance(value, list) else [value]: flags.extend(['--' + key.replace('_', '-'), str(item)])
        env = dict(os.environ, E6_V1_FAULT=json.dumps(self.publication_fault() if operation == 'publish' else {}))
        result = subprocess.run(['node', '--disable-proto=throw', '--import', str(self.parity.REPO / 'tests/fixtures/e6-v1-port/faults.mjs'), str(self.parity.CANDIDATE), operation, *flags], capture_output=True, text=True, env=env)
        self.calls += 1
        data = json.loads(result.stdout)
        if 'error' in data:
            if data['error'].startswith('injected '): raise OSError(data['error'])
            raise self.frozen.Invalid(data['error'])
        return data

    def publication_fault(self):
        if not isinstance(self.write_json, mock.Mock): return {}
        side_effect = self.write_json.side_effect
        closure = dict(zip(side_effect.__code__.co_freevars, [cell.cell_contents for cell in side_effect.__closure__ or []]))
        if 'boundary' in closure: return {'boundary': closure['boundary']}
        case = closure['self']
        if 'source_revalidation' in case.id():
            return {'mutation': {'path': str(case.root / 'spec.md'), 'value': 'concurrent edit'}}
        candidate = copy.deepcopy(case.bundle)
        candidate['user_notes'].append('concurrent enrichment')
        return {'mutation': {'path': str(case.root / 'plan.json'), 'value': json.dumps(candidate, indent=2) + '\n'}}

    def admit(self, args):
        expected = self.parity.observe(self.frozen.admit, args)
        actual = self.cli('admit', args)
        self.parity.same(self.case.id() + ':admit', (0, (json.dumps(expected, sort_keys=True, indent=2) + '\n').encode(), b''), (0, (json.dumps(actual, sort_keys=True, indent=2) + '\n').encode(), b''))
        return actual

    def publish(self, args): return self.cli('publish', args)
    def migrate(self, args): return self.cli('migrate', args)
    def coverage(self, goal, gaps, stage):
        expected = []
        self.parity.observe(self.frozen.coverage, goal, expected, stage)
        actual = self.bridge('coverage', [goal, stage])
        self.parity.same(self.case.id()+':coverage', (0, json.dumps(expected, sort_keys=True).encode(), b''), (0, json.dumps(actual, sort_keys=True).encode(), b''))
        gaps.extend(actual)
    def read(self, path): return self.paired('read', [str(path)], [path])
    def digest(self, path): return self.paired('digest', [str(path)], [path])
    def add(self, gaps, *args): gaps.extend(self.bridge('add', args))
    def goal_revision(self, *args): return self.paired('goal_revision', args)
    def gate_dimensions(self, *args): return self.paired('gate_dimensions', args)
    def applies(self, *args): return self.paired('applies', args)
    def worktree_binding(self, *args): return self.paired('worktree_binding', args)
    def worktree_inputs(self, bundle, root): return self.paired('worktree_inputs', [bundle, str(root)], [bundle, root])
    def instruction_paths(self, bundle, root): return set(self.paired('instruction_paths', [bundle, str(root)], [bundle, root]))

    def typed_gate(self, root, bundle, gate, context, files_root=None, worktree=None):
        return self.paired('typed_gate', [str(root), bundle, gate, context, str(files_root) if files_root else None, worktree], [root, bundle, gate, context, files_root, worktree])

    def worktree_observation(self, identity, files, base, clean=False, inputs=()):
        return self.paired('worktree_observation', [str(identity), str(files), base, clean, list(inputs)], [identity, files, base, clean, inputs])

    def gate_subject(self, bundle, gate, sources, policy, execution_revision=None, worktree=None):
        return self.paired('gate_subject', [bundle, gate, sources, policy, execution_revision, worktree])

    def dependency_complete(self, bundle, gid, receipts, execution_revision=None, worktree=None):
        return self.paired('dependency_complete', [bundle, gid, receipts, execution_revision, worktree])

    def policy_admit(self, root, bundle, selected, context, stage, subject, resolved=None, files_root=None, worktree=None):
        if self.POLICY != self.frozen.POLICY:
            return self.retained_policy(root, bundle, selected, context, stage, subject, worktree)
        expected_resolved = []
        expected = self.parity.observe(self.frozen.policy_admit, root, bundle, selected, context, stage, subject, expected_resolved, files_root, worktree)
        actual = self.bridge('policy_admit', [str(root), bundle, selected, context, stage, subject, str(files_root) if files_root else None, worktree])
        left, right = {'gaps': expected, 'resolved': expected_resolved}, actual
        self.parity.same(self.case.id() + ':policy_admit', (0, (json.dumps(left, sort_keys=True, indent=2) + '\n').encode(), b''), (0, (json.dumps(right, sort_keys=True, indent=2) + '\n').encode(), b''))
        if resolved is not None: resolved.extend(actual['resolved'])
        return actual['gaps']

    def retained_policy(self, root, bundle, selected, context, stage, subject, worktree):
        # The original snapshot tests relax only root equality and source currency.
        # Represent those exact two relaxations as current disposable inputs, then
        # run BOTH unchanged validators over the same bytes. No shipping waiver.
        with tempfile.TemporaryDirectory(prefix='e6-retained-') as temporary:
            target = Path(temporary).resolve()
            for name in ['AGENTS.md', 'CLAUDE.md', 'GEMINI.md', '.rules.ts', '.ai/rules', 'tests', 'scripts']:
                source = Path(root) / name
                dest = target / name
                if source.is_dir(): shutil.copytree(source, dest, ignore=shutil.ignore_patterns('node_modules', '__pycache__', '.git'))
                elif source.is_file():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(source, dest)
            b, c = copy.deepcopy(bundle), copy.deepcopy(context)
            policy = self.frozen.read(Path(root) / self.POLICY)
            for source in policy['sources']:
                original = Path(root) / source['path']
                destination = target / source['path']
                if not destination.exists() and original.is_file():
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(original, destination)
            b['repository']['root'] = str(target)
            for goal in b['goals']: goal['repository']['root'] = str(target)
            c['repository'] = copy.deepcopy(b['repository'])
            policy['repository'] = copy.deepcopy(b['repository'])
            for source in policy['sources']:
                source['sha256'] = self.frozen.digest(target / source['path'])
            c['sources'] = copy.deepcopy(policy['sources'])
            for gate in policy['gates']:
                if gate['kind'] == 'protected_approval' and gate['binding']['subject']['mode'] == 'goal-scope':
                    binding = gate['binding']['subject']
                    binding['goal_sha256'] = self.frozen.goal_revision(b, binding['goal'])
            path = target / self.frozen.POLICY
            path.parent.mkdir(parents=True, exist_ok=True)
            self.frozen.write_json(path, policy)
            c['policy']['sha256'] = self.frozen.digest(path)
            original_policy = self.POLICY
            self.POLICY = self.frozen.POLICY
            try: return self.policy_admit(target, b, selected, c, stage, subject, worktree=worktree)
            finally: self.POLICY = original_policy

    def git_read(self, root, *args):
        if isinstance(self.subprocess.run, mock.Mock):
            with tempfile.TemporaryDirectory() as d:
                trace = Path(d) / 'git-argv.json'
                try: return self.bridge('git_read', [str(root), *args], {'gitFailure': str(trace)}).encode()
                finally:
                    if trace.exists(): self.subprocess.run(json.loads(trace.read_text()))
        return self.paired('git_read', [str(root), *args], [root, *args]).encode()


def run(parity, lib):
    sys.path.insert(0, str(lib))
    sys.path.insert(0, str(parity.REPO / 'tests'))
    frozen = importlib.import_module('readiness_contract')
    assert Path(frozen.__file__).resolve().parent == lib.resolve()
    adapter = Adapter(parity, frozen)
    modules = [importlib.import_module(name) for name in ['readiness_contract_test', 'readiness_mapped_test', 'readiness_scoped_test', 'readiness_worktree_test', 'autobahn_worktree_driver_integration_test', 'readiness_merge_driver_test']]
    mapping = []
    for module in modules:
        for alias in ('c', 'contract'):
            if getattr(module, alias, None) is frozen: setattr(module, alias, adapter)
        suite = unittest.defaultTestLoader.loadTestsFromModule(module)
        def cases(suite):
            for item in suite:
                if isinstance(item, unittest.TestSuite): yield from cases(item)
                else: yield item
        for case in cases(suite):
            adapter.case = case
            before = adapter.calls
            assertions = [0]
            for name in dir(unittest.TestCase):
                if name.startswith('assert'):
                    original = getattr(case, name)
                    def counted(*args, _original=original, **kwargs):
                        assertions[0] += 1
                        return _original(*args, **kwargs)
                    setattr(case, name, counted)
            stream = io.StringIO()
            result = unittest.TextTestRunner(stream=stream, verbosity=0).run(unittest.TestSuite([case]))
            mapping.append({'case': case.id(), 'ts_calls': adapter.calls-before, 'assertions': assertions[0], 'passed': result.wasSuccessful()})
            if result.wasSuccessful(): parity.ok('TS-bound scenario ' + case.id())
            else: parity.bad('TS-bound scenario ' + case.id(), stream.getvalue())
    print('scenario_mapping=' + json.dumps(mapping, sort_keys=True))
    print('scenario_methods=%d ts_import_calls=%d' % (len(mapping), adapter.calls))
    assertions = sum(row['assertions'] for row in mapping)
    if len(mapping) == 133 and assertions == 1005: parity.ok('original 133 methods / 1005 assertion-method calls retained')
    else: parity.bad('original scenario/assertion count changed', repr((len(mapping), assertions)))
    for name in ['ach_s01_readiness_policy_test.sh', 'xskp_p5_readiness_policy_test.sh']:
        path = parity.REPO / 'tests' / name
        body = path.read_text().split("<<'PYTEST'\n", 1)[1].rsplit('\nPYTEST', 1)[0]
        adapter.case = types.SimpleNamespace(id=lambda name=name: name)
        adapter.POLICY = frozen.POLICY
        before = adapter.calls
        # Bind the import only; retain every check and the two existing snapshot
        # relaxations. The shell/source files and retained JSON stay untouched.
        body = body.replace('import readiness_contract as rc', 'rc = adapter')
        namespace = {'adapter': adapter, '__name__': '__main__'}
        previous_argv = sys.argv
        sys.argv = [str(path), str(lib)]
        try:
            try: exec(compile(body, str(path), 'exec'), namespace)
            except SystemExit as exit:
                if exit.code: raise AssertionError('retained policy assertions failed')
            parity.ok('TS-bound retained assertions ' + name)
            print('retained_mapping=' + json.dumps({'case': name, 'assertions': namespace['passes'], 'ts_calls': adapter.calls-before}))
        except Exception as error: parity.bad('TS-bound retained assertions ' + name, str(error))
        finally: sys.argv = previous_argv
