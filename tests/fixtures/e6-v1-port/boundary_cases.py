"""Paired publication boundaries and filesystem races; fixture files only."""
import json
import os
from pathlib import Path
import subprocess
import tempfile


def snapshot(root):
    return {p.relative_to(root).as_posix(): (None if p.is_dir() else p.read_bytes(), p.stat().st_mode & 0o7777) for p in root.rglob('*')}


def restore(root, files):
    for path in sorted(root.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        name = path.relative_to(root).as_posix()
        if path.is_file() and name not in files: path.unlink()
        elif path.is_dir():
            try: path.rmdir()
            except OSError: pass
    for name, (raw, mode) in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        if raw is None: path.mkdir(exist_ok=True)
        else: path.write_bytes(raw)
        path.chmod(mode)


def pair(parity, lib, args, fault):
    previous = os.environ.get('E6_V1_FAULT')
    os.environ['E6_V1_FAULT'] = json.dumps(fault)
    try:
        left = parity.run(parity.py_cmd(lib, args[0], args[1:]))
    finally:
        if previous is None: os.environ.pop('E6_V1_FAULT', None)
        else: os.environ['E6_V1_FAULT'] = previous
    return left


def candidate(parity, args, fault):
    result = subprocess.run(['node', '--disable-proto=throw', '--import', str(parity.REPO / 'tests/fixtures/e6-v1-port/faults.mjs'), str(parity.CANDIDATE), *args], capture_output=True, env=dict(os.environ, E6_V1_FAULT=json.dumps(fault)))
    return result.returncode, result.stdout, result.stderr


def run(parity, lib):
    from readiness_fixture import fixture, write
    boundaries = ['write-before', 'rename-before', 'rename-after', 'graph-before', 'graph-after', 'register-before', 'register-after']
    mutations = [(moment, target) for moment in ['payload', 'graph'] for target in ['spec.md', 'plan.json', '.ai/workflows/northstar-readiness-v1.json', '.ai/traceability/graph.json']]
    cases = [(name, {'boundary': name}) for name in boundaries] + [(moment + '-' + target, {'moment': moment, 'target': target}) for moment, target in mutations]
    for name, fault in cases:
        with tempfile.TemporaryDirectory(prefix='e6-boundary-') as temporary:
            root = Path(temporary).resolve()
            bundle, _ = fixture(root)
            args = ['publish', '--root', str(root), '--bundle', str(root / 'plan.json')]
            assert parity.run(parity.py_cmd(lib, args[0], args[1:]))[0] == 0
            bundle['extensions'] = {'boundary': name}
            write(root, 'plan.json', bundle)
            if 'target' in fault: fault['mutation'] = {'path': str(root / fault.pop('target')), 'value': 'concurrent edit'}
            before = snapshot(root)
            left = pair(parity, lib, args, fault)
            after = snapshot(root)
            restore(root, before)
            right = candidate(parity, args, fault)
            parity.same('publication-boundary-' + name, left, right)
            if after == snapshot(root): parity.ok('publication side effects ' + name)
            else: parity.bad('publication side effects ' + name)
    races(parity, lib)
    with tempfile.TemporaryDirectory(prefix='e6-candidate-read-') as temporary:
        root = Path(temporary).resolve()
        fixture(root)
        path = root / 'plan.json'
        args = ['publish', '--root', str(root), '--bundle', str(path)]
        fault = {'candidate_read': str(path), 'mutation': {'path': str(path), 'value': 'concurrent edit'}}
        before = snapshot(root)
        left = pair(parity, lib, args, fault)
        after = snapshot(root)
        restore(root, before)
        right = candidate(parity, args, fault)
        parity.same('candidate-changed-before-lock', left, right)
        if after == snapshot(root): parity.ok('candidate before-lock side effects')
        else: parity.bad('candidate before-lock side effects')


def races(parity, lib):
    from readiness_fixture import fixture, write, digest
    from readiness_mapped_test import MappedTests
    from readiness_worktree_test import WorktreeTests
    with tempfile.TemporaryDirectory(prefix='e6-path-race-') as temporary:
        root = Path(temporary).resolve()
        bundle, context = fixture(root)
        path, outside, saved = root / 'race.md', root.parent / (root.name+'-outside'), root / 'saved.md'
        path.write_bytes((root / 'spec.md').read_bytes())
        outside.write_bytes(path.read_bytes())
        bundle['spec'] = {'path': 'race.md', 'sha256': digest(path)}
        write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
        context['authority']['subject_sha256'] = digest(root / 'direct.json')
        write(root, 'context.json', context)
        args = ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')]
        fault = {'race': {'path': str(path), 'saved': str(saved), 'outside': str(outside), 'when': 'before'}}
        try:
            left = pair(parity, lib, args, fault)
            path.unlink(); saved.rename(path)
            right = candidate(parity, args, fault)
            parity.same('filesystem-outside-root-race', left, right)
        finally: outside.unlink(missing_ok=True)
    case = MappedTests('test_mapped_admission_without_application_governance_is_read_only')
    case.setUp()
    try:
        case.save()
        outside, saved = case.base / 'outside', case.base / 'saved'
        outside.mkdir()
        args = ['admit', '--root', str(case.root), '--execution-root', str(case.execution), '--goal', str(case.root / 'direct.json'), '--context', str(case.root / 'context.json')]
        fault = {'race': {'path': str(case.execution), 'saved': str(saved), 'outside': str(outside), 'when': 'after', 'directory': True}}
        left = pair(parity, lib, args, fault)
        case.execution.unlink(); saved.rename(case.execution)
        right = candidate(parity, args, fault)
        parity.same('filesystem-execution-root-symlink-race', left, right)
    finally: case.doCleanups()
    case = WorktreeTests('test_admission_keeps_canonical_identity_and_reads_only_worktree')
    case.setUp()
    try:
        args = case.admission_fixture()
        path, outside, saved = case.files / 'input.txt', case.home / 'outside', case.home / 'saved'
        outside.write_bytes(path.read_bytes())
        fault = {'lstat_race': {'path': str(path), 'saved': str(saved), 'outside': str(outside)}}
        flags = ['admit']
        for key, value in vars(args).items():
            if value is not None: flags += ['--'+key.replace('_','-'), str(value)]
        left = pair(parity, lib, flags, fault)
        path.unlink(); saved.rename(path)
        right = candidate(parity, flags, fault)
        parity.same('filesystem-worktree-symlink-input-race', left, right)
    finally: case.doCleanups()
