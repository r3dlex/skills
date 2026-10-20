"""Public regressions found by comparing language/filesystem boundary semantics."""
import json
from pathlib import Path
import tempfile


def run(parity, lib):
    from readiness_fixture import fixture, write, digest
    names = ['constructor', 'toString', 'hasOwnProperty', 'newline-id', 'newline-digest', 'readiness-key-collision', 'measured-float', 'unbound-rule-symlink', 'invalid-utf8', 'migration-null-extensions', 'migration-worktree', 'publication-duplicate-graph-ids', 'publication-nonlist-nodes', 'orphan-crlf']
    for name in names:
        with tempfile.TemporaryDirectory(prefix='e6-edge-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            policy_path = '.ai/policies/readiness-policy.json'
            policy = json.loads((root / policy_path).read_text())
            operation = 'admit'
            if name in ['constructor', 'toString', 'hasOwnProperty', 'newline-id']:
                gid = 'G1\n' if name == 'newline-id' else name
                bundle['goals'][0]['id'] = gid
                policy['gates'][0]['scope']['goals'] = [gid]
                context['authority']['goals'] = [gid]
            if name == 'newline-digest': bundle['spec']['sha256'] += '\n'
            if name == 'readiness-key-collision': bundle['goals'][0]['readiness'] = {'implementation\nmerge': 'ready', 'preparation': 'ready'}
            if name == 'measured-float':
                bundle['goals'][0].update(coverage_status='measured', coverage_percent=80.0, legacy_safe_tdd=False)
                operation = 'publish'
            if name == 'unbound-rule-symlink':
                (root / '.ai/rules').mkdir()
                (root / '.ai/rules/alias').symlink_to(root / 'AGENTS.md')
            if name == 'migration-null-extensions': bundle['extensions'] = None
            if name.startswith('migration-'): operation = 'migrate'
            if name.startswith('publication-') or name == 'orphan-crlf': operation = 'publish'
            write(root, policy_path, policy)
            context['policy']['sha256'] = digest(root / policy_path)
            write(root, 'plan.json', bundle)
            write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            if name == 'invalid-utf8':
                path = root / 'direct.json'
                path.write_bytes(path.read_bytes().replace(b'local:chosen', b'local:\xffchosen'))
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            write(root, 'context.json', context)
            if name == 'publication-duplicate-graph-ids':
                graph = json.loads((root / '.ai/traceability/graph.json').read_text())
                graph['nodes'].extend([{'id': 'other', 'path': 'other'}, {'id': 'other', 'path': 'other'}])
                write(root, '.ai/traceability/graph.json', graph)
            if name == 'publication-nonlist-nodes': write(root, '.ai/traceability/graph.json', {'nodes': {}})
            if name == 'orphan-crlf':
                result = parity.run(parity.py_cmd(lib, 'publish', ['--root', str(root), '--bundle', str(root / 'plan.json')]))
                assert result[0] == 0, result
                entry = json.loads(result[1])['published']
                path = root / entry['artifacts']['handoff']['path']
                path.write_bytes(path.read_bytes().replace(b'\n', b'\r\n'))
                write(root, '.ai/workflows/northstar-readiness-v1.json', {'schema': 'readiness-contract/1', 'plans': []})
            args = [operation, '--root', str(root)]
            if operation == 'admit': args.extend(['--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])
            else: args.extend(['--bundle', str(root / 'plan.json')])
            if operation == 'migrate': args.extend(['--legacy', str(root / 'plan.json')])
            if name == 'migration-worktree': args.extend(['--worktree-root', str(root)])
            parity.compare_args('language-edge-' + name, lib, args)
            if name == 'measured-float':
                entry = json.loads(parity.run(parity.py_cmd(lib, 'publish', args[1:]))[1])['published']
                context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
                write(root, 'context.json', context)
                parity.compare_args('registered-measured-float', lib, ['admit', '--root', str(root), '--handoff', entry['id'], '--goal-id', 'G1', '--context', str(root / 'context.json')])
