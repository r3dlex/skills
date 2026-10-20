"""Source-graph field semantics and repeat-publication identities."""
import copy
import json
from pathlib import Path
import tempfile

from boundary_cases import snapshot, restore


def run(parity, lib):
    from readiness_fixture import fixture, write
    for name in ['null-backlinks', 'string-backlinks', 'dict-backlinks', 'null-edges', 'dict-edges', 'scalar-node', 'missing-node-id', 'null-source-graph', 'bool-source-graph', 'integer-spec-id', 'float-spec-id', 'false-spec-id', 'prototype-spec-id', 'duplicate-numeric-ids', 'numeric-enrichment-id']:
        with tempfile.TemporaryDirectory(prefix='e6-publisher-') as temporary:
            root = Path(temporary).resolve()
            bundle, _ = fixture(root)
            if name == 'numeric-enrichment-id':
                bundle['extensions'] = {'notes': [{'id': 1, 'note': 'retained'}]}
                write(root, 'plan.json', bundle)
            graph = json.loads((root / '.ai/traceability/graph.json').read_text())
            if name.endswith('backlinks'): graph['nodes'][0]['backlinks'] = {'null-backlinks': None, 'string-backlinks': '', 'dict-backlinks': {}}[name]
            if name == 'null-edges': graph['edges'] = None
            if name == 'dict-edges': graph['edges'] = {}
            if name == 'scalar-node': graph['nodes'].append(False)
            if name == 'missing-node-id': graph['nodes'].append({'path': 'other'})
            if name == 'null-source-graph': graph = None
            if name == 'bool-source-graph': graph = False
            if name in ['integer-spec-id', 'float-spec-id', 'false-spec-id', 'prototype-spec-id']:
                graph['nodes'][0]['id'] = {'integer-spec-id': 0, 'float-spec-id': 0.0, 'false-spec-id': False, 'prototype-spec-id': 'constructor'}[name]
            if name == 'duplicate-numeric-ids': graph['nodes'] += [{'id': 0}, {'id': False}]
            write(root, '.ai/traceability/graph.json', graph)
            args = ['publish', '--root', str(root), '--bundle', str(root / 'plan.json')]
            before = snapshot(root)
            left = parity.run(parity.py_cmd(lib, args[0], args[1:]))
            after = snapshot(root)
            restore(root, before)
            right = parity.run(parity.ts_cmd(args[0], args[1:]))
            parity.same('publication-source-' + name, left, right)
            if after == snapshot(root): parity.ok('publication source bytes/modes ' + name)
            else: parity.bad('publication source bytes/modes ' + name)
            if left[0] == 0: parity.compare_args('publication-repeat-' + name, lib, args)
