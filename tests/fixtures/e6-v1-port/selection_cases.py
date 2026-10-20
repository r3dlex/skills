"""Registered selection, immutable artifacts and publication visibility shapes."""
import copy
import json
from pathlib import Path
import tempfile

from generated import variants, mutate


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    with tempfile.TemporaryDirectory(prefix='e6-selection-') as temporary:
        root = Path(temporary).resolve()
        bundle, context = fixture(root)
        publication = parity.run(parity.py_cmd(lib, 'publish', ['--root', str(root), '--bundle', str(root / 'plan.json')]))
        assert publication[0] == 0, publication
        entry = json.loads(publication[1])['published']
        registry = {'schema': 'readiness-contract/1', 'plans': [entry]}
        context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
        write(root, 'context.json', context)
        args = ['admit', '--root', str(root), '--handoff', entry['id'], '--goal-id', 'G1', '--context', str(root / 'context.json')]
        count = 0
        for path, action, replacement in variants(registry):
            current = copy.deepcopy(registry)
            mutate(current, path, action, replacement)
            write(root, '.ai/workflows/northstar-readiness-v1.json', current)
            parity.compare_args('selection-registry:%s:%s:%s' % ('/'.join(map(str, path)), action, json.dumps(replacement, sort_keys=True)), lib, args)
            count += 1
        write(root, '.ai/workflows/northstar-readiness-v1.json', registry)
        graph_path = root / entry['artifacts']['graph']['path']
        original = graph_path.read_bytes()
        graph = json.loads(original)
        for path, action, replacement in variants(graph):
            current = copy.deepcopy(graph)
            mutate(current, path, action, replacement)
            write(root, entry['artifacts']['graph']['path'], current)
            registration = copy.deepcopy(registry)
            registration['plans'][0]['artifacts']['graph']['sha256'] = digest(graph_path)
            write(root, '.ai/workflows/northstar-readiness-v1.json', registration)
            parity.compare_args('selection-graph:%s:%s:%s' % ('/'.join(map(str, path)), action, json.dumps(replacement, sort_keys=True)), lib, args)
            count += 1
        graph_path.write_bytes(original)
        write(root, '.ai/workflows/northstar-readiness-v1.json', registry)
        for name, change in [
            ('duplicate-goals', lambda b: b['goals'].append(copy.deepcopy(b['goals'][0]))),
            ('unknown-dependency', lambda b: b['goals'][0].update(dependencies=['missing'])),
            ('self-dependency', lambda b: b['goals'][0].update(dependencies=['G1'])),
            ('generation-digest', lambda b: b.update(extensions={'note': 'different bytes'})),
        ]:
            current = copy.deepcopy(bundle)
            change(current)
            write(root, entry['artifacts']['bundle']['path'], current)
            registration = copy.deepcopy(registry)
            registration['plans'][0]['artifacts']['bundle']['sha256'] = digest(root / entry['artifacts']['bundle']['path'])
            write(root, '.ai/workflows/northstar-readiness-v1.json', registration)
            parity.compare_args('selection-' + name, lib, args)
        print('generated_selection_mutations=%d' % (count + 4))
