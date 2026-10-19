"""Observe frozen code coverage without changing its bytes or decisions."""
import importlib
import json
import os
from pathlib import Path
import sys

lib = Path(sys.argv[1])
sys.path.insert(0, str(lib))
sys.argv = [str(lib / 'readiness_contract.py'), *sys.argv[2:]]
c = importlib.import_module('readiness_contract')
fault = json.loads(os.environ.get('E6_V1_FAULT', '{}'))
if fault:
    original_read = c.read
    original_write, original_rename, original_replace, original_resolve, original_lstat = c.write_json, Path.rename, c.os.replace, Path.resolve, Path.lstat
    armed = False
    def fail(point):
        if fault.get('boundary') == point: raise OSError('injected ' + point)
    def mutate():
        if fault.get('mutation'):
            Path(fault['mutation']['path']).write_text(fault['mutation']['value'])
    def read(path):
        value = original_read(path)
        if str(path) == fault.get('candidate_read'): mutate()
        return value
    def write_json(path, value):
        fail('write-before')
        original_write(path, value)
        if path.name == 'goals.json' and fault.get('moment') != 'graph': mutate()
    def rename(path, target):
        fail('rename-before')
        result = original_rename(path, target)
        fail('rename-after')
        return result
    def replace(source, target):
        kind = 'register' if Path(target).name == 'northstar-readiness-v1.json' else 'graph'
        fail(kind + '-before')
        result = original_replace(source, target)
        if kind == 'graph' and fault.get('moment') == 'graph': mutate()
        fail(kind + '-after')
        return result
    def race(path):
        spec = fault['race']
        original_rename(path, spec['saved'])
        path.symlink_to(spec['outside'], target_is_directory=spec.get('directory', False))
    def resolve(path, *args, **kwargs):
        global armed
        spec = fault.get('race')
        hit = spec and str(path) == spec['path'] and not path.is_symlink()
        if hit and spec['when'] == 'before': race(path)
        result = original_resolve(path, *args, **kwargs)
        if hit and spec['when'] == 'after': race(path)
        if fault.get('lstat_race') and str(path) == fault['lstat_race']['path']: armed = True
        return result
    def lstat(path, *args, **kwargs):
        global armed
        spec = fault.get('lstat_race')
        if spec and armed and str(path) == spec['path']:
            armed = False
            original_rename(path, spec['saved'])
            path.symlink_to(spec['outside'])
        return original_lstat(path, *args, **kwargs)
    c.write_json, Path.rename, c.os.replace, Path.resolve, Path.lstat = write_json, rename, replace, resolve, lstat
    c.read = read
lines, refusals, diagnostics, refusal_sites = set(), set(), set(), set()
exception_sites, gate_branches = set(), set()

def trace(frame, event, arg):
    name = frame.f_code.co_filename.rsplit('/', 1)[-1]
    if name not in ('readiness_contract.py', 'verification.py'): return None
    if event == 'line': lines.add((name, frame.f_lineno))
    if event == 'line' and 'error' in frame.f_locals and frame.f_lineno in (534,644,657,719,741,786,908,932,1165,148,155,168):
        exception_sites.add((name, frame.f_lineno, type(frame.f_locals['error']).__name__))
    if event == 'line' and name == 'readiness_contract.py' and frame.f_lineno == 785:
        error = frame.f_locals['error']
        gate_branches.add(('unknown' if any(token in str(error) for token in ('unavailable','missing','required','No such file')) else 'blocked', type(error).__name__))
    if event == 'call' and frame.f_code.co_name == 'require' and not frame.f_locals.get('value'):
        refusals.add(str(frame.f_locals.get('message')))
        refusal_sites.add((name, frame.f_back.f_lineno))
    if event == 'call' and frame.f_code.co_name == 'stop':
        refusals.add(str(frame.f_locals.get('message')))
        refusal_sites.add((name, frame.f_back.f_lineno))
    if event == 'exception': diagnostics.add((name, frame.f_lineno, arg[0].__name__))
    return trace

sys.settrace(trace)
try:
    result = c.main()
finally:
    sys.settrace(None)
    path = os.environ.get('E6_V1_TRACE')
    if path: Path(path).write_text(json.dumps({'lines': sorted(lines), 'refusals': sorted(refusals), 'diagnostics': sorted(diagnostics), 'refusal_sites': sorted(refusal_sites), 'exception_sites': sorted(exception_sites), 'gate_branches': sorted(gate_branches)}))
sys.exit(result)
