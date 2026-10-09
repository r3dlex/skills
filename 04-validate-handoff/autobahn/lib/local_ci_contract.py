"""Read reviewed local CI declarations without interpreting hosted workflows."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shlex
import sys

from verification import validate, VerificationError


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, 'duplicate JSON key: ' + key)
        result[key] = value
    return result


def source(root, name):
    require(isinstance(name, str) and name and '\\' not in name, 'invalid source path')
    path = PurePosixPath(name)
    require(not path.is_absolute() and path.as_posix() == name
            and all(part not in ('', '.', '..') for part in name.split('/')),
            'source path must be normalized and repository-relative')
    current = root
    for part in path.parts:
        current = current / part
        require(not current.is_symlink(), 'symlink source forbidden: ' + name)
    require(current.is_file() and root in current.resolve(strict=True).parents,
            'source must be a contained regular file: ' + name)
    return current


def pins(root, values, label):
    require(isinstance(values, dict) and values, label + ' must be a nonempty hash map')
    for name, expected in values.items():
        require(isinstance(expected, str) and re.fullmatch('[0-9a-f]{64}', expected),
                'invalid SHA256: ' + name)
        require(hashlib.sha256(source(root, name).read_bytes()).hexdigest() == expected,
                'stale source SHA256: ' + name)


SCHEMAS = ('local-ci/1', 'local-ci/2')
FIELDS = {'schema', 'workflows', 'sources', 'verification'}
BOOTSTRAP_NPM = ('npm ci', 'npm ci --ignore-scripts')
GLOB_CHARACTER = re.compile(r'[*?\[]')


def declared_path(value, label):
    """One declared dependency or output: a unique, normalized, repository-relative literal path
    with no glob character, no `..` and no .git component in any letter case."""
    require(isinstance(value, str) and value and '\\' not in value,
            label + ' entries must be nonempty literal paths')
    path = PurePosixPath(value)
    require(not path.is_absolute() and path.as_posix() == value and not value.endswith('/')
            and all(part not in ('', '.', '..') for part in value.split('/')),
            label + ' paths must be normalized and repository-relative')
    require(not GLOB_CHARACTER.search(value), label + ' path has a glob character: ' + value)
    require(not any(part.casefold() == '.git' for part in value.split('/')),
            label + ' path has a .git component: ' + value)
    return value


def validate_workspace(record):
    """The workspace block of a local-ci/2 record: exactly bootstrap, dependencies and outputs;
    each bootstrap entry one of the three allowlisted forms; the declared paths validated."""
    workspace = record['workspace']
    require(isinstance(workspace, dict) and set(workspace) == {'bootstrap', 'dependencies', 'outputs'},
            'local-ci/2 requires a workspace object with exactly bootstrap, dependencies and outputs')
    bootstrap = workspace['bootstrap']
    require(isinstance(bootstrap, list), 'bootstrap must be a list of the allowlisted install commands')
    for entry in bootstrap:
        require(isinstance(entry, str), 'bootstrap entries must be the allowlisted command strings')
        if entry in BOOTSTRAP_NPM:
            require('package-lock.json' in record['sources'] or 'npm-shrinkwrap.json' in record['sources'],
                    'an npm bootstrap requires a pinned package-lock.json or npm-shrinkwrap.json')
        else:
            require(entry.startswith('bash '),
                    'bootstrap admits only npm ci, npm ci --ignore-scripts and bash <pinned source>')
            name = entry[len('bash '):]
            require(name and ' ' not in name, 'bash bootstrap must name exactly one pinned source path')
            require(name in record['sources'], 'bash bootstrap path is not a pinned source: ' + name)
    declared = []
    for label in ('dependencies', 'outputs'):
        values = workspace[label]
        require(isinstance(values, list), label + ' must be a list of repository-relative paths')
        entries = [declared_path(value, label) for value in values]
        require(len(set(entries)) == len(entries),
                label + ' paths must not nest or repeat: no entry may equal another')
        declared.append([(label, value) for value in entries])
    entries = declared[0] + declared[1]
    for left_label, left in entries:
        for right_label, right in entries:
            if (left_label, left) == (right_label, right):
                continue
            require(left != right, 'declared paths must be unique: ' + left)
            require(not (left.startswith(right + '/') or right.startswith(left + '/')),
                    'declared paths must not nest: ' + left)
    return workspace


def read_record(root):
    """The validated local CI contract record. local-ci/1 is exactly its four fields; local-ci/2
    is exactly the local-ci/1 fields plus a validated workspace object."""
    record = json.loads(source(root, '.ai/ci/local-ci.json').read_text(), object_pairs_hook=unique_object)
    require(isinstance(record, dict) and record.get('schema') in SCHEMAS, 'unsupported local CI schema')
    if record['schema'] == 'local-ci/2':
        require(set(record) == FIELDS | {'workspace'},
                'local-ci/2 has unknown or missing fields: it requires exactly the local-ci/1 fields plus a workspace object')
        validate_workspace(record)
    else:
        require(set(record) == FIELDS, 'local CI contract has unknown or missing fields')
    discovered = set()
    github = root / '.github/workflows'
    require(not (root / '.github').is_symlink() and not github.is_symlink(), 'symlink workflow directory forbidden')
    if github.exists():
        require(github.is_dir(), 'workflow directory is not a directory')
        discovered.update(str(p.relative_to(root)) for p in github.iterdir() if p.suffix in ('.yml', '.yaml'))
    for name in ('azure-pipelines.yml', 'azure-pipelines.yaml', '.azure-pipelines.yml',
                 '.azure-pipelines.yaml', '.gitlab-ci.yml', '.gitlab-ci.yaml'):
        path = root / name
        if path.exists() or path.is_symlink():
            discovered.add(name)
    pins(root, record['workflows'], 'workflows')
    require(set(record['workflows']) == discovered, 'workflow inventory is incomplete or stale')
    pins(root, record['sources'], 'sources')
    validated = validate(root, record['verification'])
    for text, argv, cwd in validated:
        original = shlex.split(text)
        if original[0] == 'bash' or (original[0] == 'python3' and original[1].startswith('scripts/')):
            name = (cwd / original[1]).relative_to(root).as_posix()
            source(root, name)
            require(name in record['sources'], 'command script is not pinned: ' + name)
    return record


def read_contract(root):
    return read_record(root)['verification']


def read_declaration(root):
    """The validated workspace declaration of a local-ci/2 contract, or None for local-ci/1
    (which declares nothing)."""
    record = read_record(root)
    return record['workspace'] if record['schema'] == 'local-ci/2' else None


if __name__ == '__main__':
    try:
        print(json.dumps(read_contract(Path(sys.argv[1]).resolve(strict=True))))
    except (OSError, ValueError, VerificationError) as error:
        print('local-ci: invalid explicit contract: ' + str(error), file=sys.stderr)
        sys.exit(1)
