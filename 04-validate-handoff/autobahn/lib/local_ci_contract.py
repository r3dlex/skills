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


def read_contract(root):
    record = json.loads(source(root, '.ai/ci/local-ci.json').read_text(), object_pairs_hook=unique_object)
    require(isinstance(record, dict) and set(record) == {'schema', 'workflows', 'sources', 'verification'},
            'local CI contract has unknown or missing fields')
    require(record['schema'] == 'local-ci/1', 'unsupported local CI schema')
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
    return record['verification']


if __name__ == '__main__':
    try:
        print(json.dumps(read_contract(Path(sys.argv[1]).resolve(strict=True))))
    except (OSError, ValueError, VerificationError) as error:
        print('local-ci: invalid explicit contract: ' + str(error), file=sys.stderr)
        sys.exit(1)
