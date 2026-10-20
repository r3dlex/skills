"""Systematic single-field mutation sweep over the frozen enforcement inputs."""
import copy
import json
from pathlib import Path
import tempfile


VALUES = [None, False, 0, '', 'wrong', [], {}]


def variants(value, path=()):
    if isinstance(value, dict):
        for key, child in value.items():
            yield path + (key,), 'delete', None
            for replacement in VALUES:
                if type(replacement) is not type(child) or replacement != child:
                    yield path + (key,), 'replace', replacement
            yield from variants(child, path + (key,))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            for replacement in VALUES:
                if type(replacement) is not type(child) or replacement != child:
                    yield path + (index,), 'replace', replacement
            yield from variants(child, path + (index,))


def mutate(value, path, action, replacement):
    parent = value
    for key in path[:-1]: parent = parent[key]
    if action == 'delete': del parent[path[-1]]
    else: parent[path[-1]] = copy.deepcopy(replacement)


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    with tempfile.TemporaryDirectory(prefix='e6-generated-') as temporary:
        root = Path(temporary).resolve()
        bundle, context = fixture(root)
        write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
        context['authority']['subject_sha256'] = digest(root / 'direct.json')
        policy = json.loads((root / '.ai/policies/readiness-policy.json').read_text())
        templates = {'bundle': bundle, 'context': context, 'policy': policy}
        count = 0
        for subject, template in templates.items():
            for path, action, replacement in variants(template):
                b, c, p = copy.deepcopy(bundle), copy.deepcopy(context), copy.deepcopy(policy)
                value = {'bundle': b, 'context': c, 'policy': p}[subject]
                mutate(value, path, action, replacement)
                write(root, '.ai/policies/readiness-policy.json', p)
                if subject == 'policy': c['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
                if subject == 'policy' and path[0] == 'sources': c['sources'] = copy.deepcopy(p.get('sources'))
                write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': b})
                if subject != 'context': c['authority']['subject_sha256'] = digest(root / 'direct.json')
                write(root, 'context.json', c)
                name = 'generated-%s:%s:%s:%s' % (subject, '/'.join(map(str, path)), action, json.dumps(replacement, sort_keys=True))
                parity.compare_args(name, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
                count += 1
        print('generated_mutations=%d' % count)

    cli = [[], ['--help'], ['-h'], ['wrong'], ['wrong', '--help'], ['admit', '--stage', 'bad', '--help'], ['admit', '--goal', '--help'], ['admit', '--unknown'], ['admit', 'extra'], ['admit', '--stage', 'bad'], ['--root', '.', 'admit'], ['admit', '--root=.'], ['admit', '--exe', 'x'], ['admit', '--goal-id'], ['admit', '--goal-id', '--context', 'x'], ['admit', '--goal', '-x'], ['admit', '--root', '-.1'], ['admit', '--root', '-1.']]
    for flag in ['root', 'handoff', 'goal-id', 'goal', 'context', 'execution-record', 'execution-root', 'worktree-root', 'base-commit', 'bundle', 'legacy', 'stage']:
        for operation in ['admit', 'publish', 'migrate']:
            cli.extend([[operation, '--' + flag], [operation, '--' + flag, '--root', '.']])
    cli += [['-'], ['-1'], ['admit', '--root', '-١'], ['admit', '--root', '-1e3'], ['admit', '--hel'], ['admit','--h'], ['admit','--h=x'], ['admit','-hfoo'], ['admit','-hh'], ['admit','-h?'], ['admit','-help'], ['admit','-hx=foo'], ['admit','-h--root'], ['admit','-h=foo'], ['admit','--help=foo'], ["not'a-choice"], ['admit','--stage',"not'a-stage"]]
    for args in cli:
        parity.compare_args('argv-' + repr(args), lib, args)
