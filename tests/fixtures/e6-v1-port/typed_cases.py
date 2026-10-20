"""Generate binding/receipt mutations for every policy and additive predicate."""
import copy
import importlib
import json
from pathlib import Path
import sys
import tempfile

from generated import variants, mutate


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    sys.path.insert(0, str(lib))
    frozen = importlib.import_module('readiness_contract')
    assert Path(frozen.__file__).resolve().parent == lib.resolve()
    count = 0
    with tempfile.TemporaryDirectory(prefix='e6-typed-') as temporary:
        root = Path(temporary).resolve()
        template, base_context = fixture(root)
        (root / 'tests/check.sh').chmod(0o755)
        write(root, 'lock.json', {'commit': 'a'*40})
        write(root, 'anchor.json', {'commit': 'a'*40})
        ref = lambda name: {'path': name, 'sha256': digest(root / name)}
        profiles = {
            'ownership': {'roles': ['owner', 'reviewer']},
            'branch_target': {'target': 'main', 'branch': 'feature'},
            'fixture': {'file': ref('tests/check.sh'), 'command': 'bash tests/check.sh', 'isolation': 'temporary-directory', 'tool': 'bash'},
            'tooling': {'tool': 'bash'},
            'protected_approval': {'subject': {'mode': 'full-file', 'file': ref('evidence.txt')}},
            'goal_approval': {'subject': {'mode': 'goal-scope', 'goal': 'G1', 'goal_sha256': frozen.goal_revision(template, 'G1')}},
            'harness_trust': {'lock': ref('lock.json'), 'anchor': ref('anchor.json')},
            'independent_result': None,
        }
        original_policy = json.loads((root / '.ai/policies/readiness-policy.json').read_text())
        for profile, binding in profiles.items():
            kind = 'protected_approval' if profile == 'goal_approval' else profile
            baseline_gate = {'id': 'generated-proof', 'kind': kind, 'stage': 'implementation', 'scope': {'goals': ['G1']}}
            if binding is not None: baseline_gate['binding'] = binding
            baseline_receipt = {'gate': baseline_gate['id'], 'status': 'pass', 'stage': 'implementation', 'scope': baseline_gate['scope'], 'issuer': 'fixture-independent', 'subject_sha256': '0'*64}
            if binding is not None:
                baseline_receipt.update(observed_at='2000-01-01T00:00:00Z', expires_at='2099-01-01T00:00:00Z', evidence=['local:fixture'], value={'owner': 'Ada', 'reviewer': 'Grace'} if kind == 'ownership' else binding)
            cases = [('baseline', (), '', None)]
            if profile == 'tooling': cases.append(('gate', ('binding','tool'), 'replace', 'bash\n'))
            if profile == 'branch_target':
                for value in ['feature\x85name', 'feature\ufeffname']: cases.append(('gate', ('binding','branch'), 'replace', value))
            for subject, value in [('gate', baseline_gate), ('receipt', baseline_receipt)]:
                cases.extend((subject, path, action, replacement) for path, action, replacement in variants(value))
                cases.append((subject, ('extra',), 'replace', True))
            if profile == 'tooling':
                for value in [float('nan'), float('inf'), float('-inf'), {'quote': "it's", 'unicode': '\ufeff'}]:
                    cases.append(('receipt', ('evidence', 0), 'replace', value))
                for value in ['https://example.invalid/\ufeffSYNTHETIC-SECRET', 'https://example.invalid/\x1cvisible']:
                    cases.append(('receipt', ('evidence', 0), 'replace', value))
                for value in ['2000-02-30T00:00:00Z', '2000-13-01T00:00:00Z', '0000-01-01T00:00:00Z',
                              '2000-01-01T24:00:00Z', '2000-01-01T00:00:00z', '2000-01-01T12.5Z',
                              '2000-01-01T24Z', '2000-01-01T24:00:01Z', '2000-01-01T24:00:00.000001Z', '9999-12-31T24:00:00Z',
                              '2000-01-01Z00:00:00Z',
                              '20000101T120000Z', '2000-W01-1T00:00:00Z', '2000W011T00:00:00+00:99',
                              '2000-01-01T00:00:00+23:59:60', '2000-01-01T00:00:00',
                              '2000-01-01T00:00:00.1234567+01:02:03.1234567', '2000-01-01T12:34.5Z']:
                    cases.append(('receipt', ('observed_at',), 'replace', value))
            for subject, path, action, replacement in cases:
                bundle, context, policy = copy.deepcopy(template), copy.deepcopy(base_context), copy.deepcopy(original_policy)
                gate, receipt = copy.deepcopy(baseline_gate), copy.deepcopy(baseline_receipt)
                if subject == 'gate': mutate(gate, path, action, replacement)
                if kind == 'harness_trust':
                    policy['sources'].append(ref('anchor.json'))
                    context['sources'] = copy.deepcopy(policy['sources'])
                policy['gates'].append(gate)
                for dimension in frozen.gate_dimensions(baseline_gate): policy['not_applicable'].pop(dimension, None)
                write(root, '.ai/policies/readiness-policy.json', policy)
                context['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
                receipt['subject_sha256'] = frozen.gate_subject(bundle, gate, context['sources'], context['policy']) if subject != 'gate' or gate.get('scope') == {'goals': ['G1']} else '0'*64
                if subject == 'receipt': mutate(receipt, path, action, replacement)
                context['results'] = [receipt]
                write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
                context['authority']['subject_sha256'] = digest(root / 'direct.json')
                if kind == 'independent_result' and not (subject == 'receipt' and path == ('subject_sha256',)):
                    receipt['subject_sha256'] = context['authority']['subject_sha256']
                write(root, 'context.json', context)
                name = 'typed-%s:%s:%s:%s:%s' % (profile, subject, '/'.join(map(str, path)), action, json.dumps(replacement, sort_keys=True))
                parity.compare_args(name, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
                count += 1
            bundle, context, policy = copy.deepcopy(template), copy.deepcopy(base_context), copy.deepcopy(original_policy)
            requirement = copy.deepcopy(baseline_gate)
            requirement['scope'] = {'goals': ['unrelated-scope-must-not-win']}
            bundle['goals'][0]['requirements'] = [requirement]
            effective = dict(requirement, scope={'goals': ['G1']})
            if kind == 'harness_trust': policy['sources'].append(ref('anchor.json'))
            context['sources'] = copy.deepcopy(policy['sources'])
            write(root, '.ai/policies/readiness-policy.json', policy)
            context['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
            receipt = copy.deepcopy(baseline_receipt)
            receipt['scope'] = effective['scope']
            receipt['subject_sha256'] = frozen.gate_subject(bundle, effective, context['sources'], context['policy'])
            context['results'] = [receipt]
            write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            if kind == 'independent_result': receipt['subject_sha256'] = context['authority']['subject_sha256']
            write(root, 'context.json', context)
            parity.compare_args('additive-typed-route-' + profile, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
            count += 1
        print('generated_typed_mutations=%d' % count)
