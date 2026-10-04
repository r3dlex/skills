"""Pinned, read-only observer and the readiness-contract/2 driver operations.

Observation only reads: git objects and refs, the hosted API through one adapter,
file digests, tool presence and the machine-local trust anchor. Every fact is
recorded as observation/1 with its source, time and commit, and handed to the pure
validator (readiness_contract_v2) to decide. Nothing supplied is trusted:
contexts, observations, verdicts and certificate claims are compared with a
fresh re-observation.

The only writers are publish-v2 (immutable generation files, registry last) and
the observer state under the repository's git common directory (certificates,
review records and the driver log). Approvals are never written here; only an
agent-mode approval (K3) is signed here, with the agent key under its own namespace.
"""
import argparse
import atexit
import base64
import json
import os
from pathlib import Path
import posixpath
import pwd
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tempfile
import unicodedata
from datetime import datetime, timedelta, timezone

import readiness_contract_v2 as v2
from readiness_contract import Invalid, canonical, read as read_json, worktree_observation
from verification import validate as validate_commands, VerificationError

HERE = Path(__file__).resolve().parents[1]
PASS_THROUGH = ('PATH', 'LANG', 'LC_ALL', 'TMPDIR', 'SSH_AUTH_SOCK', 'GH_TOKEN')
# Git repository selection that would redirect what git observes; set in the caller it refuses (P6).
IDENTITY_ENV = ('GIT_DIR', 'GIT_COMMON_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_OBJECT_DIRECTORY')
GIT_SETTINGS = {'GIT_CONFIG_NOSYSTEM': '1', 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_NO_REPLACE_OBJECTS': '1',
                'GIT_OPTIONAL_LOCKS': '0'}
OPERATIONS = ('admit-v2', 'publish-v2', 'approval-request', 'certify-v2', 'merge-v2')
RESERVED = ('context-build', 'export-evidence')
LOGGED = ('admit-v2', 'certify-v2', 'merge-v2', 'audit-merges', 'approval-request', 'inventory-v1')
AUDIT_LIMIT = 200
ROUTE_LIMIT = 1000  # the v1 inventory's hosted PR lists (token search needs them whole); reaching it fails closed
GOAL_PR_LIMIT = 100  # PRs on one exact goal branch; reaching it fails closed
FILES_LIMIT = 3000  # GitHub's cap on a pull request's changed-files list; reaching it fails closed
EXIT_V1 = 10
EXIT_FAIL_CLOSED = 4
THREADS_QUERY = ('query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo)'
                 '{pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved}pageInfo{hasNextPage}}}}}')


# --- environment and locators -------------------------------------------------

def passwd_home():
    return pwd.getpwuid(os.getuid()).pw_dir


def clean_env(source=None):
    """Allowlisted environment: HOME and GH_CONFIG_DIR always come from passwd."""
    source = os.environ if source is None else source
    env = {name: source[name] for name in PASS_THROUGH if name in source}
    env.setdefault('PATH', '/usr/bin:/bin')
    home = passwd_home()
    env['HOME'] = home
    env['GH_CONFIG_DIR'] = os.path.join(home, '.config', 'gh')
    return env


def default_anchor_path():
    return Path(passwd_home()) / '.config/ai-catapult/allowed_signers'


def default_signing_key():
    return Path(passwd_home()) / '.config/ai-catapult/agent_signing_key'


# Test-only in-process hooks. There is deliberately no environment variable or flag.
anchor_locator = default_anchor_path
signing_key_locator = default_signing_key


def gate_env(home):
    """Local gates run PR code: no credentials, no agent socket, a throwaway HOME, and
    never any bytecode written into the observed tree."""
    env = {name: os.environ[name] for name in ('PATH', 'LANG', 'LC_ALL', 'TMPDIR') if name in os.environ}
    env.setdefault('PATH', '/usr/bin:/bin')
    env.update(HOME=str(home), PYTHONDONTWRITEBYTECODE='1')
    return env


def command(argv, cwd=None, data=None, env=None):
    return subprocess.run([str(a) for a in argv], cwd=None if cwd is None else str(cwd), env=env or clean_env(),
                          input=data, stdin=None if data is not None else subprocess.DEVNULL,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def git(root, *args, check=True):
    env = clean_env()
    env.update(GIT_SETTINGS)
    result = subprocess.run(['git', '--no-replace-objects', '-c', 'core.fsmonitor=false', '-c',
                             'core.hooksPath=' + os.devnull, '-C', str(root), *args], env=env,
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode:
        raise Invalid('git_failed:%s:%s' % (args[0], result.stderr.decode(errors='replace').strip()[:200]))
    return result


def git_text(root, *args):
    return git(root, *args).stdout.decode().strip()


def show(root, ref, path):
    result = git(root, 'cat-file', 'blob', '%s:%s' % (ref, path), check=False)
    return result.stdout if result.returncode == 0 else None


def is_ancestor(root, commit, ref):
    return (git(root, 'cat-file', '-e', commit + '^{commit}', check=False).returncode == 0
            and git(root, 'merge-base', '--is-ancestor', commit, ref, check=False).returncode == 0)


def ancestry(root, commit, ref):
    """True or False when commit is or is not an ancestor of ref; None when unobservable."""
    if not (isinstance(commit, str) and re.fullmatch('[0-9a-f]{40}', commit)) or \
            git(root, 'cat-file', '-e', commit + '^{commit}', check=False).returncode:
        return None
    return git(root, 'merge-base', '--is-ancestor', commit, ref, check=False).returncode == 0


def path_key(name):
    """A path compared case-insensitively and Unicode-normalized (P4)."""
    return unicodedata.normalize('NFC', name).casefold()


def parse_json(data, label):
    def unique(pairs):
        keys = [key for key, _ in pairs]
        if len(set(keys)) != len(keys):
            raise ValueError('duplicate key')
        return dict(pairs)
    try:
        return json.loads(data, object_pairs_hook=unique)
    except (TypeError, ValueError):
        raise Invalid(label + '_invalid:not unique-key JSON')


def state_dir(root):
    common = Path(git_text(root, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
    return common / 'ai-catapult' / 'observer'


def common_dir(root):
    return str(Path(git_text(root, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve())


def registered_worktrees(root):
    """Every worktree the common directory lists, the primary checkout first."""
    listed = git(root, 'worktree', 'list', '--porcelain', '-z').stdout.split(b'\0')
    return [Path(os.fsdecode(entry[len(b'worktree '):])) for entry in listed if entry.startswith(b'worktree ')]


def observed_root(value):
    """P6: the root whose identity is observed. Identity is the policy's repository.id plus the
    observed git common directory, so the primary checkout and every registered linked worktree
    of one common directory match; the path itself is informational. Refused, each with its own
    code: git repository selection in the environment (identity_git_env_injected), a path through
    a symlink (identity_root_symlinked), a bare repository (identity_bare_repository), a directory
    below the top level (identity_root_not_toplevel) and a worktree the common directory does not
    list (identity_worktree_unregistered)."""
    injected = sorted(name for name in IDENTITY_ENV if name in os.environ)
    v2.check(not injected, 'identity_git_env_injected', ', '.join(injected) + ' would redirect what git observes')
    root = Path(os.path.abspath(value))
    v2.check(root == root.resolve(strict=True), 'identity_root_symlinked', str(root))
    v2.check(git_text(root, 'rev-parse', '--is-bare-repository') == 'false', 'identity_bare_repository', str(root))
    v2.check(Path(git_text(root, 'rev-parse', '--show-toplevel')) == root, 'identity_root_not_toplevel', str(root))
    v2.check(root in {path.resolve() for path in registered_worktrees(root)}, 'identity_worktree_unregistered', str(root))
    return root


def fact(value, source, commit, now):
    return {'value': value, 'source': source, 'observed_at': v2.stamp(now), 'commit': commit}


# --- hosted adapters ---------------------------------------------------------------

class GhAdapter:
    """The production hosted adapter: the gh CLI under the allowlisted environment."""
    name = 'production-gh'

    def __init__(self, root):
        self.root = Path(root)

    def _api(self, path, *extra, allow_missing=False):
        result = command(['gh', 'api', path, *extra], cwd=self.root)
        if result.returncode:
            if allow_missing and re.search(r'HTTP 40[34]', result.stderr.decode(errors='replace')):
                return None
            raise Invalid('hosted_api_unavailable:' + path)
        return parse_json(result.stdout, 'hosted_api')

    def pull(self, number):
        data = self._api('repos/{owner}/{repo}/pulls/%d' % number)
        return {'number': number, 'head': data['head']['sha'], 'head_ref': data['head']['ref'],
                'base': data['base']['sha'], 'base_ref': data['base']['ref'], 'state': data.get('state'),
                'merged': bool(data.get('merged'))}

    def check_runs(self, sha):
        data = self._api('repos/{owner}/{repo}/commits/%s/check-runs?per_page=100' % sha)
        v2.check(data.get('total_count', 0) <= len(data.get('check_runs', [])), 'hosted_api_incomplete', 'check-runs')
        return [{'name': r.get('name'), 'status': r.get('status'), 'conclusion': r.get('conclusion'),
                 'completed_at': r.get('completed_at')} for r in data.get('check_runs', [])]

    def unresolved_threads(self, number):
        data = self._api('graphql', '-f', 'query=' + THREADS_QUERY, '-F', 'owner={owner}', '-F', 'repo={repo}',
                         '-F', 'number=%d' % number)
        threads = data['data']['repository']['pullRequest']['reviewThreads']
        v2.check(not (threads.get('pageInfo') or {}).get('hasNextPage'), 'hosted_api_incomplete', 'review threads')
        nodes = threads['nodes']
        return sum(1 for node in nodes if not node.get('isResolved'))

    def protection(self, branch):
        data = self._api('repos/{owner}/{repo}/branches/%s/protection/required_status_checks' % branch, allow_missing=True)
        if data is None:
            return {'status': 'unavailable'}
        contexts = list(data.get('contexts') or []) + [c.get('context') for c in data.get('checks') or [] if c.get('context')]
        return {'status': 'available', 'contexts': sorted(set(contexts))}

    def merged_prs(self, limit=AUDIT_LIMIT):
        result = command(['gh', 'pr', 'list', '--state', 'merged', '--limit', str(limit), '--json',
                          'number,headRefName,headRefOid,mergeCommit,mergedAt,baseRefName'], cwd=self.root)
        if result.returncode:
            raise Invalid('hosted_api_unavailable:pr list')
        return [pull_record(p) for p in parse_json(result.stdout, 'hosted_api')]

    def goal_branch_prs(self, branch, target, state):
        """PRs on one exact head branch into target (L4): a bounded query, never a global list."""
        result = command(['gh', 'pr', 'list', '--state', state, '--head', branch, '--base', target, '--limit',
                          str(GOAL_PR_LIMIT), '--json', 'number,headRefName,headRefOid,mergeCommit,baseRefName'], cwd=self.root)
        if result.returncode:
            raise Invalid('hosted_api_unavailable:pr list ' + branch)
        pulls = parse_json(result.stdout, 'hosted_api')
        v2.check(isinstance(pulls, list) and len(pulls) < GOAL_PR_LIMIT, 'v2_goal_prs_unobservable',
                 '%s PRs on %s reached %d' % (state, branch, GOAL_PR_LIMIT))
        return [pull_record(p) for p in pulls]

    def open_prs(self, limit=ROUTE_LIMIT):
        result = command(['gh', 'pr', 'list', '--state', 'open', '--limit', str(limit), '--json',
                          'number,headRefName,headRefOid'], cwd=self.root)
        if result.returncode:
            raise Invalid('hosted_api_unavailable:pr list open')
        return [{'number': p.get('number'), 'head_ref': p.get('headRefName'), 'head': p.get('headRefOid')}
                for p in parse_json(result.stdout, 'hosted_api')]

    def branches(self):
        result = git(self.root, 'ls-remote', '--heads', 'origin', check=False)
        if result.returncode:
            raise Invalid('hosted_api_unavailable:ls-remote origin')
        return [dict(zip(('sha', 'ref'), line.split('\t', 1))) for line in result.stdout.decode().splitlines() if '\t' in line]

    def pr_files(self, number):
        """The hosted changed-files list; a rename carries previous_filename. Reaching GitHub's
        3000-file cap, or a count that differs from the pull's changed_files, fails closed."""
        expected = self._api('repos/{owner}/{repo}/pulls/%d' % number).get('changed_files')
        v2.check(type(expected) is int, 'hosted_api_incomplete', 'pull changed_files')
        files, page = [], 1
        while True:
            batch = self._api('repos/{owner}/{repo}/pulls/%d/files?per_page=100&page=%d' % (number, page))
            v2.check(isinstance(batch, list), 'hosted_api_incomplete', 'pull files')
            files += [{'filename': f.get('filename'), 'previous_filename': f.get('previous_filename'),
                       'status': f.get('status')} for f in batch]
            if len(batch) < 100 or len(files) >= FILES_LIMIT:
                break
            page += 1
        v2.check(len(files) < FILES_LIMIT, 'pr_files_truncated', 'the hosted list reached %d files' % FILES_LIMIT)
        v2.check(expected == len(files), 'pr_files_truncated',
                 '%d of %s changed files listed' % (len(files), expected))
        return files

    def merge(self, number, head, admin):
        argv = ['gh', 'pr', 'merge', str(number), '--squash', '--match-head-commit', head] + (['--admin'] if admin else [])
        result = command(argv, cwd=self.root)
        return result.returncode == 0, result.stderr.decode(errors='replace').strip()


class FixtureAdapter:
    """In-process test adapter over a recorded host state. Never accepted for a merge."""
    name = 'fixture'

    def __init__(self, state):
        self.state = state

    def pull(self, number):
        data = self.state['pulls'][str(number)]
        return {'number': number, 'head': data['head']['sha'], 'head_ref': data['head']['ref'],
                'base': data['base']['sha'], 'base_ref': data['base']['ref'], 'state': 'open', 'merged': False}

    def check_runs(self, sha):
        return list(self.state.get('checks', {}).get(sha, []))

    def unresolved_threads(self, number):
        return sum(1 for t in self.state.get('threads', {}).get(str(number), []) if not t.get('isResolved'))

    def protection(self, branch):
        value = self.state.get('protection')
        return {'status': 'available', 'contexts': value.get('contexts', [])} if isinstance(value, dict) else {'status': 'unavailable'}

    def merged_prs(self, limit=AUDIT_LIMIT):
        return [pull_record(p) for p in self.state.get('merged_prs', [])]

    def goal_branch_prs(self, branch, target, state):
        pulls = [pull_record(p) for p in self.state.get('open_prs' if state == 'open' else 'merged_prs', [])]
        return [p for p in pulls if p['head_ref'] == branch and p['base_ref'] in (None, target)]

    def open_prs(self, limit=ROUTE_LIMIT):
        return [{'number': p.get('number'), 'head_ref': p.get('headRefName'), 'head': p.get('headRefOid')}
                for p in self.state.get('open_prs', [])]

    def branches(self):
        return [{'ref': b.get('ref'), 'sha': b.get('sha')} for b in self.state.get('branches', [])]

    def pr_files(self, number):
        """The in-process test stub is the only place a PR without recorded files lists none."""
        return list(self.state.get('files', {}).get(str(number), []))

    def merge(self, number, head, admin):
        return False, 'the fixture adapter never merges'


def pull_record(p):
    return {'number': p.get('number'), 'head_ref': p.get('headRefName'), 'head': p.get('headRefOid'),
            'base_ref': p.get('baseRefName'), 'merge_commit': (p.get('mergeCommit') or {}).get('oid')}


def hosted_adapter_factory(root):
    return GhAdapter(root)


# --- trust anchor and SSH signatures ---------------------------------------------

def split_options(text):
    tokens, current, quoted = [], '', False
    for char in text:
        if char == '"':
            quoted = not quoted
        if char == ',' and not quoted:
            tokens.append(current)
            current = ''
        else:
            current += char
    return tokens + ([current] if current else [])


def parse_anchor_line(line):
    """principals [options] keytype key [comment] (allowed_signers format)."""
    tokens, current, quoted = [], '', False
    for char in line.strip():
        if char == '"':
            quoted = not quoted
        if char.isspace() and not quoted:
            if current:
                tokens.append(current)
            current = ''
        else:
            current += char
    if current:
        tokens.append(current)
    if len(tokens) < 3:
        return None
    principals, rest = tokens[0].split(','), tokens[1:]
    options = []
    if not re.match(r'^(ssh-|sk-|ecdsa-)', rest[0]):
        options, rest = split_options(rest[0]), rest[1:]
    if len(rest) < 2:
        return None
    namespaces = []
    for option in options:
        if option.startswith('namespaces='):
            namespaces = [n for n in option.split('=', 1)[1].strip('"').split(',') if n]
    return {'principals': principals, 'options': [o.split('=', 1)[0] for o in options], 'namespaces': namespaces,
            'key_type': rest[0], 'key': rest[1]}


def anchor_lines(anchor):
    lines = []
    for raw in Path(anchor).read_text().splitlines():
        if raw.strip() and not raw.lstrip().startswith('#'):
            parsed = parse_anchor_line(raw)
            if parsed:
                lines.append(parsed)
    return lines


def ambiguous_principals(lines):
    """Principals listed on more than one line, or lines naming several principals."""
    seen, ambiguous = {}, set()
    for entry in lines:
        if len(entry['principals']) != 1:
            ambiguous.update(entry['principals'])
        for principal in entry['principals']:
            seen[principal] = seen.get(principal, 0) + 1
    return sorted(ambiguous | {p for p, count in seen.items() if count > 1})


_PRIVATE = []


def private_copy(data):
    """A read-once private copy of the anchor; ssh-keygen only ever reads this copy."""
    if not _PRIVATE:
        _PRIVATE.append(tempfile.mkdtemp(prefix='observer-anchor-'))
        atexit.register(shutil.rmtree, _PRIVATE[0], True)
    descriptor, name = tempfile.mkstemp(dir=_PRIVATE[0])
    with os.fdopen(descriptor, 'wb') as handle:
        handle.write(data)
    os.chmod(name, 0o600)
    return Path(name)


def observe_anchor():
    """(private copy or None, facts). The anchor itself must be a regular, non-symlink
    file whose resolved location lies outside every git worktree."""
    path = Path(anchor_locator())
    facts = {'present': False, 'symlink': False, 'inside_worktree': False, 'sha256': None, 'ambiguous': []}
    try:
        mode = os.lstat(path).st_mode
    except OSError:
        return None, facts
    if stat.S_ISLNK(mode):
        facts['symlink'] = True
        return None, facts
    if not stat.S_ISREG(mode):
        return None, facts
    resolved = path.resolve(strict=True)
    inside = any((parent / '.git').exists() for parent in resolved.parents)
    if not inside:
        inside = git(resolved.parent, 'rev-parse', '--is-inside-work-tree', check=False).stdout.strip() == b'true'
    data = resolved.read_bytes()
    copy = private_copy(data)
    facts.update(present=True, inside_worktree=inside, sha256=v2.sha256(data),
                 ambiguous=ambiguous_principals(anchor_lines(copy)))
    return copy, facts


def signature_public_key(signature_text):
    """(key type, base64 public key blob) of the key that made an SSHSIG signature."""
    body = ''.join(line.strip() for line in signature_text.strip().splitlines() if not line.startswith('-----'))
    blob = base64.b64decode(body, validate=True)
    if blob[:6] != b'SSHSIG' or len(blob) < 14:
        raise ValueError('not an SSHSIG signature')
    length = int.from_bytes(blob[10:14], 'big')
    public = blob[14:14 + length]
    type_length = int.from_bytes(public[:4], 'big')
    return public[4:4 + type_length].decode(), base64.b64encode(public).decode()


def verify_signature(anchor, signature_text, data, namespace):
    """Select the anchor line by the signing public key, require that line to be the
    principal's only line, then ssh-keygen -Y verify -I <principal> -n <namespace>."""
    refused = {'principal': None, 'verified': False, 'namespaces': [], 'key_type': None, 'options': []}
    try:
        key_type, key = signature_public_key(signature_text)
    except (ValueError, UnicodeDecodeError):
        return refused
    lines = anchor_lines(anchor)
    matches = [entry for entry in lines if (entry['key_type'], entry['key']) == (key_type, key)]
    if len(matches) != 1 or len(matches[0]['principals']) != 1 or \
            matches[0]['principals'][0] in ambiguous_principals(lines):
        return dict(refused, ambiguous=bool(matches))
    line, principal = matches[0], matches[0]['principals'][0]
    with tempfile.TemporaryDirectory(prefix='observer-') as tmp:
        signature = Path(tmp) / 'signature'
        signature.write_text(signature_text)
        verified = command(['ssh-keygen', '-Y', 'verify', '-f', anchor, '-I', principal, '-n', namespace, '-s', signature],
                           data=data)
    return {'principal': principal, 'verified': verified.returncode == 0, 'namespaces': line['namespaces'],
            'key_type': line['key_type'], 'options': line['options']}


def signing_identity(anchor):
    """The anchor principal of the agent signing key (it must hold the certificate role)."""
    key, entry = key_line(anchor)
    v2.check(v2.NS_CERTIFICATE in entry['namespaces'] and v2.NS_APPROVAL not in entry['namespaces'],
             'certifier_key_not_agent', entry['principals'][0])
    return key, entry['principals'][0]


def agent_approval_identity(anchor):
    """K3: the agent signing key may issue an approval only when its anchor line holds
    ai-catapult-agent-approval and never the human ai-catapult-plan-approval."""
    key, entry = key_line(anchor)
    v2.check(v2.NS_AGENT_APPROVAL in entry['namespaces'] and v2.NS_APPROVAL not in entry['namespaces'],
             'agent_approval_signer_not_agent', entry['principals'][0])
    return key, entry['principals'][0]


def key_line(anchor):
    """The one anchor line of the local agent signing key."""
    v2.check(anchor is not None, 'anchor_missing', 'no usable trust anchor for the agent key')
    key = Path(signing_key_locator())
    if key.suffix == '.pub':
        public = key.read_text().split()
    else:
        derived = command(['ssh-keygen', '-y', '-f', key])
        if derived.returncode:
            raise Invalid('certifier_key_unavailable:' + str(key))
        public = derived.stdout.decode().split()
    lines = anchor_lines(anchor)
    matches = [entry for entry in lines if public[:2] == [entry['key_type'], entry['key']]]
    v2.check(matches, 'certifier_key_not_in_anchor')
    entry = matches[0]
    v2.check(len(matches) == 1 and len(entry['principals']) == 1 and entry['principals'][0] not in ambiguous_principals(lines),
             'anchor_principal_ambiguous', ','.join(entry['principals']))
    return key, entry


def sign(key, namespace, data):
    with tempfile.TemporaryDirectory(prefix='observer-') as tmp:
        payload = Path(tmp) / 'payload'
        payload.write_bytes(data)
        result = command(['ssh-keygen', '-q', '-Y', 'sign', '-f', key, '-n', namespace, payload])
        if result.returncode:
            raise Invalid('certificate_signing_failed:' + result.stderr.decode(errors='replace').strip()[:200])
        return (Path(tmp) / 'payload.sig').read_text()


# --- planning inputs on the target (B5) ---------------------------------------------

def target_ref(target):
    return 'refs/remotes/origin/' + target


def load_generation(root, ref, handoff):
    """Every planning input is read from origin/<target>, never from the checkout."""
    registry_bytes = show(root, ref, v2.REGISTRY)
    v2.check(registry_bytes is not None, 'handoff_missing_or_ambiguous', 'no v2 registry on ' + ref)
    registry = parse_json(registry_bytes, 'registry')
    v2.check(isinstance(registry, dict) and registry.get('schema') == v2.VERSION and isinstance(registry.get('plans'), list),
             'registry_invalid')
    matches = [p for p in registry['plans'] if isinstance(p, dict) and handoff in (p.get('id'), p.get('handoff_path'))]
    v2.check(len(matches) == 1, 'handoff_missing_or_ambiguous', handoff)
    entry = matches[0]
    v2.check(entry.get('status') == 'active', 'handoff_not_active', entry.get('status'))
    generation = entry.get('generation')
    v2.check(isinstance(generation, str) and v2.SHA.fullmatch(generation), 'registry_invalid', 'generation')
    prefix = '%s/%s/%s' % (v2.GEN, entry.get('plan_id'), generation)
    artifacts = entry.get('artifacts') or {}

    def artifact(name):
        reference = artifacts.get(name) or {}
        v2.check(str(reference.get('path', '')).startswith(prefix + '/'), 'generation_artifact_mismatch', name)
        data = show(root, ref, reference['path'])
        v2.check(data is not None and ('sha256' not in reference or v2.sha256(data) == reference['sha256']),
                 'generation_artifact_mismatch', name)
        return data

    bundle = v2.validate_bundle(parse_json(artifact('bundle'), 'bundle'))
    v2.check(bundle['id'] == entry.get('plan_id'), 'registry_invalid', 'plan_id')
    sidecar_path = artifacts.get('sidecar', {}).get('path')
    sidecar = v2.validate_sidecar(parse_json(artifact('sidecar'), 'sidecar'), bundle)
    live_bytes = show(root, ref, v2.POLICY)
    try:
        live2 = json.loads(live_bytes).get('schema') == v2.POLICY_SCHEMA if live_bytes else False
    except (ValueError, AttributeError):
        live2 = False
    candidate = artifact('policy_candidate') if 'policy_candidate' in artifacts else None
    if candidate is not None:
        mode = 'policy-amendment' if entry.get('mode') == 'policy-amendment' else 'bootstrap'
        policy_bytes = candidate
    else:
        v2.check(live2, 'policy2_not_live', 'no readiness-policy/2 on ' + ref)
        mode, policy_bytes = 'live', live_bytes
    policy = v2.validate_policy(parse_json(policy_bytes, 'policy'))
    # Rule (d): an amendment's approval form must also pass the live policy's form rule. A
    # bootstrap generation's live list is empty by definition (a v1 or absent live policy).
    live_policy = v2.validate_policy(parse_json(live_bytes, 'policy')) if mode == 'policy-amendment' and live2 else None
    spec = show(root, ref, bundle['spec']['path'])
    v2.check(spec is not None, 'spec_missing', bundle['spec']['path'])
    digests = {'bundle_sha256': v2.bundle_sha256(bundle), 'spec_sha256': v2.sha256(spec),
               'policy_sha256': v2.sha256(policy_bytes), 'anchor_sha256': policy['approval']['anchor_sha256']}
    added = git_text(root, 'log', '--format=%H', '--diff-filter=A', ref, '--', prefix + '/goals.json').split()
    return {'entry': entry, 'bundle': bundle, 'sidecar': sidecar, 'sidecar_path': sidecar_path, 'policy': policy,
            'mode': mode, 'live_policy2': live2, 'candidate_is_live': candidate is not None and live_bytes == candidate,
            'live_policy': live_policy, 'live_sha256': v2.sha256(live_bytes) if live_bytes is not None else None,
            'digests': digests, 'prefix': prefix, 'published_at': added[-1] if added else None}


def routing_pattern(root, rev, gen):
    """M4: the live policy's branch_pattern routes; a candidate's only while no policy/2 is live.
    A live policy/2 that does not validate, or a policy file that does not parse, refuses."""
    data = show(root, rev, v2.POLICY)
    if data is None:
        return gen['policy']['branch_pattern']
    try:
        live = json.loads(data)
        if isinstance(live, dict) and live.get('schema') == v2.POLICY_SCHEMA:
            return v2.validate_policy(live)['branch_pattern']
    except (ValueError, Invalid) as error:
        v2.refuse('policy_unloadable', 'the live policy at %s: %s' % (rev[:12], error))
    return gen['policy']['branch_pattern']


def goal_merges(root, ref, gen, goal_id, adapter, pattern=None):
    """Merged PRs that complete one goal (M3, L4): queried per exact goal branch into the target,
    with a merge commit that is an ancestor of the target and descends from the commit that
    published the generation. A same-named PR merged before publication completes nothing."""
    target = gen['policy']['target']
    pattern = pattern or gen['policy']['branch_pattern']
    found = []
    for branch in v2.branch_names(pattern, gen['bundle']['id'], goal_id):
        for pull in adapter.goal_branch_prs(branch, target, 'merged'):
            if pull['head_ref'] != branch or pull['base_ref'] not in (None, target):
                continue
            commit = pull.get('merge_commit')
            if ancestry(root, commit, ref) is True and gen['published_at'] and ancestry(root, gen['published_at'], commit) is True:
                found.append(dict(pull, reached=True))
            else:
                found.append(dict(pull, reached=False))
    return found


def find_sidecar_v0(root, ref, path, digest, bundle):
    """The approved sidecar is the committed, valid version whose digest the approval names."""
    for commit in git_text(root, 'log', '--format=%H', ref, '--', path).split():
        data = show(root, commit, path)
        try:
            sidecar = parse_json(data, 'sidecar') if data is not None else None
            if sidecar is not None and canonical(sidecar) == digest:
                return v2.validate_sidecar(sidecar, bundle)
        except Invalid:
            continue
    return None


def observe_approval(root, ref, gen):
    """Read the one approval tag; verify an ssh-tag signature against the anchor."""
    plan_id, generation = gen['bundle']['id'], gen['entry']['generation']
    anchor, anchor_facts = observe_anchor()
    carrier = {'anchor': anchor_facts, 'tag': None}
    tag = 'approval/%s/%s' % (plan_id, generation[:12])
    found = git(root, 'rev-parse', '--verify', '--quiet', 'refs/tags/' + tag, check=False)
    if found.returncode:
        return carrier
    oid = found.stdout.decode().strip()
    carrier['tag'] = tag
    carrier['annotated'] = git_text(root, 'cat-file', '-t', oid) == 'tag'
    if not carrier['annotated']:
        return carrier
    raw = git(root, 'cat-file', 'tag', oid).stdout
    header, _, message = raw.partition(b'\n\n')
    target = re.search(rb'^object ([0-9a-f]{40})$', header, re.M)
    remote = git(root, 'ls-remote', 'origin', 'refs/tags/' + tag, check=False).stdout.decode().split()
    carrier['on_origin'] = bool(remote) and remote[0] == oid
    carrier['target_contains_generation'] = bool(target) and is_ancestor(root, target.group(1).decode(), ref) and \
        show(root, target.group(1).decode(), gen['prefix'] + '/goals.json') is not None
    lines = message.decode(errors='replace').split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    if len(lines) != 2 or b'gpgsig' in header:
        carrier['form'] = 'invalid'
        return carrier
    try:
        record = json.loads(lines[0])
    except ValueError:
        carrier['form'] = 'invalid'
        return carrier
    carrier['record'] = record
    carrier['record_canonical'] = v2.canonical_bytes(record).decode() == lines[0]
    if lines[1].startswith('signature: '):
        carrier['form'] = 'ssh-tag'
        try:
            signature = base64.b64decode(lines[1][len('signature: '):], validate=True).decode()
        except ValueError:
            signature = ''
        carrier['signature'] = verify_signature(anchor, signature, lines[0].encode(), v2.NS_APPROVAL) if \
            anchor_facts['present'] and signature else {'principal': None, 'verified': False}
    elif lines[1].startswith('digest-echo: '):
        carrier['form'] = 'in-session'
        carrier['digest_echo'] = lines[1][len('digest-echo: '):]
    elif lines[1].startswith('agent-signature: '):
        carrier['form'] = 'agent-self'
        try:
            signature = base64.b64decode(lines[1][len('agent-signature: '):], validate=True).decode()
        except ValueError:
            signature = ''
        carrier['signature'] = {'principal': None, 'verified': False}
        if anchor_facts['present'] and signature:
            carrier['signature'] = verify_signature(anchor, signature, lines[0].encode(), v2.NS_AGENT_APPROVAL)
            if not carrier['signature']['verified'] and \
                    verify_signature(anchor, signature, lines[0].encode(), v2.NS_APPROVAL)['verified']:
                carrier['signature_namespace'] = 'human'
    else:
        carrier['form'] = 'invalid'
    return carrier


# --- observation/1 -----------------------------------------------------------------

def tree_state(root):
    """HEAD plus whether index and working tree equal the HEAD tree byte for byte."""
    head = git_text(root, 'rev-parse', '--verify', 'HEAD^{commit}')
    tree = {}
    for entry in git(root, 'ls-tree', '-r', '-z', head).stdout.split(b'\0'):
        if entry:
            meta, name = entry.split(b'\t', 1)
            mode, _, oid = meta.split()
            tree[os.fsdecode(name)] = (mode, oid)
    index = {}
    for entry in git(root, 'ls-files', '--stage', '-z').stdout.split(b'\0'):
        if entry:
            meta, name = entry.split(b'\t', 1)
            mode, oid, stage = meta.split()
            if stage != b'0':
                return head, False
            index[os.fsdecode(name)] = (mode, oid)
    if index != tree:
        return head, False
    disk = set()
    for directory, directories, names in os.walk(root):
        if Path(directory) == Path(root):
            directories[:] = [d for d in directories if d != '.git']
            names = [n for n in names if n != '.git']
        disk.update(Path(directory, n).relative_to(root).as_posix() for n in names)
        disk.update(Path(directory, d).relative_to(root).as_posix() for d in directories if Path(directory, d).is_symlink())
    if disk != set(tree) or any(mode not in (b'100644', b'100755') for mode, _ in tree.values()):
        return head, False
    paths = sorted(tree)
    if not paths:
        return head, True
    env = clean_env()
    env.update(GIT_SETTINGS)
    hashed = subprocess.run(['git', '-C', str(root), 'hash-object', '--no-filters', '--stdin-paths'], env=env,
                            input='\n'.join(paths).encode() + b'\n', stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if hashed.returncode:
        return head, False
    for name, oid in zip(paths, hashed.stdout.split()):
        mode = b'100755' if os.stat(Path(root, name)).st_mode & 0o100 else b'100644'
        if (mode, oid) != tree[name]:
            return head, False
    return head, True


def worktree_rows(root):
    """The canonical digest of #92's worktree_observation rows for every tracked or present path
    under root, ignored and untracked included: [path, mode, sha256], [path, 'directory', mode], or
    [path, 'deleted'] for a tracked path that is gone. Where v1 refuses, a symlink is recorded as
    [path, 'symlink', target] (never followed) and any other file as [path, 'nonregular', type]."""
    def unreadable(error):
        raise Invalid('worktree_unobservable:' + str(error))
    paths = {os.fsdecode(p) for p in git(root, 'ls-files', '--cached', '-z').stdout.split(b'\0') if p}
    for directory, directories, names in os.walk(root, onerror=unreadable):
        if Path(directory) == Path(root):
            directories[:] = [d for d in directories if d != '.git']
            names = [n for n in names if n != '.git']
        paths.update(Path(directory, n).relative_to(root).as_posix() for n in names)
        paths.update(Path(directory, d).relative_to(root).as_posix() for d in directories if Path(directory, d).is_symlink())
    rows = []
    for name in sorted(paths):
        path = Path(root, name)
        try:
            mode = os.lstat(path).st_mode
        except (FileNotFoundError, NotADirectoryError):
            rows.append([name, 'deleted'])
            continue
        if stat.S_ISLNK(mode):
            rows.append([name, 'symlink', os.readlink(path)])
        elif stat.S_ISDIR(mode):
            rows.append([name, 'directory', stat.S_IMODE(mode)])
        elif stat.S_ISREG(mode):
            rows.append([name, stat.S_IMODE(mode), v2.sha256(path.read_bytes())])
        else:
            rows.append([name, 'nonregular', stat.S_IFMT(mode)])
    return canonical(rows)


def v1_worktree_state(root, head):
    """#92's worktree_observation (v1, read-only) of a registered linked worktree on a branch, or
    None where it does not apply: the primary checkout, a detached HEAD, no origin/main, or a tree
    v1 refuses."""
    linked = Path(git_text(root, 'rev-parse', '--absolute-git-dir')).resolve() != Path(common_dir(root))
    base = git(root, 'merge-base', head, 'refs/remotes/origin/main', check=False)
    if not linked or git(root, 'symbolic-ref', '--quiet', 'HEAD', check=False).returncode or base.returncode:
        return None
    try:
        return worktree_observation(registered_worktrees(root)[0], Path(root), base.stdout.decode().strip())['state_sha256']
    except (Invalid, OSError):
        return None


def worktree_snapshot(root):
    """G3: the worktree state compared before and after gate commands: HEAD, the raw index and the
    state of every path under root. A registered linked worktree on a branch is observed by #92's
    worktree_observation itself; every other root is walked with the same rows (worktree_rows), so
    one tree has one digest whichever worktree of the common directory holds it."""
    head = git_text(root, 'rev-parse', '--verify', 'HEAD^{commit}')
    return {'head': head, 'index_sha256': v2.sha256(git(root, 'ls-files', '--stage', '-z').stdout),
            'state_sha256': v1_worktree_state(root, head) or worktree_rows(root)}


def observe(root, ref, gen, goals, stage, adapter, now, pr=None, review_record=None):
    policy, bundle = gen['policy'], gen['bundle']
    head = git_text(root, 'rev-parse', '--verify', 'HEAD^{commit}')
    target = git_text(root, 'rev-parse', '--verify', ref + '^{commit}')
    branch = git(root, 'symbolic-ref', '--quiet', 'HEAD', check=False).stdout.decode().strip() or None
    facts = {'repository': fact({'id': policy['repository']['id'], 'common_dir': common_dir(root),
                                 'root': str(root), 'head': head, 'branch': branch}, 'git', head, now),
             'worktree_state': fact(worktree_snapshot(root), 'git+filesystem', head, now)}
    for source in policy['sources']:
        data = show(root, 'HEAD', source)
        facts['source:' + source] = fact(v2.sha256(data) if data is not None else None, 'git:HEAD', head, now)
    path = clean_env()['PATH']
    for tool in policy['tools']:
        facts['tool:' + tool] = fact(shutil.which(tool, path=path), 'PATH', head, now)
    publication = git_text(root, 'log', '-1', '--format=%H', ref, '--', gen['prefix']) or None
    facts['planning_inputs'] = fact({'publication_commit': publication, 'on_target': bool(publication),
                                     'in_head': bool(publication) and is_ancestor(root, publication, 'HEAD')},
                                    'git:' + ref, target, now)
    for gate in policy['gates']:
        binding = gate.get('binding', {})
        if gate['kind'] == 'file_digest':
            data = show(root, 'HEAD', binding['path'])
            facts['file:' + binding['path']] = fact(v2.sha256(data) if data is not None else None, 'git:HEAD', head, now)
        for commit in binding.get('commits', []) + ([binding['commit']] if 'commit' in binding else []):
            facts['ancestor:' + commit] = fact(is_ancestor(root, commit, ref), 'git:' + ref, target, now)
        if gate['kind'] == 'fixture' and 'path' in binding:
            fixture_path = Path(root, binding['path'])
            facts['fixture:' + binding['path']] = fact(fixture_path.is_file() and os.access(fixture_path, os.X_OK),
                                                       'filesystem', head, now)
    needed = sorted(set().union(*(v2.ancestors(bundle, gid) for gid in goals))) if goals else []
    for dependency in needed:
        matches = goal_merges(root, ref, gen, dependency, adapter)
        reached = [p for p in matches if p['reached']]
        facts['dependency:' + dependency] = fact(
            {'prs': [p['number'] for p in matches], 'merge_commit': reached[0]['merge_commit'] if reached else None,
             'ancestor': bool(reached)}, 'hosted:%s+git' % adapter.name, target, now)
    if pr is not None:
        pull = adapter.pull(pr)
        facts['pr'] = fact(pull, 'hosted:' + adapter.name, pull['head'], now)
        facts['checks'] = fact(adapter.check_runs(pull['head']), 'hosted:' + adapter.name, pull['head'], now)
        facts['threads'] = fact({'unresolved': adapter.unresolved_threads(pr)}, 'hosted:' + adapter.name, pull['head'], now)
        facts['protection'] = fact(adapter.protection(policy['target']), 'hosted:' + adapter.name, target, now)
        facts['review_lane'] = fact(observe_review(review_record, pull, bundle['id'], goals), 'anchor+ssh-keygen',
                                    pull['head'], now)
    return {'schema': v2.OBSERVATION_SCHEMA, 'adapter': adapter.name, 'target': ref, 'target_revision': target,
            'facts': facts}


def observe_review(path, pull, plan_id, goals):
    """An agent-signed review-lane/1 record bound to this PR head; None when absent."""
    if not path:
        return None
    path = Path(path)
    data = path.read_bytes()
    signature = Path(str(path) + '.sig')
    anchor, anchor_facts = observe_anchor()
    lane = {'digest': v2.sha256(data), 'principal': None, 'verdict': None, 'lane': None, 'code': None}
    try:
        record = json.loads(data)
    except ValueError:
        return dict(lane, code='review_lane_binding_mismatch')
    lane['verdict'] = record.get('verdict') if isinstance(record, dict) else None
    lane['lane'] = record.get('lane') if isinstance(record, dict) else None
    if not anchor_facts['present'] or not signature.is_file():
        return dict(lane, code='review_lane_signature_invalid')
    verified = verify_signature(anchor, signature.read_text(), data, v2.NS_REVIEW)
    lane['principal'] = verified['principal']
    if not verified['principal']:
        return dict(lane, code='review_lane_signature_invalid')
    if v2.NS_REVIEW not in verified['namespaces'] or v2.NS_APPROVAL in verified['namespaces']:
        return dict(lane, code='review_lane_role_invalid')
    if not verified['verified']:
        return dict(lane, code='review_lane_signature_invalid')
    binding = {'schema': v2.REVIEW_SCHEMA, 'plan_id': plan_id, 'pr': pull['number'], 'head': pull['head'], 'verdict': 'approve'}
    if not isinstance(record, dict) or any(record.get(k) != v for k, v in binding.items()) or record.get('goal_id') not in goals:
        return dict(lane, code='review_lane_binding_mismatch')
    return lane


# --- v1 inventory (O10) ---------------------------------------------------------------

def v1_inventory(root, ref, adapter):
    """Every v1 registry entry on ref with its fate, decided by inventory_fate from hosted
    merged/open PR head branches, origin branches and merge-commit ancestry only."""
    data = show(root, ref, v2.V1_REGISTRY)
    if data is None:
        return []
    registry = parse_json(data, 'v1_registry')
    v2.check(isinstance(registry, dict) and isinstance(registry.get('plans'), list), 'v1_registry_invalid')
    unobservable, merged, open_prs, branches = None, [], [], []
    try:
        merged, open_prs, branches = adapter.merged_prs(ROUTE_LIMIT), adapter.open_prs(ROUTE_LIMIT), adapter.branches()
        if len(merged) >= ROUTE_LIMIT or len(open_prs) >= ROUTE_LIMIT:
            unobservable = 'hosted_list_truncated'
    except Invalid as error:
        unobservable = v2.code(error)
    merged = [dict(p, reached=ancestry(root, p.get('merge_commit'), ref)) for p in merged]
    branches = [dict(b, merged=ancestry(root, b.get('sha'), ref) is True) for b in branches]
    entries = []
    for entry in registry['plans']:
        try:
            bundle = parse_json(show(root, ref, entry['artifacts']['bundle']['path']), 'v1_bundle')
            goal_ids = [goal['id'] for goal in bundle['goals']]
        except (Invalid, KeyError, TypeError) as error:
            v2.refuse('v1_registry_invalid', '%s: %s' % (entry.get('id') if isinstance(entry, dict) else entry, error))
        fate = v2.inventory_fate(goal_ids, merged, open_prs, branches, unobservable)
        record = dict({'id': entry.get('id'), 'plan_id': entry.get('plan_id'), 'generation': entry.get('generation'),
                       'goals': goal_ids}, **fate)
        if fate['fate'] == 'completed':
            record['retire_record'] = {'id': entry.get('id'), 'plan_id': entry.get('plan_id'),
                                       'generation': entry.get('generation'), 'registry': v2.V1_REGISTRY,
                                       'fate': 'completed', 'merged': fate['merged']}
        entries.append(record)
    return entries


# --- driver provenance (P8) -----------------------------------------------------------

def manifest_paths():
    manifest = json.loads((HERE / 'readiness-dependency-v2.json').read_text())
    peer = HERE.parent / 'northstar'
    if not peer.is_dir():
        peer = HERE.parent.parent / '02-govern-plan/northstar'
    return [peer / name[len('northstar/'):] if name.startswith('northstar/') else HERE / name for name in manifest['files']]


PROVENANCE = ('source-lane', 'base-copy')
PROMINENT = ('in-session', 'agent-self')  # agent-writable assurance levels every report prints prominently (K2, K3)


def checked_provenance(root, target):
    """provenance() with its result checked; callers record it in every report."""
    origin = provenance(root, target)
    v2.check(origin in PROVENANCE, 'driver_provenance_unknown', origin)
    return origin


def provenance(root, target):
    """A driver inside the repository it admits must equal the target branch's copy."""
    driver = git(HERE, 'rev-parse', '--show-toplevel', check=False)
    if driver.returncode:
        return 'source-lane'
    driver_top = Path(driver.stdout.decode().strip()).resolve()
    common = lambda path: Path(git_text(path, 'rev-parse', '--path-format=absolute', '--git-common-dir')).resolve()
    if common(HERE) != common(root):
        return 'source-lane'
    ref = target_ref(target)
    for path in manifest_paths():
        relative = path.resolve().relative_to(driver_top).as_posix()
        blob = show(root, ref, relative)
        v2.check(blob is not None and blob == path.read_bytes(), 'driver_not_base_copy', relative)
    return 'base-copy'


# --- operations -----------------------------------------------------------------------

def admission_inputs(root, ref, handoff, goals, stage, adapter, now, pr=None, review_record=None):
    """Gather every fact for the pure validator; structural failures become gaps."""
    inputs = {'stage': stage, 'goals': goals, 'now': now, 'errors': []}
    try:
        gen = load_generation(root, ref, handoff)
        for gid in goals:
            v2.check(gid in {g['id'] for g in gen['bundle']['goals']}, 'requested_goal_missing', gid)
        v2.check(target_ref(gen['policy']['target']) == ref, 'policy_target_mismatch', gen['policy']['target'])
        carrier = observe_approval(root, ref, gen)
        sidecar_v0 = None
        record = carrier.get('record')
        if isinstance(record, dict) and record.get('sidecar_sha256') != canonical(gen['sidecar']):
            sidecar_v0 = find_sidecar_v0(root, ref, gen['sidecar_path'], record.get('sidecar_sha256'), gen['bundle'])
        inputs.update(registered={'id': gen['entry']['id'], 'generation': gen['entry']['generation'], 'mode': gen['mode'],
                                  'policy_sha256': gen['entry'].get('policy_sha256'),
                                  'anchor_sha256': gen['entry'].get('anchor_sha256'),
                                  'amends_policy_sha256': gen['entry'].get('amends_policy_sha256')},
                      policy=gen['policy'], policy_mode=gen['mode'], live_policy2=gen['live_policy2'],
                      candidate_is_live=gen['candidate_is_live'], live_policy=gen['live_policy'],
                      live_policy_sha256=gen['live_sha256'], bundle=gen['bundle'],
                      sidecar=gen['sidecar'], sidecar_v0=sidecar_v0, digests=gen['digests'], carrier=carrier,
                      observation=observe(root, ref, gen, goals, stage, adapter, now, pr, review_record))
        if gen['mode'] in v2.POLICY_MODES and stage in v2.APPROVED_STAGES and set(goals) & set(v2.policy_goals(gen['bundle'])):
            # O10: the policy goal swaps the policy only while no v1 entry is in flight.
            inputs['v1_inventory'] = [{'id': e['id'], 'fate': e['fate']} for e in v1_inventory(root, ref, adapter)]
        return inputs, gen
    except (Invalid, OSError, KeyError, TypeError, ValueError) as error:
        detail = str(error).split(':', 1)
        inputs['errors'].append({'code': v2.code(error) if isinstance(error, Invalid) else 'admission_failed',
                                 'detail': detail[1] if len(detail) > 1 else str(error)})
        return inputs, None


def op_admit(args, now, adapter):
    root = observed_root(args.root)
    ref = target_ref(args.target)
    origin = checked_provenance(root, args.target)
    adapter = adapter or hosted_adapter_factory(root)
    inputs, _ = admission_inputs(root, ref, args.handoff, args.goal_id, args.stage, adapter, now, args.pr,
                                 args.review_record)
    context = v2.admission(inputs)
    context['provenance'] = origin
    context['observation'] = dict(context['observation'], adapter=adapter.name)
    refusals = []
    for kind, path, rebuilt in (('context', args.context, context), ('observation', args.observation, context['observation']),
                                ('verdict', args.verdict, v2.verdict_of(context))):
        if path:
            try:
                v2.compare_supplied(kind, read_json(path), rebuilt)
            except (Invalid, OSError, ValueError) as error:
                refusals.append({'code': 'supplied_%s_mismatch' % kind, 'detail': str(error)})
    if refusals:
        context = dict(context, admitted=False, refusals=refusals)
    return (0 if context['admitted'] else 1), context


def op_publish(args, now, adapter):
    root = Path(args.root).resolve(strict=True)
    bundle = v2.validate_bundle(read_json(args.bundle))
    sidecar = v2.validate_sidecar(read_json(args.sidecar), bundle)
    held = [gid for gid, entry in sorted(sidecar['goals'].items()) if 'blocked' in entry['readiness'].values()]
    v2.check(not held, 'publication_hold_refused', ','.join(held))
    for goal in bundle['goals']:
        try:
            validate_commands(root, goal['verification'])
        except VerificationError as error:
            v2.refuse('verification_invalid', '%s: %s' % (goal['id'], error))
    live = root / v2.POLICY
    live_bytes = live.read_bytes() if live.is_file() else None
    try:
        live2 = live_bytes is not None and json.loads(live_bytes).get('schema') == v2.POLICY_SCHEMA
    except (ValueError, AttributeError):
        live2 = False
    if args.policy_candidate:
        if live2:
            # While policy/2 is live a candidate is a policy amendment: one goal scoping the fixed path.
            v2.check(len(bundle['goals']) == 1 and v2.policy_goals(bundle), 'bootstrap_policy_live')
            v2.validate_amendment(bundle, True, v2.validate_policy(parse_json(Path(args.policy_candidate).read_bytes(), 'policy')),
                                  v2.validate_policy(parse_json(live_bytes, 'policy')))
            mode = 'policy-amendment'
        else:
            v2.validate_bootstrap(bundle, live_policy2=False)
            mode = 'bootstrap'
        policy_bytes = Path(args.policy_candidate).read_bytes()
    else:
        v2.check(live2, 'policy2_not_live')
        policy_bytes = live_bytes
        v2.validate_live_scope(bundle)
        mode = 'live'
    policy = v2.validate_policy(parse_json(policy_bytes, 'policy'))
    v2.check(policy['repository']['id'] == bundle['repository']['id'], 'policy_repository_mismatch')
    v2.check(policy['approval']['anchor_sha256'] is not None, 'anchor_unset')
    spec = root / bundle['spec']['path']
    v2.check(spec.is_file() and not spec.is_symlink(), 'spec_missing', bundle['spec']['path'])
    digests = {'bundle_sha256': v2.bundle_sha256(bundle), 'spec_sha256': v2.sha256(spec.read_bytes()),
               'policy_sha256': v2.sha256(policy_bytes), 'anchor_sha256': policy['approval']['anchor_sha256']}
    amends = v2.sha256(live_bytes) if mode == 'policy-amendment' else None
    generation = v2.generation_v2(amends_policy_sha256=amends, **digests)
    prefix = '%s/%s/%s' % (v2.GEN, bundle['id'], generation)
    repo = bundle['repository']['id']
    parent = 'handoff:%s:%s:%s' % (repo, bundle['id'], generation)
    graph = {'schema_version': '1.1', 'contract': v2.VERSION, 'generation': generation, 'plan_id': bundle['id'],
             'goal_ids': [g['id'] for g in bundle['goals']],
             'nodes': [{'id': parent, 'type': 'handoff', 'repo_id': repo, 'path': prefix + '/handoff.md'}],
             'edges': []}
    for goal in bundle['goals']:
        node = 'plan:%s:%s:%s:%s' % (repo, bundle['id'], goal['id'], generation)
        graph['nodes'].append({'id': node, 'type': 'plan', 'repo_id': repo, 'path': prefix + '/goals.json',
                               'goal_revision': v2.goal_revision_v2(bundle, goal['id'])})
        graph['edges'].append({'source': parent, 'target': node, 'type': 'plans'})
    handoff = ('# Northstar handoff (%s): %s\n\nGeneration: %s\n\nGoals: %s\n\nPublication grants no authority. '
               'Admission requires one verified plan approval carried by tag approval/%s/%s.\n'
               % (v2.VERSION, bundle['id'], generation, ', '.join(g['id'] for g in bundle['goals']), bundle['id'], generation[:12]))
    dumps = lambda value: (json.dumps(value, indent=2, sort_keys=True) + '\n').encode()
    files = {'goals.json': dumps(bundle), 'sidecar.json': dumps(sidecar), 'graph.json': dumps(graph),
             'handoff.md': handoff.encode()}
    if mode in v2.POLICY_MODES:
        files['policy-candidate.json'] = policy_bytes
    final = root / prefix
    workflows = root / '.ai/workflows'
    workflows.mkdir(parents=True, exist_ok=True)
    lock = workflows / '.northstar-readiness-v2.lock'
    try:
        lock.mkdir()
    except FileExistsError:
        v2.refuse('publication_locked', 'inspect the existing publisher; never steal a lock')
    try:
        if final.exists():
            v2.check(sorted(p.name for p in final.iterdir()) == sorted(files) and
                     all((final / name).read_bytes() == data for name, data in files.items() if name != 'sidecar.json'),
                     'generation_collision', prefix)
        else:
            final.parent.mkdir(parents=True, exist_ok=True)
            staging = Path(tempfile.mkdtemp(prefix='.staging-', dir=final.parent))
            try:
                for name, data in files.items():
                    (staging / name).write_bytes(data)
                staging.rename(final)
            finally:
                if staging.exists():
                    shutil.rmtree(staging)
        artifacts = {name: {'path': prefix + '/' + filename, 'sha256': v2.sha256((final / filename).read_bytes())}
                     for name, filename in (('bundle', 'goals.json'), ('graph', 'graph.json'), ('handoff', 'handoff.md'))}
        artifacts['sidecar'] = {'path': prefix + '/sidecar.json'}
        if mode in v2.POLICY_MODES:
            artifacts['policy_candidate'] = {'path': prefix + '/policy-candidate.json', 'sha256': digests['policy_sha256']}
        entry = {'schema': v2.VERSION, 'id': 'northstar-plan-' + bundle['id'], 'plan_id': bundle['id'],
                 'generation': generation, 'mode': mode, 'status': 'active', 'handoff_path': prefix + '/handoff.md',
                 'artifacts': artifacts, 'spec': {'path': bundle['spec']['path'], 'sha256': digests['spec_sha256']},
                 'policy_sha256': digests['policy_sha256'], 'anchor_sha256': digests['anchor_sha256']}
        if amends is not None:
            entry['amends_policy_sha256'] = amends  # M1: the live policy this amendment amends
        registry_path = root / v2.REGISTRY
        registry = read_json(registry_path) if registry_path.exists() else {'schema': v2.VERSION, 'plans': []}
        v2.check(registry.get('schema') == v2.VERSION and isinstance(registry.get('plans'), list), 'registry_invalid')
        registry['plans'] = [p for p in registry['plans'] if p.get('id') != entry['id']] + [entry]
        temporary = registry_path.with_name('.' + registry_path.name + '.tmp')
        temporary.write_bytes(dumps(registry))
        os.replace(temporary, registry_path)  # registry last: the sole visibility pointer
    finally:
        lock.rmdir()
    return 0, {'schema': v2.VERSION, 'published': entry, 'generation': generation,
               'next': 'merge this publication, then: contract-run.sh approval-request --handoff ' + entry['id']}


def op_approval_request(args, now, adapter):
    root = Path(args.root).resolve(strict=True)
    ref = target_ref(args.target)
    origin = checked_provenance(root, args.target)
    gen = load_generation(root, ref, args.handoff)
    v2.check(1 <= args.days <= gen['policy']['approval']['max_age_days'], 'approval_request_invalid', 'days')
    publication = git_text(root, 'log', '-1', '--format=%H', ref, '--', gen['prefix'])
    v2.check(publication, 'planning_input_not_on_target', gen['prefix'])
    fields = dict(plan_id=gen['bundle']['id'], generation=gen['entry']['generation'],
                  goals=[g['id'] for g in gen['bundle']['goals']], sidecar_sha256=canonical(gen['sidecar']),
                  owner=args.owner, reviewer_lane=args.reviewer_lane, issued_at=v2.stamp(now),
                  expires_at=v2.stamp(now + timedelta(days=args.days)), **gen['digests'])
    if args.assurance == 'agent-self':
        return issue_agent_approval(root, gen, fields, publication, origin)
    record = v2.approval_record(assurance=args.assurance, **fields)
    fallback = v2.approval_record(assurance='in-session', **fields)
    tag = 'approval/%s/%s' % (gen['bundle']['id'], gen['entry']['generation'][:12])
    line, fallback_line = v2.canonical_bytes(record).decode(), v2.canonical_bytes(fallback).decode()
    tag_commands = ['git tag -a --cleanup=verbatim -F approval.msg %s %s' % (tag, publication),
                    'git push origin refs/tags/' + tag]
    notice = v2.render_assurance('in-session') + ' (fallback only; prefer the ssh-tag form)'
    return 0, {
        'schema': 'plan-approval-request/1', 'record': record, 'digest': canonical(record), 'tag': tag,
        'anchor_sha256': gen['digests']['anchor_sha256'], 'publication_commit': publication,
        'assurance': args.assurance, 'notice': notice,
        'commands': {'ssh-tag': [
            "printf '%%s' %s > approval.json" % shlex.quote(line),
            'ssh-keygen -Y sign -f <your approver key> -n %s approval.json' % v2.NS_APPROVAL,
            "printf '%s\\nsignature: %s\\n' \"$(cat approval.json)\" \"$(base64 < approval.json.sig | tr -d '\\n')\" > approval.msg",
            *tag_commands]},
        'fallback': {'assurance': 'in-session', 'record': fallback, 'digest': canonical(fallback), 'commands': [
            "printf '%%s\\ndigest-echo: %%s\\n' %s %s > approval.msg" % (shlex.quote(fallback_line), canonical(fallback)),
            *tag_commands]},
        'signs': False, 'provenance': origin}


def issue_agent_approval(root, gen, fields, publication, origin):
    """K3 agent mode: Autobahn issues the plan-approval/1 itself, signed with the agent key under
    ai-catapult-agent-approval, for the single approval tag. It never writes or pushes the tag."""
    v2.check_form('agent-self', gen['policy'], gen['mode'], gen['live_policy'])
    anchor, facts = observe_anchor()
    v2.check(anchor is not None and not facts['inside_worktree'], 'anchor_missing', 'no usable trust anchor')
    v2.check(facts['sha256'] == gen['digests']['anchor_sha256'], 'anchor_digest_mismatch')
    v2.check(not facts['ambiguous'], 'anchor_principal_ambiguous', ','.join(facts['ambiguous']))
    key, principal = agent_approval_identity(anchor)
    record = v2.approval_record(assurance='agent-self', **fields)
    line = v2.canonical_bytes(record)
    signature = sign(key, v2.NS_AGENT_APPROVAL, line)
    verified = verify_signature(anchor, signature, line, v2.NS_AGENT_APPROVAL)
    v2.check(verified['verified'] and verified['principal'] == principal, 'approval_signing_failed', 'self-verification')
    tag = 'approval/%s/%s' % (gen['bundle']['id'], gen['entry']['generation'][:12])
    message = line.decode() + '\nagent-signature: ' + base64.b64encode(signature.encode()).decode() + '\n'
    return 0, {'schema': 'plan-approval-request/1', 'plan_id': gen['bundle']['id'], 'record': record,
               'digest': canonical(record), 'tag': tag, 'anchor_sha256': gen['digests']['anchor_sha256'],
               'publication_commit': publication, 'assurance': 'agent-self', 'principal': principal,
               'message': message, 'notice': v2.render_assurance('agent-self'),
               'notices': v2.policy_change_notices('agent-self', gen['mode']),
               'commands': {'agent-self': ['git tag -a --cleanup=verbatim -F approval.msg %s %s' % (tag, publication),
                                           'git push origin refs/tags/' + tag]},
               'signs': True, 'provenance': origin}


def run_local_gates(root, goal):
    # Gate scripts start their embedded Python isolated (python3 -I -B), and they also run
    # from a fresh empty directory and receive the PR checkout only through --root: a
    # PR-root json.py can never stand in for a gate's own code.
    with tempfile.TemporaryDirectory(prefix='observer-') as tmp:
        home = Path(tmp) / 'home'
        home.mkdir()
        neutral = Path(tmp) / 'cwd'
        neutral.mkdir()
        record = Path(tmp) / 'goal.json'
        record.write_text(json.dumps({'id': goal['id'], 'verification': goal['verification']}))
        gates = [('tdd-evidence', ['bash', HERE / 'tdd-evidence.sh', '--verify', '--goal', goal['id'], '--root', root]),
                 ('lint-gate', ['bash', HERE / 'lint-gate.sh', '--root', root]),
                 ('local safe CI subset', ['bash', HERE / 'local-ci.sh', '--root', root]),
                 ('ci-gate --verify', ['bash', HERE / 'ci-gate.sh', '--verify', '--root', root, '--goal-record', record])]
        results = []
        for name, argv in gates:
            outcome = command(argv, cwd=neutral, env=gate_env(home))
            if outcome.returncode:
                sys.stderr.write(outcome.stdout.decode(errors='replace') + outcome.stderr.decode(errors='replace'))
            results.append({'name': name, 'exit': outcome.returncode})
        return results


def derive_certificate(root, ref, handoff, goal_id, pr, review_record, adapter, now, certifier=None):
    """Everything a merge certificate binds, re-observed from scratch. At issue the
    certifier is the local agent signing key; at merge it is the verified signer."""
    anchor, _ = observe_anchor()
    head_before, clean_before = tree_state(root)
    inputs, gen = admission_inputs(root, ref, handoff, [goal_id], 'merge', adapter, now, pr, review_record)
    context = v2.admission(inputs)
    refusals = [g['code'] for g in context['gaps']]
    if gen is None:
        return None, context, sorted(set(refusals))
    facts = context['observation']['facts']
    pull, lane = facts['pr']['value'], facts['review_lane']['value']
    key = None
    if certifier is None:
        try:
            key, certifier = signing_identity(anchor)
        except (Invalid, OSError) as error:
            refusals.append(v2.code(error) if isinstance(error, Invalid) else 'certifier_key_unavailable')
    goal = next(g for g in gen['bundle']['goals'] if g['id'] == goal_id)
    gates = run_local_gates(root, goal) if not refusals and clean_before and pull['head'] == head_before else []
    head_after, clean_after = tree_state(root)
    # G3: the snapshot admission took before the gates must still hold after them.
    if worktree_snapshot(root) != facts['worktree_state']['value']:
        refusals.append('worktree_changed_during_gates')
    policy_goal = v2.policy_goals(gen['bundle'])[0] if gen['mode'] in v2.POLICY_MODES and v2.policy_goals(gen['bundle']) else None
    head_policy = show(root, 'HEAD', v2.POLICY)
    refusals += v2.certificate_refusals({
        'clean_before': clean_before, 'clean_after': clean_after, 'head_before': head_before, 'head_after': head_after,
        'pr_head': pull['head'], 'local_gates': gates, 'now': now,
        'runs': facts['checks']['value'], 'required_checks': gen['policy']['required_checks'],
        'skippable_checks': gen['policy']['skippable_checks'],
        'unresolved_threads': facts['threads']['value']['unresolved'], 'review_lane': lane if lane and not lane['code'] else None,
        'certifier': certifier, 'policy_goal': policy_goal, 'goal_id': goal_id,
        'head_policy_sha256': v2.sha256(head_policy) if head_policy is not None else None,
        'policy_sha256': gen['digests']['policy_sha256']})
    refusals += goal_reserved_refusals(root, ref, gen, goal_id, adapter)
    if not gates and not refusals:
        refusals.append('local_gates_not_run')
    approval = context['approval'] or {}
    body = v2.certificate_body(
        repository={'id': gen['policy']['repository']['id'], 'common_dir': facts['repository']['value']['common_dir']},
        plan_id=gen['bundle']['id'], generation=gen['entry']['generation'], goal_id=goal_id,
        approval_digest=approval.get('digest'), assurance=approval.get('assurance') or 'in-session',
        pr=pr, head=pull['head'], base=pull['base'], base_ref=pull['base_ref'],
        merge_admission_digest=canonical(v2.projection(context)), local_gates=gates,
        required_checks=v2.required_check_summary(gen['policy'], facts['checks']['value']),
        unresolved_threads=facts['threads']['value']['unresolved'],
        review_lane={'digest': lane['digest'] if lane else None, 'principal': lane['principal'] if lane else None,
                     'verdict': lane['verdict'] if lane else None},
        admin=gen['policy']['identity_model'] == 'single', adapter=adapter.name, certifier=certifier,
        issued_at=v2.stamp(now))
    return {'body': body, 'key': key, 'anchor': anchor, 'gen': gen, 'approval': approval,
            'certifier': certifier}, context, sorted(set(refusals))


def certificate_path(root, plan_id, goal_id, pr, head):
    return state_dir(root) / 'certificates' / plan_id / goal_id / ('%d-%s.json' % (pr, head))


def op_certify(args, now, adapter):
    root = observed_root(args.root)
    ref = target_ref(args.target)
    origin = checked_provenance(root, args.target)
    adapter = adapter or hosted_adapter_factory(root)
    derived, context, refusals = derive_certificate(root, ref, args.handoff, args.goal_id, args.pr, args.review_record,
                                                    adapter, now)
    if derived and args.goal_record:
        goal = next(g for g in derived['gen']['bundle']['goals'] if g['id'] == args.goal_id)
        if read_json(args.goal_record) != goal:
            refusals.append('execution_record_mismatch')
    result = {'schema': 'merge-certificate-result/1', 'issued': False, 'pr': args.pr, 'plan_id': context.get('plan_id'),
              'goal_id': args.goal_id, 'assurance': context.get('assurance'), 'context_gaps': context['gaps'],
              'notices': v2.policy_change_notices(context.get('assurance'), (context.get('policy') or {}).get('mode')),
              'provenance': origin}
    if refusals:
        result['refusals'] = [{'code': c.split(':', 1)[0], 'detail': c} for c in refusals]
        result['local_gates'] = derived['body']['local_gates'] if derived else []
        return 1, result
    body = derived['body']
    data = v2.canonical_bytes(body)
    signature = sign(derived['key'], v2.NS_CERTIFICATE, data)
    check = verify_signature(derived['anchor'], signature, data, v2.NS_CERTIFICATE)
    v2.check(check['verified'] and check['principal'] == derived['certifier'], 'certificate_signing_failed', 'self-verification')
    path = certificate_path(root, body['plan_id'], body['goal_id'], body['pr'], body['head'])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(body, indent=2, sort_keys=True) + '\n')
    Path(str(path) + '.sig').write_text(signature)
    reviews = state_dir(root) / 'reviews'
    reviews.mkdir(parents=True, exist_ok=True)
    review = Path(args.review_record)
    shutil.copyfile(review, reviews / (body['review_lane']['digest'] + '.json'))
    shutil.copyfile(str(review) + '.sig', reviews / (body['review_lane']['digest'] + '.json.sig'))
    result.update(issued=True, certificate=body, path=str(path), approval_digest=body['approval_digest'],
                  assurance=body['assurance'])
    if body['assurance'] in PROMINENT:
        result['assurance_notice'] = v2.render_assurance(body['assurance'])
    return 0, result


def carries_v2(root, rev):
    """True when rev carries a v2 registry or a readiness-policy/2 at the fixed path."""
    if show(root, rev, v2.REGISTRY) is not None:
        return True
    data = show(root, rev, v2.POLICY)
    try:
        return data is not None and json.loads(data).get('schema') == v2.POLICY_SCHEMA
    except (ValueError, AttributeError):
        return False


def route(cwd, pr, target, adapter):
    """('v1', None) only while no v2 artifact is observable anywhere: on origin/<target>
    (checked against git ls-remote), on the ls-remote commit, or at HEAD. Once one
    exists, every ambiguity refuses; nothing falls back to the verdict path.

    An exact registered goal branch routes to v2. A branch in an active registered plan's
    reserved namespace (its branch_pattern with that plan id, any goal id, case-insensitive)
    refuses. Any other PR takes the v1 lane, and once v2 is live on origin/<target> only when
    its observed diff touches no reserved path or an exception lane covers the touch."""
    top = git(cwd, 'rev-parse', '--show-toplevel', check=False)
    if top.returncode:
        v2.check(pr is None, 'pr_outside_repository', 'merge-authority.sh --pr runs inside the target repository')
        return 'v1', None
    root = Path(top.stdout.decode().strip()).resolve()
    ref = target_ref(target)
    local = git(root, 'rev-parse', '--verify', '--quiet', ref + '^{commit}', check=False)
    local_sha = local.stdout.decode().strip() if local.returncode == 0 else None
    has_head = git(root, 'rev-parse', '--verify', '--quiet', 'HEAD^{commit}', check=False).returncode == 0
    remote_sha = None
    if git(root, 'remote', 'get-url', 'origin', check=False).returncode == 0:
        listed = git(root, 'ls-remote', 'origin', 'refs/heads/' + target, check=False).stdout.split()
        remote_sha = listed[0].decode() if listed else None
    remote_known = remote_sha is not None and git(root, 'cat-file', '-e', remote_sha + '^{commit}', check=False).returncode == 0
    if not ((has_head and carries_v2(root, 'HEAD')) or (local_sha and carries_v2(root, ref))
            or (remote_known and carries_v2(root, remote_sha))):
        return 'v1', None
    v2.check(local_sha is not None, 'target_ref_unobservable', ref + ' is missing while v2 artifacts exist')
    v2.check(remote_sha is not None, 'target_ref_unobservable', 'git ls-remote origin %s returned nothing' % target)
    v2.check(local_sha == remote_sha, 'target_ref_rewound', '%s is %s but origin has %s; fetch first' % (ref, local_sha, remote_sha))
    v2.check(pr is not None, 'pr_required', '%s carries readiness-contract/2 artifacts; every merge-authority call needs --pr' % ref)
    adapter = adapter or hosted_adapter_factory(root)
    pull = adapter.pull(pr)
    v2.check(pull.get('base_ref') == target, 'pr_base_not_target',
             'PR %s targets %s, not %s' % (pr, pull.get('base_ref'), target))
    active = []
    for entry in registry_plans(root, ref):
        if isinstance(entry, dict) and entry.get('status') != 'active':
            continue  # a retired or superseded plan never blocks a --pr call
        try:
            gen = load_generation(root, ref, entry['id'])
        except (Invalid, KeyError, TypeError, OSError) as error:
            v2.refuse('plan_unloadable', '%s: %s' % (entry.get('id') if isinstance(entry, dict) else entry, error))
        pattern = routing_pattern(root, ref, gen)
        for goal in gen['bundle']['goals']:
            if re.fullmatch(v2.fill(pattern, gen['bundle']['id'], goal['id']), pull['head_ref']):
                return 'v2', {'root': root, 'handoff': entry['id'], 'goal_id': goal['id'], 'pull': pull, 'adapter': adapter}
        active.append(v2.plan_namespace(pattern, gen['bundle']['id']))
    for namespace in active:
        v2.check(not re.fullmatch(namespace, pull['head_ref'], re.IGNORECASE), 'v2_branch_without_plan', pull['head_ref'])
    lane, notices, diff_head = non_goal_lane(root, ref, pull, adapter) if carries_v2(root, ref) else ('v1', [], None)
    return 'v1', {'root': root, 'pull': pull, 'lane': lane, 'notices': notices, 'diff_head': diff_head}


def registry_plans(root, rev):
    data = show(root, rev, v2.REGISTRY)
    registry = parse_json(data, 'registry') if data is not None else {'plans': []}
    v2.check(isinstance(registry, dict) and isinstance(registry.get('plans'), list), 'plan_unloadable', 'registry')
    return registry['plans']


# --- reserved paths (O4, O1, U2; review round 1) ----------------------------------------

def fixed_reserved(name):
    """The policy file, the v2 registry and .ai/handoff/readiness-v2/** (P4 matching)."""
    key, gen = path_key(name), path_key(v2.GEN)
    return key in (path_key(v2.POLICY), path_key(v2.REGISTRY)) or key == gen or key.startswith(gen + '/')


def free_planning_path(name):
    """Planning inputs and the local CI contract are never reserved through goal scope."""
    key = path_key(name)
    return (key in (path_key('.ai/traceability/graph.json'), path_key('.ai/ci/local-ci.json'))
            or key.startswith(path_key('docs/specifications/ACTIVE') + '/')
            or re.fullmatch(r'\.ai/handoff/[^/]+-plan-approval(-request\.json|\.md)', key) is not None)


def active_generations(root, rev):
    """Every active registry entry on rev, loaded; an active entry that fails to load refuses."""
    loaded = []
    for entry in registry_plans(root, rev):
        if not isinstance(entry, dict) or entry.get('status') != 'active':
            continue
        try:
            loaded.append(load_generation(root, rev, entry['id']))
        except (Invalid, KeyError, TypeError, OSError) as error:
            v2.refuse('plan_unloadable', '%s at %s: %s' % (entry.get('id'), rev, error))
    return loaded


def bound_specs(root, revs):
    """L5: the spec copies bound by active generations stay reserved, {spec key: registry entry ids}."""
    owners = {}
    for rev in revs:
        for gen in active_generations(root, rev):
            owners.setdefault(path_key(gen['bundle']['spec']['path']), set()).add(gen['entry']['id'])
    return owners


def active_scopes(root, ref, base, adapter):
    """Scope entries of every active goal, the union of what is active at the PR base and at
    origin/<target>. A goal stops being active once a merged PR on its exact goal branch into the
    target has a merge commit that is an ancestor of origin/<target> and descends from the
    generation's publication (M3), queried per goal branch (L4)."""
    scopes = []
    for rev in (ref, base):
        for gen in active_generations(root, rev):
            pattern = routing_pattern(root, rev, gen)
            for goal in gen['bundle']['goals']:
                if any(p['reached'] for p in goal_merges(root, ref, gen, goal['id'], adapter, pattern)):
                    continue
                scopes += [(path_key(s), '%s %s' % (gen['bundle']['id'], goal['id'])) for s in goal['scope']]
    return scopes


def local_changes(root, ref, pull):
    """M2: (objects repository, the PR head's three-dot diff from git objects, renames off and
    submodules included), or None only when every fetch of the PR head fails outright. A fetch
    that lands on another commit than the observed head refuses (pr_head_moved)."""
    try:
        objects = pr_objects(root, pull)
    except Invalid as error:
        if v2.code(error) == 'pr_head_moved':
            v2.refuse('v2_diff_unobservable', str(error))
        return None
    target = git_text(root, 'rev-parse', '--verify', ref + '^{commit}')
    base = git(objects, 'merge-base', target, pull['head'], check=False)
    v2.check(base.returncode == 0, 'v2_diff_unobservable', 'the PR head shares no history with ' + ref)
    return objects, changed_names(objects, base.stdout.decode().strip(), pull['head'])


def changed_names(repo, base, head):
    """Every path a commit range changes, renames off and gitlinks included, plus every reserved
    tree entry that differs (L7: .gitmodules ignore= cannot hide one)."""
    listed = git(repo, 'diff', '--name-only', '--no-renames', '--ignore-submodules=none', '-z', base, head).stdout
    names = {os.fsdecode(name) for name in listed.split(b'\0') if name}
    before, after = reserved_entries(repo, base), reserved_entries(repo, head)
    names.update(name for name in set(before) | set(after) if before.get(name) != after.get(name))
    return sorted(names)


def non_goal_lane(root, ref, pull, adapter):
    """The v1 verdict lane for a non-goal PR once v2 is live on origin/<target>. The hosted
    changed-files list (renames by both names) is unioned with the reserved paths of the head's
    own three-dot diff, and the PR must not move while it is listed. No reserved path may be
    touched, unless the publish-v2 replay or the sidecar-tighten lane covers every touch. The
    policy file and the spec copies bound by active generations are never covered."""
    changed = set()
    for item in adapter.pr_files(pull['number']):
        changed.update(item.get(k) for k in ('filename', 'previous_filename') if item.get(k) is not None)
    v2.check(all(isinstance(name, str) and name for name in changed), 'v2_diff_unobservable', 'changed file names')
    local = local_changes(root, ref, pull)
    again = adapter.pull(pull['number'])
    v2.check((again['head'], again['base']) == (pull['head'], pull['base']), 'v2_diff_unobservable',
             'the PR moved while its files were listed')
    diff_head = pull['head'] if local is not None else None
    replaced = set()
    if local is not None:
        objects, names = local
        specs = bound_specs(root, [ref])
        changed.update(name for name in names if fixed_reserved(name) or path_key(name) in specs)
        before = {p.get('id'): p for p in registry_plans(root, ref) if isinstance(p, dict)}
        after = {p.get('id'): p for p in registry_plans(objects, pull['head']) if isinstance(p, dict)}
        replaced = {plan_id for plan_id in before if plan_id in after and after[plan_id] != before[plan_id]}
    if not changed:
        return 'v1', [], diff_head
    touched = [name for name in changed if path_key(name) == path_key(v2.POLICY)]
    v2.check(not touched, 'v2_scope_outside_goal', 'the policy file merges only through a policy goal certificate')
    v2.check(isinstance(pull['base'], str) and git(root, 'cat-file', '-e', pull['base'] + '^{commit}', check=False).returncode == 0,
             'v2_diff_unobservable', 'the PR base %s is not available; fetch first' % pull['base'])
    specs = bound_specs(root, [ref, pull['base']])
    # R2 L1: the spec of a plan whose entry this PR replaces may change; the replay lane then decides.
    bound = sorted(name for name in changed if path_key(name) in specs and not specs[path_key(name)] <= replaced)
    v2.check(not bound, 'v2_scope_outside_goal', 'spec copies bound by an active generation: ' + ', '.join(bound))
    candidates = [name for name in changed if not fixed_reserved(name) and not free_planning_path(name)]
    if candidates:
        scopes = active_scopes(root, ref, pull['base'], adapter)
        scoped = sorted({'%s (%s)' % (name, goal) for name in candidates for scope, goal in scopes
                         if path_key(name) == scope or path_key(name).startswith(scope + '/')})
        v2.check(not scoped, 'v2_scope_outside_goal', '; '.join(scoped))
    reserved = sorted(name for name in changed if fixed_reserved(name))
    if not reserved:
        return 'v1', [], diff_head
    if all(existing_sidecar(root, ref, pull['base'], name) for name in changed):
        return sidecar_lane(root, ref, pull, sorted(changed)) + (diff_head,)
    return replay_lane(root, ref, pull, adapter) + (diff_head,)


SIDECAR = re.compile(re.escape(v2.GEN) + r'/[A-Za-z0-9][A-Za-z0-9._-]*/[0-9a-f]{64}/sidecar\.json')


def existing_sidecar(root, ref, base, name):
    """The sidecar.json of a generation that exists at the PR base and on origin/<target>."""
    return bool(SIDECAR.fullmatch(name)) and show(root, base, name) is not None and show(root, ref, name) is not None


def pr_objects(root, pull):
    """A repository holding the PR head objects: the root when it has them already, otherwise a
    throwaway repository that borrows the root's objects and fetches only the PR head (P3)."""
    if git(root, 'cat-file', '-e', pull['head'] + '^{commit}', check=False).returncode == 0:
        return root
    scratch = Path(tempfile.mkdtemp(prefix='observer-pr-'))
    atexit.register(shutil.rmtree, scratch, True)
    git(scratch, 'init', '-q', '--bare')
    objects = git_text(root, 'rev-parse', '--path-format=absolute', '--git-path', 'objects')
    (scratch / 'objects/info/alternates').write_text(objects + '\n')
    url = git_text(root, 'remote', 'get-url', 'origin')
    refspecs = (['refs/pull/%d/head' % pull['number']] if isinstance(pull.get('number'), int) else []) + \
        (['refs/heads/' + pull['head_ref']] if pull.get('head_ref') else [])
    for refspec in refspecs:
        fetched = git(scratch, 'fetch', '-q', '--no-tags', url, refspec, check=False)
        if fetched.returncode:
            continue
        got = git(scratch, 'rev-parse', 'FETCH_HEAD', check=False).stdout.decode().strip()
        # The fetched object must be the head being routed on; anything else is a moved head (A-B-A).
        v2.check(got == pull['head'], 'pr_head_moved', '%s is %s, not the observed head %s' % (refspec, got, pull['head']))
        return scratch
    v2.refuse('v2_diff_unobservable', 'the PR head %s cannot be fetched' % pull['head'])


def tree_entries(repo, commit, *paths):
    """{path: (mode, type, oid)} for every entry at or under paths, recursively."""
    listed = git(repo, 'ls-tree', '-r', '-t', '-z', '--full-tree', commit, '--', *paths).stdout
    entries = {}
    for item in listed.split(b'\0'):
        if item:
            meta, name = item.split(b'\t', 1)
            mode, kind, oid = meta.decode().split()
            entries[os.fsdecode(name)] = (mode, kind, oid)
    return entries


def reserved_entries(repo, commit):
    """M6: every non-tree entry of the whole tree that fixed_reserved() matches, case variants
    included (a case-sensitive pathspec would hide them)."""
    return {name: entry for name, entry in tree_entries(repo, commit).items() if entry[1] != 'tree' and fixed_reserved(name)}


def regular_reserved(repo, commit, names):
    """P2: reserved paths and their parents are plain trees and regular files, never a
    symlink or a submodule."""
    entries = tree_entries(repo, commit)
    for name in names:
        parts = name.split('/')
        for depth in range(1, len(parts) + 1):
            prefix = '/'.join(parts[:depth])
            found = entries.get(prefix)
            if found is None:
                break
            expected = ('100644', 'blob') if depth == len(parts) else ('040000', 'tree')
            v2.check(found[:2] == expected, 'v2_scope_outside_goal', '%s is not a regular %s' % (prefix, expected[1]))


def sidecar_lane(root, ref, pull, changed):
    """O1: every changed sidecar.json of an existing generation passes the pinned tighten-only
    check against the PR base and, for a stale base, against the current target's bytes. No
    other reserved entry, case variants included, may differ (M6)."""
    objects = pr_objects(root, pull)
    target = git_text(root, 'rev-parse', '--verify', ref + '^{commit}')
    merge_base = git_text(objects, 'merge-base', target, pull['head'])
    before, after = reserved_entries(objects, merge_base), reserved_entries(objects, pull['head'])
    differing = sorted(name for name in set(before) | set(after) if before.get(name) != after.get(name))
    v2.check(set(differing) <= set(changed) and all(existing_sidecar(root, ref, pull['base'], n) for n in differing),
             'v2_scope_outside_goal', 'reserved entries beyond existing sidecars: ' + ', '.join(sorted(set(differing) - set(changed))))
    regular_reserved(objects, pull['head'], changed)
    for name in changed:
        bundle = v2.validate_bundle(parse_json(show(root, ref, name.rsplit('/', 1)[0] + '/goals.json'), 'bundle'))
        try:
            head = v2.validate_sidecar(parse_json(show(objects, pull['head'], name), 'sidecar'), bundle)
            for rev in (pull['base'], ref):
                v2.sidecar_leq(v2.validate_sidecar(parse_json(show(root, rev, name), 'sidecar'), bundle), head)
        except Invalid as error:
            v2.refuse('v2_sidecar_not_tightening', '%s: %s' % (name, error))
    return 'sidecar-tighten', []


def replay_lane(root, ref, pull, adapter):
    """O4: the reserved-path part of the diff must equal a publish-v2 replay by this pinned
    driver, in a scratch tree built from git objects whose reserved paths are reset to the
    up-to-date base, with the PR head's new goals.json, sidecar.json and optional
    policy-candidate.json as inputs. The whole head tree's reserved entries (case variants
    included) are compared, except the unchanged policy file. A replaced registry entry is
    allowed only for a plan without goal PRs."""
    objects = pr_objects(root, pull)
    base = git_text(root, 'rev-parse', '--verify', ref + '^{commit}')
    v2.check(ancestry(objects, base, pull['head']) is True, 'v2_scope_outside_goal',
             'a publish-v2 replay applies only to a PR that is up to date with ' + ref)
    head_entries = {k: v for k, v in reserved_entries(objects, pull['head']).items() if k != v2.POLICY}
    base_entries = {k: v for k, v in reserved_entries(root, base).items() if k != v2.POLICY}
    generation_dir = lambda name: '/'.join(name.split('/')[:5])
    added = sorted({generation_dir(n) for n in head_entries if n.startswith(v2.GEN + '/')}
                   - {generation_dir(n) for n in base_entries if n.startswith(v2.GEN + '/')})
    v2.check(len(added) == 1, 'v2_scope_outside_goal', 'a replay adds exactly one generation directory, not %d' % len(added))
    regular_reserved(objects, pull['head'], sorted(head_entries))
    with tempfile.TemporaryDirectory(prefix='observer-replay-') as tmp:
        scratch, inputs = Path(tmp) / 'tree', Path(tmp) / 'inputs'
        inputs.mkdir()
        names = {'bundle': 'goals.json', 'sidecar': 'sidecar.json', 'policy_candidate': 'policy-candidate.json'}
        files = {}
        for key, filename in names.items():
            data = show(objects, pull['head'], added[0] + '/' + filename)
            if data is not None:
                files[key] = inputs / filename
                files[key].write_bytes(data)
        v2.check('bundle' in files and 'sidecar' in files, 'v2_scope_outside_goal', 'the new generation lacks its inputs')
        try:
            bundle = v2.validate_bundle(parse_json(files['bundle'].read_bytes(), 'bundle'))
            needed, directories = replay_inputs(bundle)
        except Invalid as error:
            v2.refuse('v2_scope_outside_goal', 'the new generation is not publishable: %s' % error)
        materialize(objects, pull['head'], scratch, needed)
        materialize(root, base, scratch, [n for n, e in tree_entries(root, base).items() if e[1] == 'blob'
                                          and (n in (v2.REGISTRY, v2.POLICY) or n.startswith(v2.GEN + '/'))])
        for directory in directories:
            (scratch / directory).mkdir(parents=True, exist_ok=True)
        replay = argparse.Namespace(root=str(scratch), bundle=str(files['bundle']), sidecar=str(files['sidecar']),
                                    policy_candidate=str(files['policy_candidate']) if 'policy_candidate' in files else None)
        try:
            op_publish(replay, None, adapter)
        except (Invalid, OSError, KeyError, TypeError, ValueError) as error:
            v2.refuse('v2_scope_outside_goal', 'the reserved paths are not a publish-v2 replay: %s' % error)
        replayed = scratch_entries(root, scratch)
    v2.check(replayed == {k: v[0:3:2] for k, v in head_entries.items()}, 'v2_scope_outside_goal',
             'the reserved paths differ from the publish-v2 replay')
    before = {p.get('id'): p for p in registry_plans(root, base) if isinstance(p, dict)}
    after = {p.get('id'): p for p in registry_plans(objects, pull['head']) if isinstance(p, dict)}
    notices = []
    for plan_id in sorted(plan_id for plan_id in before if plan_id in after and after[plan_id] != before[plan_id]):
        old = load_generation(root, base, plan_id)
        pattern = routing_pattern(root, base, old)
        busy = sorted({p['number'] for goal in old['bundle']['goals'] for branch in
                       v2.branch_names(pattern, old['bundle']['id'], goal['id']) for state in ('merged', 'open')
                       for p in adapter.goal_branch_prs(branch, old['policy']['target'], state) if p['head_ref'] == branch},
                      key=str)
        v2.check(not busy, 'v2_scope_outside_goal', '%s has merged or open goal PRs %s' % (plan_id, busy))
        notices.append({'code': 'v2_plan_entry_replaced', 'detail': plan_id})
    return 'publish-v2-replay', notices


def replay_inputs(bundle):
    """L6: the head paths a publish-v2 replay reads besides the reserved paths: the spec copy and
    every verification script, plus the verification working directories."""
    needed, directories = {bundle['spec']['path']}, set()
    for goal in bundle['goals']:
        for entry in goal['verification']:
            cwd, text = ('.', entry) if isinstance(entry, str) else (entry.get('cwd', '.'), entry.get('command', ''))
            try:
                argv = shlex.split(text)
            except ValueError:
                continue
            script = argv[1] if len(argv) > 1 and (argv[0] == 'bash' or (argv[0] == 'python3' and argv[1].startswith('scripts/'))) else None
            if cwd != '.':
                directories.add(cwd)
            if script:
                needed.add(posixpath.normpath(posixpath.join(cwd, script)))
    v2.check(all(safe_tree_name(n) for n in needed | directories), 'v2_scope_outside_goal', 'unsafe verification path')
    return sorted(needed), sorted(directories)


def safe_tree_name(name):
    """L6: a tree path that stays inside the scratch tree and never names a .git directory."""
    return (isinstance(name, str) and bool(name) and not name.startswith('/')
            and all(part not in ('', '.', '..') and part.lower() != '.git' for part in name.split('/')))


def materialize(repo, commit, destination, names):
    """Write exactly the named regular files of commit, streamed blob by blob; unsafe names refuse."""
    wanted = set(names)
    v2.check(all(safe_tree_name(n) for n in wanted), 'v2_scope_outside_goal', 'unsafe tree entry name')
    entries = [(name, mode, oid) for name, (mode, kind, oid) in tree_entries(repo, commit).items()
               if name in wanted and kind == 'blob' and mode in ('100644', '100755')]
    modes = {oid: [] for _, _, oid in entries}
    for name, mode, oid in entries:
        modes[oid].append((name, mode))
    for oid, data in git_blobs(repo, list(modes)):
        for name, mode in modes[oid]:
            path = destination / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            path.chmod(0o755 if mode == '100755' else 0o644)


def git_blobs(repo, oids):
    """Stream (oid, bytes) for each blob through one git cat-file --batch process."""
    env = clean_env()
    env.update(GIT_SETTINGS)
    process = subprocess.Popen(['git', '--no-replace-objects', '-C', str(repo), 'cat-file', '--batch'], env=env,
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        for oid in oids:
            process.stdin.write((oid + '\n').encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().split()
            v2.check(len(header) == 3 and header[1] == 'blob', 'v2_diff_unobservable', 'git cat-file --batch ' + oid)
            data = process.stdout.read(int(header[2]))
            process.stdout.read(1)
            yield oid, data
    finally:
        process.stdin.close()
        process.wait()


def scratch_entries(root, scratch):
    """{path: (mode, oid)} of the registry and .ai/handoff/readiness-v2/** in the scratch tree."""
    found = sorted(p for p in [scratch / v2.REGISTRY, *(scratch / v2.GEN).rglob('*')] if p.is_file() or p.is_symlink())
    if not found:
        return {}
    env = clean_env()
    env.update(GIT_SETTINGS)
    hashed = subprocess.run(['git', '-C', str(root), 'hash-object', '--no-filters', '--stdin-paths'], env=env,
                            input='\n'.join(str(p) for p in found).encode() + b'\n', stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE)
    v2.check(hashed.returncode == 0, 'v2_diff_unobservable', 'git hash-object')
    return {p.relative_to(scratch).as_posix(): ('120000' if p.is_symlink() else '100755' if os.stat(p).st_mode & 0o100
                                                else '100644', oid)
            for p, oid in zip(found, hashed.stdout.decode().split())}


def goal_reserved_refusals(root, ref, gen, goal_id, adapter):
    """H1: a goal PR's own diff (merge-base..head from git objects, renames off) may touch a
    reserved path, or a spec copy bound by an active generation, only inside the goal's bound
    scope, and then only as: the policy goal's policy file; a pinned publish-v2 replay of the
    registry and .ai/handoff/readiness-v2/**; a registry change limited to the top-level
    retired_v1 key, for the policy goal; or a tightening change to an existing sidecar."""
    head = git_text(root, 'rev-parse', '--verify', 'HEAD^{commit}')
    target = git_text(root, 'rev-parse', '--verify', ref + '^{commit}')
    base = git_text(root, 'merge-base', target, head)
    changed = changed_names(root, base, head)
    specs = bound_specs(root, [ref])
    reserved = [name for name in changed if fixed_reserved(name) or path_key(name) in specs]
    if not reserved:
        return []
    goal = next(g for g in gen['bundle']['goals'] if g['id'] == goal_id)
    scope = [path_key(s) for s in goal['scope']]
    inside = lambda name: any(path_key(name) == s or path_key(name).startswith(s + '/') for s in scope)
    policy_goal = gen['mode'] in v2.POLICY_MODES and goal_id in v2.policy_goals(gen['bundle'])
    refusals = ['goal_reserved_path:' + name for name in reserved if not inside(name)
                or (path_key(name) == path_key(v2.POLICY) and not (name == v2.POLICY and policy_goal))]
    handoff = sorted(name for name in reserved if inside(name) and fixed_reserved(name) and path_key(name) != path_key(v2.POLICY))
    if not handoff:
        return refusals
    pull = {'number': None, 'head': head, 'base': base, 'head_ref': None}
    try:
        if policy_goal and handoff == [v2.REGISTRY] and retired_only(root, target, head):
            pass
        elif all(existing_sidecar(root, ref, base, name) for name in handoff):
            sidecar_lane(root, ref, pull, handoff)
        else:
            replay_lane(root, ref, pull, adapter)
    except Invalid:
        refusals += ['goal_reserved_path:' + name for name in handoff]
    return refusals


def retired_only(root, target, head):
    """A registry change limited to the top-level retired_v1 key."""
    before, after = parse_json(show(root, target, v2.REGISTRY), 'registry'), parse_json(show(root, head, v2.REGISTRY), 'registry')
    return isinstance(before, dict) and isinstance(after, dict) and \
        {k: v for k, v in before.items() if k != 'retired_v1'} == {k: v for k, v in after.items() if k != 'retired_v1'}


def op_merge(args, now, adapter):
    cwd = Path(os.getcwd())
    top = git(cwd, 'rev-parse', '--show-toplevel', check=False)
    # P1: provenance first, so a v1-lane decision comes only from a base-copy or source-lane driver.
    origin = checked_provenance(Path(top.stdout.decode().strip()).resolve(), args.target) if top.returncode == 0 else None
    kind, found = route(cwd, args.pr, args.target, adapter)
    if kind == 'v1':
        if not found:
            return EXIT_V1, {'schema': v2.VERSION, 'decision': 'v1', 'detail': 'no readiness-contract/2 PR here; v1 path'}
        head = found['pull']['head']
        v2.check(found.get('diff_head') in (None, head), 'v2_diff_unobservable', 'the decision head is not the diff head')
        return EXIT_V1, {'schema': 'merge-decision/1', 'decision': 'v1', 'pr': args.pr, 'head': head,
                         'diff_head': found.get('diff_head'),
                         'head_ref': found['pull']['head_ref'], 'lane': found['lane'], 'notices': found['notices'],
                         'merge_with': ['--match-head-commit', head], 'provenance': origin,
                         'detail': 'not a readiness-contract/2 goal PR: the v1 adapter decides, and the merge must use '
                                   'gh pr merge --match-head-commit at this head'}
    root, adapter = found['root'], found['adapter']
    ref = target_ref(args.target)
    result = {'schema': 'merge-decision/1', 'decision': 'refused', 'pr': args.pr, 'goal_id': found['goal_id'],
              'handoff': found['handoff'], 'assurance': None, 'notices': []}

    def refused(code_text, detail=''):
        result['refusals'] = [{'code': code_text, 'detail': detail}]
        return EXIT_FAIL_CLOSED, result
    if args.verdict:
        return refused('verdict_refused_for_v2', 'a v2 PR merges only on a re-observed merge certificate')
    if type(adapter) is not GhAdapter:
        return refused('adapter_not_production', adapter.name)
    result['provenance'] = origin
    root = observed_root(root)
    pull = adapter.pull(args.pr)
    gen = load_generation(root, ref, found['handoff'])
    path = certificate_path(root, gen['bundle']['id'], found['goal_id'], args.pr, pull['head'])
    if not path.is_file():
        others = list(path.parent.glob('%d-*.json' % args.pr)) if path.parent.is_dir() else []
        return refused('head_moved' if others else 'certificate_missing', pull['head'])
    stored = parse_json(path.read_bytes(), 'certificate')
    anchor, _ = observe_anchor()
    signature = Path(str(path) + '.sig')
    signed = verify_signature(anchor, signature.read_text(), v2.canonical_bytes(stored), v2.NS_CERTIFICATE) \
        if signature.is_file() and anchor is not None else {'principal': None, 'verified': False, 'namespaces': []}
    if not (signed['principal'] and signed['verified'] and v2.NS_CERTIFICATE in signed['namespaces']
            and v2.NS_APPROVAL not in signed['namespaces']):
        return refused('certificate_signature_invalid', str(signed['principal']))
    certified, observed = stored.get('repository') if isinstance(stored.get('repository'), dict) else {}, common_dir(root)
    if certified.get('common_dir') != observed:
        return refused('certificate_common_dir_mismatch',
                       'certified in %s, merging from %s' % (certified.get('common_dir'), observed))
    result['assurance'] = stored.get('assurance')
    result['notices'] = v2.policy_change_notices(stored.get('assurance'), gen['mode'])
    inputs, _ = admission_inputs(root, ref, found['handoff'], [found['goal_id']], 'merge', adapter, now)
    approval_codes = [g['code'] for g in v2.admission(inputs)['gaps'] if g['source'] == 'plan-approval/1']
    if approval_codes:
        return refused(approval_codes[0], 'the plan approval no longer verifies at merge time')
    review = state_dir(root) / 'reviews' / ('%s.json' % (stored.get('review_lane') or {}).get('digest'))
    derived, context, refusals = derive_certificate(root, ref, found['handoff'], found['goal_id'], args.pr,
                                                    review if review.is_file() else None, adapter, now,
                                                    certifier=signed['principal'])
    rederived = derived['body'] if derived else {}
    differences = v2.certificate_differences(stored, rederived) if derived else ['fields']
    if differences:
        return refused('certificate_claim_mismatch', ','.join(differences))
    if refusals:
        return refused('merge_admission_refused', ','.join(refusals))
    if args.admin:
        if gen['policy']['identity_model'] != 'single':
            return refused('admin_requires_single_identity', gen['policy']['identity_model'])
        if not stored['admin'] or stored['review_lane']['principal'] in (None, stored['certifier']):
            return refused('admin_self_review_refused', 'an admin merge needs an independent agent review lane')
    merged, detail = adapter.merge(args.pr, stored['head'], args.admin)
    if not merged:
        return refused('head_moved_at_merge', detail)
    result.update(decision='merge', head=stored['head'], certificate=str(path), merged_with=['--match-head-commit', stored['head']])
    if stored['assurance'] in PROMINENT:
        result['assurance_notice'] = v2.render_assurance(stored['assurance'])
    return 0, result


def op_audit(args, now, adapter):
    """Re-observe merged v2 PRs: each must carry an agent-signed certificate for its
    merged head. Timing checks and export-evidence belong to a later goal."""
    root = Path(args.root).resolve(strict=True)
    ref = target_ref(args.target)
    origin = checked_provenance(root, args.target)
    adapter = adapter or hosted_adapter_factory(root)
    report = {'schema': 'merge-audit/1', 'provenance': origin, 'adapter': adapter.name, 'prs': [], 'findings': [],
              'notices': []}
    if type(adapter) is not GhAdapter:
        report['refusals'] = [{'code': 'adapter_not_production', 'detail': adapter.name}]
        return EXIT_FAIL_CLOSED, report
    gen = load_generation(root, ref, args.handoff)
    report.update(plan_id=gen['bundle']['id'], generation=gen['entry']['generation'])
    merged = adapter.merged_prs()
    if len(merged) >= AUDIT_LIMIT:
        report['refusals'] = [{'code': 'audit_unobservable', 'detail': 'merged PR list reached %d' % AUDIT_LIMIT}]
        return EXIT_FAIL_CLOSED, report
    anchor, anchor_facts = observe_anchor()
    if anchor is None or anchor_facts['ambiguous']:
        report['refusals'] = [{'code': 'audit_unobservable', 'detail': 'no usable trust anchor'}]
        return EXIT_FAIL_CLOSED, report
    # M5: assurance is recomputed from the approval tag itself, never taken from a certificate.
    carrier = observe_approval(root, ref, gen)
    tag_digest = canonical(carrier['record']) if isinstance(carrier.get('record'), dict) else None
    tag_assurance = v2.carrier_assurance(carrier)
    for pull in sorted(merged, key=lambda p: p['number'] or 0):
        goal = next((g['id'] for g in gen['bundle']['goals'] if isinstance(pull['head_ref'], str) and
                     re.fullmatch(v2.fill(gen['policy']['branch_pattern'], gen['bundle']['id'], g['id']), pull['head_ref'])), None)
        if goal is None:
            continue
        entry = {'pr': pull['number'], 'goal_id': goal, 'head': pull['head'], 'merge_commit': pull['merge_commit'],
                 'certificate': None, 'approval_digest': None, 'assurance': None, 'lane_independence': None, 'flags': []}
        path = certificate_path(root, gen['bundle']['id'], goal, pull['number'], str(pull['head']))
        others = sorted(path.parent.glob('%d-*.json' % pull['number'])) if path.parent.is_dir() else []
        if not path.is_file():
            entry['flags'].append('certified_head_mismatch' if others else 'merged_without_certificate')
        else:
            certificate = parse_json(path.read_bytes(), 'certificate')
            signature = Path(str(path) + '.sig')
            signed = verify_signature(anchor, signature.read_text(), v2.canonical_bytes(certificate), v2.NS_CERTIFICATE) \
                if signature.is_file() else {'principal': None, 'verified': False, 'namespaces': []}
            if not (signed['principal'] and signed['verified'] and v2.NS_CERTIFICATE in signed['namespaces']
                    and v2.NS_APPROVAL not in signed['namespaces']):
                entry['flags'].append('certificate_signature_invalid')
            if certificate.get('head') != pull['head'] or certificate.get('pr') != pull['number']:
                entry['flags'].append('certified_head_mismatch')
            observed = tag_assurance if certificate.get('approval_digest') == tag_digest else None
            if certificate.get('approval_digest') != tag_digest:
                entry['flags'].append('approval_digest_unobserved')
            elif observed != certificate.get('assurance'):
                entry['flags'].append('assurance_mismatch')
            entry.update(certificate=str(path), approval_digest=certificate.get('approval_digest'), assurance=observed,
                         certified_assurance=certificate.get('assurance'),
                         lane_independence=certificate.get('lane_independence'))
            if entry['assurance'] in PROMINENT:
                entry['assurance_notice'] = v2.render_assurance(entry['assurance'])
            entry['notices'] = v2.policy_change_notices(entry['assurance'], gen['mode'])
            report['notices'] += [dict(n, detail='PR %s: %s' % (pull['number'], n['detail'])) for n in entry['notices']]
        report['prs'].append(entry)
        report['findings'] += [{'code': flag, 'detail': 'PR %s' % pull['number']} for flag in entry['flags']]
    return (1 if report['findings'] else 0), report


def op_inventory(args, now, adapter):
    """O10: decide every v1 registry entry's fate on origin/<target>; exit 1 while any is in flight."""
    root = Path(args.root).resolve(strict=True)
    ref = target_ref(args.target)
    origin = checked_provenance(root, args.target)
    adapter = adapter or hosted_adapter_factory(root)
    report = {'schema': 'v1-inventory/1', 'registry': v2.V1_REGISTRY, 'target': ref,
              'target_revision': git_text(root, 'rev-parse', '--verify', ref + '^{commit}'), 'adapter': adapter.name,
              'provenance': origin, 'entries': v1_inventory(root, ref, adapter)}
    busy = [entry['id'] for entry in report['entries'] if entry['fate'] == 'in-flight']
    if busy:
        report['refusals'] = [{'code': 'v1_inventory_in_flight', 'detail': ', '.join(busy)}]
        return 1, report
    return 0, report


def op_reserved(args, now, adapter):
    return 2, {'schema': v2.VERSION, 'refusals': [{'code': 'operation_not_in_this_release', 'detail': args.operation}]}


HANDLERS = {'admit-v2': op_admit, 'publish-v2': op_publish, 'approval-request': op_approval_request,
            'certify-v2': op_certify, 'merge-v2': op_merge, 'audit-merges': op_audit, 'inventory-v1': op_inventory}


def parser():
    # No help action: argparse help exits 0, and exit 0 means "authorized: merge" to merge-authority.sh.
    main_parser = argparse.ArgumentParser(prog='contract-run.sh (readiness-contract/2)', allow_abbrev=False, add_help=False)
    operations = main_parser.add_subparsers(dest='operation', required=True)

    def operation(name):
        return operations.add_parser(name, allow_abbrev=False, add_help=False,
                                     prog='contract-run.sh %s (readiness-contract/2)' % name)
    admit = operation('admit-v2')
    admit.add_argument('--root', required=True)
    admit.add_argument('--handoff', required=True)
    admit.add_argument('--goal-id', action='append', required=True)
    admit.add_argument('--stage', choices=('planning', *v2.STAGES), default='implementation')
    admit.add_argument('--target', default='main')
    admit.add_argument('--pr', type=int)
    admit.add_argument('--review-record')
    admit.add_argument('--context')
    admit.add_argument('--observation')
    admit.add_argument('--verdict')
    publish = operation('publish-v2')
    publish.add_argument('--root', required=True)
    publish.add_argument('--bundle', required=True)
    publish.add_argument('--sidecar', required=True)
    publish.add_argument('--policy-candidate')
    request = operation('approval-request')
    request.add_argument('--root', required=True)
    request.add_argument('--handoff', required=True)
    request.add_argument('--owner', required=True)
    request.add_argument('--reviewer-lane', required=True)
    request.add_argument('--target', default='main')
    request.add_argument('--days', type=int, default=v2.MAX_AGE_DAYS)
    request.add_argument('--assurance', choices=('key-held', 'user-presence', 'agent-self'), default='key-held')
    certify = operation('certify-v2')
    certify.add_argument('--root', required=True)
    certify.add_argument('--handoff', required=True)
    certify.add_argument('--goal-id', required=True)
    certify.add_argument('--pr', type=int, required=True)
    certify.add_argument('--review-record')
    certify.add_argument('--goal-record')
    certify.add_argument('--target', default='main')
    merge = operation('merge-v2')
    merge.add_argument('--pr', type=int)
    merge.add_argument('--verdict')
    merge.add_argument('--admin', action='store_true')
    merge.add_argument('--target', default='main')
    audit = operation('audit-merges')
    audit.add_argument('--root', required=True)
    audit.add_argument('--handoff', required=True)
    audit.add_argument('--target', default='main')
    inventory = operation('inventory-v1')
    inventory.add_argument('--root', required=True)
    inventory.add_argument('--target', default='main')
    for name in RESERVED:
        operation(name)
    return main_parser


def log_root(operation, root_arg):
    """The repository whose observer state records a run: --root, or the cwd for merge-v2."""
    if operation == 'merge-v2':
        top = git(Path(os.getcwd()), 'rev-parse', '--show-toplevel', check=False)
        return Path(top.stdout.decode().strip()) if top.returncode == 0 else None
    return Path(root_arg).resolve(strict=True) if root_arg else None


def log_exit(operation, root_arg, code, result, goal_id=None, pr=None):
    """Append every driver exit code (usage errors included) to the driver log."""
    try:
        root = log_root(operation, root_arg)
        if root is None:
            return
        directory = state_dir(root)
        directory.mkdir(parents=True, exist_ok=True)
        entry = {'at': v2.stamp(datetime.now(timezone.utc)), 'op': operation, 'exit': code,
                 'plan_id': result.get('plan_id'), 'goal_id': result.get('goal_id') or goal_id, 'pr': pr,
                 'assurance': result.get('assurance'), 'provenance': result.get('provenance'),
                 'codes': sorted({r['code'] for r in result.get('refusals', []) + result.get('gaps', [])
                                  + result.get('findings', [])})}
        with (directory / 'driver-log.jsonl').open('a') as handle:
            handle.write(json.dumps(entry, sort_keys=True) + '\n')
    except (Invalid, OSError):
        pass


def run(argv, now=None, adapter=None):
    """Parse, run one operation, log the exit code. Unknown arguments exit 2; any
    unexpected error refuses (merge-v2 fails closed with 4). Every run is logged."""
    try:
        args = parser().parse_args(argv)
    except SystemExit:
        # Every parser exit is a usage refusal; nothing argparse does may yield exit 0.
        result = {'schema': v2.VERSION, 'refusals': [{'code': 'usage', 'detail': 'unknown or missing argument'}]}
        operation = argv[0] if argv and argv[0] in LOGGED else None
        if operation:
            root_arg = argv[argv.index('--root') + 1] if '--root' in argv[:-1] else None
            log_exit(operation, root_arg, 2, result)
        return 2, result
    now = now or datetime.now(timezone.utc).replace(microsecond=0)
    handler = HANDLERS.get(args.operation, op_reserved)
    try:
        code, result = handler(args, now, adapter)
    except Exception as error:  # noqa: BLE001 - every failure is a refusal, never a crash or an exit 0
        code_text = v2.code(error) if isinstance(error, Invalid) else 'operation_failed'
        code = EXIT_FAIL_CLOSED if args.operation == 'merge-v2' else 1
        result = {'schema': v2.VERSION, 'refusals': [{'code': code_text, 'detail': '%s: %s' % (type(error).__name__, error)}]}
    if args.operation in LOGGED and code != EXIT_V1:
        log_exit(args.operation, getattr(args, 'root', None), code, result, getattr(args, 'goal_id', None),
                 getattr(args, 'pr', None))
    return code, result


def main(argv):
    code, result = run(argv)
    if code == EXIT_V1:
        if result.get('head'):
            # U2: a v1-lane decision prints the observed head before the v1 adapter runs.
            print(json.dumps(result, indent=2, sort_keys=True))
        return code
    print(json.dumps(result, indent=2, sort_keys=True))
    notice = result.get('assurance_notice') or result.get('notice')
    if notice:
        print(notice, file=sys.stderr)
    if result.get('refusals'):
        print('readiness-contract/2: refused (%s)' % ', '.join(r['code'] for r in result['refusals']), file=sys.stderr)
    return code
