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
import shlex
import stat
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

from verification import validate as validate_commands, VerificationError

VERSION = 'readiness-contract/1'
POLICY = '.ai/policies/readiness-policy.json'
MANIFEST = '.ai/workflows/repo-workflow.json'
GRAPH = '.ai/traceability/graph.json'
REGISTRY = '.ai/workflows/northstar-readiness-v1.json'
GEN = '.ai/handoff/readiness-v1'
ID = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')
SHA = re.compile(r'^[a-f0-9]{64}$')
REVISION = re.compile(r'^[a-f0-9]{40}$')
MAPPED = 'mapped-handoff-goals/1'
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


def git_read(root, *arguments):
    # Ignore caller-selected repositories, object stores, indexes, config injection,
    # and replacement objects. Only argument-vector read operations are used.
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull,
               GIT_NO_REPLACE_OBJECTS='1', GIT_OPTIONAL_LOCKS='0')
    result = subprocess.run(['git', '--no-lazy-fetch', '--no-replace-objects', '-c', 'core.fsmonitor=false', '-c', 'core.filemode=true', '-c', 'core.hooksPath=' + os.devnull, '-C', str(root), *arguments],
                            env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    require(result.returncode == 0, 'worktree_git_proof_failed:' + arguments[0])
    return result.stdout


def exact_root(value):
    path = Path(value)
    require(path.exists(), 'worktree_root_missing')
    require(path.is_absolute() and str(path) == str(path.resolve(strict=True))
            and path.is_dir() and not any(p.is_symlink() for p in (path, *path.parents)),
            'worktree_root_not_canonical')
    require(git_read(path, 'rev-parse', '--show-toplevel').decode().strip() == str(path),
            'worktree_toplevel_mismatch')
    require(git_read(path, 'rev-parse', '--is-bare-repository').strip() == b'false',
            'worktree_bare_repository')
    return path


def worktree_observation(identity_root, files_root, base_commit, clean=False, inputs=()):
    identity_root, files_root = exact_root(identity_root), exact_root(files_root)
    require(identity_root != files_root, 'worktree_must_be_distinct')
    require(isinstance(base_commit, str) and REVISION.fullmatch(base_commit), 'worktree_base_required')
    common = Path(git_read(identity_root, 'rev-parse', '--path-format=absolute', '--git-common-dir').decode().strip()).resolve(strict=True)
    actual_common = Path(git_read(files_root, 'rev-parse', '--path-format=absolute', '--git-common-dir').decode().strip()).resolve(strict=True)
    require(common == actual_common, 'worktree_common_dir_mismatch')
    git_dir = Path(git_read(files_root, 'rev-parse', '--absolute-git-dir').decode().strip()).resolve(strict=True)
    require(git_dir != common and (files_root / '.git').is_file(), 'linked_worktree_required')
    records = git_read(identity_root, 'worktree', 'list', '--porcelain', '-z').split(b'\0\0')
    require(any(b'worktree ' + os.fsencode(files_root) in record.split(b'\0') for record in records),
            'registered_worktree_required')
    head = git_read(files_root, 'rev-parse', '--verify', 'HEAD^{commit}').decode().strip()
    branch = git_read(files_root, 'symbolic-ref', '--quiet', 'HEAD').decode().strip()
    require(branch.startswith('refs/heads/'), 'worktree_branch_required')
    target_ref = 'refs/remotes/origin/main'
    target = git_read(files_root, 'rev-parse', '--verify', target_ref + '^{commit}').decode().strip()
    require(git_read(files_root, 'rev-parse', '--verify', base_commit + '^{commit}').decode().strip() == base_commit,
            'worktree_base_not_commit')
    git_read(files_root, 'merge-base', '--is-ancestor', base_commit, head)
    git_read(files_root, 'merge-base', '--is-ancestor', base_commit, target)
    if clean:
        flags = git_read(files_root, 'ls-files', '-v', '-z').split(b'\0')
        require(all(not entry or (entry[:1].isupper() and entry[:1] != b'S') for entry in flags),
                'worktree_merge_index_flags_unsupported')
    tracked = git_read(files_root, 'ls-files', '--cached', '-z').split(b'\0')
    paths = {os.fsdecode(p) for p in tracked if p}
    # Exact worktree freshness includes ignored/untracked files too. Only the
    # linked worktree's root Git metadata is outside the observed working tree.
    def unreadable_directory(error):
        raise Invalid('worktree_unreadable_directory') from error

    for directory, directories, names in os.walk(files_root, onerror=unreadable_directory):
        if Path(directory) == files_root:
            directories[:] = [name for name in directories if name != '.git']
            names = [name for name in names if name != '.git']
        for name in directories:
            require(not (Path(directory) / name).is_symlink(), 'worktree_symlink_directory')
        paths.update((Path(directory) / name).relative_to(files_root).as_posix() for name in names)
    for name in inputs:
        require(not any(char in name for char in '*?[]'), 'worktree_glob_scope_unsupported')
        path = relative(files_root, name, exists=False)
        paths.add(name)
        if path.is_dir():
            paths.update(p.relative_to(files_root).as_posix() for p in path.rglob('*') if not p.is_dir())
    state = []
    for name in sorted(paths):
        path = relative(files_root, name, exists=False)
        # lstat records deletion and mode changes; symlinks are not followed.
        if not path.exists() and not path.is_symlink():
            state.append([name, 'deleted'])
            continue
        mode = path.lstat().st_mode
        require(not stat.S_ISLNK(mode), 'worktree_symlink_input:' + name)
        if stat.S_ISDIR(mode):
            state.append([name, 'directory', stat.S_IMODE(mode)])
        else:
            require(stat.S_ISREG(mode), 'worktree_nonregular_input:' + name)
            state.append([name, stat.S_IMODE(mode), digest(path)])
    if clean:
        tree = {}
        for entry in git_read(files_root, 'ls-tree', '-r', '-z', head).split(b'\0'):
            if entry:
                metadata, name = entry.split(b'\t', 1)
                mode, kind, object_id = metadata.split()
                require(kind == b'blob' and mode in (b'100644', b'100755'), 'worktree_merge_tree_type_unsupported')
                tree[os.fsdecode(name)] = (mode, object_id)
        index = {}
        for entry in git_read(files_root, 'ls-files', '--stage', '-z').split(b'\0'):
            if entry:
                metadata, name = entry.split(b'\t', 1)
                mode, object_id, stage = metadata.split()
                require(stage == b'0', 'worktree_merge_unmerged_index')
                index[os.fsdecode(name)] = (mode, object_id)
        require(index == tree, 'worktree_merge_index_mismatch')
        actual_files = {name for name in paths if (files_root / name).is_file()}
        require(actual_files == set(tree), 'worktree_merge_uncommitted_files')
        for name, (mode, object_id) in tree.items():
            path = files_root / name
            disk_mode = b'100755' if path.stat().st_mode & stat.S_IXUSR else b'100644'
            raw_hash = git_read(files_root, 'hash-object', '--no-filters', '--', name).strip()
            require(disk_mode == mode and raw_hash == object_id, 'worktree_merge_head_bytes_mismatch')
    return {'schema': 'git-worktree/1', 'root': str(files_root), 'base_commit': base_commit,
            'target_ref': target_ref, 'common_dir': str(common), 'head': head,
            'branch': branch, 'target_revision': target, 'state_sha256': canonical(state)}


def worktree_binding(observation):
    return {key: observation[key] for key in ('schema', 'root', 'base_commit', 'target_ref')}


def worktree_inputs(bundle, root):
    paths = {'.ai/matrix.json', MANIFEST, GRAPH, REGISTRY, POLICY, GEN, bundle['spec']['path'],
             'prek.toml', '.pre-commit-config.yaml', 'package.json', '.ai/ci', '.github/workflows'}

    def command_inputs(command, cwd=root):
        if not isinstance(command, str):
            return
        for token in shlex.split(command):
            if not Path(token).is_absolute() and (cwd / token).is_file():
                path = relative(root, (cwd / token).relative_to(root).as_posix())
                paths.add(path.relative_to(root).as_posix())

    for goal in bundle['goals']:
        paths.update(goal['scope'])
        for command in goal['verification']:
            if isinstance(command, dict):
                cwd = root if command.get('cwd') == '.' else relative(root, command.get('cwd'))
                command_inputs(command.get('command'), cwd)
            else:
                command_inputs(command)
    # Recursively collect explicit file references, including typed trust/fixture
    # inputs. Unsupported shapes still fail closed during normal validation.
    def collect(value):
        if isinstance(value, dict):
            if isinstance(value.get('path'), str):
                paths.add(value['path'])
            for child in value.values():
                collect(child)
        elif isinstance(value, list):
            for child in value:
                collect(child)
    collect(bundle)
    collect(read(relative(root, POLICY)))
    paths.update(instruction_paths(bundle, root))
    return sorted(paths)


def worktree_request(args, identity_root):
    target, base = getattr(args, 'worktree_root', None), getattr(args, 'base_commit', None)
    require(bool(target) == bool(base), 'worktree_root_and_base_required')
    require(not target or not getattr(args, 'execution_root', None), 'worktree_mapped_conflict')
    if not target:
        return identity_root, None
    require(args.root == str(identity_root), 'worktree_identity_alias')
    files_root = Path(target)
    context = getattr(args, 'context', None)
    require(not context or not Path(context).resolve().is_relative_to(files_root.resolve()),
            'worktree_context_must_be_external')
    return files_root, worktree_observation(identity_root, files_root, base, clean=args.stage == 'merge')


def repository(value, root):
    require(isinstance(value, dict) and ID.fullmatch(value.get('id', '')),
            'repository_id_required')
    require(value.get('root') == str(root), 'repository_root_mismatch')


def file_ref(root, value):
    require(isinstance(value, dict) and SHA.fullmatch(value.get('sha256', '')), 'file_digest_required')
    path = relative(root, value.get('path'))
    require(path.is_file() and digest(path) == value['sha256'], 'stale_file:' + value['path'])


def mapped(bundle):
    return bundle.get('schema') == MAPPED


def execution_root(bundle, planning_root):
    return Path(bundle['execution']['repository']['root']) if mapped(bundle) else planning_root


def execution_shape(bundle, root):
    binding = bundle.get('execution')
    require(isinstance(binding, dict) and set(binding) ==
            {'repository', 'target', 'source_revision', 'sources', 'validation'}, 'execution_binding_required')
    repo = binding['repository']
    require(isinstance(repo, dict) and set(repo) == {'id', 'root'} and string(repo.get('root')),
            'execution_repository_required')
    target_root = Path(repo['root'])
    require(target_root.is_absolute() and str(target_root.resolve(strict=True)) == repo['root']
            and target_root.is_dir(), 'execution_root_not_canonical')
    require(not any(p.is_symlink() for p in (target_root, *target_root.parents)), 'execution_root_symlink')
    repository(repo, target_root)
    require(repo['id'] != bundle['repository']['id'] and target_root != root
            and root not in target_root.parents and target_root not in root.parents, 'execution_roots_not_disjoint')
    require(string(binding['target']) and not re.search(r'\s|[;&|`$<>]', binding['target']), 'execution_target_required')
    require(isinstance(binding['source_revision'], str) and REVISION.fullmatch(binding['source_revision']),
            'execution_source_revision_required')
    require(binding['validation'] in ('local', 'external-only'), 'execution_validation_required')
    sources = binding['sources']
    require(isinstance(sources, list) and sources and all(isinstance(x, dict) and
            set(x) == {'path', 'sha256'} for x in sources), 'execution_sources_required')
    require(len({x['path'] for x in sources}) == len(sources), 'duplicate_execution_sources')
    for source in sources:
        file_ref(target_root, source)
    return target_root


def instruction_paths(bundle, root):
    directories = {root}
    for goal in bundle['goals']:
        for scope in goal['scope']:
            require(not any(char in scope for char in '*?[]'), 'execution_scope_must_be_literal')
            path = relative(root, scope, exists=False)
            directories.update(p for p in path.parents if p == root or root in p.parents)
            if path.is_dir():
                directories.add(path)
                directories.update(p for p in path.rglob('*') if p.is_dir())
    required = {'AGENTS.md'}
    for directory in directories:
        for name in ('AGENTS.md', 'CLAUDE.md', 'GEMINI.md', '.rules.ts'):
            path = directory / name
            if path.is_file():
                required.add(path.relative_to(root).as_posix())
        rules = directory / '.ai/rules'
        if rules.is_dir():
            required.update(p.relative_to(root).as_posix() for p in rules.rglob('*') if p.is_file())
    return required


def execution_instruction_sources(bundle, root):
    require(instruction_paths(bundle, root) <= {x['path'] for x in bundle['execution']['sources']}, 'execution_source_set_incomplete')


def goal_shape(goal, root, files_root=None):
    files_root = root if files_root is None else files_root
    require(isinstance(goal, dict) and ID.fullmatch(goal.get('id', '')), 'goal_id_required')
    repository(goal.get('repository'), root)
    require(string(goal.get('issue_ref')), 'goal_issue_required')
    for key in ('scope', 'acceptance_criteria'):
        require(isinstance(goal.get(key), list) and goal[key] and all(string(x) for x in goal[key]), key + '_required')
    for scope in goal['scope']:
        relative(files_root, scope, exists=False)
    deps = goal.get('dependencies')
    require(isinstance(deps, list) and all(isinstance(x, str) and ID.fullmatch(x) for x in deps)
            and len(set(deps)) == len(deps) and goal['id'] not in deps, 'invalid_dependencies')
    readiness = goal.get('readiness')
    require(isinstance(readiness, dict) and set(readiness) == set(STAGES)
            and all(x in ('ready', 'blocked', 'unknown') for x in readiness.values()), 'stage_readiness_required')
    require(isinstance(goal.get('verification'), list) and goal['verification'], 'verification_required')


def bundle_shape(bundle, root, files_root=None):
    files_root = root if files_root is None else files_root
    require(isinstance(bundle, dict) and bundle.get('schema') in ('handoff-goals/1', MAPPED), 'migration_required:handoff-goals/1')
    require(ID.fullmatch(bundle.get('id', '')), 'bundle_id_required')
    repository(bundle.get('repository'), root)
    require(mapped(bundle) or 'execution' not in bundle, 'execution_requires_mapped_schema')
    goal_root = execution_shape(bundle, root) if mapped(bundle) else root
    require(string(bundle.get('issue_ref')), 'bundle_issue_required')
    require(isinstance(bundle.get('planning_complete'), bool), 'planning_complete_required')
    require(bundle.get('status') in ('active', 'blocked', 'superseded'), 'bundle_status_required')
    file_ref(files_root, bundle.get('spec'))
    goals = bundle.get('goals')
    require(isinstance(goals, list) and goals, 'goals_required')
    for goal in goals:
        goal_shape(goal, goal_root, goal_root if mapped(bundle) else files_root)
        require(goal['repository'] == (bundle['execution']['repository'] if mapped(bundle) else bundle['repository']), 'goal_repository_mismatch')
    if mapped(bundle):
        execution_instruction_sources(bundle, goal_root)
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


def redact(value):
    if isinstance(value, str):
        return re.sub(r'https?://[^\s]+', '[redacted-url]', value)
    if isinstance(value, list):
        return [redact(item) for item in value]
    if isinstance(value, dict):
        return {redact(key): redact(item) for key, item in value.items()}
    return value


def add(gaps, code, detail, scope, stage, status='blocked'):
    # Diagnostics must never echo credential-bearing URLs from external evidence.
    detail = re.sub(r'https?://[^\s]+', '[redacted-url]', str(detail))
    gaps.append({'code': code, 'detail': detail, 'scope': scope, 'stage': stage, 'status': status,
                 'responsible': 'unassigned', 'source': 'independent-context-and-repository-policy',
                 'freshness': 'unavailable', 'evidence_refs': [],
                 'recovery': 'Supply current independently verified evidence for this gate; rerun exact selection'})


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


def applies(scope, gid):
    return scope == 'repository' or scope == {'repository': True} or (isinstance(scope, list) and gid in scope) or (isinstance(scope, dict) and gid in scope.get('goals', []))


def goal_revision(bundle, gid):
    goals = {g['id']: g for g in bundle['goals']}
    require(isinstance(gid, str) and gid in goals, 'unknown_goal_revision_subject')
    # Iterative postorder avoids recursion limits for validated deep DAGs.
    revisions, pending = {}, [(gid, False)]
    while pending:
        current, expanded = pending.pop()
        if current in revisions:
            continue
        goal = goals[current]
        if not expanded:
            pending.append((current, True))
            pending.extend((dep, False) for dep in goal['dependencies'] if dep not in revisions)
        else:
            revisions[current] = canonical({'repository': bundle['repository'], 'plan_id': bundle['id'],
                'spec': bundle['spec'], 'goal': goal,
                **({'execution': bundle['execution']} if mapped(bundle) else {}),
                'dependencies': {dep: revisions[dep] for dep in sorted(goal['dependencies'])}})
    return revisions[gid]


def dependency_complete(bundle, gid, receipts, execution_revision=None, worktree=None):
    matches = [r for r in receipts if isinstance(r, dict) and r.get('goal') == gid]
    if len(matches) != 1:
        return False
    receipt = matches[0]
    try:
        fields = {'goal', 'goal_sha256', 'status', 'issuer', 'evidence', 'observed_at', 'expires_at'}
        if mapped(bundle):
            fields.add('execution_revision')
            require(isinstance(execution_revision, str) and REVISION.fullmatch(execution_revision)
                    and receipt.get('execution_revision') == execution_revision, 'completion_execution_revision')
        if worktree:
            fields.update({'integration_commit', 'execution_commit'})
            predecessor = receipt.get('execution_commit')
            require(isinstance(predecessor, str) and REVISION.fullmatch(predecessor), 'completion_execution_required')
            commit = receipt.get('integration_commit')
            require(isinstance(commit, str) and REVISION.fullmatch(commit), 'completion_integration_required')
            git_read(Path(worktree['root']), 'merge-base', '--is-ancestor', commit, worktree['base_commit'])
        require(set(receipt) == fields, 'completion_fields')
        require(receipt['status'] == 'complete' and receipt['goal_sha256'] == goal_revision(bundle, gid), 'completion_revision')
        provenance(receipt)
        return True
    except (Invalid, ValueError, TypeError):
        return False


def provenance(receipt):
    require(string(receipt.get('issuer')) and isinstance(receipt.get('evidence'), list)
            and receipt['evidence'] and all(string(x) for x in receipt['evidence']), 'evidence_provenance_required')
    require(string(receipt.get('observed_at')) and string(receipt.get('expires_at')), 'evidence_freshness_required')
    now = datetime.now(timezone.utc)
    observed = datetime.fromisoformat(receipt.get('observed_at', '').replace('Z', '+00:00'))
    expires = datetime.fromisoformat(receipt.get('expires_at', '').replace('Z', '+00:00'))
    require(observed.tzinfo is not None and expires.tzinfo is not None and observed <= now < expires,
            'evidence_expired_or_future')


def gate_subject(bundle, gate, sources, policy, execution_revision=None, worktree=None):
    # The exact gate (including declared source hashes) and governed goal revisions,
    # not unrelated goals or their receipts. Full-file bindings remain full-file.
    goals = [g['id'] for g in bundle['goals'] if applies(gate['scope'], g['id'])]
    binding = {}
    if mapped(bundle):
        require(isinstance(execution_revision, str) and REVISION.fullmatch(execution_revision), 'gate_execution_revision_required')
        binding = {'execution': bundle['execution'], 'execution_revision': execution_revision}
    if worktree:
        binding['worktree'] = worktree
    return canonical({**binding, 'repository': bundle['repository'], 'plan_id': bundle['id'], 'gate': gate, 'policy_sources': sources, 'policy': policy,
                      'goals': {gid: goal_revision(bundle, gid) for gid in sorted(goals)}})


def typed_gate(root, bundle, gate, context, files_root=None, worktree=None):
    binding, kind = gate['binding'], gate['kind']
    fields = {'ownership': {'roles'}, 'branch_target': {'target', 'branch'},
              'fixture': {'file', 'command', 'isolation', 'tool'}, 'tooling': {'tool'},
              'protected_approval': {'subject'}, 'harness_trust': {'lock', 'anchor'}}
    require(set(binding) == fields[kind], 'unsupported_typed_binding')
    if kind == 'ownership':
        require(isinstance(binding['roles'], list) and binding['roles'] and
                set(binding['roles']) <= {'owner', 'reviewer'} and len(set(binding['roles'])) == len(binding['roles']), 'ownership_roles_required')
    elif kind == 'branch_target':
        require(all(string(binding[k]) and not re.search(r'\s|[;&|`$<>]', binding[k]) for k in ('target', 'branch')), 'target_branch_required')
    elif kind == 'fixture':
        require(isinstance(binding['file'], dict) and set(binding['file']) == {'path', 'sha256'}, 'fixture_file_ref_required')
        file_ref(root, binding['file'])
        require(binding['isolation'] in ('disposable-database', 'transaction-rollback', 'temporary-directory', 'container'), 'fixture_isolation_required')
        require(isinstance(binding['command'], str), 'fixture_command_required')
        validate_commands(root, [binding['command']])
        path = relative(root, binding['file']['path'])
        require(os.access(path, os.X_OK), 'fixture_not_executable')
    elif kind == 'protected_approval':
        subject = binding['subject']
        require(isinstance(subject, dict) and subject.get('mode') in ('full-file', 'goal-scope'), 'approval_subject_required')
        if subject['mode'] == 'full-file':
            require(set(subject) == {'mode', 'file'}, 'approval_subject_fields')
            require(isinstance(subject['file'], dict) and set(subject['file']) == {'path', 'sha256'}, 'approval_file_ref_required')
            file_ref(root, subject['file'])
        else:
            require(set(subject) == {'mode', 'goal', 'goal_sha256'} and
                    isinstance(subject['goal'], str) and subject['goal'] in {g['id'] for g in bundle['goals']} and
                    applies(gate['scope'], subject['goal']) and
                    subject['goal_sha256'] == goal_revision(bundle, subject['goal']), 'approval_goal_subject_mismatch')
    elif kind == 'harness_trust':
        # Independent anchor is a separately approved source, never the lock itself.
        require(all(isinstance(binding[k], dict) and set(binding[k]) == {'path', 'sha256'} for k in ('lock', 'anchor')), 'trust_sources_required')
        require(binding['lock'].get('path') != binding['anchor'].get('path'), 'trust_anchor_not_independent')
        try:
            file_ref(root, binding['lock'])
            file_ref(root, binding['anchor'])
        except (Invalid, OSError) as error:
            raise Invalid('trust_source_unavailable:expected=unavailable:actual=unverified:independent_source=' + str(binding['anchor'].get('path')) + ':' + str(error)) from error
        require(not os.path.samefile(relative(root, binding['lock']['path']), relative(root, binding['anchor']['path'])), 'trust_anchor_not_independent')
        require(binding['anchor']['sha256'] != bundle['spec']['sha256'] and not os.path.samefile(relative(root, binding['anchor']['path']), relative(files_root if files_root is not None else Path(bundle['repository']['root']), bundle['spec']['path'])), 'trust_anchor_is_plan_source')
        require(binding['anchor'] in (context['execution']['sources'] if gate.get('root') == 'execution' else context['sources']), 'trust_anchor_not_independently_approved')
        anchor_data = read(relative(root, binding['anchor']['path']))
        require(isinstance(anchor_data, dict) and not ({'goals', 'bundle', 'readiness', 'planning_complete'} & set(anchor_data)), 'trust_anchor_is_plan_source')
        require(set(anchor_data) == {'commit'}, 'unsupported_trust_anchor_shape')
        expected = anchor_data.get('commit')
        actual = read(relative(root, binding['lock']['path'])).get('commit')
        require(isinstance(expected, str) and re.fullmatch(r'[a-f0-9]{40}', expected), 'trust_expected_commit_unavailable')
        require(isinstance(actual, str) and re.fullmatch(r'[a-f0-9]{40}', actual), 'trust_actual_commit_unavailable')
        require(expected == actual, 'trust_commit_mismatch:expected=' + expected + ':actual=' + actual + ':independent_source=' + binding['anchor']['path'])
    if worktree and kind == 'branch_target':
        require(binding['target'] == worktree['target_ref'] and binding['branch'] == worktree['branch'], 'worktree_branch_target_mismatch')
    if kind in ('fixture', 'tooling'):
        tool = binding['tool']
        require(string(tool) and re.fullmatch(r'[A-Za-z0-9_.+-]+', tool), 'tool_name_required')
        require(shutil.which(tool) is not None, 'tool_unavailable:' + tool)
    results = [r for r in context['results'] if r.get('gate') == gate['id']]
    require(len(results) == 1, 'typed_evidence_missing_or_ambiguous')
    receipt = results[0]
    require(set(receipt) == {'gate', 'status', 'stage', 'scope', 'subject_sha256', 'issuer', 'evidence', 'observed_at', 'expires_at', 'value'}, 'typed_evidence_fields')
    require(receipt['status'] == 'pass' and receipt['stage'] == gate['stage'] and receipt['scope'] == gate['scope']
            and receipt['subject_sha256'] == gate_subject(bundle, gate, context['sources'], context['policy'], context.get('execution_revision'), worktree), 'typed_evidence_subject_mismatch')
    provenance(receipt)
    value = receipt['value']
    if kind == 'ownership':
        require(isinstance(value, dict) and set(value) == set(binding['roles']) and
                all(string(v) and v.strip().lower() not in ('tbd', 'unknown', 'unassigned', 'placeholder') for v in value.values()), 'named_ownership_required')
    else:
        require(value == binding, 'typed_observation_mismatch')


def gate_dimensions(gate):
    dimensions = {gate['dimension']} if 'dimension' in gate else set()
    kind = gate.get('kind')
    if kind == 'ownership':
        roles = gate.get('binding', {}).get('roles', [])
        dimensions |= {'owners' if role == 'owner' else 'reviewer' for role in roles if role in ('owner', 'reviewer')}
    else:
        dimension = {'branch_target': 'branch_target', 'fixture': 'fixtures', 'tooling': 'tooling',
                     'protected_approval': 'registration_approval', 'harness_trust': 'harness_trust'}.get(kind)
        if dimension:
            dimensions.add(dimension)
    return dimensions


def gate_shape(gate):
    require(isinstance(gate, dict) and ID.fullmatch(gate.get('id', '')), 'gate_id_required')
    require(gate.get('stage') in STAGES and string(gate.get('kind')), 'unknown_gate_stage_or_kind')
    allowed = {'id', 'stage', 'scope', 'kind', 'dimension', 'responsible', 'root'}
    require(gate.get('root', 'planning') in ('planning', 'execution'), 'invalid_gate_root')
    if gate['kind'] == 'file_digest':
        allowed |= {'path', 'sha256'}
    elif gate['kind'] == 'executable_presence':
        allowed |= {'path'}
    elif gate['kind'] in ('ownership', 'branch_target', 'fixture', 'protected_approval', 'harness_trust', 'tooling'):
        allowed |= {'binding'}
        require(isinstance(gate.get('binding'), dict), 'typed_binding_required')
    require(set(gate) <= allowed, 'unsupported_gate_fields')


def scoped_findings(gaps, requested, ancestors):
    # A currently failing prerequisite cannot be laundered by a cached completion.
    # Only selected goals and their dependencies are evaluated; unrelated gates stay local.
    visible = []
    for gap in gaps:
        affected = [gid for gid in sorted(requested) if applies(gap['scope'], gid) or
                    any(applies(gap['scope'], dependency) for dependency in ancestors[gid])]
        if affected:
            gap['blocked_goals'] = affected
            if gap['scope'] not in ('repository', {'repository': True}):
                gap['scope'] = {'goals': affected}
            visible.append(gap)
    return visible


def policy_admit(root, bundle, selected, context, stage, subject_hash, resolved=None, files_root=None, worktree=None):
    identity_root = root
    root = root if files_root is None else files_root
    gaps = []
    requested = set(selected)
    edges = {g['id']: g['dependencies'] for g in bundle['goals']}
    ancestors = {}
    for gid in requested:
        pending, seen = list(edges[gid]), set()
        while pending:
            dependency = pending.pop()
            if dependency not in seen:
                seen.add(dependency)
                pending.extend(edges[dependency])
        ancestors[gid] = seen
    evaluated = requested | set().union(*ancestors.values())

    additive_gates = []
    for goal in bundle['goals']:
        if goal['id'] not in evaluated:
            continue
        if goal['id'] in requested:
            coverage(goal, gaps, stage)
        if goal['id'] in requested and goal['readiness'][stage] != 'ready':
            add(gaps, 'goal_not_ready', goal['readiness'][stage], [goal['id']], stage,
                'unknown' if goal['readiness'][stage] == 'unknown' else 'blocked')
        for dependency in goal['dependencies']:
            if not dependency_complete(bundle, dependency, (context.get('completed_goals', []) if isinstance(context, dict) and isinstance(context.get('completed_goals', []), list) else []), context.get('execution_revision') if isinstance(context, dict) else None, worktree=worktree):
                add(gaps, 'dependency_incomplete', dependency, [goal['id']], stage)
        try:
            if goal['id'] in requested:
                validate_commands(execution_root(bundle, root), goal['verification'])
        except (VerificationError, OSError) as error:
            add(gaps, 'verification_invalid', str(error), [goal['id']], stage)
        # Goal requirements are additive only. Unsupported predicates never pass.
        requirements = goal.get('requirements', [])
        if not isinstance(requirements, list):
            add(gaps, 'goal_requirement_invalid', 'Expected requirement array', [goal['id']], stage)
            continue
        for gate in requirements:
            if not isinstance(gate, dict) or not string(gate.get('id')) or not ID.fullmatch(gate['id']) or gate.get('stage') not in STAGES or not string(gate.get('kind')):
                add(gaps, 'goal_requirement_invalid', 'Requires id, stage and typed kind', [goal['id']], stage)
                continue
            try:
                gate_shape(gate)
            except (Invalid, TypeError, AttributeError) as error:
                add(gaps, 'goal_requirement_invalid', str(error), [goal['id']], stage)
                continue
            additive_gates.append(dict(gate, scope={'goals': [goal['id']]}))
    try:
        require(context.get('schema') == 'readiness-context/1', 'independent_context_required')
        require(set(context) <= ({'schema', 'repository', 'policy', 'sources', 'authority', 'results', 'completed_goals', 'extensions'} | ({'execution', 'execution_revision'} if mapped(bundle) else set()) | ({'worktree'} if worktree else set())), 'unsupported_context_fields')
        require(isinstance(context.get('results'), list) and all(isinstance(r, dict) for r in context['results']), 'invalid_independent_results')
        require(isinstance(context.get('completed_goals'), list) and all(isinstance(g, dict) for g in context['completed_goals']), 'invalid_completed_goals')
        repository(context.get('repository'), identity_root)
        require((root / POLICY).is_file(), 'unsupported_policy_source:' + POLICY)
        policy_path = relative(root, POLICY)
        policy = read(policy_path)
        require(policy.get('schema') == 'readiness-policy/1', 'unsupported_policy_schema')
        require(set(policy) <= ({'schema', 'repository', 'sources', 'gates', 'not_applicable', 'extensions'} | ({'execution'} if mapped(bundle) else set()) | ({'worktree'} if worktree else set())), 'unsupported_policy_fields')
        require(policy.get('repository') == bundle['repository'] == context['repository'], 'policy_repository_mismatch')
        if mapped(bundle):
            require(policy.get('execution') == bundle['execution'] == context.get('execution'), 'execution_mapping_mismatch')
            require(isinstance(context.get('execution_revision'), str) and REVISION.fullmatch(context['execution_revision']), 'execution_revision_required')
        if worktree:
            require(policy.get('worktree') == worktree_binding(worktree), 'worktree_policy_mismatch')
            require(context.get('worktree') == worktree, 'worktree_context_mismatch')
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
        if worktree:
            required_sources |= instruction_paths(bundle, root)
        require(required_sources <= {x.get('path') for x in sources}, 'policy_source_set_incomplete')
        for source in sources:
            file_ref(root, source)
        gates = policy.get('gates')
        require(isinstance(gates, list), 'policy_gates_required')
        exclusions = policy.get('not_applicable')
        require(isinstance(exclusions, dict) and all(string(k) and string(v) for k, v in exclusions.items()), 'explicit_not_applicable_reasons_required')
        covered = set().union(*(gate_dimensions(g) for g in gates if isinstance(g, dict)))
        require(DIMENSIONS <= set(exclusions) | covered, 'policy_dimensions_required')
        require(not (set(exclusions) & covered), 'contradictory_policy_dimension')
        all_ids = {g['id'] for g in bundle['goals']}
        gate_ids = []
        for gate in gates:
            gate_shape(gate)
            gate_ids.append(gate['id'])
            scope = gate.get('scope')
            require(isinstance(scope, dict) and (scope == {'repository': True} or
                    (set(scope) == {'goals'} and isinstance(scope['goals'], list) and scope['goals']
                     and all(isinstance(g, str) and g in all_ids for g in scope['goals']))), 'explicit_gate_scope_required')
        gates = [*gates, *additive_gates]
        require(mapped(bundle) or all(g.get('root', 'planning') == 'planning' for g in gates), 'execution_requires_mapped_schema')
        if mapped(bundle) and stage in ('implementation', 'merge'):
            require('branch_target' not in exclusions, 'mapped_branch_target_cannot_be_exempted')
            for gid in evaluated:
                target_gates = [g for g in gates if g['kind'] == 'branch_target' and g['stage'] == stage and applies(g['scope'], gid)]
                require(target_gates and all(g['binding'].get('target') == bundle['execution']['target'] for g in target_gates), 'mapped_branch_target_required')
        gate_ids = [g['id'] for g in gates]
        require(len(set(gate_ids)) == len(gate_ids), 'duplicate_policy_gate_ids')
    except (Invalid, OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        add(gaps, 'policy_context_invalid', str(error), 'repository', stage, 'unknown')
        return scoped_findings(gaps, requested, ancestors)
    if resolved is not None:
        for dimension, reason in sorted(exclusions.items()):
            exempt = sorted(gid for gid in evaluated if not any(g['stage'] == stage and applies(g['scope'], gid) and dimension in gate_dimensions(g) for g in additive_gates))
            if not exempt:
                continue
            resolved.append({'gate': dimension, 'stage': stage, 'scope': {'goals': exempt},
                             'status': 'not_applicable', 'source': {'policy': POLICY, 'sha256': context['policy']['sha256']},
                             'responsible': 'unassigned', 'evidence_refs': [], 'freshness': 'current-policy-digest',
                             'recovery': 'Reevaluate if repository policy changes', 'reason': reason})
    try:
        authority = context.get('authority', {})
        require(isinstance(authority, dict) and set(authority) == ({'status', 'stage', 'subject_sha256', 'issuer', 'goals'} | ({'execution_revision'} if mapped(bundle) else set()) | ({'worktree', 'policy_sha256'} if worktree else set())), 'unsupported_authority_fields')
        if worktree:
            require(authority.get('worktree') == worktree and authority.get('policy_sha256') == context['policy']['sha256'], 'authority_worktree_mismatch')
        if mapped(bundle):
            require(authority.get('execution_revision') == context['execution_revision'], 'authority_execution_revision_mismatch')
        require(authority.get('status') == 'pass' and authority.get('stage') == stage
                and authority.get('subject_sha256') == subject_hash and string(authority.get('issuer'))
                and isinstance(authority.get('goals'), list) and set(selected) <= set(authority['goals']), 'independent_authority_required')
    except (Invalid, TypeError) as error:
        add(gaps, 'authority_unavailable', str(error), 'repository', stage, 'unknown')
    for gate in gates:
        scope = gate.get('scope', {})
        targets = all_ids if scope == {'repository': True} else set(scope.get('goals', []))
        if gate.get('stage') != stage or not (targets & evaluated):
            continue
        try:
            kind = gate.get('kind')
            gate_root = execution_root(bundle, root) if gate.get('root') == 'execution' else root
            if kind == 'file_digest':
                file_ref(gate_root, gate)
            elif kind == 'executable_presence':
                path = relative(gate_root, gate.get('path'))
                require(path.is_file() and os.access(path, os.X_OK), 'executable_unavailable')
            elif kind == 'measured_coverage':
                require(all(g.get('coverage_status', 'measured') == 'measured' and
                            isinstance(g.get('coverage_percent'), (float, int)) and
                            not isinstance(g.get('coverage_percent'), bool) and
                            0 <= g['coverage_percent'] <= 100 for g in bundle['goals'] if g['id'] in targets & evaluated), 'measured_coverage_required')
            elif kind in ('ownership', 'branch_target', 'fixture', 'protected_approval', 'harness_trust', 'tooling'):
                typed_gate(gate_root, bundle, gate, context, files_root=root, worktree=worktree)
            elif kind == 'independent_result':
                results = [x for x in context.get('results', []) if x.get('gate') == gate['id']]
                require(len(results) == 1, 'independent_result_missing_or_ambiguous')
                result = results[0]
                require(set(result) == ({'gate', 'status', 'stage', 'scope', 'subject_sha256', 'issuer'} | ({'execution_revision'} if mapped(bundle) else set()) | ({'worktree', 'policy_sha256'} if worktree else set())), 'unsupported_result_fields')
                if worktree:
                    require(result.get('worktree') == worktree and result.get('policy_sha256') == context['policy']['sha256'], 'result_worktree_mismatch')
                if mapped(bundle):
                    require(result.get('execution_revision') == context['execution_revision'], 'result_execution_revision_mismatch')
                require(result.get('status') == 'pass' and result.get('stage') == stage and result.get('scope') == scope
                        and result.get('subject_sha256') == subject_hash and string(result.get('issuer')), 'independent_result_invalid')
            else:
                add(gaps, 'unsupported_gate', str(kind), scope, stage, 'unknown')
                continue
            if resolved is not None:
                receipt = next((r for r in context['results'] if r.get('gate') == gate['id']), {})
                resolved.append({'gate': gate['id'], 'stage': stage, 'scope': scope, 'status': 'ready',
                                 'source': {'policy': POLICY, 'sha256': context['policy']['sha256']},
                                 'responsible': gate.get('responsible', 'unassigned'),
                                 'evidence_refs': [re.sub(r'https?://[^\s]+', '[redacted-url]', str(ref)) for ref in receipt.get('evidence', [])] if isinstance(receipt.get('evidence'), list) else [],
                                 'freshness': {'observed_at': receipt.get('observed_at', 'current-file-read'), 'expires_at': receipt.get('expires_at', 'not-declared')},
                                 'recovery': 'Retain while exact binding and freshness remain valid; does not authorize dispatch'})
        except (Invalid, VerificationError, OSError, ValueError, TypeError, KeyError, AttributeError) as error:
            unavailable = any(token in str(error) for token in ('unavailable', 'missing', 'required', 'No such file'))
            add(gaps, 'gate_failed', gate.get('id', '') + ':' + str(error), scope, stage, 'unknown' if unavailable else 'blocked')
            gaps[-1]['responsible'] = gate.get('responsible', 'unassigned')
            receipt = next((r for r in context['results'] if r.get('gate') == gate['id']), {})
            gaps[-1]['source'] = {'policy': POLICY, 'gate': gate['id'], 'issuer': receipt.get('issuer', 'unavailable')}
            gaps[-1]['freshness'] = {'observed_at': receipt.get('observed_at', 'unavailable'),
                                    'expires_at': receipt.get('expires_at', 'unavailable'), 'validated': False}
            gaps[-1]['evidence_refs'] = [re.sub(r'https?://[^\s]+', '[redacted-url]', str(ref))
                                        for ref in receipt.get('evidence', [])] if isinstance(receipt.get('evidence'), list) else []
            gaps[-1]['recovery'] = {
                'ownership': 'Supply named required owner/reviewer and an independent current receipt',
                'branch_target': 'Supply the approved exact target/branch binding and independent current receipt',
                'fixture': 'Prepare the isolated executable fixture and obtain independent current fixture evidence',
                'tooling': 'Install the declared tool in the governed environment and refresh independent evidence',
                'protected_approval': 'Obtain approval only for this changed or missing exact subject; retain unaffected receipts',
                'harness_trust': 'Verify expected commit against the independent provenance anchor; never rewrite trust to fit the lock',
            }.get(kind, 'Resolve the specified gate evidence and rerun this exact stage')
    return scoped_findings(gaps, requested, ancestors)


def select(root, args, files_root=None):
    identity_root = root
    root = root if files_root is None else files_root
    require(bool(args.goal) != bool(args.handoff), 'selection_required:use exact --handoff with --goal-id or explicit --goal')
    if args.goal:
        require(not args.goal_id, 'direct_goal_selector_conflict')
        if files_root is not None and root != identity_root:
            require(Path(args.goal).is_absolute() and root in Path(args.goal).parents, 'worktree_direct_goal_outside_root')
            relative(root, Path(args.goal).relative_to(root).as_posix())
        envelope = read(Path(args.goal))
        require(isinstance(envelope, dict) and envelope.get('schema') == 'direct-goal/1', 'migration_required:direct-goal/1')
        bundle = envelope.get('bundle')
        bundle_shape(bundle, identity_root, root)
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
    require(entry.get('status') == 'active' or (args.stage == 'planning' and entry.get('status') == 'blocked'), 'handoff_not_active')
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
    bundle_shape(bundle, identity_root, root)
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
              'authority_verification': 'external-required', 'goals': args.goal_id or [], 'gaps': [], 'resolved': []}
    try:
        files_root, worktree = worktree_request(args, root)
        require(all((files_root / name).is_file() for name in ('.ai/matrix.json', MANIFEST, GRAPH)), 'v3_root_required')
        for name in ('.ai/matrix.json', MANIFEST, GRAPH):
            require(isinstance(read(relative(files_root, name)), dict), 'v3_root_malformed')
        bundle, selected, subject, entry = select(root, args, files_root)
        require(not worktree or not mapped(bundle), 'worktree_mapped_conflict')
        if worktree:
            inputs = worktree_inputs(bundle, files_root)
            if args.goal:
                inputs.append(Path(args.goal).relative_to(files_root).as_posix())
            worktree = worktree_observation(root, files_root, args.base_commit, clean=args.stage == 'merge', inputs=inputs)
            report['worktree'] = worktree
        if mapped(bundle):
            require(bool(getattr(args, 'execution_root', None)), 'execution_root_required')
        if getattr(args, 'execution_root', None):
            require(mapped(bundle) and args.execution_root == bundle['execution']['repository']['root'], 'execution_root_mismatch')
        if getattr(args, 'execution_record', None):
            record = read(Path(args.execution_record))
            selected_records = [goal for goal in bundle['goals'] if goal['id'] in selected]
            require(len(selected_records) == 1 and record == selected_records[0], 'execution_record_mismatch')
        report.update(plan_id=bundle['id'], repository=bundle['repository'],
                      bundle={'schema': bundle['schema'], 'id': bundle['id'], 'canonical_sha256': canonical(bundle)},
                      specification=bundle['spec'], goals=selected,
                      planning_complete=bundle['planning_complete'], handoff=entry, subject_sha256=subject)
        context = {}
        context_error = None
        if args.context:
            try:
                context = read(args.context)
            except (OSError, ValueError) as error:
                context_error = str(error)
        if mapped(bundle):
            report.update(execution=bundle['execution'],
                          execution_revision=context.get('execution_revision') if isinstance(context, dict) else None,
                          execution_revision_source='independent-context')
        stages = STAGES if args.stage == 'planning' else (args.stage,)
        for stage in stages:
            report['gaps'].extend(policy_admit(root, bundle, selected, context, stage, subject, report['resolved'], files_root, worktree))
            if not bundle['planning_complete'] or bundle['status'] != 'active':
                add(report['gaps'], 'plan_not_active_or_incomplete', bundle['status'], 'repository', stage)
            if context_error:
                add(report['gaps'], 'context_unavailable', context_error, 'repository', stage, 'unknown')
        report['per_goal'] = {}
        for gid in selected:
            report['per_goal'][gid] = {}
            for stage in stages:
                findings = [gap for gap in report['gaps'] if gap['stage'] == stage and
                            applies(gap['scope'], gid)]
                status = 'blocked' if any(f['status'] == 'blocked' for f in findings) else ('unknown' if findings else 'ready')
                report['per_goal'][gid][stage] = {'status': status, 'findings': findings + [r for r in report['resolved'] if r['stage'] == stage and applies(r['scope'], gid)]}
        if worktree:
            require(worktree == worktree_observation(root, files_root, args.base_commit, clean=args.stage == 'merge', inputs=inputs), 'worktree_changed_during_validation')
        report['execution_ready'] = args.stage != 'planning' and not report['gaps']
    except (Invalid, OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        add(report['gaps'], 'admission_failed', str(error), 'repository', args.stage)
    report['remaining_blockers'] = report['gaps']
    return redact(report)


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


def validate_generation(root, prefix, bundle, generation, spec, identity_root=None):
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
    identity_root = Path(args.root).resolve(strict=True)
    root, worktree = worktree_request(args, identity_root)
    candidate = Path(args.bundle).resolve(strict=True)
    if worktree:
        require(root in candidate.parents, 'worktree_candidate_outside_root')
        relative(root, candidate.relative_to(root).as_posix())
        require(read(relative(root, POLICY)).get('worktree') == worktree_binding(worktree), 'worktree_policy_mismatch')
    candidate_hash = digest(candidate)
    bundle = read(candidate)
    require(not worktree or not mapped(bundle), 'worktree_mapped_conflict')
    bundle_shape(bundle, identity_root, root)
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
            graph = validate_generation(root, prefix, bundle, generation, matching[0], identity_root=identity_root)
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
        bundle_shape(bundle, identity_root, root)
        require(digest(candidate) == candidate_hash, 'candidate_changed')
        require((digest(registry_path) if registry_path.exists() else None) == registry_hash and digest(graph_path) == graph_hash, 'publication_source_changed')
        # Visibility boundary 1: additive graph, never completion by itself.
        if worktree:
            current = worktree_observation(identity_root, root, args.base_commit)
            require(all(current[key] == value for key, value in worktree.items() if key != 'state_sha256'), 'worktree_changed_during_publication')
        replace_json(graph_path, live_graph)
        require(digest(candidate) == candidate_hash, 'candidate_changed')
        require((digest(registry_path) if registry_path.exists() else None) == registry_hash, 'publication_source_changed')
        bundle_shape(bundle, identity_root, root)
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
    require(not getattr(args, 'worktree_root', None) and not getattr(args, 'base_commit', None), 'worktree_migration_unsupported')
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
    parser.add_argument('--execution-record')
    parser.add_argument('--execution-root')
    parser.add_argument('--worktree-root')
    parser.add_argument('--base-commit')
    parser.add_argument('--bundle')
    parser.add_argument('--legacy')
    parser.add_argument('--stage', choices=('planning', *STAGES), default='implementation')
    args = parser.parse_args()
    try:
        result = {'admit': admit, 'publish': publish, 'migrate': migrate}[args.operation](args)
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1 if result.get('gaps') and not (args.stage == 'planning' and result.get('planning_complete') and 'per_goal' in result) else 0
    except (Invalid, OSError, ValueError, TypeError, AttributeError, KeyError) as error:
        print(json.dumps({'schema': VERSION, 'error': str(error), 'execution_ready': False, 'dispatch_authorized': False, 'authority_verification': 'external-required'}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
