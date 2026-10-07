"""readiness-contract/2 core: policy/2, content-only revision, sidecar order (AC-4),
pure validator, policy bootstrap, publication, rebuilt admission and the pinned
entry point. Disposable fixtures only; nothing here is an approval or authority.

The fixture helpers in this module are shared by the approval and certificate
suites (imported by name, so their test classes are not collected twice)."""
import ast
import builtins
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from unittest import mock

REPO = Path(__file__).resolve().parents[1]
AUTO = REPO / '04-validate-handoff/autobahn'
NORTH = REPO / '02-govern-plan/northstar'
sys.path.insert(0, str(AUTO / 'lib'))
import readiness_contract_v2 as v2  # noqa: E402
import observer  # noqa: E402

NOW = datetime(2026, 10, 3, 12, 0, 0, tzinfo=timezone.utc)
POLICY = '.ai/policies/readiness-policy.json'
REGISTRY = '.ai/workflows/northstar-readiness-v2.json'
PATTERN = '^(feat|fix|chore)/<plan_id>-<goal_id>$'


def sha(data):
    return hashlib.sha256(data if isinstance(data, bytes) else Path(data).read_bytes()).hexdigest()


def stamp(moment):
    return moment.strftime('%Y-%m-%dT%H:%M:%SZ')


def git(cwd, *args, check=True):
    result = subprocess.run(['git', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid',
                             '-c', 'commit.gpgsign=false', '-c', 'tag.gpgsign=false', '-c', 'init.defaultBranch=main',
                             '-c', 'core.hooksPath=/dev/null', *args],
                            cwd=str(cwd), capture_output=True, text=True)
    if check and result.returncode:
        raise AssertionError('git %s failed: %s' % (' '.join(args), result.stderr))
    return result.stdout.strip()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')
    return path


def codes(result):
    """Refusal or gap codes from any v2 result object."""
    entries = result.get('gaps', []) + result.get('refusals', []) + result.get('findings', [])
    return {entry['code'] for entry in entries}


def ssh_sign(key, namespace, data, workdir):
    workdir = Path(tempfile.mkdtemp(dir=workdir))
    payload = workdir / 'payload'
    payload.write_bytes(data)
    subprocess.run(['ssh-keygen', '-q', '-Y', 'sign', '-f', str(key), '-n', namespace, str(payload)],
                   check=True, capture_output=True)
    return (workdir / 'payload.sig').read_text()


class Keys:
    """Ephemeral role keys and a temporary trust anchor outside every worktree."""

    def __init__(self, base):
        self.dir = Path(tempfile.mkdtemp(prefix='keys-', dir=base))
        self.paths = {}
        for name in ('approver', 'certifier', 'reviewer', 'outsider', 'certonly'):
            path = self.dir / name
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', name, '-f', str(path)],
                           check=True, capture_output=True)
            self.paths[name] = path
        self.anchor = self.dir / 'anchor' / 'allowed_signers'
        self.anchor.parent.mkdir()
        self.write_anchor()

    def public(self, name):
        return ' '.join(self.paths[name].with_suffix('.pub').read_text().split()[:2])

    def write_anchor(self, approver_namespaces=v2.NS_APPROVAL):
        agent = v2.NS_REVIEW + ',' + v2.NS_CERTIFICATE
        lines = ['approver@human namespaces="%s" %s' % (approver_namespaces, self.public('approver')),
                 'certifier@agent namespaces="%s" %s' % (agent, self.public('certifier')),
                 'reviewer@agent namespaces="%s" %s' % (agent, self.public('reviewer')),
                 'certonly@agent namespaces="%s" %s' % (v2.NS_CERTIFICATE, self.public('certonly'))]
        self.anchor.write_text('\n'.join(lines) + '\n')
        return sha(self.anchor)


def fake_sk_line(principal, namespaces):
    """A parseable sk-ssh-ed25519 anchor line for a key nobody holds."""
    import base64
    blob = b''.join(len(part).to_bytes(4, 'big') + part for part in
                    (b'sk-ssh-ed25519@openssh.com', bytes(range(32)), b'ssh:'))
    return '%s namespaces="%s" sk-ssh-ed25519@openssh.com %s\n' % (principal, namespaces, base64.b64encode(blob).decode())


def gh_shim(directory, state_path, log_path):
    """A recording stand-in for the production `gh` binary (found through PATH)."""
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    script = directory / 'gh'
    script.write_text('''#!/usr/bin/env python3
import json, os, re, sys
STATE, LOG = %r, %r
args = sys.argv[1:]
with open(LOG, 'a') as handle:
    handle.write(json.dumps({'args': args, 'env': dict(os.environ)}) + '\\n')
state = json.load(open(STATE))
def out(value):
    print(json.dumps(value)); sys.exit(0)
def fail(message, code=1):
    sys.stderr.write(message + '\\n'); sys.exit(code)
def save():
    json.dump(state, open(STATE, 'w'))
if args[:2] == ['api', 'graphql']:
    number = next(a.split('=', 1)[1] for a in args if a.startswith('number='))
    nodes = state.get('threads', {}).get(number, [])
    out({'data': {'repository': {'pullRequest': {'reviewThreads': {'nodes': nodes}}}}})
if args[:1] == ['api']:
    path = args[1]
    match = re.fullmatch(r'repos/\\{owner\\}/\\{repo\\}/pulls/(\\d+)', path)
    if match:
        pull = state['pulls'][match.group(1)]
        sequence = pull.get('head_sequence') or []
        if sequence:
            pull['head']['sha'] = sequence.pop(0)
            save()
        out({'number': int(match.group(1)), 'state': pull.get('state', 'open'), 'merged': pull.get('merged', False),
             'merge_commit_sha': pull.get('merge_commit_sha'), 'head': pull['head'], 'base': pull['base']})
    match = re.fullmatch(r'repos/\\{owner\\}/\\{repo\\}/commits/([0-9a-f]{40})/check-runs\\?per_page=100', path)
    if match:
        runs = state.get('checks', {}).get(match.group(1), [])
        out({'total_count': len(runs), 'check_runs': runs})
    match = re.fullmatch(r'repos/\\{owner\\}/\\{repo\\}/branches/([^/]+)/protection/required_status_checks', path)
    if match:
        protection = state.get('protection')
        if protection is None:
            fail('gh: Not Found (HTTP 404)')
        if protection == 403:
            fail('gh: Resource not accessible (HTTP 403)')
        out(protection)
if args[:2] == ['pr', 'list']:
    out(state.get('merged_prs', []))
if args[:2] == ['pr', 'merge']:
    number = args[2]
    head = args[args.index('--match-head-commit') + 1]
    pull = state['pulls'][number]
    current = pull.get('head_at_merge', pull['head']['sha'])
    if head != current:
        fail('Head branch was modified. Review and try the merge again.')
    state.setdefault('merged', []).append({'pr': number, 'head': head, 'args': args})
    save()
    sys.exit(0)
fail('unsupported gh call: ' + ' '.join(args), 2)
''' % (str(state_path), str(log_path)))
    script.chmod(0o755)
    return script


def sample_policy(anchor_sha256, identity_model='single', accept=('ssh-tag', 'in-session')):
    repo = {'repository': True}
    return {
        'schema': 'readiness-policy/2', 'repository': {'id': 'fixture'}, 'identity_model': identity_model,
        'sources': ['AGENTS.md'], 'required_checks': ['Test Suite'], 'skippable_checks': ['Optional Smoke'],
        'branch_pattern': PATTERN, 'target': 'main', 'tools': ['git', 'python3'],
        'reviewer_requirements': {'independent_lane': True},
        'approval': {'anchor_sha256': anchor_sha256, 'max_age_days': 14, 'accept': list(accept)},
        'gates': [
            {'id': 'owner', 'kind': 'ownership', 'stage': 'implementation', 'scope': repo, 'binding': {'roles': ['owner']}},
            {'id': 'reviewer', 'kind': 'ownership', 'stage': 'merge', 'scope': repo, 'binding': {'roles': ['reviewer']}},
            {'id': 'approval', 'kind': 'plan_approval', 'stage': 'implementation', 'scope': repo},
            {'id': 'approval-merge', 'kind': 'plan_approval', 'stage': 'merge', 'scope': repo},
            {'id': 'branch', 'kind': 'branch_target', 'stage': 'merge', 'scope': repo},
            {'id': 'tools', 'kind': 'tooling', 'stage': 'implementation', 'scope': repo},
            {'id': 'b5', 'kind': 'git_ancestor', 'stage': 'implementation', 'scope': repo},
            {'id': 'checks', 'kind': 'hosted_checks', 'stage': 'merge', 'scope': repo},
            {'id': 'review', 'kind': 'review', 'stage': 'merge', 'scope': repo},
            {'id': 'fixtures', 'kind': 'fixture', 'stage': 'implementation', 'scope': repo,
             'not_applicable': {'reason': 'no-fixture-dependency'}},
            {'id': 'harness', 'kind': 'harness_trust', 'stage': 'implementation', 'scope': repo,
             'not_applicable': {'reason': 'no-pinned-harness'}},
        ],
    }


def sample_bundle(goals=None):
    goals = goals or [{'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['The app file exists'],
                       'dependencies': [], 'verification': ['bash tests/check.sh']}]
    return {'schema': 'handoff-goals/2', 'id': 'plan-a', 'repository': {'id': 'fixture'},
            'spec': {'path': 'spec.md'}, 'goals': goals}


def sample_sidecar(bundle):
    return {'schema': 'readiness-sidecar/1', 'plan_id': bundle['id'], 'goals': {
        goal['id']: {'readiness': {'preparation': 'unknown', 'implementation': 'unknown', 'merge': 'unknown'},
                     'coverage_status': 'unknown', 'legacy_safe_tdd': True,
                     'legacy_risk_reason': 'Fixture coverage is unmeasured'} for goal in bundle['goals']}}


def admission_inputs(policy, bundle, sidecar, stage='implementation'):
    """The pure admission input contract, as the observer assembles it."""
    digests = {'bundle_sha256': v2.bundle_sha256(bundle), 'spec_sha256': '2' * 64,
               'policy_sha256': '3' * 64, 'anchor_sha256': policy['approval']['anchor_sha256']}
    generation = v2.generation_v2(**digests)
    record = v2.approval_record(plan_id=bundle['id'], generation=generation, bundle_sha256=digests['bundle_sha256'],
                                spec_sha256=digests['spec_sha256'], policy_sha256=digests['policy_sha256'],
                                sidecar_sha256=v2.canonical(sidecar), goals=[g['id'] for g in bundle['goals']],
                                owner='Owner', reviewer_lane='lane', issued_at=stamp(NOW - timedelta(days=1)),
                                expires_at=stamp(NOW + timedelta(days=6)), anchor_sha256=digests['anchor_sha256'],
                                assurance='in-session')
    line = json.dumps(record, sort_keys=True, separators=(',', ':')).encode()
    carrier = {'tag': 'approval/%s/%s' % (bundle['id'], generation[:12]), 'annotated': True, 'on_origin': True,
               'target_contains_generation': True, 'form': 'in-session', 'record': record, 'record_canonical': True,
               'digest_echo': sha(line), 'signature': None,
               'anchor': {'present': True, 'inside_worktree': False, 'sha256': digests['anchor_sha256']}}
    head = 'c' * 40

    def fact(value, source='git'):
        return {'value': value, 'source': source, 'observed_at': stamp(NOW), 'commit': head}
    facts = {'repository': fact({'id': 'fixture', 'common_dir': '/repo/.git', 'root': '/repo', 'head': head,
                                 'branch': 'refs/heads/feat/plan-a-G1'}),
             'planning_inputs': fact({'publication_commit': 'b' * 40, 'on_target': True, 'in_head': True})}
    for tool in policy['tools']:
        facts['tool:' + tool] = fact('/usr/bin/' + tool, 'PATH')
    return {'stage': stage, 'goals': [bundle['goals'][0]['id']], 'now': NOW,
            'registered': {'id': 'northstar-plan-' + bundle['id'], 'generation': generation, 'mode': 'live'},
            'policy': policy, 'policy_mode': 'live', 'live_policy2': True, 'candidate_is_live': False,
            'bundle': bundle, 'sidecar': sidecar, 'sidecar_v0': None, 'digests': digests, 'carrier': carrier,
            'observation': {'schema': 'observation/1', 'adapter': 'none', 'target': 'main',
                            'target_revision': 'a' * 40, 'facts': facts},
            'errors': []}


class Fixture:
    """A disposable repository with a bare origin, a published v2 generation and role keys."""

    def __init__(self, base, *, identity_model='single', accept=('ssh-tag', 'in-session'), bundle=None,
                 candidate=False, live_policy=True, anchor_prefix=''):
        self.base = Path(base)
        self.keys = Keys(self.base)
        if anchor_prefix:
            self.keys.anchor.write_text(anchor_prefix + self.keys.anchor.read_text())
        self.anchor_sha256 = sha(self.keys.anchor)
        self.origin = self.base / 'origin.git'
        self.work = self.base / 'work'
        git(self.base, 'init', '-q', '--bare', str(self.origin))
        git(self.base, 'clone', '-q', str(self.origin), str(self.work))
        self.policy = sample_policy(self.anchor_sha256, identity_model, accept)
        self.bundle = bundle or sample_bundle()
        self.sidecar = sample_sidecar(self.bundle)
        files = {'AGENTS.md': 'Fixture instructions\n', 'spec.md': 'Fixture specification\n',
                 'src/app.txt': 'v0\n', 'tests/check.sh': '#!/bin/sh\nexit 0\n',
                 '.github/workflows/ci.yml': 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/check.sh\n'}
        for name, text in files.items():
            path = self.work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        (self.work / 'tests/check.sh').chmod(0o755)
        if live_policy:
            write_json(self.work / POLICY, self.policy)
        self.commit_push('fixture: initial repository')
        self.inputs = Path(tempfile.mkdtemp(prefix='inputs-', dir=self.base))
        self.candidate_path = None
        if candidate:
            self.candidate_path = write_json(self.inputs / 'policy-candidate.json', self.policy)
        exit_code, self.published = self.publish()
        if exit_code:
            raise AssertionError(json.dumps(self.published))
        self.entry = self.published['published']
        self.generation = self.entry['generation']
        self.commit_push('fixture: publish v2 generation')
        self.publication_commit = git(self.work, 'rev-parse', 'HEAD')

    def publish(self, bundle=None, sidecar=None):
        bundle_path = write_json(self.inputs / 'bundle.json', bundle or self.bundle)
        sidecar_path = write_json(self.inputs / 'sidecar.json', sidecar or self.sidecar)
        argv = ['publish-v2', '--root', str(self.work), '--bundle', str(bundle_path), '--sidecar', str(sidecar_path)]
        if self.candidate_path:
            argv += ['--policy-candidate', str(self.candidate_path)]
        return observer.run(argv, now=NOW)

    def commit_push(self, message, branch='main'):
        git(self.work, 'add', '-A')
        git(self.work, 'commit', '-q', '--allow-empty', '-m', message)
        git(self.work, 'push', '-q', 'origin', 'HEAD:refs/heads/' + branch)
        git(self.work, 'fetch', '-q', 'origin')
        return git(self.work, 'rev-parse', 'HEAD')

    def expected(self):
        return {'plan_id': 'plan-a', 'generation': self.generation, 'goals': [g['id'] for g in self.bundle['goals']],
                'bundle_sha256': v2.bundle_sha256(self.bundle), 'spec_sha256': sha(self.work / 'spec.md'),
                'policy_sha256': sha(self.candidate_path or (self.work / POLICY)), 'anchor_sha256': self.anchor_sha256}

    def record(self, form='ssh-tag', issued=None, days=7, **overrides):
        issued = issued or NOW - timedelta(hours=1)
        expected = self.expected()
        record = v2.approval_record(
            plan_id=expected['plan_id'], generation=expected['generation'], bundle_sha256=expected['bundle_sha256'],
            spec_sha256=expected['spec_sha256'], policy_sha256=expected['policy_sha256'],
            sidecar_sha256=v2.canonical(self.sidecar), goals=expected['goals'], owner='Fixture Owner',
            reviewer_lane='independent review lane', issued_at=stamp(issued),
            expires_at=stamp(issued + timedelta(days=days)), anchor_sha256=expected['anchor_sha256'],
            assurance='in-session' if form == 'in-session' else 'key-held')
        record.update(overrides)
        return record

    def approve(self, form='ssh-tag', key='approver', record=None, message=None, push=True):
        """Create the approval tag as the human would (never through the driver)."""
        record = record or self.record(form)
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        if message is None:
            if form == 'ssh-tag':
                signature = ssh_sign(self.keys.paths[key], v2.NS_APPROVAL, line.encode(), self.base)
                import base64
                message = line + '\nsignature: ' + base64.b64encode(signature.encode()).decode() + '\n'
            else:
                message = line + '\ndigest-echo: ' + sha(line.encode()) + '\n'
        path = self.inputs / 'approval.msg'
        path.write_text(message)
        tag = 'approval/plan-a/' + self.generation[:12]
        git(self.work, 'tag', '-f', '-a', '--cleanup=verbatim', '-F', str(path), tag, self.publication_commit)
        if push:
            git(self.work, 'push', '-q', '-f', 'origin', 'refs/tags/' + tag)
        return record

    def state_dir(self):
        return Path(git(self.work, 'rev-parse', '--path-format=absolute', '--git-common-dir')) / 'ai-catapult/observer'

    def hooks(self, anchor=None, key='certifier'):
        """In-process locator hooks; the only way tests redirect the anchor and the signing key."""
        anchor = self.keys.anchor if anchor is None else anchor
        return [mock.patch.object(observer, 'anchor_locator', lambda: Path(anchor)),
                mock.patch.object(observer, 'signing_key_locator', lambda: self.keys.paths[key])]

    def run(self, argv, now=NOW, adapter=None, anchor=None, key='certifier', env=None):
        patches = self.hooks(anchor=anchor, key=key)
        if env is not None:
            patches.append(mock.patch.dict(os.environ, env))
        for patch in patches:
            patch.start()
        try:
            return observer.run(argv, now=now, adapter=adapter)
        finally:
            for patch in reversed(patches):
                patch.stop()

    def admit(self, stage='implementation', goal='G1', extra=(), **kwargs):
        return self.run(['admit-v2', '--root', str(self.work), '--handoff', 'northstar-plan-plan-a',
                         '--goal-id', goal, '--stage', stage, *extra], **kwargs)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.policy = sample_policy('a' * 64)

    def refused(self, policy, expected):
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_policy(policy)
        self.assertEqual(v2.code(raised.exception), expected, str(raised.exception))

    def test_valid_policy_and_fail_closed_placeholders(self):
        self.assertEqual(v2.validate_policy(copy.deepcopy(self.policy)), self.policy)
        placeholder = copy.deepcopy(self.policy)
        placeholder['approval']['anchor_sha256'] = None
        placeholder['required_checks'] = []
        v2.validate_policy(placeholder)  # structurally valid, refused at admission with named gaps
        self.assertEqual(v2.policy_gaps(placeholder), ['anchor_unset', 'required_checks_unset'])

    def test_named_policy_refusals(self):
        def mutate(change):
            policy = copy.deepcopy(self.policy)
            change(policy)
            return policy
        cases = [
            (lambda p: p.update(schema='readiness-policy/1'), 'policy_schema_unsupported'),
            (lambda p: p.update(worktree={'root': '/x'}), 'policy_unknown_field'),
            (lambda p: p.update(extensions={'active_plan': 'plan-a'}), 'policy_active_plan_refused'),
            (lambda p: p.update(identity_model='shared'), 'policy_identity_model_invalid'),
            (lambda p: p.update(reviewer_requirements={'independent_lane': False}), 'policy_reviewer_lane_required'),
            (lambda p: p['approval'].update(max_age_days=30), 'policy_approval_invalid'),
            (lambda p: p['approval'].update(accept=['email']), 'policy_approval_invalid'),
            (lambda p: p['approval'].update(accept=[]), 'policy_approval_invalid'),
            (lambda p: p.update(sources=[{'path': 'AGENTS.md', 'sha256': 'a' * 64}]), 'policy_field_invalid'),
            (lambda p: p.update(branch_pattern='^main$'), 'policy_field_invalid'),
            (lambda p: p['gates'][0].update(scope={'goals': ['G1']}), 'policy_gate_goal_scoped'),
            (lambda p: p['gates'][0].update(kind='independent_result'), 'policy_gate_unknown_kind'),
            (lambda p: p['gates'][0].update(path='x'), 'policy_gate_unknown_field'),
            (lambda p: p['gates'][5].update(not_applicable={'reason': 'no-fixture-dependency'}), 'policy_not_applicable_refused'),
            (lambda p: p['gates'][9].update(not_applicable={'reason': 'not needed'}), 'policy_not_applicable_reason'),
            (lambda p: p['gates'][9].update(not_applicable={'reason': 'no-pinned-harness'}), 'policy_not_applicable_reason'),
            (lambda p: p['gates'].append(copy.deepcopy(p['gates'][0])), 'policy_gate_duplicate_id'),
        ]
        for change, expected in cases:
            with self.subTest(expected=expected):
                self.refused(mutate(change), expected)
        self.assertEqual(set(v2.GATE_KINDS), {'ownership', 'review', 'branch_target', 'tooling', 'file_digest',
                                                'git_ancestor', 'hosted_checks', 'plan_approval', 'fixture', 'harness_trust'})

    def test_bundle_cannot_supply_gates_or_mutable_fields(self):
        cases = [
            (lambda b: b['goals'][0].update(requirements=[{'id': 'x', 'kind': 'tooling'}]), 'bundle_gate_refused'),
            (lambda b: b.update(gates=[]), 'bundle_gate_refused'),
            (lambda b: b.update(policy={}), 'bundle_gate_refused'),
            (lambda b: b['goals'][0].update(readiness={'merge': 'ready'}), 'bundle_mutable_field'),
            (lambda b: b['goals'][0].update(owner='someone'), 'bundle_mutable_field'),
            (lambda b: b['goals'][0].update(coverage_status='unknown'), 'bundle_mutable_field'),
            (lambda b: b['goals'][0].update(dependencies=['G9']), 'bundle_dependency_unknown'),
            (lambda b: b['goals'][0].update(scope=['../outside']), 'bundle_scope_unsafe'),
            (lambda b: b.update(schema='handoff-goals/1'), 'bundle_schema_unsupported'),
        ]
        for change, expected in cases:
            with self.subTest(expected=expected):
                bundle = sample_bundle()
                change(bundle)
                with self.assertRaises(v2.Invalid) as raised:
                    v2.validate_bundle(bundle)
                self.assertEqual(v2.code(raised.exception), expected, str(raised.exception))


class RevisionAndSidecarTests(unittest.TestCase):
    def test_goal_revision_v2_hashes_content_only(self):
        bundle = sample_bundle()
        base = v2.goal_revision_v2(bundle, 'G1')
        reordered = json.loads(json.dumps(bundle, sort_keys=True))
        self.assertEqual(v2.goal_revision_v2(reordered, 'G1'), base)
        for change in (lambda b: b['goals'][0]['scope'].append('src/other.txt'),
                       lambda b: b['goals'][0]['acceptance_criteria'].append('more'),
                       lambda b: b['goals'][0]['verification'].append('git diff --check'),
                       lambda b: b['repository'].update(id='other')):
            changed = copy.deepcopy(bundle)
            change(changed)
            self.assertNotEqual(v2.goal_revision_v2(changed, 'G1'), base)
        two = sample_bundle([dict(bundle['goals'][0]), {'id': 'G2', 'scope': ['b'], 'acceptance_criteria': ['b'],
                                                         'dependencies': ['G1'], 'verification': ['bash tests/check.sh']}])
        edited = copy.deepcopy(two)
        edited['goals'][0]['acceptance_criteria'].append('dependency content changed')
        # Dependencies are hashed by id: a dependency's content edit leaves the dependent's revision alone.
        self.assertEqual(v2.goal_revision_v2(two, 'G2'), v2.goal_revision_v2(edited, 'G2'))

    def test_generation_binds_content_spec_policy_and_anchor(self):
        args = dict(bundle_sha256='1' * 64, spec_sha256='2' * 64, policy_sha256='3' * 64, anchor_sha256='4' * 64)
        base = v2.generation_v2(**args)
        for name in args:
            self.assertNotEqual(v2.generation_v2(**dict(args, **{name: '5' * 64})), base, name)

    def test_sidecar_total_order_per_field_and_product(self):
        bundle = sample_bundle()
        v0 = sample_sidecar(bundle)
        v2.validate_sidecar(v0, bundle)

        def edited(change):
            sidecar = copy.deepcopy(v0)
            change(sidecar['goals']['G1'])
            return sidecar
        tighter = [lambda g: g['readiness'].update(merge='blocked'),
                   lambda g: g.update(legacy_risk_reason=g['legacy_risk_reason'] + '; seam extended'),
                   lambda g: g.update(coverage_status='measured', coverage_percent=41.5)]
        for change in tighter:
            v2.sidecar_leq(v0, edited(change))
        looser = [(v0, edited(lambda g: g.update(legacy_safe_tdd=False))),
                  (edited(tighter[0]), v0),
                  (edited(tighter[1]), v0),
                  (edited(tighter[2]), edited(lambda g: g.update(coverage_status='measured', coverage_percent=50))),
                  (edited(tighter[2]), v0),
                  (v0, edited(lambda g: (g['readiness'].update(merge='blocked'), g.update(legacy_safe_tdd=False))))]
        for before, after in looser:
            with self.assertRaises(v2.Invalid) as raised:
                v2.sidecar_leq(before, after)
            self.assertEqual(v2.code(raised.exception), 'sidecar_loosened')
        for change, expected in ((lambda g: g.update(owner='x'), 'sidecar_unknown_field'),
                                 (lambda g: g['readiness'].update(merge='ready'), 'sidecar_hold_invalid'),
                                 (lambda g: g.update(coverage_status='measured'), 'sidecar_coverage_invalid')):
            with self.assertRaises(v2.Invalid) as raised:
                v2.validate_sidecar(edited(change), bundle)
            self.assertEqual(v2.code(raised.exception), expected)

    def test_ac4_both_directions(self):
        policy = sample_policy('4' * 64)
        bundle, sidecar = sample_bundle(), None
        sidecar = sample_sidecar(bundle)
        policy_sha256, spec_sha256 = '3' * 64, '2' * 64

        def expected_for(content):
            digests = dict(bundle_sha256=v2.bundle_sha256(content), spec_sha256=spec_sha256,
                           policy_sha256=policy_sha256, anchor_sha256='4' * 64)
            return dict(digests, plan_id='plan-a', goals=['G1'], generation=v2.generation_v2(**digests))

        def approval_for(content, bound_sidecar):
            expected = expected_for(content)
            return v2.approval_record(plan_id='plan-a', generation=expected['generation'],
                                      bundle_sha256=expected['bundle_sha256'], spec_sha256=spec_sha256,
                                      policy_sha256=policy_sha256, sidecar_sha256=v2.canonical(bound_sidecar),
                                      goals=['G1'], owner='Owner', reviewer_lane='lane',
                                      issued_at=stamp(NOW - timedelta(days=1)), expires_at=stamp(NOW + timedelta(days=6)),
                                      anchor_sha256='4' * 64, assurance='in-session')

        def decide(approval, content, current, v0):
            line = json.dumps(approval, sort_keys=True, separators=(',', ':')).encode()
            carrier = {'tag': 'approval/plan-a/x', 'annotated': True, 'on_origin': True, 'target_contains_generation': True,
                       'form': 'in-session', 'record': approval, 'record_canonical': True, 'digest_echo': sha(line),
                       'signature': None, 'anchor': {'present': True, 'inside_worktree': False, 'sha256': '4' * 64}}
            return v2.decide_approval(carrier, policy, expected_for(content), NOW, current, v0)

        approval = approval_for(bundle, sidecar)
        generation = expected_for(bundle)['generation']
        # (a) tightening sidecar edits keep generation_v2 and the approval valid.
        tightened = copy.deepcopy(sidecar)
        tightened['goals']['G1']['readiness']['implementation'] = 'blocked'
        tightened['goals']['G1']['coverage_status'] = 'measured'
        tightened['goals']['G1']['coverage_percent'] = 12
        tightened['goals']['G1']['legacy_risk_reason'] += '; observed seam'
        self.assertEqual(expected_for(bundle)['generation'], generation)
        self.assertEqual(decide(approval, bundle, tightened, sidecar)['assurance'], 'in-session')
        # (b) scope or acceptance edits change generation_v2 and invalidate the approval.
        for change in (lambda b: b['goals'][0]['scope'].append('src/new.txt'),
                       lambda b: b['goals'][0]['acceptance_criteria'].append('new criterion')):
            content = copy.deepcopy(bundle)
            change(content)
            self.assertNotEqual(expected_for(content)['generation'], generation)
            with self.assertRaises(v2.Invalid) as raised:
                decide(approval, content, sidecar, None)
            self.assertEqual(v2.code(raised.exception), 'approval_bundle_mismatch')
        # (c) loosening edits are refused until a new approval binds a new sidecar_v0.
        hold_removed = copy.deepcopy(tightened)
        hold_removed['goals']['G1']['readiness']['implementation'] = 'unknown'
        legacy_dropped = copy.deepcopy(sidecar)
        legacy_dropped['goals']['G1']['legacy_safe_tdd'] = False
        for v0, loosened in ((tightened, hold_removed), (sidecar, legacy_dropped)):
            with self.assertRaises(v2.Invalid) as raised:
                decide(approval_for(bundle, v0), bundle, loosened, v0)
            self.assertEqual(v2.code(raised.exception), 'sidecar_loosened')
            renewed = approval_for(bundle, loosened)
            self.assertEqual(decide(renewed, bundle, loosened, None)['assurance'], 'in-session')


class PurityAndBootstrapTests(unittest.TestCase):
    def test_validator_is_pure(self):
        def forbidden(*args, **kwargs):
            raise AssertionError('validator attempted a command or a write')
        real_open = builtins.open

        def read_only_open(file, mode='r', *args, **kwargs):
            if any(flag in mode for flag in 'wax+'):
                forbidden()
            return real_open(file, mode, *args, **kwargs)
        policy, bundle = sample_policy('4' * 64), sample_bundle()
        sidecar = sample_sidecar(bundle)
        inputs = admission_inputs(policy, bundle, sidecar)
        patches = [mock.patch('subprocess.run', forbidden), mock.patch('subprocess.Popen', forbidden),
                   mock.patch('subprocess.check_output', forbidden), mock.patch('os.system', forbidden),
                   mock.patch('os.replace', forbidden), mock.patch('os.rename', forbidden),
                   mock.patch('os.mkdir', forbidden), mock.patch('pathlib.Path.write_text', forbidden),
                   mock.patch('pathlib.Path.write_bytes', forbidden), mock.patch('builtins.open', read_only_open)]
        for patch in patches:
            patch.start()
        try:
            v2.validate_policy(policy)
            v2.validate_bundle(bundle)
            v2.validate_sidecar(sidecar, bundle)
            context = v2.admission(inputs)
            self.assertIn('admitted', context)
            self.assertTrue(context['admitted'], context['gaps'])
            blocked = copy.deepcopy(inputs)
            blocked['observation']['facts']['tool:git']['value'] = None
            self.assertFalse(v2.admission(blocked)['admitted'])
        finally:
            for patch in reversed(patches):
                patch.stop()

    def test_import_surface_is_read_only_v1_helpers(self):
        tree = ast.parse((AUTO / 'lib/readiness_contract_v2.py').read_text())
        imported = {}
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imported.setdefault(alias.name, set())
            elif isinstance(node, ast.ImportFrom):
                imported.setdefault(node.module, set()).update(alias.name for alias in node.names)
        self.assertLessEqual(set(imported), {'hashlib', 'json', 're', 'datetime', 'readiness_contract', 'pathlib'})
        self.assertLessEqual(imported.get('readiness_contract', set()), v2.V1_HELPERS)
        self.assertEqual(v2.V1_HELPERS, {'Invalid', 'canonical', 'require', 'string', 'ID', 'SHA', 'REVISION'})
        source = (AUTO / 'lib/observer.py').read_text()
        self.assertNotIn('policy.worktree', source)
        self.assertNotIn("['worktree']", (AUTO / 'lib/readiness_contract_v2.py').read_text())

    def test_policy_bootstrap_rules(self):
        policy_goal = {'id': 'P', 'scope': [POLICY, 'tests/policy_test.sh'], 'acceptance_criteria': ['policy lands'],
                       'dependencies': [], 'verification': ['bash tests/check.sh']}
        sibling = {'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['works'],
                   'dependencies': ['P'], 'verification': ['bash tests/check.sh']}
        grandchild = dict(sibling, id='G2', dependencies=['G1'])
        bundle = sample_bundle([policy_goal, sibling, grandchild])
        self.assertEqual(v2.validate_bootstrap(bundle, live_policy2=False), 'P')
        self.assertEqual(v2.validate_bootstrap(bundle, live_policy2=True, candidate_is_live=True), 'P')
        cases = [
            (bundle, dict(live_policy2=True), 'bootstrap_policy_live'),
            (sample_bundle([policy_goal, dict(sibling, scope=[POLICY])]), {}, 'bootstrap_multiple_policy_goals'),
            (sample_bundle([dict(sibling, dependencies=[])]), {}, 'bootstrap_policy_goal_missing'),
            (sample_bundle([policy_goal, dict(sibling, dependencies=[])]), {}, 'bootstrap_sibling_not_dependent'),
        ]
        for content, kwargs, expected in cases:
            with self.subTest(expected=expected):
                with self.assertRaises(v2.Invalid) as raised:
                    v2.validate_bootstrap(content, **dict({'live_policy2': False}, **kwargs))
                self.assertEqual(v2.code(raised.exception), expected)
        with self.assertRaises(v2.Invalid) as raised:
            v2.validate_live_scope(sample_bundle([policy_goal]))
        self.assertEqual(v2.code(raised.exception), 'policy_goal_requires_bootstrap')
        self.assertEqual(v2.bootstrap_certificate_gaps('P', 'P', head_policy_sha256='a' * 64, policy_sha256='b' * 64),
                         ['bootstrap_head_policy_mismatch'])
        self.assertEqual(v2.bootstrap_certificate_gaps('P', 'P', head_policy_sha256='b' * 64, policy_sha256='b' * 64), [])
        self.assertEqual(v2.bootstrap_certificate_gaps(None, 'G1', head_policy_sha256=None, policy_sha256='b' * 64), [])


class PublicationAndAdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def test_publish_v2_layout_registry_last_and_never_v1(self):
        fixture = Fixture(self.base)
        prefix = '.ai/handoff/readiness-v2/plan-a/' + fixture.generation
        names = sorted(p.name for p in (fixture.work / prefix).iterdir())
        self.assertEqual(names, ['goals.json', 'graph.json', 'handoff.md', 'sidecar.json'])
        self.assertFalse((fixture.work / '.ai/handoff/readiness-v1').exists())
        registry = json.loads((fixture.work / REGISTRY).read_text())
        self.assertEqual(registry['schema'], 'readiness-contract/2')
        entry = registry['plans'][0]
        self.assertEqual(entry['id'], 'northstar-plan-plan-a')
        for name in ('bundle', 'graph', 'handoff'):
            self.assertEqual(sha(fixture.work / entry['artifacts'][name]['path']), entry['artifacts'][name]['sha256'])
        self.assertEqual(entry['generation'], v2.generation_v2(**{k: fixture.expected()[k] for k in (
            'bundle_sha256', 'spec_sha256', 'policy_sha256', 'anchor_sha256')}))
        self.assertEqual(json.loads((fixture.work / prefix / 'goals.json').read_text()), fixture.bundle)
        # Publishing a hold, or into a generation directory whose bytes differ, is refused.
        held = copy.deepcopy(fixture.sidecar)
        held['goals']['G1']['readiness']['merge'] = 'blocked'
        exit_code, result = fixture.publish(sidecar=held)
        self.assertNotEqual(exit_code, 0)
        self.assertIn('publication_hold_refused', codes(result))

    def test_bootstrap_candidate_publication_and_live_refusal(self):
        policy_goal = {'id': 'P', 'scope': [POLICY], 'acceptance_criteria': ['policy lands'],
                       'dependencies': [], 'verification': ['bash tests/check.sh']}
        sibling = {'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['works'],
                   'dependencies': ['P'], 'verification': ['bash tests/check.sh']}
        fixture = Fixture(self.base, bundle=sample_bundle([policy_goal, sibling]), candidate=True, live_policy=False)
        prefix = fixture.work / '.ai/handoff/readiness-v2/plan-a' / fixture.generation
        self.assertEqual(sha(prefix / 'policy-candidate.json'), sha(fixture.candidate_path))
        self.assertEqual(fixture.entry['mode'], 'bootstrap')
        # Once a live policy/2 exists, a new candidate is refused before anything is written.
        write_json(fixture.work / POLICY, fixture.policy)
        before = sorted(str(p) for p in fixture.work.rglob('*') if '.git' not in p.parts)
        changed = copy.deepcopy(fixture.bundle)
        changed['goals'][1]['acceptance_criteria'].append('another')
        exit_code, result = fixture.publish(bundle=changed)
        self.assertNotEqual(exit_code, 0)
        self.assertIn('bootstrap_policy_live', codes(result))
        self.assertEqual(before, sorted(str(p) for p in fixture.work.rglob('*') if '.git' not in p.parts))

    def test_admission_rebuilds_context_and_refuses_supplied_differences(self):
        fixture = Fixture(self.base)
        fixture.approve('in-session')
        exit_code, context = fixture.admit()
        self.assertEqual(exit_code, 0, json.dumps(context, indent=1))
        self.assertTrue(context['admitted'])
        self.assertEqual(context['schema'], 'readiness-context/2')
        self.assertEqual(context['assurance'], 'in-session')
        observation = context['observation']
        for fact in observation['facts'].values():
            self.assertTrue({'value', 'source', 'observed_at', 'commit'} <= set(fact), fact)
        self.assertEqual(observation['adapter'], 'production-gh')
        supplied = write_json(self.base / 'supplied-context.json', context)
        self.assertEqual(fixture.admit(extra=('--context', str(supplied)))[0], 0)
        tampered = copy.deepcopy(context)
        tampered['gaps'] = []
        tampered['goals'] = ['G1', 'G2']
        write_json(supplied, tampered)
        exit_code, result = fixture.admit(extra=('--context', str(supplied)))
        self.assertNotEqual(exit_code, 0)
        self.assertIn('supplied_context_mismatch', codes(result))
        forged = copy.deepcopy(observation)
        forged['facts']['tool:git']['value'] = '/forged/git'
        path = write_json(self.base / 'supplied-observation.json', forged)
        self.assertIn('supplied_observation_mismatch', codes(fixture.admit(extra=('--observation', str(path)))[1]))
        verdict = write_json(self.base / 'verdict.json', {'admitted': True, 'gaps': ['forged']})
        self.assertIn('supplied_verdict_mismatch', codes(fixture.admit(extra=('--verdict', str(verdict)))[1]))

    def test_admission_without_approval_carries_no_authority(self):
        fixture = Fixture(self.base)
        exit_code, context = fixture.admit()
        self.assertNotEqual(exit_code, 0)
        self.assertFalse(context['admitted'])
        self.assertIn('approval_tag_missing', codes(context))
        self.assertEqual(context['authority'], 'none: no verified plan approval; this report carries no authority')


class EntryPointTests(unittest.TestCase):
    def setUp(self):
        # In-process usage refusals are logged against the cwd repository: keep them out of this checkout.
        self.cwd = tempfile.TemporaryDirectory()
        self.addCleanup(self.cwd.cleanup)
        self.addCleanup(os.chdir, os.getcwd())
        os.chdir(self.cwd.name)

    def test_route_prelude_dispatches_only_v2_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            run = lambda *args: subprocess.run(['bash', str(AUTO / 'contract-run.sh'), *args],
                                               capture_output=True, text=True, cwd=tmp)
            v1 = run('admit', '--root', tmp)
            self.assertEqual(json.loads(v1.stdout)['schema'], 'readiness-contract/1')
            self.assertIn('invalid choice', run('not-an-operation').stderr)
            for operation in ('admit-v2', 'publish-v2', 'approval-request', 'certify-v2', 'merge-v2', 'audit-merges',
                              'context-build'):
                result = run(operation, '--definitely-unknown')
                self.assertEqual(result.returncode, 2, operation + result.stdout + result.stderr)
                self.assertIn('readiness-contract/2', result.stderr)
        prelude = (AUTO / 'contract-run.sh').read_text().split('exec python3 -B - "$HERE" "$@"')[0]
        self.assertIn('contract-run-v2.sh', prelude)
        for name in ('admit)', 'publish)', 'migrate)', 'admit|', 'publish|', 'migrate|'):
            self.assertNotIn(name, prelude)

    def test_help_is_a_usage_refusal_never_exit_0(self):
        for argv in (['-h'], ['--help'], ['merge-v2', '-h'], ['merge-v2', '--help'], ['admit-v2', '--help']):
            self.assertEqual(observer.run(argv)[0], 2, argv)
        with tempfile.TemporaryDirectory() as tmp:
            for args in (['-h'], ['--help'], ['--pr', '1', '--help']):
                result = subprocess.run(['bash', str(AUTO / 'merge-authority.sh'), *args], cwd=tmp, capture_output=True,
                                        text=True, stdin=subprocess.DEVNULL)
                self.assertEqual(result.returncode, 2, args)

    def test_unknown_arguments_and_proceed_text_exit_2(self):
        for operation in ('admit-v2', 'publish-v2', 'approval-request', 'certify-v2', 'merge-v2', 'audit-merges',
                          'context-build'):
            for extra in (['proceed'], ['override'], ['--force'], ['--admin', 'if', 'necessary'], ['--anchor', '/x'],
                          ['-h'], ['--help']):
                with self.subTest(operation=operation, extra=extra):
                    exit_code, result = observer.run([operation, *extra])
                    self.assertEqual(exit_code, 2, result)

    def test_dependency_manifest_v2_pins_every_executable(self):
        autobahn = json.loads((AUTO / 'readiness-dependency-v2.json').read_text())
        northstar = json.loads((NORTH / 'readiness-dependency-v2.json').read_text())
        self.assertEqual(autobahn, northstar)
        self.assertEqual((AUTO / 'readiness-dependency-v2.json').read_bytes(), (NORTH / 'readiness-dependency-v2.json').read_bytes())
        self.assertEqual(autobahn['schema'], 'readiness-contract/2')
        self.assertEqual(set(autobahn['files']), {
            'lib/readiness_contract_v2.py', 'lib/observer.py', 'lib/readiness_contract.py', 'lib/verification.py',
            'schemas/readiness-contract-v2.json', 'contract-run.sh', 'contract-run-v2.sh', 'run-gates.sh',
            'merge-authority.sh', 'prereq-check.sh', 'migrate-handoff.sh', 'northstar/handoff-write.sh',
            # ACH-S-03: the five local gate scripts and the local CI contract module they run.
            'tdd-evidence.sh', 'tdd-mode.sh', 'lint-gate.sh', 'ci-gate.sh', 'local-ci.sh', 'lib/local_ci_contract.py',
            # ACH-S-04: the mode-aware northstar approve entry point.
            'northstar/approve.sh'})
        for name, expected in autobahn['files'].items():
            path = NORTH / name[len('northstar/'):] if name.startswith('northstar/') else AUTO / name
            self.assertEqual(sha(path), expected, name)
        with tempfile.TemporaryDirectory() as tmp:
            flat = Path(tmp)
            shutil.copytree(AUTO, flat / 'autobahn', ignore=shutil.ignore_patterns('__pycache__'))
            shutil.copytree(NORTH, flat / 'northstar', ignore=shutil.ignore_patterns('__pycache__'))
            run = lambda: subprocess.run(['bash', str(flat / 'autobahn/contract-run.sh'), 'admit-v2', '--root', tmp,
                                          '--handoff', 'x', '--goal-id', 'G1'], capture_output=True, text=True, cwd=tmp)
            self.assertNotIn('dependency_failed', run().stdout)
            with (flat / 'autobahn/lib/observer.py').open('a') as handle:
                handle.write('\n# drift\n')
            result = run()
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('dependency_failed', result.stdout)
            shutil.copy(AUTO / 'lib/observer.py', flat / 'autobahn/lib/observer.py')
            (flat / 'northstar/readiness-dependency-v2.json').write_text('{}')
            self.assertIn('fingerprint mismatch', run().stdout)


class ObserverFactTests(unittest.TestCase):
    def test_hosted_facts_dedupe_checks_and_treat_protection_as_unavailable(self):
        policy = sample_policy('4' * 64)
        success = {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success', 'completed_at': '2026-10-03T11:00:00Z'}
        self.assertEqual(v2.decide_checks(policy, [success, dict(success)]), [])
        self.assertEqual(v2.decide_checks(policy, [success, dict(success, conclusion='failure')]), ['check_failed:Test Suite'])
        self.assertEqual(v2.decide_checks(policy, [success, dict(success, status='in_progress', conclusion=None)]),
                         ['check_pending:Test Suite'])
        self.assertEqual(v2.decide_checks(policy, []), ['check_missing:Test Suite'])
        self.assertEqual(v2.decide_checks(policy, [success, dict(success, name='Optional Smoke', conclusion='skipped')]), [])
        self.assertEqual(v2.decide_checks(policy, [success, dict(success, name='Lint', conclusion='skipped')]),
                         ['check_skipped_unlisted:Lint'])
        self.assertEqual(v2.decide_checks(policy, [dict(success, conclusion='skipped')]), ['check_skipped_unlisted:Test Suite'])
        self.assertEqual(v2.protection_gaps({'status': 'unavailable'}, [success]), [])
        self.assertEqual(v2.protection_gaps({'status': 'available', 'contexts': ['Test Suite', 'Hosted Lint']}, [success]),
                         ['protection_check_unsatisfied:Hosted Lint'])

    def test_certificate_itself_refuses_unsatisfied_required_checks_and_missing_lane(self):
        ok = {'name': 'Test Suite', 'status': 'completed', 'conclusion': 'success', 'completed_at': '2026-10-03T11:00:00Z'}
        base = {'clean_before': True, 'clean_after': True, 'head_before': 'a' * 40, 'head_after': 'a' * 40,
                'pr_head': 'a' * 40, 'local_gates': [{'name': 'tdd-evidence', 'exit': 0}], 'now': NOW, 'runs': [ok],
                'required_checks': ['Test Suite'], 'skippable_checks': ['Optional Smoke'], 'unresolved_threads': 0,
                'review_lane': {'principal': 'reviewer@agent'}, 'certifier': 'certifier@agent', 'policy_goal': None,
                'goal_id': 'G1', 'head_policy_sha256': None, 'policy_sha256': 'b' * 64}
        self.assertEqual(v2.certificate_refusals(base), [])
        cases = [({'runs': [dict(ok, conclusion='failure')]}, 'check_not_success:Test Suite'),
                 ({'runs': [dict(ok, conclusion='skipped')]}, 'check_not_success:Test Suite'),
                 ({'runs': [dict(ok, name='Other')]}, 'check_missing:Test Suite'),
                 ({'runs': [ok, dict(ok, status='in_progress', conclusion=None)]}, 'check_not_success:Test Suite'),
                 ({'review_lane': None}, 'review_lane_missing')]
        for change, expected in cases:
            self.assertIn(expected, v2.certificate_refusals(dict(base, **change)), expected)
        skippable = dict(base, required_checks=['Test Suite', 'Optional Smoke'],
                         runs=[ok, dict(ok, name='Optional Smoke', conclusion='skipped')])
        self.assertEqual(v2.certificate_refusals(skippable), [])
        for kind in ('hosted_checks', 'review'):
            policy = sample_policy('4' * 64)
            policy['gates'] = [g for g in policy['gates'] if g['kind'] != kind]
            with self.assertRaises(v2.Invalid) as raised:
                v2.validate_policy(policy)
            self.assertEqual(v2.code(raised.exception), 'policy_merge_gate_required', kind)

    def test_production_adapter_and_transitive_dependency_completion(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            goals = [{'id': 'G1', 'scope': ['src/app.txt'], 'acceptance_criteria': ['one'], 'dependencies': [],
                      'verification': ['bash tests/check.sh']},
                     {'id': 'G2', 'scope': ['src/two.txt'], 'acceptance_criteria': ['two'], 'dependencies': ['G1'],
                      'verification': ['bash tests/check.sh']},
                     {'id': 'G3', 'scope': ['src/three.txt'], 'acceptance_criteria': ['three'], 'dependencies': ['G2'],
                      'verification': ['bash tests/check.sh']}]
            fixture = Fixture(base, bundle=sample_bundle(goals))
            fixture.approve('in-session')
            state, log = base / 'gh-state.json', base / 'gh-log.jsonl'
            write_json(state, {'merged_prs': []})
            shim = gh_shim(base / 'bin', state, log)
            env = {'PATH': str(shim.parent) + os.pathsep + os.environ['PATH']}
            exit_code, context = fixture.admit(goal='G3', env=env, adapter=observer.GhAdapter(fixture.work))
            self.assertIn('dependency_incomplete', codes(context))
            self.assertEqual(context['observation']['adapter'], 'production-gh')
            # Squash merges: the PR merge commit, not the branch tip, must be reachable from origin/main.
            for goal in ('G1', 'G2'):
                (fixture.work / ('src/%s.txt' % goal)).write_text(goal)
                commit = fixture.commit_push('squash merge of ' + goal)
                state_value = json.loads(state.read_text())
                state_value['merged_prs'].append({'number': len(state_value['merged_prs']) + 1,
                                                  'headRefName': 'feat/plan-a-' + goal,
                                                  'mergeCommit': {'oid': commit}, 'mergedAt': '2026-10-03T10:00:00Z'})
                write_json(state, state_value)
            exit_code, context = fixture.admit(goal='G3', env=env, adapter=observer.GhAdapter(fixture.work))
            self.assertNotIn('dependency_incomplete', codes(context), context['gaps'])
            facts = context['observation']['facts']
            self.assertTrue(facts['dependency:G1']['value']['ancestor'])
            self.assertEqual(facts['dependency:G1']['source'], 'hosted:production-gh+git')
            unreachable = json.loads(state.read_text())
            unreachable['merged_prs'][0]['mergeCommit']['oid'] = 'f' * 40
            write_json(state, unreachable)
            self.assertIn('dependency_incomplete', codes(fixture.admit(goal='G3', env=env,
                                                                       adapter=observer.GhAdapter(fixture.work))[1]))


if __name__ == '__main__':
    unittest.main()
