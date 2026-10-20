"""Defensive Git proof refusals via a read-only fixture Git adapter."""
import copy
import json
import os
from pathlib import Path
import shutil
import tempfile


SHIM = '''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
cfg=json.loads(os.environ['E6_GIT_PROOF'])
args=sys.argv[1:]
at=args.index('-C')
cwd,operation=args[at+1],args[at+2:]
if cwd == cfg['cwd'] and operation == cfg['args']:
    counter=Path(cfg['counter'])
    count=int(counter.read_text())+1
    counter.write_text(str(count))
    if count >= cfg.get('after',1):
        sys.stdout.write(cfg['stdout'])
        sys.exit(0)
result=subprocess.run([cfg['git'],*args],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
sys.stdout.buffer.write(result.stdout);sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''


def run(parity, lib):
    from readiness_worktree_test import WorktreeTests
    from readiness_fixture import write
    names = ['toplevel', 'bare', 'linked', 'registered', 'branch', 'base-commit', 'tree-type', 'validation-changed', 'publication-changed',
             'bad-base', 'identity-alias', 'inside-context', 'outside-direct', 'outside-candidate', 'unreadable-directory', 'nonregular', 'symlink-directory', 'authority-binding', 'independent-result',
             'publication-policy', 'mapped-admission', 'mapped-publication']
    for name in names:
        case = WorktreeTests('test_admission_keeps_canonical_identity_and_reads_only_worktree')
        case.setUp()
        try:
            args = case.admission_fixture()
            common = case.git(case.files, 'rev-parse', '--path-format=absolute', '--git-common-dir')
            config = {'git': shutil.which('git'), 'cwd': str(case.files), 'counter': str(case.home / 'git-counter'), 'after': 1}
            overrides = {'toplevel': (['rev-parse', '--show-toplevel'], str(case.identity)+'\n'),
                         'bare': (['rev-parse', '--is-bare-repository'], 'true\n'),
                         'linked': (['rev-parse', '--absolute-git-dir'], common+'\n'),
                         'registered': (['worktree', 'list', '--porcelain', '-z'], ''),
                         'branch': (['symbolic-ref', '--quiet', 'HEAD'], 'not-a-head\n'),
                         'base-commit': (['rev-parse', '--verify', case.base+'^{commit}'], '0'*40+'\n'),
                         'tree-type': (['ls-tree', '-r', '-z', case.base], '160000 commit '+'0'*40+'\tinput.txt\0'),
                         'validation-changed': (['symbolic-ref', '--quiet', 'HEAD'], 'refs/heads/changed\n'),
                         'publication-changed': (['symbolic-ref', '--quiet', 'HEAD'], 'refs/heads/changed\n')}
            if name == 'registered': config['cwd'] = str(case.identity)
            if name == 'tree-type': args.stage = 'merge'
            if name == 'validation-changed': config['after'] = 3
            if name == 'publication-changed':
                config['after'] = 2
                args.bundle = str(write(case.files, 'candidate.json', case.bundle))
            if name == 'bad-base': args.base_commit = 'not-a-revision'
            if name == 'identity-alias':
                alias = case.home / 'primary-alias'
                alias.symlink_to(case.identity, target_is_directory=True)
                args.root = str(alias)
            if name == 'inside-context': args.context = str(write(case.files, 'context.json', case.context))
            if name == 'outside-direct': args.goal = str(write(case.home, 'outside-direct.json', {'schema': 'direct-goal/1', 'bundle': case.bundle}))
            if name == 'outside-candidate': args.bundle = str(write(case.home, 'outside-candidate.json', case.bundle))
            if name == 'publication-policy':
                case.policy['worktree'] = None
                write(case.files, '.ai/policies/readiness-policy.json', case.policy)
                args.bundle = str(write(case.files, 'candidate.json', case.bundle))
            if name in ('mapped-admission', 'mapped-publication'):
                application = case.home / 'application'
                application.mkdir()
                (application / 'AGENTS.md').write_text('Separate execution instructions')
                from readiness_fixture import digest
                execution = {'repository': {'id': 'application', 'root': str(application)}, 'target': 'main',
                             'source_revision': 'a'*40, 'sources': [{'path': 'AGENTS.md', 'sha256': digest(application / 'AGENTS.md')}], 'validation': 'external-only'}
                case.bundle.update(schema='mapped-handoff-goals/1', execution=execution)
                case.bundle['goals'][0]['repository'] = copy.deepcopy(execution['repository'])
                write(case.files, 'direct.json', {'schema': 'direct-goal/1', 'bundle': case.bundle})
                args.bundle = str(write(case.files, 'candidate.json', case.bundle))
            if name == 'unreadable-directory':
                (case.files / 'unreadable').mkdir(mode=0)
            if name == 'nonregular': os.mkfifo(case.files / 'fifo')
            if name == 'symlink-directory': (case.files / 'alias').symlink_to(case.home, target_is_directory=True)
            if name == 'authority-binding':
                case.context['authority']['worktree'] = dict(case.context['worktree'], branch='wrong')
                write(case.home, 'independent-context.json', case.context)
            if name == 'independent-result':
                policy = case.policy
                gate = {'id': 'independent', 'kind': 'independent_result', 'stage': 'implementation', 'scope': {'repository': True}}
                policy['gates'].append(gate)
                write(case.files, '.ai/policies/readiness-policy.json', policy)
                case.refresh_admission()
                from readiness_fixture import digest
                case.context['policy']['sha256'] = digest(case.files / '.ai/policies/readiness-policy.json')
                case.context['authority']['policy_sha256'] = case.context['policy']['sha256']
                case.context['results'] = [{'gate': gate['id'], 'stage': 'implementation', 'scope': gate['scope'], 'status': 'pass',
                    'subject_sha256': case.context['authority']['subject_sha256'], 'issuer': 'fixture', 'policy_sha256': case.context['policy']['sha256'],
                    'worktree': dict(case.context['worktree'], branch='wrong')}]
                write(case.home, 'independent-context.json', case.context)
            operation = 'publish' if name in ('publication-changed','outside-candidate','publication-policy','mapped-publication') else 'admit'
            flags = [operation]
            for key, value in vars(args).items():
                if value is not None: flags.extend(['--'+key.replace('_','-'), str(value)])
            previous_path, previous_proof = os.environ['PATH'], os.environ.get('E6_GIT_PROOF')
            try:
                if name in overrides:
                    config['args'], config['stdout'] = overrides[name]
                    shim = case.home / 'bin'
                    shim.mkdir()
                    (shim / 'git').write_text(SHIM)
                    (shim / 'git').chmod(0o755)
                    os.environ['PATH'] = str(shim) + os.pathsep + previous_path
                    os.environ['E6_GIT_PROOF'] = json.dumps(config)
                Path(config['counter']).write_text('0')
                left = parity.run(parity.py_cmd(lib, flags[0], flags[1:]))
                Path(config['counter']).write_text('0')
                right = parity.run(parity.ts_cmd(flags[0], flags[1:]))
                parity.same('worktree-proof-' + name, left, right)
            finally:
                os.environ['PATH'] = previous_path
                if previous_proof is None: os.environ.pop('E6_GIT_PROOF', None)
                else: os.environ['E6_GIT_PROOF'] = previous_proof
                if name == 'unreadable-directory': (case.files / 'unreadable').chmod(0o755)
        finally:
            case.doCleanups()
