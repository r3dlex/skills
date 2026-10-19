"""Additional public-entrypoint differential cases; no alternate validator."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from urllib.parse import quote


def run(parity, lib):
    sys.path.insert(0, str(parity.REPO / 'tests'))
    from readiness_fixture import fixture, write, digest
    from readiness_merge_driver_test import MergeDriverTests

    mutations = {
        'incomplete': lambda r, b, c: b.update(planning_complete=False),
        'blocked': lambda r, b, c: b.update(status='blocked'),
        'superseded': lambda r, b, c: b.update(status='superseded'),
        'extra-readiness': lambda r, b, c: b['goals'][0]['readiness'].update(extra='ready'),
        'coverage-null-status': lambda r, b, c: b['goals'][0].update(coverage_status=None),
        'null-requirements': lambda r, b, c: b['goals'][0].update(requirements=None),
    }
    requirements = {
        'file': {'kind': 'file_digest', 'path': 'absent.txt', 'sha256': '0'*64},
        'executable': {'kind': 'executable_presence', 'path': 'absent.sh'},
        'measured': {'kind': 'measured_coverage'},
        'unsupported': {'kind': 'not_a_predicate'},
        'owner': {'kind': 'ownership', 'binding': {'roles': ['owner']}},
    }
    for name, requirement in requirements.items():
        def change(r, b, c, requirement=requirement):
            b['goals'][0]['requirements'] = [dict(requirement, id='added', stage='implementation')]
        mutations['requirement-' + name] = change
    for name, change in mutations.items():
        with tempfile.TemporaryDirectory(prefix='e6-differential-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            change(root, bundle, context)
            write(root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            context['authority']['subject_sha256'] = digest(root / 'direct.json')
            write(root, 'context.json', context)
            parity.compare_args('direct-' + name, lib, ['admit', '--root', str(root), '--goal', str(root / 'direct.json'), '--context', str(root / 'context.json')])

    for raw in ['{"control":"\\b\\f"}', '{"number":1.0}', '{"coverage_percent":80.0}',
                '{"x":0.000001}', '{"x":9007199254740993}', '{"x":1e20}',
                '{"x":-0.0}', '{"\\ue000":1,"\\ud83d\\ude00":2}']:
        script = "import {read,canonical,dumps} from './04-validate-handoff/autobahn/lib/json.mjs'; const v=read(process.argv[1]); console.log(dumps(v,null,true,true)); console.log(canonical(v));"
        value = json.loads(raw)
        expected = json.dumps(value, sort_keys=True, separators=(',', ':')) + '\n' + parity.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()) + '\n'
        with tempfile.TemporaryDirectory(prefix='e6-canonical-') as temporary:
            source = Path(temporary) / 'input.json'
            source.write_text(raw)
            parity.same('canonical-export-' + raw, (0, expected.encode(), b''), parity.run(['node', '--input-type=module', '-e', script, str(source)]))

    for name in ['baseline', *requirements, 'incomplete', 'blocked', 'superseded', 'extra-readiness']:
        case = MergeDriverTests('test_ready_exact_direct_goal_passes_without_granting_authority')
        case.setUp()
        try:
            bundle, context = copy.deepcopy(case.bundle), copy.deepcopy(case.context)
            goal = bundle['goals'][0]
            if name in requirements:
                goal['requirements'] = [dict(requirements[name], id='added', stage='merge')]
            elif name in mutations:
                mutations[name](case.root, bundle, context)
            write(case.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            write(case.root, 'record.json', goal)
            context['authority']['subject_sha256'] = digest(case.root / 'direct.json')
            write(case.root, 'context.json', context)
            args = ['admit', '--root', str(case.root), '--goal', str(case.root / 'direct.json'), '--execution-record', str(case.root / 'record.json'), '--context', str(case.root / 'context.json'), '--stage', 'merge']
            parity.compare_args('driver-admission-' + name, lib, args)
            result = case.run_driver()
            expected = name == 'baseline'
            if (result.returncode == 0) == expected and (case.root / 'VERIFIED').exists() == expected and (expected or 'readiness' in result.stdout + result.stderr):
                parity.ok('public-pre-merge-' + name)
            else:
                parity.bad('public-pre-merge-' + name, result.stdout + result.stderr)
        finally:
            case.doCleanups()

    for boundary in ['payload-spec', 'graph-spec', 'payload-candidate', 'payload-registry', 'payload-graph']:
        with tempfile.TemporaryDirectory(prefix='e6-publication-') as temporary:
            root = Path(temporary).resolve()
            bundle, _ = fixture(root)
            args = ['publish', '--root', str(root), '--bundle', str(root / 'plan.json')]
            baseline = parity.run(parity.py_cmd(lib, 'publish', args[1:]))
            assert baseline[0] == 0, baseline
            before = (root / '.ai/workflows/northstar-readiness-v1.json').read_bytes()
            bundle['extensions'] = {'note': boundary}
            write(root, 'plan.json', bundle)
            hook = '''import fs from 'node:fs'; import {syncBuiltinESMExports} from 'node:module';
const originalWrite = fs.writeFileSync, originalRename = fs.renameSync;
let changed = false;
function mutate() { if (!changed) { changed = true; originalWrite(process.env.E6_MUTATE_PATH, process.env.E6_MUTATE_VALUE); } }
fs.writeFileSync = function(path,...args) { const result = originalWrite(path,...args); if (String(path).endsWith('/goals.json') && process.env.E6_BOUNDARY === 'payload') mutate(); return result; };
fs.renameSync = function(path,target) { const result = originalRename(path,target); if (String(target).endsWith('/.ai/traceability/graph.json') && process.env.E6_BOUNDARY === 'graph') mutate(); return result; };
syncBuiltinESMExports();'''
            moment, target = boundary.split('-')
            paths = {'spec': 'spec.md', 'candidate': 'plan.json', 'registry': '.ai/workflows/northstar-readiness-v1.json', 'graph': '.ai/traceability/graph.json'}
            env = dict(os.environ, E6_MUTATE_PATH=str(root / paths[target]), E6_MUTATE_VALUE='concurrent edit', E6_BOUNDARY=moment)
            result = subprocess.run(['node', '--disable-proto=throw', '--import', 'data:text/javascript,' + quote(hook), str(parity.CANDIDATE), *args], capture_output=True, env=env)
            code = {'spec': 'stale_file', 'candidate': 'candidate_changed', 'registry': 'publication_source_changed', 'graph': 'publication_source_changed'}[target]
            data = json.loads(result.stdout)
            preserved = target == 'registry' or (root / '.ai/workflows/northstar-readiness-v1.json').read_bytes() == before
            if result.returncode == 1 and code in data.get('error', '') and preserved and (root / paths[target]).read_text() == 'concurrent edit':
                parity.ok('publication-revalidation-' + boundary)
            else:
                parity.bad('publication-revalidation-' + boundary, str((result.returncode, data, preserved)))

    for name in ['unrelated-coverage', 'unrelated-file', 'selected-G2-blocked', 'dependency-requirement', 'duplicate-requirement', 'null-context', 'missing-context-file', 'duplicate-json']:
        with tempfile.TemporaryDirectory(prefix='e6-scope-') as temporary:
            root = Path(temporary).resolve()
            bundle, context = fixture(root)
            bundle['goals'].append(dict(copy.deepcopy(bundle['goals'][0]), id='G2'))
            selected = ['G1']
            if name == 'unrelated-coverage': bundle['goals'][1]['legacy_risk_reason'] = ''
            if name == 'unrelated-file':
                policy = json.loads((root / '.ai/policies/readiness-policy.json').read_text())
                policy['gates'].append(dict(requirements['file'], id='other-missing', stage='implementation', scope={'goals': ['G2']}))
                write(root, '.ai/policies/readiness-policy.json', policy)
                context['policy']['sha256'] = digest(root / '.ai/policies/readiness-policy.json')
            if name == 'selected-G2-blocked':
                selected = ['G1', 'G2']
                bundle['goals'][1]['readiness']['implementation'] = 'blocked'
            if name == 'dependency-requirement':
                bundle['goals'][0]['dependencies'] = ['G2']
                bundle['goals'][1]['requirements'] = [dict(requirements['file'], id='ancestor-missing', stage='implementation')]
                import readiness_contract as frozen
                context['completed_goals'] = [{'goal': 'G2', 'goal_sha256': frozen.goal_revision(bundle, 'G2'), 'status': 'complete',
                    'issuer': 'fixture-independent', 'evidence': ['local:completed'], 'observed_at': '2000-01-01T00:00:00Z', 'expires_at': '2099-01-01T00:00:00Z'}]
            if name == 'duplicate-requirement':
                bundle['goals'][0]['requirements'] = [dict(requirements['file'], id='fixture-proof', stage='implementation')]
            write(root, 'plan.json', bundle)
            result = parity.run(parity.py_cmd(lib, 'publish', ['--root', str(root), '--bundle', str(root / 'plan.json')]))
            assert result[0] == 0, result
            entry = json.loads(result[1])['published']
            context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
            context['authority']['goals'] = selected
            write(root, 'context.json', None if name == 'null-context' else context)
            if name == 'missing-context-file': (root / 'context.json').unlink()
            if name == 'duplicate-json':
                path = root / entry['artifacts']['bundle']['path']
                path.write_text(path.read_text().replace('"planning_complete": true', '"planning_complete": false, "planning_complete": true'))
                registry = json.loads((root / '.ai/workflows/northstar-readiness-v1.json').read_text())
                registry['plans'][0]['artifacts']['bundle']['sha256'] = digest(path)
                write(root, '.ai/workflows/northstar-readiness-v1.json', registry)
            args = ['admit', '--root', str(root), '--handoff', entry['id'], '--context', str(root / 'context.json')]
            for gid in selected: args.extend(['--goal-id', gid])
            parity.compare_args('scope-' + name, lib, args)
