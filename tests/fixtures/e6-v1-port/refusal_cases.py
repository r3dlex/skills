"""Target refusals not reached by single-field shape mutations."""
import copy
import json
from pathlib import Path
import tempfile


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    def extra_context(r, b, c, p): c['unsupported'] = True
    def extra_policy(r, b, c, p): p['unsupported'] = True
    def duplicate_sources(r, b, c, p): p['sources'].append(copy.deepcopy(p['sources'][0])); c['sources'] = copy.deepcopy(p['sources'])
    def contradiction(r, b, c, p): p['not_applicable']['fixtures'] = 'Contradiction'
    def duplicate_gates(r, b, c, p): p['gates'].append(copy.deepcopy(p['gates'][0]))
    def requirement_root(r, b, c, p): b['goals'][0]['requirements'] = [{'id': 'bad-root', 'kind': 'measured_coverage', 'stage': 'implementation', 'root': 'other'}]
    def execution_gate(r, b, c, p): b['goals'][0]['requirements'] = [{'id': 'execution-root', 'kind': 'measured_coverage', 'stage': 'implementation', 'root': 'execution'}]
    def executable(r, b, c, p): p['gates'].append({'id': 'executable', 'stage': 'implementation', 'scope': {'repository': True}, 'kind': 'executable_presence', 'path': 'tests/check.sh'})
    def owner_roles(r, b, c, p):
        p['gates'].append({'id': 'owner', 'kind': 'ownership', 'stage': 'implementation', 'scope': {'repository': True}, 'dimension': 'owners', 'binding': {'roles': []}})
        del p['not_applicable']['owners']
    def cycle(r, b, c, p):
        b['goals'].append(dict(copy.deepcopy(b['goals'][0]), id='G2', dependencies=['G1']))
        b['goals'][0]['dependencies'] = ['G2']
    mutations = {'unsupported-context': extra_context, 'unsupported-policy': extra_policy, 'duplicate-sources': duplicate_sources,
                 'contradictory-dimension': contradiction, 'duplicate-gates': duplicate_gates, 'invalid-gate-root': requirement_root,
                 'execution-gate-root': execution_gate, 'executable-unavailable': executable,
                 'verification-runtime': lambda r,b,c,p: b['goals'][0].update(verification=[{'cwd': 'missing', 'command': 'git diff --check'}]),
                 'embedded-null-gate': lambda r,b,c,p: b['goals'][0].update(requirements=[{'id': 'null-path', 'kind': 'file_digest', 'stage': 'implementation', 'path': '\0missing', 'sha256': '0'*64}]),
                 'unicode-exclusion-order': lambda r,b,c,p: p['not_applicable'].update({'\ue000': 'first', '\U0001f600': 'second'}),
                 'ownership-roles': owner_roles, 'dependency-cycle': cycle,
                 'coverage-required': lambda r,b,c,p: b['goals'][0].update(coverage_required=True),
                 'invalid-coverage-required': lambda r,b,c,p: b['goals'][0].update(coverage_required=0),
                 'multiple-direct-goals': lambda r,b,c,p: b['goals'].append(dict(copy.deepcopy(b['goals'][0]), id='G2'))}
    for name, change in mutations.items():
        with tempfile.TemporaryDirectory(prefix='e6-refusal-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            policy = json.loads((root / '.ai/policies/readiness-policy.json').read_text())
            change(root, bundle, context, policy)
            write(root, '.ai/policies/readiness-policy.json', policy)
            context['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
            write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            write(root, 'context.json', context)
            parity.compare_args('target-refusal-' + name, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])

    for name in ['missing-policy', 'missing-v3', 'malformed-v3', 'selector-conflict', 'direct-selector-conflict', 'missing-goal', 'duplicate-selection', 'plan-identity', 'duplicate-registration', 'spec-node-missing', 'enrichment-loss', 'enrichment-changed', 'orphan-nonfile', 'orphan-payload', 'orphan-identity', 'orphan-nodes', 'orphan-graph', 'legacy-direct', 'legacy-selection', 'context-duplicate', 'graph-conflict', 'registered-collision', 'publication-registry', 'publication-lock', 'enrichment-dict-type', 'enrichment-list-type', 'enrichment-list-id']:
        with tempfile.TemporaryDirectory(prefix='e6-refusal-selection-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            pub_args = ['publish', '--root', str(root), '--bundle', str(root / 'plan.json')]
            baseline = parity.run(parity.py_cmd(lib, 'publish', pub_args[1:]))
            assert baseline[0] == 0, baseline
            entry = json.loads(baseline[1])['published']
            context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
            write(root, 'context.json', context)
            registry_path = '.ai/workflows/northstar-readiness-v1.json'
            registry = json.loads((root / registry_path).read_text())
            args = ['admit', '--root', str(root), '--handoff', entry['id'], '--goal-id', 'G1', '--context', str(root / 'context.json')]
            if name == 'missing-policy': (root / '.ai/policies/readiness-policy.json').unlink()
            if name == 'missing-v3': (root / '.ai/matrix.json').unlink()
            if name == 'malformed-v3': write(root, '.ai/matrix.json', [])
            if name in ('selector-conflict', 'direct-selector-conflict'):
                write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
                if name == 'direct-selector-conflict': args = ['admit', '--root', str(root), '--goal-id', 'G1']
                args += ['--goal', str(root / 'direct.json')]
            if name == 'missing-goal': args[args.index('G1')] = 'absent'
            if name == 'duplicate-selection': args += ['--goal-id', 'G1']
            if name == 'legacy-direct':
                write(root, 'direct.json', {'schema': 'old', 'bundle': bundle})
                args = ['admit', '--root', str(root), '--goal', str(root / 'direct.json')]
            if name == 'legacy-selection':
                write(root, '.ai/workflows/repo-workflow.json', {'optional_branches': [{'id': 'northstar-handoff-old'}]})
                args[args.index(entry['id'])] = 'northstar-handoff-old'
            if name == 'context-duplicate':
                path = root / 'context.json'
                path.write_text(path.read_text().replace('"schema": "readiness-context/1"', '"schema": "old", "schema": "readiness-context/1"'))
            if name == 'plan-identity':
                bundle['id'] = 'other'
                path = entry['artifacts']['bundle']['path']
                write(root, path, bundle)
                registry['plans'][0]['artifacts']['bundle']['sha256'] = digest(root / path)
                write(root, registry_path, registry)
            if name in ('duplicate-registration', 'spec-node-missing', 'enrichment-loss', 'enrichment-changed') or name.startswith('orphan-'):
                args = pub_args
            if name in ('graph-conflict','registered-collision','publication-registry','publication-lock','enrichment-dict-type','enrichment-list-type','enrichment-list-id'): args = pub_args
            if name == 'duplicate-registration':
                registry['plans'].append(copy.deepcopy(entry))
                write(root, registry_path, registry)
            if name == 'spec-node-missing': write(root, '.ai/traceability/graph.json', {'nodes': [], 'edges': []})
            if name == 'publication-registry': write(root, registry_path, {'schema': 'old', 'plans': []})
            if name == 'publication-lock': (root / '.ai/workflows/.northstar-readiness-v1.lock').mkdir()
            if name == 'graph-conflict':
                bundle['extensions'] = {'note': 'new generation'}
                write(root, 'plan.json', bundle)
                generation = __import__('readiness_contract').canonical(bundle)
                graph = json.loads((root / '.ai/traceability/graph.json').read_text())
                graph['nodes'].append({'id': 'handoff:fixture:chosen:'+generation, 'path': 'wrong'})
                write(root, '.ai/traceability/graph.json', graph)
            if name == 'registered-collision':
                path = entry['artifacts']['graph']['path']
                graph = json.loads((root / path).read_text())
                graph['nodes'][0]['title'] = 'permitted enrichment changes artifact bytes'
                write(root, path, graph)
            if name in ('enrichment-loss', 'enrichment-changed'):
                old = copy.deepcopy(bundle)
                old['extensions'] = {'note': 'retain'}
                write(root, 'plan.json', old)
                result = parity.run(parity.py_cmd(lib, 'publish', pub_args[1:]))
                assert result[0] == 0, result
                if name == 'enrichment-changed': bundle['extensions'] = {'note': 'changed'}
                write(root, 'plan.json', bundle)
            if name in ('enrichment-dict-type','enrichment-list-type','enrichment-list-id'):
                bundle['extensions'] = {'notes': [{'id': 'N1', 'text': 'keep'}]}
                write(root, 'plan.json', bundle)
                result = parity.run(parity.py_cmd(lib, 'publish', pub_args[1:]))
                assert result[0] == 0, result
                if name == 'enrichment-dict-type': bundle['extensions'] = []
                else: bundle['extensions']['notes'] = None if name == 'enrichment-list-type' else []
                write(root, 'plan.json', bundle)
            if name.startswith('orphan-'):
                write(root, registry_path, {'schema': 'readiness-contract/1', 'plans': []})
                if name == 'orphan-nonfile':
                    path = root / entry['artifacts']['handoff']['path']
                    path.unlink(); path.mkdir()
                elif name == 'orphan-payload': (root / entry['artifacts']['handoff']['path']).write_text('wrong')
                else:
                    path = entry['artifacts']['graph']['path']
                    graph = json.loads((root / path).read_text())
                    if name == 'orphan-identity': graph['generation'] = '0'*64
                    if name == 'orphan-nodes': graph['nodes'].pop()
                    if name == 'orphan-graph': graph['edges'] = []
                    write(root, path, graph)
            parity.compare_args('target-refusal-' + name, lib, args)
    trust_cases(parity, lib)


def trust_cases(parity, lib):
    from readiness_fixture import fixture, write, digest
    for name in ['unapproved-anchor', 'unsupported-anchor', 'bad-expected', 'bad-actual', 'unavailable-anchor']:
        with tempfile.TemporaryDirectory(prefix='e6-trust-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            write(root, 'lock.json', {'commit': 'bad' if name == 'bad-actual' else 'a'*40})
            anchor = {'commit': 'bad' if name == 'bad-expected' else 'a'*40}
            if name == 'unsupported-anchor': anchor['extra'] = True
            write(root, 'anchor.json', anchor)
            ref = {'path': 'anchor.json', 'sha256': digest(root / 'anchor.json')}
            policy = json.loads((root / '.ai/policies/readiness-policy.json').read_text())
            if name != 'unapproved-anchor': policy['sources'].append(ref)
            context['sources'] = copy.deepcopy(policy['sources'])
            binding = {'lock': {'path': 'lock.json', 'sha256': digest(root / 'lock.json')}, 'anchor': ref}
            if name == 'unavailable-anchor': binding['anchor'] = {'path': 'missing.json', 'sha256': '0'*64}
            policy['gates'].append({'id': 'trust', 'kind': 'harness_trust', 'stage': 'implementation', 'scope': {'repository': True}, 'binding': binding})
            del policy['not_applicable']['harness_trust']
            write(root, '.ai/policies/readiness-policy.json', policy)
            context['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
            write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            write(root, 'context.json', context)
            parity.compare_args('target-trust-' + name, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
