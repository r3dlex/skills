"""Versioned, read-only admission; publication is an explicit separate subcommand.

Context is supplied by the caller's independent authority adapter. JSON labels do
not authenticate a human or runtime. No goal can create its own policy exemption.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tempfile

from verification import validate as validate_commands, VerificationError

VERSION = 'readiness-contract/1'
POLICY = '.ai/policies/readiness-policy.json'
MANIFEST = '.ai/workflows/repo-workflow.json'
GRAPH = '.ai/traceability/graph.json'
REGISTRY = '.ai/workflows/northstar-readiness-v1.json'
GEN = '.ai/handoff/readiness-v1'
ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
SHA = re.compile(r'^[a-f0-9]{64}$')
STAGES = ('preparation', 'implementation', 'merge')
DIMENSIONS = {'owners', 'reviewer', 'branch_target', 'fixtures', 'tooling', 'registration_approval', 'harness_trust'}


class Invalid(ValueError):
    pass


def require(value, message):
    if not value:
        raise Invalid(message)


def string(value):
    return isinstance(value, str) and bool(value.strip())


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result, 'duplicate_key:' + key)
            result[key] = value
        return result
    return json.loads(Path(path).read_text(), object_pairs_hook=unique)


def relative(root, name, exists=True):
    require(string(name), 'path_required')
    parts = PurePosixPath(name)
    require(not parts.is_absolute() and parts.as_posix() == name and '\\' not in name
            and all(p not in ('', '.', '..') for p in name.split('/')), 'unsafe_path:' + name)
    path = root / name
    for parent in [path, *path.parents]:
        if parent == root:
            break
        require(not parent.is_symlink(), 'symlink_path:' + name)
    resolved = path.resolve(strict=exists)
    require(root in resolved.parents, 'outside_root:' + name)
    return path


def repository(value, root):
    require(isinstance(value, dict) and ID.fullmatch(value.get('id', '')),
            'repository_id_required')
    require(value.get('root') == str(root), 'repository_root_mismatch')


def file_ref(root, value):
    require(isinstance(value, dict) and SHA.fullmatch(value.get('sha256', '')), 'file_digest_required')
    path = relative(root, value.get('path'))
    require(path.is_file() and digest(path) == value['sha256'], 'stale_file:' + value['path'])


def goal_shape(goal, root):
    require(isinstance(goal, dict) and ID.fullmatch(goal.get('id', '')), 'goal_id_required')
    repository(goal.get('repository'), root)
    require(string(goal.get('issue_ref')), 'goal_issue_required')
    for key in ('scope', 'acceptance_criteria'):
        require(isinstance(goal.get(key), list) and goal[key] and all(string(x) for x in goal[key]), key + '_required')
    for scope in goal['scope']:
        relative(root, scope, exists=False)
    deps = goal.get('dependencies')
    require(isinstance(deps, list) and all(isinstance(x, str) and ID.fullmatch(x) for x in deps)
            and len(set(deps)) == len(deps) and goal['id'] not in deps, 'invalid_dependencies')
    readiness = goal.get('readiness')
    require(isinstance(readiness, dict) and set(readiness) == set(STAGES)
            and all(x in ('ready', 'blocked', 'unknown') for x in readiness.values()), 'stage_readiness_required')
    require(isinstance(goal.get('verification'), list) and goal['verification'], 'verification_required')


def bundle_shape(bundle, root):
    require(isinstance(bundle, dict) and bundle.get('schema') == 'handoff-goals/1', 'migration_required:handoff-goals/1')
    require(ID.fullmatch(bundle.get('id', '')), 'bundle_id_required')
    repository(bundle.get('repository'), root)
    require(string(bundle.get('issue_ref')), 'bundle_issue_required')
    require(isinstance(bundle.get('planning_complete'), bool), 'planning_complete_required')
    require(bundle.get('status') in ('active', 'blocked', 'superseded'), 'bundle_status_required')
    file_ref(root, bundle.get('spec'))
    goals = bundle.get('goals')
    require(isinstance(goals, list) and goals, 'goals_required')
    for goal in goals:
        goal_shape(goal, root)
        require(goal['repository'] == bundle['repository'], 'goal_repository_mismatch')
    ids = [g['id'] for g in goals]
    require(len(set(ids)) == len(ids), 'duplicate_goal_ids')
    edges = {g['id']: g['dependencies'] for g in goals}
    require(all(d in ids for ds in edges.values() for d in ds), 'unknown_dependency')
    # Kahn traversal avoids exponential revisits and recursive depth limits.
    from collections import deque
    degree = {gid: len(deps) for gid, deps in edges.items()}
    dependents = {gid: [] for gid in ids}
    for gid, deps in edges.items():
        for dependency in deps:
            dependents[dependency].append(gid)
    ready = deque(gid for gid in ids if degree[gid] == 0)
    visited = 0
    while ready:
        gid = ready.popleft()
        visited += 1
        for dependent in dependents[gid]:
            degree[dependent] -= 1
            if degree[dependent] == 0:
                ready.append(dependent)
    require(visited == len(ids), 'dependency_cycle')


def add(gaps, code, detail, scope, stage, status='blocked'):
    gaps.append({'code': code, 'detail': detail, 'scope': scope, 'stage': stage, 'status': status})


def coverage(goal, gaps, stage):
    percent, status = goal.get('coverage_percent'), goal.get('coverage_status', 'measured')
    valid = isinstance(percent, (float, int)) and not isinstance(percent, bool) and 0 <= percent <= 100
    unknown = status == 'unknown' and percent is None
    if status not in ('unknown', 'measured') or (status == 'unknown' and not unknown) or (status == 'measured' and not valid):
        add(gaps, 'invalid_coverage', 'Declare measured 0..100 or unknown without a number', [goal['id']], stage)
    if unknown and (goal.get('legacy_safe_tdd') is not True or not string(goal.get('legacy_risk_reason'))):
        add(gaps, 'unknown_coverage_tdd', 'Unknown coverage requires legacy_safe_tdd=true and legacy_risk_reason', [goal['id']], stage)
    if 'coverage_required' in goal and not isinstance(goal['coverage_required'], bool):
        add(gaps, 'invalid_coverage_required', 'Expected boolean', [goal['id']], stage)
    if unknown and goal.get('coverage_required') is True:
        add(gaps, 'measured_coverage_required', 'Goal strengthens policy to measured coverage', [goal['id']], stage)
    if 'legacy_safe_tdd' in goal and not isinstance(goal['legacy_safe_tdd'], bool):
        add(gaps, 'invalid_legacy_safe_tdd', 'Expected boolean', [goal['id']], stage)
    if valid and percent >= 30 and goal.get('legacy_safe_tdd') is True and not string(goal.get('legacy_risk_reason')):
        add(gaps, 'legacy_risk_reason_required', 'High coverage legacy-safe override needs reason', [goal['id']], stage)


def gate_shape(gate):
    require(isinstance(gate, dict) and ID.fullmatch(gate.get('id', '')), 'gate_id_required')
    require(gate.get('stage') in STAGES and string(gate.get('kind')), 'unknown_gate_stage_or_kind')
    allowed = {'id', 'stage', 'scope', 'kind', 'dimension'}
    if gate['kind'] == 'file_digest':
        allowed |= {'path', 'sha256'}
    elif gate['kind'] == 'executable_presence':
        allowed |= {'path'}
    require(set(gate) <= allowed, 'unsupported_gate_fields')


def policy_admit(root, bundle, selected, context, stage, subject_hash):
    gaps = []
    try:
        require(context.get('schema') == 'readiness-context/1', 'independent_context_required')
        require(set(context) <= {'schema', 'repository', 'policy', 'sources', 'authority', 'results', 'completed_goals', 'extensions'}, 'unsupported_context_fields')
        require(isinstance(context.get('results'), list) and all(isinstance(r, dict) for r in context['results']), 'invalid_independent_results')
        require(isinstance(context.get('completed_goals'), list) and all(string(g) for g in context['completed_goals']), 'invalid_completed_goals')
        repository(context.get('repository'), root)
        require((root / POLICY).is_file(), 'unsupported_policy_source:' + POLICY)
        policy_path = relative(root, POLICY)
        policy = read(policy_path)
        require(policy.get('schema') == 'readiness-policy/1', 'unsupported_policy_schema')
        require(set(policy) <= {'schema', 'repository', 'sources', 'gates', 'not_applicable', 'extensions'}, 'unsupported_policy_fields')
        require(policy.get('repository') == bundle['repository'] == context['repository'], 'policy_repository_mismatch')
        approved = context.get('policy', {})
        require(isinstance(approved, dict) and set(approved) == {'sha256', 'revision', 'issuer'}, 'unsupported_approval_fields')
        require(approved.get('sha256') == digest(policy_path) and string(approved.get('issuer')) and string(approved.get('revision')), 'unapproved_policy_revision')
        sources = policy.get('sources')
        require(isinstance(sources, list) and sources and sources == context.get('sources'), 'policy_source_set_mismatch')
        require(len({x.get('path') for x in sources}) == len(sources), 'duplicate_policy_sources')
        required_sources = {name for name in ('AGENTS.md', '.rules.ts') if (root / name).is_file()}
        rules = root / '.ai/rules'
        if rules.is_dir():
            required_sources |= {p.relative_to(root).as_posix() for p in rules.rglob('*') if p.is_file()}
        require(required_sources <= {x.get('path') for x in sources}, 'policy_source_set_incomplete')
        for source in sources:
            file_ref(root, source)
        authority = context.get('authority', {})
        require(isinstance(authority, dict) and set(authority) == {'status', 'stage', 'subject_sha256', 'issuer', 'goals'}, 'unsupported_authority_fields')
        require(authority.get('status') == 'pass' and authority.get('stage') == stage
                and authority.get('subject_sha256') == subject_hash and string(authority.get('issuer'))
                and isinstance(authority.get('goals'), list) and set(selected) <= set(authority['goals']), 'independent_authority_required')
        gates = policy.get('gates')
        require(isinstance(gates, list), 'policy_gates_required')
        exclusions = policy.get('not_applicable')
        require(isinstance(exclusions, dict) and all(string(k) and string(v) for k, v in exclusions.items()), 'explicit_not_applicable_reasons_required')
        require(DIMENSIONS <= set(exclusions) | {g.get('dimension') for g in gates if isinstance(g, dict)}, 'policy_dimensions_required')
        require(not (set(exclusions) & {g.get('dimension') for g in gates if isinstance(g, dict)}), 'contradictory_policy_dimension')
        all_ids = {g['id'] for g in bundle['goals']}
        gate_ids = []
        for gate in gates:
            gate_shape(gate)
            gate_ids.append(gate['id'])
            scope = gate.get('scope')
            require(isinstance(scope, dict) and (scope == {'repository': True} or
                    (set(scope) == {'goals'} and isinstance(scope['goals'], list) and scope['goals']
                     and all(isinstance(g, str) and g in all_ids for g in scope['goals']))), 'explicit_gate_scope_required')
        require(len(set(gate_ids)) == len(gate_ids), 'duplicate_policy_gate_ids')
    except (Invalid, OSError, ValueError, TypeError, AttributeError) as error:
        add(gaps, 'policy_context_invalid', str(error), 'repository', stage)
        return gaps
    for goal in bundle['goals']:
        if goal['id'] not in selected:
            continue
        coverage(goal, gaps, stage)
        if goal['readiness'][stage] != 'ready':
            add(gaps, 'goal_not_ready', goal['readiness'][stage], [goal['id']], stage)
        for dependency in goal['dependencies']:
            if dependency not in context.get('completed_goals', []):
                add(gaps, 'dependency_incomplete', dependency, [goal['id']], stage)
        try:
            validate_commands(root, goal['verification'])
        except (VerificationError, OSError) as error:
            add(gaps, 'verification_invalid', str(error), [goal['id']], stage)
        # Goal requirements are additive only. Unsupported predicates never pass.
        requirements = goal.get('requirements', [])
        if not isinstance(requirements, list):
            add(gaps, 'goal_requirement_invalid', 'Expected requirement array', [goal['id']], stage)
            continue
        for gate in requirements:
            if not isinstance(gate, dict) or not ID.fullmatch(gate.get('id', '')) or gate.get('stage') not in STAGES or not string(gate.get('kind')):
                add(gaps, 'goal_requirement_invalid', 'Requires id, stage and typed kind', [goal['id']], stage)
                continue
            try:
                gate_shape(gate)
            except Invalid as error:
                add(gaps, 'goal_requirement_invalid', str(error), [goal['id']], stage)
                continue
            gates = [*gates, dict(gate, scope={'goals': [goal['id']]})]
    for gate in gates:
        scope = gate.get('scope', {})
        targets = all_ids if scope == {'repository': True} else set(scope.get('goals', []))
        if gate.get('stage') != stage or not (targets & set(selected)):
            continue
        try:
            kind = gate.get('kind')
            if kind == 'file_digest':
                file_ref(root, gate)
            elif kind == 'executable_presence':
                path = relative(root, gate.get('path'))
                require(path.is_file() and os.access(path, os.X_OK), 'executable_unavailable')
            elif kind == 'measured_coverage':
                require(all(g.get('coverage_status', 'measured') == 'measured' and
                            isinstance(g.get('coverage_percent'), (float, int)) and
                            not isinstance(g.get('coverage_percent'), bool) and
                            0 <= g['coverage_percent'] <= 100 for g in bundle['goals'] if g['id'] in targets & set(selected)), 'measured_coverage_required')
            elif kind == 'independent_result':
                results = [x for x in context.get('results', []) if x.get('gate') == gate['id']]
                require(len(results) == 1, 'independent_result_missing_or_ambiguous')
                result = results[0]
                require(set(result) == {'gate', 'status', 'stage', 'scope', 'subject_sha256', 'issuer'}, 'unsupported_result_fields')
                require(result.get('status') == 'pass' and result.get('stage') == stage and result.get('scope') == scope
                        and result.get('subject_sha256') == subject_hash and string(result.get('issuer')), 'independent_result_invalid')
            else:
                add(gaps, 'unsupported_gate', str(kind), scope, stage, 'unknown')
        except (Invalid, OSError, ValueError, TypeError) as error:
            add(gaps, 'gate_failed', gate.get('id', '') + ':' + str(error), scope, stage)
    return gaps


def select(root, args):
    require(bool(args.goal) != bool(args.handoff), 'selection_required:use exact --handoff with --goal-id or explicit --goal')
    if args.goal:
        require(not args.goal_id, 'direct_goal_selector_conflict')
        envelope = read(Path(args.goal))
        require(isinstance(envelope, dict) and envelope.get('schema') == 'direct-goal/1', 'migration_required:direct-goal/1')
        bundle = envelope.get('bundle')
        bundle_shape(bundle, root)
        require(len(bundle['goals']) == 1, 'direct_requires_one_goal')
        return bundle, [bundle['goals'][0]['id']], digest(args.goal), None
    require(args.goal_id and len(set(args.goal_id)) == len(args.goal_id), 'goal_selection_required')
    registry = relative(root, REGISTRY, exists=False)
    manifest = read(registry) if registry.exists() else {'schema': VERSION, 'plans': []}
    require(manifest.get('schema') == VERSION, 'unsupported_registry_schema')
    branches = manifest.get('plans', [])
    matches = [b for b in branches if isinstance(b, dict) and args.handoff in (b.get('id'), b.get('handoff_path'))]
    if not matches:
        # Legacy lookup supplies migration diagnostics only, never executable data.
        legacy_matches = []
        for branch in read(relative(root, MANIFEST)).get('optional_branches', []):
            if not isinstance(branch, dict):
                continue
            identity = branch.get('id')
            if not isinstance(identity, str) or not identity.startswith('northstar-handoff-'):
                continue
            path = '.ai/handoff/northstar-' + identity[len('northstar-handoff-'):] + '.md'
            if args.handoff in (identity, path, branch.get('handoff_path')):
                legacy_matches.append(branch)
        require(len(legacy_matches) != 1, 'migration_required:registered legacy handoff; use migrate-handoff.sh')
    require(len(matches) == 1, 'handoff_missing_or_ambiguous')
    entry = matches[0]
    require(entry.get('schema') == VERSION, 'migration_required:registered handoff')
    require(entry.get('status') == 'active', 'handoff_not_active')
    generation = entry.get('generation')
    require(isinstance(generation, str) and SHA.fullmatch(generation), 'invalid_generation')
    prefix = f'{GEN}/{entry.get("plan_id")}/{generation}/'
    paths = entry.get('artifacts')
    require(isinstance(paths, dict) and set(paths) == {'bundle', 'handoff', 'graph'}, 'incomplete_generation')
    loaded = {}
    for name, ref in paths.items():
        require(ref.get('path', '').startswith(prefix), 'mixed_generation')
        file_ref(root, ref)
        loaded[name] = relative(root, ref['path'])
    require(entry.get('handoff_path') == paths['handoff']['path'], 'handoff_path_mismatch')
    bundle = read(loaded['bundle'])
    bundle_shape(bundle, root)
    require(entry.get('plan_id') == bundle['id'], 'plan_identity_mismatch')
    require(set(args.goal_id) <= {g['id'] for g in bundle['goals']}, 'requested_goal_missing')
    require(generation == canonical(bundle), 'generation_digest_mismatch')
    # Graph and handoff are immutable members of this generation, never legacy pointers.
    graph = read(loaded['graph'])
    require(graph.get('generation') == generation and graph.get('goal_ids') == [g['id'] for g in bundle['goals']], 'graph_identity_mismatch')
    live_graph = read(relative(root, GRAPH))
    live_nodes = {n.get('id'): n for n in live_graph.get('nodes', [])}
    for node in graph['nodes']:
        require(node['id'] in live_nodes, 'generation_graph_missing')
        require(all(live_nodes[node['id']].get(k) == node.get(k) for k in ('id', 'type', 'repo_id', 'path', 'status')), 'generation_graph_identity_mismatch')
    for edge in graph['edges']:
        require(edge in live_graph.get('edges', []) and edge['source'] in live_nodes[edge['target']].get('backlinks', []) and edge['target'] in live_nodes[edge['source']].get('backlinks', []), 'generation_graph_link_missing')
    return bundle, args.goal_id, digest(loaded['bundle']), entry


def admit(args):
    root = Path(args.root).resolve(strict=True)
    report = {'schema': VERSION, 'stage': args.stage, 'repository_root': str(root),
              'planning_complete': False, 'execution_ready': False, 'dispatch_authorized': False,
              'authority_verification': 'external-required', 'goals': args.goal_id or [], 'gaps': []}
    try:
        require(all((root / name).is_file() for name in ('.ai/matrix.json', MANIFEST, GRAPH)), 'v3_root_required')
        for name in ('.ai/matrix.json', MANIFEST, GRAPH):
            require(isinstance(read(relative(root, name)), dict), 'v3_root_malformed')
        bundle, selected, subject, entry = select(root, args)
        report.update(plan_id=bundle['id'], repository=bundle['repository'],
                      bundle={'schema': bundle['schema'], 'id': bundle['id'], 'canonical_sha256': canonical(bundle)},
                      specification=bundle['spec'], goals=selected,
                      planning_complete=bundle['planning_complete'], handoff=entry, subject_sha256=subject)
        if args.stage == 'planning':
            return report
        require(bundle['planning_complete'] and bundle['status'] == 'active', 'plan_not_active_or_incomplete')
        require(args.context, 'independent_context_required')
        context = read(args.context)
        report['gaps'] = policy_admit(root, bundle, selected, context, args.stage, subject)
        report['execution_ready'] = not report['gaps']
    except (Invalid, OSError, ValueError, TypeError, AttributeError) as error:
        add(report['gaps'], 'admission_failed', str(error), 'repository', args.stage)
    return report


def preserve(previous, proposed, path=''):
    """Unknown/enriched fields may not be silently dropped by regeneration."""
    if isinstance(previous, dict):
        require(isinstance(proposed, dict), 'enrichment_loss:' + path)
        for key, value in previous.items():
            require(key in proposed, 'enrichment_loss:' + path + '/' + key)
            preserve(value, proposed[key], path + '/' + key)
    elif isinstance(previous, list) and previous and all(isinstance(x, dict) and 'id' in x for x in previous):
        require(isinstance(proposed, list), 'enrichment_loss:' + path)
        next_by_id = {x['id']: x for x in proposed if isinstance(x, dict) and 'id' in x}
        for item in previous:
            require(item['id'] in next_by_id, 'enrichment_loss:' + path)
            preserve(item, next_by_id[item['id']], path + '/' + item['id'])
    else:
        parts = path.strip('/').split('/')
        mutable = path in ('/planning_complete', '/status', '/spec/sha256')
        mutable |= len(parts) == 4 and parts[0] == 'goals' and parts[2] == 'readiness' and parts[3] in STAGES
        mutable |= len(parts) == 3 and parts[0] == 'goals' and parts[2] in {'coverage_percent', 'coverage_status', 'legacy_safe_tdd', 'legacy_risk_reason'}
        require(mutable or previous == proposed, 'enrichment_changed:' + path)


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    with path.open('rb') as handle:
        os.fsync(handle.fileno())


def replace_json(path, value):
    fd, name = tempfile.mkstemp(prefix='.readiness-', dir=path.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        write_json(temporary, value)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def handoff_text(bundle):
    return ('# Northstar handoff: ' + bundle['id'] + '\n\nPlanning complete: ' +
            str(bundle['planning_complete']).lower() +
            '\n\nExecution readiness: independently revalidate; planning is not admission.\n\nGoals: ' +
            ', '.join(g['id'] for g in bundle['goals']) + '\n')


def validate_generation(root, prefix, bundle, generation, spec):
    paths = {name: relative(root, prefix + '/' + name) for name in ('goals.json', 'graph.json', 'handoff.md')}
    require(all(p.is_file() for p in paths.values()), 'generation_collision:non-file')
    require(read(paths['goals.json']) == bundle and paths['handoff.md'].read_text() == handoff_text(bundle), 'generation_collision:payload')
    graph = read(paths['graph.json'])
    require(graph.get('generation') == generation and graph.get('plan_id') == bundle['id'] and
            graph.get('goal_ids') == [g['id'] for g in bundle['goals']] and
            SHA.fullmatch(graph.get('source_graph_sha256', '')), 'generation_collision:identity')
    parent = 'handoff:' + bundle['repository']['id'] + ':' + bundle['id'] + ':' + generation
    expected = {spec['id']: {'id': spec['id'], 'type': spec['type'], 'repo_id': spec['repo_id'], 'path': spec['path'], 'backlinks': [parent]},
                parent: {'id': parent, 'type': 'handoff', 'repo_id': bundle['repository']['id'], 'path': prefix + '/handoff.md', 'backlinks': [spec['id']]}}
    edges = [{'source': spec['id'], 'target': parent, 'type': 'plans'}]
    for goal in bundle['goals']:
        gid = 'plan:' + bundle['repository']['id'] + ':' + bundle['id'] + ':' + goal['id'] + ':' + generation
        expected[gid] = {'id': gid, 'type': 'plan', 'repo_id': bundle['repository']['id'], 'path': prefix + '/goals.json', 'backlinks': [parent]}
        expected[parent]['backlinks'].append(gid)
        edges.append({'source': parent, 'target': gid, 'type': 'plans'})
    nodes = graph.get('nodes', [])
    require(len(nodes) == len(expected) and {n.get('id') for n in nodes} == set(expected), 'generation_collision:nodes')
    require(all(all(n.get(k) == v for k, v in expected[n['id']].items()) for n in nodes) and graph.get('edges') == edges, 'generation_collision:graph')
    return graph


def publish(args):
    root = Path(args.root).resolve(strict=True)
    candidate = Path(args.bundle).resolve(strict=True)
    candidate_hash = digest(candidate)
    bundle = read(candidate)
    bundle_shape(bundle, root)
    generation = canonical(bundle)
    base = relative(root, f'{GEN}/{bundle["id"]}', exists=False)
    base.mkdir(parents=True, exist_ok=True)
    workflows = relative(root, '.ai/workflows')
    lock = workflows / '.northstar-readiness-v1.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        raise Invalid('publication_locked:inspect existing publisher; never steal a lock')
    staging = None
    try:
        require(digest(candidate) == candidate_hash, 'candidate_changed')
        registry_path = relative(root, REGISTRY, exists=False)
        registry_hash = digest(registry_path) if registry_path.exists() else None
        registry = read(registry_path) if registry_path.exists() else {'schema': VERSION, 'plans': []}
        require(registry.get('schema') == VERSION and isinstance(registry.get('plans'), list), 'unsupported_registry_schema')
        branches = registry['plans']
        registration = 'northstar-plan-' + bundle['id']
        previous = [b for b in branches if b.get('id') == registration]
        require(len(previous) <= 1, 'duplicate_registration')
        if previous:
            ref = previous[0]['artifacts']['bundle']
            file_ref(root, ref)
            preserve(read(relative(root, ref['path'])), bundle)
        graph_path = relative(root, GRAPH)
        graph_hash = digest(graph_path)
        live_graph = read(graph_path)
        nodes = live_graph.get('nodes')
        require(isinstance(nodes, list), 'source_graph_nodes_required')
        matching = [n for n in nodes if n.get('path') == bundle['spec']['path']]
        require(len(matching) == 1, 'spec_graph_identity_missing_or_ambiguous')
        known_ids = [n.get('id') for n in nodes]
        require(len(set(known_ids)) == len(known_ids), 'source_graph_duplicate_ids')
        final = base / generation
        prefix = f'{GEN}/{bundle["id"]}/{generation}'
        if final.exists():
            graph = validate_generation(root, prefix, bundle, generation, matching[0])
        else:
            spec_node = copy.deepcopy(matching[0])
            parent_id = 'handoff:' + bundle['repository']['id'] + ':' + bundle['id'] + ':' + generation
            spec_node['backlinks'] = [parent_id]
            handoff_node = {'id': parent_id, 'type': 'handoff', 'title': bundle['id'], 'status': 'active',
                            'repo_id': bundle['repository']['id'], 'path': prefix + '/handoff.md', 'backlinks': [spec_node['id']]}
            graph = {'schema_version': '1.1', 'generation': generation, 'plan_id': bundle['id'],
                     'goal_ids': [g['id'] for g in bundle['goals']], 'source_graph_sha256': graph_hash,
                     'nodes': [spec_node, handoff_node], 'edges': [{'source': spec_node['id'], 'target': parent_id, 'type': 'plans'}]}
            for goal in bundle['goals']:
                goal_id = 'plan:' + bundle['repository']['id'] + ':' + bundle['id'] + ':' + goal['id'] + ':' + generation
                graph['nodes'].append({'id': goal_id, 'type': 'plan', 'title': goal['id'], 'status': 'planned',
                                       'repo_id': bundle['repository']['id'], 'path': prefix + '/goals.json', 'backlinks': [parent_id]})
                handoff_node['backlinks'].append(goal_id)
                graph['edges'].append({'source': parent_id, 'target': goal_id, 'type': 'plans'})
            staging = Path(tempfile.mkdtemp(prefix='.staging-', dir=base))
            write_json(staging / 'goals.json', bundle)
            write_json(staging / 'graph.json', graph)
            (staging / 'handoff.md').write_text(handoff_text(bundle))
            with (staging / 'handoff.md').open('rb') as handle:
                os.fsync(handle.fileno())
            staging.rename(final)
            staging = None
        artifacts = {name: {'path': prefix + '/' + filename, 'sha256': digest(final / filename)}
                     for name, filename in [('bundle', 'goals.json'), ('graph', 'graph.json'), ('handoff', 'handoff.md')]}
        # Current registered bytes may never be silently repaired after corruption.
        if previous and previous[0].get('generation') == generation:
            require(previous[0].get('artifacts') == artifacts, 'generation_collision')
        entry = {'schema': VERSION, 'id': registration, 'plan_id': bundle['id'], 'generation': generation,
                 'status': bundle['status'], 'handoff_path': artifacts['handoff']['path'], 'artifacts': artifacts,
                 'planning_complete': bundle['planning_complete'], 'execution_admitted': False}
        if previous:
            # Retain registration annotations; owned completion fields are refreshed.
            entry = dict(previous[0], **entry)
        indexed = {n['id']: n for n in live_graph['nodes']}
        for node in graph['nodes']:
            if node['id'] not in indexed:
                live_graph['nodes'].append(copy.deepcopy(node))
                indexed[node['id']] = live_graph['nodes'][-1]
            else:
                current = indexed[node['id']]
                require(current.get('path') == node['path'], 'graph_identity_conflict')
                for backlink in node.get('backlinks', []):
                    if backlink not in current.setdefault('backlinks', []):
                        current['backlinks'].append(backlink)
        for edge in graph['edges']:
            if edge not in live_graph.setdefault('edges', []):
                live_graph['edges'].append(edge)
        bundle_shape(bundle, root)
        require(digest(candidate) == candidate_hash, 'candidate_changed')
        require((digest(registry_path) if registry_path.exists() else None) == registry_hash and digest(graph_path) == graph_hash, 'publication_source_changed')
        # Visibility boundary 1: additive graph, never completion by itself.
        replace_json(graph_path, live_graph)
        require(digest(candidate) == candidate_hash, 'candidate_changed')
        require((digest(registry_path) if registry_path.exists() else None) == registry_hash, 'publication_source_changed')
        bundle_shape(bundle, root)
        registry['plans'] = [entry if b.get('id') == registration else b for b in branches]
        if not previous:
            registry['plans'].append(entry)
        # Visibility boundary 2: sole completion pointer. Never whole-file rollback.
        replace_json(registry_path, registry)
        return {'schema': VERSION, 'published': entry, 'execution_ready': False, 'dispatch_authorized': False, 'authority_verification': 'external-required'}
    finally:
        if staging is not None and staging.exists():
            shutil.rmtree(staging)
        lock.rmdir()


def migrate(args):
    """Explicit normalization assistance, not migration-by-default or admission."""
    root = Path(args.root).resolve(strict=True)
    legacy = read(args.legacy)
    supplied = read(args.bundle)
    bundle_shape(supplied, root)
    bundle = copy.deepcopy(supplied)
    extensions = bundle.setdefault('extensions', {})
    require(isinstance(extensions, dict) and 'legacy_original' not in extensions, 'migration_extension_collision')
    extensions['legacy_original'] = legacy
    extensions['legacy_sha256'] = digest(args.legacy)
    for goal in bundle['goals']:
        goal['readiness'] = {stage: 'unknown' for stage in STAGES}
    return {'schema': VERSION, 'bundle': bundle, 'dispatch_authorized': False,
            'execution_ready': False, 'authority_verification': 'external-required', 'next': 'Review retained evidence; publish explicitly; revalidate independently'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=('admit', 'publish', 'migrate'))
    parser.add_argument('--root', default='.')
    parser.add_argument('--handoff')
    parser.add_argument('--goal-id', action='append')
    parser.add_argument('--goal')
    parser.add_argument('--context')
    parser.add_argument('--bundle')
    parser.add_argument('--legacy')
    parser.add_argument('--stage', choices=('planning', *STAGES), default='implementation')
    args = parser.parse_args()
    try:
        result = {'admit': admit, 'publish': publish, 'migrate': migrate}[args.operation](args)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1 if result.get('gaps') else 0
    except (Invalid, OSError, ValueError, TypeError, AttributeError) as error:
        print(json.dumps({'schema': VERSION, 'error': str(error), 'execution_ready': False, 'dispatch_authorized': False, 'authority_verification': 'external-required'}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
