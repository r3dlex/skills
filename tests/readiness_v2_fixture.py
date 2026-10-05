"""In-process end-to-end fixture for readiness-contract/2 (ACH-S-06, AC-3).

A disposable repository with a bare origin, per-goal linked worktrees and a HostStub that
stands in for the production `gh` CLI by patching `observer.hosted_command` in-process
(B-S06-3: offline, not environment-selected, and every observation still records
`adapter: production-gh` because the production code path ran). The whole chain runs
through the captured `observer.main` with counting human-interaction wrappers.

The AC-1 measure (B3 ruling): the counted hook calls are invocations of the fixture's
human-interaction wrappers (`builtins.input` / `getpass.getpass`); `/dev/tty` opens and
reads of the counting stdin wrapper over `/dev/null` count as TTY read attempts; exit-3
results count run codes, subprocess exits and driver-log `exit` values; human-only report
lines are stderr lines starting `ready-for-human`. Prompt mode sums to exactly 1 (the one
`ready-for-human` line from `approval-request --mode prompt`); agent mode sums to exactly
0. The harness acting as the user reads the returned digest in-process, never through a
hook. Assurance notices, `next` fields and JSON `human_action` fields are not counted.

Runs are prompt mode (a bootstrap generation approved in-session) or agent mode (a live
generation over a pre-seeded live policy listing `agent-self`, approved agent-self with a
non-bootstrap generation — bootstrap refuses agent-self by design).
"""
import atexit
import builtins
import getpass
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from datetime import timedelta
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import readiness_v2_core_test as core  # noqa: E402
from readiness_v2_core_test import (AUTO, NOW, POLICY, git, observer, sample_bundle, sample_policy,  # noqa: E402
                                    sample_sidecar, sha, ssh_sign, stamp, v2, write_json)

PLAN = 'plan-e2e'
HANDOFF = 'northstar-plan-plan-e2e'
LANE = 'independent review lane'
POLICY_PATH = '.ai/policies/readiness-policy.json'


class Clock:
    """A monotonic fixture clock: one minute per step, shared by the stub's mergedAt,
    the check completed_at values and every `now=` handed to observer.run."""

    def __init__(self):
        self.now = NOW

    def tick(self, minutes=1):
        self.now = self.now + timedelta(minutes=minutes)
        return self.now

    def stamp(self):
        return stamp(self.now)


class FixtureKeys:
    """Throwaway role keys and a trust anchor outside every worktree: an approver, a
    certifier holding review+certificate+agent-approval (the skills `agent@autobahn`
    shape), a reviewer distinct from the certifier, and an outsider key that is not in
    the anchor."""

    def __init__(self, base):
        self.dir = Path(tempfile.mkdtemp(prefix='e2e-keys-', dir=base))
        self.paths = {}
        for name in ('approver', 'certifier', 'reviewer', 'outsider'):
            path = self.dir / name
            subprocess.run(['ssh-keygen', '-q', '-t', 'ed25519', '-N', '', '-C', name, '-f', str(path)],
                           check=True, capture_output=True)
            self.paths[name] = path
        self.anchor = self.dir / 'anchor' / 'allowed_signers'
        self.anchor.parent.mkdir()

    def public(self, name):
        return ' '.join(self.paths[name].with_suffix('.pub').read_text().split()[:2])

    def write_anchor(self):
        agent = ','.join((v2.NS_REVIEW, v2.NS_CERTIFICATE, v2.NS_AGENT_APPROVAL))
        lines = ['approver@human namespaces="%s" %s' % (v2.NS_APPROVAL, self.public('approver')),
                 'certifier@agent namespaces="%s" %s' % (agent, self.public('certifier')),
                 'reviewer@agent namespaces="%s" %s' % (v2.NS_REVIEW, self.public('reviewer'))]
        self.anchor.write_text('\n'.join(lines) + '\n')
        return sha(self.anchor)


class Run:
    """The CompletedProcess-shaped result HostStub returns to GhAdapter."""

    def __init__(self, code, out='', err=''):
        self.returncode = code
        self.stdout = out.encode() if isinstance(out, str) else out
        self.stderr = err.encode() if isinstance(err, str) else err


class HostStub:
    """In-process stand-in for the production `gh` CLI, installed by patching
    `observer.hosted_command`. It implements exactly what GhAdapter calls and squash-
    merges with `git commit-tree` into the bare origin, so the first-parent walk the
    audit re-derives is a real git history."""

    def __init__(self, repo):
        self.repo = repo
        self.pulls = {}
        self.next_number = 1
        self.calls = []
        self.knobs = {'pending_checks': [], 'files_override': {}, 'head_sequence': {}, 'unfetchable': []}

    def clock(self):
        return self.repo.clock

    def stamp_now(self):
        return self.clock().stamp()

    def register(self, *, head, head_ref, base, base_ref, files=None, checks=None, threads=None, state='open'):
        number = self.next_number
        self.next_number += 1
        completed = self.stamp_now()
        self.pulls[number] = {
            'number': number, 'state': state, 'merged': False,
            'head': {'sha': head, 'ref': head_ref}, 'base': {'sha': base, 'ref': base_ref},
            'merge_commit_sha': None, 'mergeCommit': None, 'createdAt': completed,
            'closedAt': None, 'mergedAt': None, 'changed_files': 0, 'files': files or [],
            'checks': checks or [{'name': name, 'status': 'completed', 'conclusion': 'success',
                                  'completed_at': self.stamp_now()}
                                 for name in self.repo.required_checks()],
            'threads': threads if threads is not None else [{'isResolved': True}]}
        self.pulls[number]['changed_files'] = len(self.pulls[number]['files'])
        return number

    def diff_files(self, base, head):
        """The real name-only diff of base..head in the primary clone."""
        listed = git(self.repo.work, 'diff', '--name-only', '-z', base, head)
        return [{'filename': name, 'status': 'modified'} for name in listed.split('\0') if name]

    def dispatch(self, argv, cwd=None, data=None, env=None):
        """The one seam GhAdapter calls: every gh invocation lands here, in-process."""
        self.calls.append([str(a) for a in argv])
        if argv[:2] == ['gh', 'api']:
            return self.api(argv[2], argv[3:])
        if argv[:2] == ['gh', 'pr'] and argv[2] == 'list':
            return self.pr_list(argv[3:])
        if argv[:2] == ['gh', 'pr'] and argv[2] == 'merge':
            return self.pr_merge(argv[3:])
        return Run(1, err='unsupported gh call: ' + ' '.join(str(a) for a in argv))

    def api(self, path, extra):
        match = re.fullmatch(r'repos/\{owner\}/\{repo\}/pulls/(\d+)', path)
        if match:
            return Run(0, out=json.dumps(self.pull(int(match.group(1)))))
        match = re.fullmatch(r'repos/\{owner\}/\{repo\}/pulls/(\d+)/files\?per_page=100&page=\d+', path)
        if match:
            number = int(match.group(1))
            files = self.knobs['files_override'].get(number, self.pulls[number]['files'])
            return Run(0, out=json.dumps(files))
        match = re.fullmatch(r'repos/\{owner\}/\{repo\}/commits/([0-9a-f]{40})/check-runs\?per_page=100', path)
        if match:
            sha = match.group(1)
            runs = self.pull_checks(sha)
            return Run(0, out=json.dumps({'total_count': len(runs), 'check_runs': runs}))
        if re.fullmatch(r'repos/\{owner\}/\{repo\}/branches/([^/]+)/protection/required_status_checks', path):
            return Run(1, err='gh: Not Found (HTTP 404)')  # protection unavailable, like the shim
        if path == 'graphql':
            number = next(a.split('=', 1)[1] for a in extra if a.startswith('number='))
            nodes = self.pulls[int(number)]['threads']
            return Run(0, out=json.dumps({'data': {'repository': {'pullRequest': {
                'reviewThreads': {'nodes': nodes, 'pageInfo': {'hasNextPage': False}}}}}}))
        return Run(1, err='gh: unsupported api path ' + path)

    def pull(self, number):
        pull = self.pulls[number]
        sequence = self.knobs['head_sequence'].get(number)
        if sequence:
            pull['head']['sha'] = sequence.pop(0)
        return {'number': number, 'state': pull['state'], 'merged': pull['merged'],
                'merge_commit_sha': pull['merge_commit_sha'], 'head': pull['head'], 'base': pull['base'],
                'changed_files': pull['changed_files']}

    def pull_checks(self, sha):
        checks = []
        for pull in self.pulls.values():
            if pull['head']['sha'] == sha:
                checks = pull['checks']
        for name in list(self.knobs['pending_checks']):
            checks = [dict(run, status='in_progress', conclusion=None) if run.get('name') == name else run
                      for run in checks]
        return checks

    def pr_list(self, args):
        state = next((args[i + 1] for i, a in enumerate(args) if a == '--state'), None)
        head = next((args[i + 1] for i, a in enumerate(args) if a == '--head'), None)
        base = next((args[i + 1] for i, a in enumerate(args) if a == '--base'), None)
        wanted = {'merged': 'MERGED', 'open': 'OPEN', 'all': None}.get(state, None)
        rows = []
        for pull in sorted(self.pulls.values(), key=lambda p: p['number']):
            if wanted is not None and pull['state'] != wanted:
                continue
            if head is not None and pull['head']['ref'] != head:
                continue
            if base is not None and pull['base']['ref'] != base:
                continue
            rows.append({'number': pull['number'], 'headRefName': pull['head']['ref'],
                         'headRefOid': pull['head']['sha'], 'mergeCommit': pull['mergeCommit'],
                         'baseRefName': pull['base']['ref'], 'createdAt': pull['createdAt'],
                         'closedAt': pull['closedAt'], 'mergedAt': pull['mergedAt'], 'state': pull['state']})
        return Run(0, out=json.dumps(rows))

    def pr_merge(self, args):
        number = int(args[0])
        head = args[args.index('--match-head-commit') + 1]
        pull = self.pulls[number]
        if head != pull['head']['sha']:
            return Run(1, err='Head branch was modified. Review and try the merge again.')
        if number in self.knobs['unfetchable']:
            git(self.repo.origin, 'fetch', '-q', str(self.repo.base / 'fork.git'), head)
        main = git(self.repo.origin, 'rev-parse', 'refs/heads/main')
        ancestry = subprocess.run(['git', '-C', str(self.repo.origin), 'merge-base', '--is-ancestor', main, head],
                                  capture_output=True)
        if ancestry.returncode:
            return Run(1, err='Pull request is not mergeable: the base branch is out of date.')
        tree = git(self.repo.origin, 'rev-parse', head + '^{tree}')
        merged = git(self.repo.origin, 'commit-tree', tree, '-p', main, '-m', 'Merge %s (#%d)' % (head, number))
        git(self.repo.origin, 'update-ref', 'refs/heads/main', merged)
        pull.update(state='MERGED', merged=True, merge_commit_sha=merged,
                    mergeCommit={'oid': merged}, mergedAt=self.stamp_now(), closedAt=self.stamp_now())
        return Run(0)

    def snapshot(self):
        """The recorded host state, so a copied repository can rebuild its own stub."""
        return {'next_number': self.next_number, 'pulls': self.pulls, 'knobs': self.knobs}

    def restore(self, data, repo):
        import copy as _copy
        self.repo = repo
        self.next_number = data['next_number']
        self.pulls = _copy.deepcopy(data['pulls'])
        self.knobs = _copy.deepcopy(data['knobs'])


class Counters:
    """The AC-1 measure, one counter set per run."""

    def __init__(self):
        self.hook_calls = 0
        self.tty_reads = 0
        self.exit3 = 0
        self.human_lines = 0

    def total(self):
        return self.hook_calls + self.tty_reads + self.exit3 + self.human_lines

    def components(self):
        return {'hook_calls': self.hook_calls, 'tty_reads': self.tty_reads, 'exit3': self.exit3,
                'human_lines': self.human_lines}


class _StderrProxy(io.TextIOBase):
    """Counts stderr lines starting `ready-for-human` (the human-only report lines)."""

    def __init__(self, inner, counters):
        self._inner, self._counters = inner, counters

    def write(self, text):
        for line in text.splitlines(keepends=True):
            if line.startswith('ready-for-human'):
                self._counters.human_lines += 1
        return self._inner.write(text)

    def flush(self):
        return self._inner.flush()

    def __getattr__(self, name):
        return getattr(self._inner, name)


def e2e_bundle(mode):
    """G1←G2←G3. In prompt mode G1 is the bootstrap policy goal (the candidate bytes land
    through its certificate); in agent mode the three goals scope src/g1.txt..src/g3.txt."""
    if mode == 'prompt':
        goals = [{'id': 'G1', 'scope': [POLICY_PATH], 'acceptance_criteria': ['the bootstrap policy lands'],
                  'dependencies': [], 'verification': ['bash tests/check.sh']},
                 {'id': 'G2', 'scope': ['src/g2.txt'], 'acceptance_criteria': ['G2 implemented'],
                  'dependencies': ['G1'], 'verification': ['bash tests/check.sh']},
                 {'id': 'G3', 'scope': ['src/g3.txt'], 'acceptance_criteria': ['G3 implemented'],
                  'dependencies': ['G2'], 'verification': ['bash tests/check.sh']}]
    else:
        goals = [{'id': 'G1', 'scope': ['src/g1.txt'], 'acceptance_criteria': ['G1 implemented'],
                  'dependencies': [], 'verification': ['bash tests/check.sh']},
                 {'id': 'G2', 'scope': ['src/g2.txt'], 'acceptance_criteria': ['G2 implemented'],
                  'dependencies': ['G1'], 'verification': ['bash tests/check.sh']},
                 {'id': 'G3', 'scope': ['src/g3.txt'], 'acceptance_criteria': ['G3 implemented'],
                  'dependencies': ['G2'], 'verification': ['bash tests/check.sh']}]
    bundle = sample_bundle(goals)
    bundle['id'] = PLAN
    return bundle


class E2ERepo:
    """One disposable fixture repository with a bare origin, a primary clone and per-goal
    linked worktrees. `run_op` runs one operation through the real `observer.main` with
    every counting wrapper installed."""

    def __init__(self, base, mode):
        self.base = Path(base).resolve()
        self.base.mkdir(parents=True, exist_ok=True)
        self.mode = mode
        self.keys = FixtureKeys(self.base)
        self.anchor_sha256 = self.keys.write_anchor()
        self.clock = Clock()
        self.counters = Counters()
        self.inputs = Path(tempfile.mkdtemp(prefix='e2e-inputs-', dir=self.base))
        self.origin = self.base / 'origin.git'
        git(self.base, 'init', '-q', '--bare', str(self.origin))
        self.work = self.base / 'work'
        git(self.base, 'clone', '-q', str(self.origin), str(self.work))
        self.bundle = e2e_bundle(mode)
        self.sidecar = sample_sidecar(self.bundle)
        policy = sample_policy(self.anchor_sha256, 'single', ('in-session', 'ssh-tag'))
        policy['tools'] = ['git', 'python3', 'e2e-tool']
        files = {'AGENTS.md': 'Fixture instructions\n', 'spec.md': 'Fixture specification\n',
                 'tests/check.sh': '#!/bin/sh\nexit 0\n',
                 '.github/workflows/ci.yml': 'jobs:\n  t:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/check.sh\n',
                 'src/g1.txt': 'v0\n', 'src/g2.txt': 'v0\n', 'src/g3.txt': 'v0\n'}
        for name, text in files.items():
            path = self.work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        (self.work / 'tests/check.sh').chmod(0o755)
        self.candidate_path = None
        if mode == 'prompt':
            self.policy = policy  # bootstrap: the candidate below; no live policy at the initial commit
            self.candidate_path = write_json(self.inputs / 'policy-candidate.json', policy)
        else:
            policy = dict(policy)
            policy['approval']['accept'] = ['agent-self', 'in-session', 'ssh-tag']
            policy['approval']['default_mode'] = 'agent'
            self.policy = policy
            write_json(self.work / POLICY, policy)
        git(self.work, 'add', '-A')
        git(self.work, 'commit', '-q', '--allow-empty', '-m', 'fixture: initial repository')
        git(self.work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
        git(self.work, 'fetch', '-q', 'origin')
        self.bundle_path = write_json(self.inputs / 'bundle.json', self.bundle)
        self.sidecar_path = write_json(self.inputs / 'sidecar.json', self.sidecar)
        self.stub = HostStub(self)
        self.bin = self.base / 'bin'
        self.bin.mkdir(exist_ok=True)
        (self.bin / 'e2e-tool').write_text('#!/bin/sh\nexit 0\n')
        (self.bin / 'e2e-tool').chmod(0o755)
        self.generation = None
        self.publication = None
        self.approval = None
        self.assurance = None
        self.results = {'admissions': [], 'certificates': [], 'merges': [], 'audits': [], 'exports': []}

    def required_checks(self):
        return self.policy['required_checks']

    def env(self):
        return {'PATH': str(self.bin) + os.pathsep + os.environ['PATH']}

    def state_dir(self):
        return Path(git(self.work, 'rev-parse', '--path-format=absolute', '--git-common-dir')) / 'ai-catapult/observer'

    def driver_log_lines(self):
        path = self.state_dir() / 'driver-log.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.is_file() else []

    def human_patches(self):
        """The counting wrappers: input/getpass hook calls, /dev/tty opens, stdin reads and
        subprocess exit 3."""
        counters = self.counters

        def guarded_input(prompt=None):
            counters.hook_calls += 1
            raise AssertionError('the chain must never read input()')

        real_open, real_os_open = builtins.open, os.open

        def counted_open(file, *args, **kwargs):
            if str(file) == '/dev/tty':
                counters.tty_reads += 1
            return real_open(file, *args, **kwargs)

        def counted_os_open(path, *args, **kwargs):
            if str(path) == '/dev/tty':
                counters.tty_reads += 1
            return real_os_open(path, *args, **kwargs)

        class CountingStdin:
            def __init__(self, inner, counters):
                self._inner, self._counters = inner, counters

            def read(self, *args):
                self._counters.tty_reads += 1
                return self._inner.read(*args)

            def readline(self, *args):
                self._counters.tty_reads += 1
                return self._inner.readline(*args)

            def __getattr__(self, name):
                return getattr(self._inner, name)

        self._devnull = open(os.devnull, 'rb')
        atexit.register(self._devnull.close)
        real_run, real_popen = subprocess.run, subprocess.Popen

        def counted_run(*args, **kwargs):
            result = real_run(*args, **kwargs)
            if getattr(result, 'returncode', None) == 3:
                counters.exit3 += 1
            return result

        def counted_popen(*args, **kwargs):
            process = real_popen(*args, **kwargs)
            wait = process.wait

            def counted_wait(*wargs, **wkwargs):
                code = wait(*wargs, **wkwargs)
                if code == 3:
                    counters.exit3 += 1
                return code

            process.wait = counted_wait
            return process

        return [mock.patch.object(builtins, 'input', guarded_input),
                mock.patch.object(getpass, 'getpass', guarded_input),
                mock.patch.object(builtins, 'open', counted_open),
                mock.patch.object(os, 'open', counted_os_open),
                mock.patch.object(sys, 'stdin', CountingStdin(self._devnull, counters)),
                mock.patch.object(subprocess, 'run', counted_run),
                mock.patch.object(subprocess, 'Popen', counted_popen)]

    def run_op(self, argv, env=None, key='certifier', anchor=None):
        """One operation through the real main(), with every counter installed and the
        fixture clock as the observer's `now` (so every timestamp is monotonic)."""
        real_run = observer.run

        def clocked_run(argv_, now=None, adapter=None):
            return real_run(argv_, now=self.clock.now, adapter=adapter)

        patches = [mock.patch.object(observer, 'anchor_locator', lambda: Path(anchor or self.keys.anchor)),
                   mock.patch.object(observer, 'signing_key_locator', lambda: self.keys.paths[key]),
                   mock.patch.object(observer, 'hosted_command', self.stub.dispatch),
                   mock.patch.object(observer, 'run', clocked_run),
                   *self.human_patches()]
        if env is not None:
            patches.append(mock.patch.dict(os.environ, env))
        for patch in patches:
            patch.start()
        stdout, stderr_buffer = io.StringIO(), io.StringIO()
        try:
            with mock.patch.object(sys, 'stdout', stdout):
                with mock.patch.object(sys, 'stderr', _StderrProxy(stderr_buffer, self.counters)):
                    code = observer.main(argv)
        finally:
            for patch in reversed(patches):
                patch.stop()
        if code == 3:
            self.counters.exit3 += 1
        return code, stdout.getvalue(), stderr_buffer.getvalue()

    def fetch(self, *worktrees):
        for wt in worktrees:
            git(wt, 'fetch', '-q', '--tags', 'origin')

    def tag_and_push(self, message, tag, target):
        path = self.inputs / (tag.replace('/', '-') + '.msg')
        path.write_text(message)
        git(self.work, 'tag', '-f', '-a', '--cleanup=verbatim', '-F', str(path), tag, target)
        git(self.work, 'push', '-q', '-f', 'origin', 'refs/tags/' + tag)
        git(self.work, 'fetch', '-q', '--tags', 'origin')

    def review_record(self, gid, pr, head, key='reviewer'):
        record = {'schema': 'review-lane/1', 'plan_id': PLAN, 'goal_id': gid, 'pr': pr, 'head': head,
                  'verdict': 'approve', 'lane': LANE, 'issued_at': self.clock.stamp()}
        line = json.dumps(record, sort_keys=True, separators=(',', ':'))
        path = Path(tempfile.mkdtemp(prefix='review-', dir=self.base)) / 'review.json'
        path.write_text(line)
        Path(str(path) + '.sig').write_text(ssh_sign(self.keys.paths[key], v2.NS_REVIEW, line.encode(), self.base))
        return path

    def scope_file(self, gid):
        return POLICY_PATH if (self.mode == 'prompt' and gid == 'G1') else 'src/%s.txt' % gid.lower()

    def flip_script(self, gid):
        scope = self.scope_file(gid)
        if scope == POLICY_PATH:
            return '#!/bin/sh\ntest -f %s\n' % scope
        return '#!/bin/sh\ngrep -q ^done$ %s\n' % scope

    def add_worktree(self, suffix, branch):
        wt = self.base / ('wt-' + suffix)
        git(self.work, 'worktree', 'add', '-q', str(wt), '-b', branch, 'origin/main')
        self.fetch(wt)
        return wt

    def publication_chain(self):
        """Publish as a planning PR, then merge it through the real merge-v2 v1 decision."""
        wt = self.add_worktree('pub', 'docs/%s-publication' % PLAN)
        argv = ['publish-v2', '--root', str(wt), '--bundle', str(self.bundle_path), '--sidecar', str(self.sidecar_path)]
        if self.candidate_path:
            argv += ['--policy-candidate', str(self.candidate_path)]
        argv += ['--admit-planning']
        code, out, err = self.run_op(argv, env=self.env())
        assert code == 0, (out, err)
        result = json.loads(out)
        assert result['planning_complete'] is True, json.dumps(result, indent=1)
        assert not result['planning']['blocking'], json.dumps(result['planning'], indent=1)
        assert 'approval_tag_missing' in [g['code'] for g in result['planning']['approval']], out
        self.generation = result['generation']
        git(wt, 'add', '-A')
        git(wt, 'commit', '-q', '-m', 'publish %s' % PLAN)
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/docs/%s-publication' % PLAN)
        head = git(wt, 'rev-parse', 'HEAD')
        self.fetch(wt)
        base_sha = git(wt, 'rev-parse', 'origin/main')
        self.stub.register(head=head, head_ref='docs/%s-publication' % PLAN, base=base_sha, base_ref='main',
                           files=self.stub.diff_files(base_sha, head))
        cwd = os.getcwd()
        os.chdir(wt)
        try:
            code, out, err = self.run_op(['merge-v2', '--pr', '1'], env=self.env())
        finally:
            os.chdir(cwd)
        assert code == 10, (out, err)
        decision = json.loads(out)
        assert decision['decision'] == 'v1', out
        expected_lane = 'v1' if self.mode == 'prompt' else 'publish-v2-replay'
        assert decision['lane'] == expected_lane, out
        self.stub.pr_merge(['1', '--squash', '--match-head-commit', head])
        self.fetch(self.work, wt)
        self.publication = git(self.work, 'rev-parse', 'origin/main')
        assert self.generation and self.publication

    def approval_chain(self, days=14):
        if self.mode == 'prompt':
            code, out, err = self.run_op(['approval-request', '--root', str(self.work), '--handoff', HANDOFF,
                                          '--mode', 'prompt', '--owner', 'Fixture Owner', '--reviewer-lane', LANE,
                                          '--days', str(days)], env=self.env())
            assert code == 0, (out, err)
            request = json.loads(out)
            assert request['human_action'], out
            digest = request['digest']
            code, out, err = self.run_op(['approval-request', '--root', str(self.work), '--handoff', HANDOFF,
                                          '--confirm', digest], env=self.env())
            assert code == 0, (out, err)
            confirmed = json.loads(out)
            message = confirmed['message']
            self.approval = request['record']
            self.assurance = 'in-session'
        else:
            code, out, err = self.run_op(['approval-request', '--root', str(self.work), '--handoff', HANDOFF,
                                          '--mode', 'default', '--owner', 'Fixture Owner', '--reviewer-lane', LANE,
                                          '--days', str(days)], env=self.env())
            assert code == 0, (out, err)
            issued = json.loads(out)
            assert issued['assurance'] == 'agent-self', out
            assert issued['human_action'] is None, out
            message = issued['message']
            self.approval = issued['record']
            self.assurance = 'agent-self'
        self.tag_and_push(message, 'approval/%s/%s' % (PLAN, self.generation[:12]), self.publication)

    def admit(self, wt, gid, stage='implementation', extra=()):
        code, out, err = self.run_op(['admit-v2', '--root', str(wt), '--handoff', HANDOFF, '--goal-id', gid,
                                      '--stage', stage, *extra], env=self.env())
        return code, json.loads(out), err

    def implement_goal(self, wt, gid):
        """The CertificateFixture red/green pattern, on the goal's own linked worktree."""
        flip = wt / ('tests/flip_%s.sh' % gid.lower())
        flip.write_text(self.flip_script(gid))
        flip.chmod(0o755)
        evidence = AUTO / 'tdd-evidence.sh'
        subprocess.run(['bash', str(evidence), '--record-red', '--goal', gid, '--root', str(wt),
                        '--command', 'sh tests/flip_%s.sh' % gid.lower()], check=True, capture_output=True)
        scope = wt / self.scope_file(gid)
        scope.parent.mkdir(parents=True, exist_ok=True)
        if self.scope_file(gid) == POLICY_PATH:
            scope.write_bytes(self.candidate_path.read_bytes())
        else:
            scope.write_text('done\n')
        subprocess.run(['bash', str(evidence), '--record-green', '--goal', gid, '--root', str(wt),
                        '--command', 'sh tests/flip_%s.sh' % gid.lower()], check=True, capture_output=True)
        git(wt, 'add', '-A')
        git(wt, 'commit', '-q', '-m', 'feat: implement ' + gid)
        git(wt, 'push', '-q', 'origin', 'HEAD:refs/heads/feat/%s-%s' % (PLAN, gid))
        head = git(wt, 'rev-parse', 'HEAD')
        self.fetch(wt)
        base_sha = git(wt, 'rev-parse', 'origin/main')
        self.stub.register(head=head, head_ref='feat/%s-%s' % (PLAN, gid), base=base_sha, base_ref='main',
                           files=self.stub.diff_files(base_sha, head))
        self.clock.tick()  # the checks completed before the certificate issue
        return head

    def certify(self, wt, gid, pr, review=None, extra=()):
        argv = ['certify-v2', '--root', str(wt), '--handoff', HANDOFF, '--goal-id', gid, '--pr', str(pr)]
        if review:
            argv += ['--review-record', str(review)]
        argv += list(extra)
        code, out, err = self.run_op(argv, env=self.env())
        if code == 0:
            self.clock.tick()  # the issue predates the merge
        return code, out, err

    def merge(self, wt, pr, extra=()):
        cwd = os.getcwd()
        os.chdir(wt)
        try:
            return self.run_op(['merge-v2', '--pr', str(pr), *extra], env=self.env())
        finally:
            os.chdir(cwd)

    def full_chain(self):
        """AC3: publication as a PR, one approval, then admit+certify+merge of G1, G2, G3,
        each from its own linked worktree."""
        self.publication_chain()
        self.approval_chain()
        wts = {}
        for gid in ('G1', 'G2', 'G3'):
            wts[gid] = self.add_worktree(gid, 'feat/%s-%s' % (PLAN, gid))
        for gid in ('G2', 'G3'):
            code, context, err = self.admit(wts[gid], gid)
            assert code == 1, json.dumps(context, indent=1)
            assert 'dependency_incomplete' in {g['code'] for g in context['gaps']}, json.dumps(context, indent=1)
        for gid, pr in (('G1', 2), ('G2', 3), ('G3', 4)):
            wt = wts[gid]
            code, context, err = self.admit(wt, gid)
            assert code == 0, json.dumps(context, indent=1)
            assert context['assurance'] == self.assurance, json.dumps(context, indent=1)
            self.results['admissions'].append(context)
            head = self.implement_goal(wt, gid)
            # A real goal PR is up to date with main at certify time (H1): rebase onto the
            # latest main and re-register the PR head, like a PR that merged its base.
            git(wt, 'rebase', '-q', 'origin/main')
            git(wt, 'push', '-q', '--force-with-lease', 'origin', 'HEAD:refs/heads/feat/%s-%s' % (PLAN, gid))
            head = git(wt, 'rev-parse', 'HEAD')
            self.fetch(wt)
            base_sha = git(wt, 'rev-parse', 'origin/main')
            self.stub.pulls[pr].update({'head': {'sha': head, 'ref': 'feat/%s-%s' % (PLAN, gid)},
                                        'base': {'sha': base_sha, 'ref': 'main'},
                                        'files': self.stub.diff_files(base_sha, head)})
            review = self.review_record(gid, pr, head)
            code, out, err = self.certify(wt, gid, pr, review)
            assert code == 0, (out, err)
            issued = json.loads(out)
            assert issued['certificate']['assurance'] == self.assurance, out
            self.results['certificates'].append(issued)
            code, out, err = self.merge(wt, pr, ['--admin'])
            assert code == 0, (out, err)
            merged = json.loads(out)
            assert merged['assurance'] == self.assurance, out
            self.results['merges'].append(merged)
            self.fetch(self.work, *wts.values())
        self.wts = wts

    def audit(self, extra=()):
        code, out, err = self.run_op(['audit-merges', '--root', str(self.work), '--plan', PLAN, *extra],
                                     env=self.env())
        return code, json.loads(out), err

    def export(self, extra=()):
        code, out, err = self.run_op(['export-evidence', '--root', str(self.work), '--plan', PLAN, *extra],
                                     env=self.env())
        return code, json.loads(out), err
