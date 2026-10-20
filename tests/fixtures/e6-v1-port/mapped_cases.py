"""Mapped execution/source-shape sweep through the public CLI."""
import copy
import json
from pathlib import Path

from generated import variants, mutate


def run(parity, lib):
    from readiness_fixture import write, digest
    from readiness_mapped_test import MappedTests
    case = MappedTests('test_mapped_admission_without_application_governance_is_read_only')
    case.setUp()
    try:
        case.save()
        b, c, p = copy.deepcopy(case.bundle), copy.deepcopy(case.context), copy.deepcopy(case.policy)
        count = 0
        for subject, template in [('execution', b['execution']), ('policy-execution', p['execution']), ('context-execution', c['execution'])]:
            for path, action, replacement in variants(template):
                bundle, context, policy = copy.deepcopy(b), copy.deepcopy(c), copy.deepcopy(p)
                target = {'execution': bundle['execution'], 'policy-execution': policy['execution'], 'context-execution': context['execution']}[subject]
                mutate(target, path, action, replacement)
                write(case.root, '.ai/policies/readiness-policy.json', policy)
                context['policy']['sha256'] = digest(case.root / '.ai/policies/readiness-policy.json')
                write(case.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
                context['authority']['subject_sha256'] = digest(case.root / 'direct.json')
                write(case.root, 'context.json', context)
                args = ['admit', '--root', str(case.root), '--execution-root', str(case.execution), '--goal', str(case.root / 'direct.json'), '--context', str(case.root / 'context.json')]
                parity.compare_args('mapped-%s:%s:%s:%s' % (subject, '/'.join(map(str, path)), action, json.dumps(replacement, sort_keys=True)), lib, args)
                count += 1
        case.bundle, case.context, case.policy = copy.deepcopy(b), copy.deepcopy(c), copy.deepcopy(p)
        outside = case.base / 'outside-instructions'
        outside.mkdir()
        (outside / 'AGENTS.md').write_text('Unbound nested instructions')
        (case.execution / 'tests/linked').symlink_to(outside, target_is_directory=True)
        case.bundle['goals'][0]['scope'] = ['tests']
        case.save()
        parity.compare_args('mapped-nested-symlink-instructions', lib, ['admit', '--root', str(case.root), '--execution-root', str(case.execution), '--goal', str(case.root / 'direct.json'), '--context', str(case.root / 'context.json')])
        print('generated_mapped_mutations=%d' % (count + 1))
        for name in ['duplicate-sources', 'missing-target', 'result-revision', 'missing-execution-root']:
            case.bundle, case.context, case.policy = copy.deepcopy(b), copy.deepcopy(c), copy.deepcopy(p)
            # The symlink-specific probe above is over; restore its fixture only.
            alias = case.execution / 'tests/linked'
            if alias.is_symlink(): alias.unlink()
            if name == 'duplicate-sources': case.bundle['execution']['sources'].append(copy.deepcopy(case.bundle['execution']['sources'][0]))
            if name == 'missing-target': case.policy['gates'][-1]['stage'] = 'preparation'
            if name == 'result-revision': case.policy['gates'].append({'id': 'independent', 'kind': 'independent_result', 'stage': 'implementation', 'scope': {'repository': True}})
            case.save()
            if name == 'result-revision':
                case.context['results'].append({'gate': 'independent', 'status': 'pass', 'stage': 'implementation', 'scope': {'repository': True},
                    'subject_sha256': case.context['authority']['subject_sha256'], 'issuer': 'fixture', 'execution_revision': 'c'*40})
                write(case.root, 'context.json', case.context)
            args = ['admit', '--root', str(case.root), '--goal', str(case.root / 'direct.json'), '--context', str(case.root / 'context.json')]
            if name != 'missing-execution-root': args += ['--execution-root', str(case.execution)]
            parity.compare_args('mapped-refusal-' + name, lib, args)
    finally:
        case.doCleanups()
