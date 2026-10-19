"""Keep deep JSON acceptance without copying the reference's fatal preservation bug.

The frozen helper raises an uncaught RecursionError on republication at 1100
nested objects. That fatal interpreter failure is NOT an interpreter-diagnostic
normalization: only that exact pathological republication is excluded. Its
first publication, sane-depth republications and deep admissions stay paired.
"""
import json
from pathlib import Path
import tempfile

from boundary_cases import snapshot, restore


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    for depth in (1, 900, 1100, 3000):
        with tempfile.TemporaryDirectory(prefix='e6-depth-admit-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            bundle['extensions'] = {'payload': '__NESTED__'}
            raw = json.dumps({'schema': 'direct-goal/1', 'bundle': bundle}).replace('"__NESTED__"', '[' * depth + '0' + ']' * depth)
            (root / 'direct.json').write_text(raw)
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            write(root, 'context.json', context)
            parity.compare_args('depth-admission-%d' % depth, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
    for depth in (20, 100, 1100):
        with tempfile.TemporaryDirectory(prefix='e6-depth-publish-') as temporary:
            root = Path(temporary).resolve()
            bundle, _ = fixture(root)
            bundle['extensions'] = {'payload': '__NESTED__'}
            raw = json.dumps(bundle).replace('"__NESTED__"', '{"node":' * depth + '0' + '}' * depth)
            (root / 'plan.json').write_text(raw)
            before = snapshot(root)
            args = ['publish', '--root', str(root), '--bundle', str(root / 'plan.json')]
            left = parity.run(parity.py_cmd(lib, 'publish', args[1:]))
            after = snapshot(root)
            restore(root, before)
            right = parity.run(parity.ts_cmd('publish', args[1:]))
            parity.same('depth-first-publication-%d' % depth, left, right)
            if after == snapshot(root): parity.ok('depth-publication-bytes-%d' % depth)
            else: parity.bad('depth-publication-bytes-%d' % depth)
            if depth < 1100:
                parity.compare_args('depth-republication-%d' % depth, lib, args)
            else:
                # Do not run or mask the fatal reference call in required parity.
                result = parity.run(parity.ts_cmd('publish', args[1:]))
                if result == right and after == snapshot(root): parity.ok('depth-1100-TS-safe-republication (known frozen-reference limitation)')
                else: parity.bad('depth-1100-TS-safe-republication')
