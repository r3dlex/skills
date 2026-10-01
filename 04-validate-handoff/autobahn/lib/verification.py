"""Pure shared command validation. Does not run verification or fixture commands."""
import json
import os
import re
import shlex
import sys
from pathlib import Path, PurePosixPath

FORBIDDEN = re.compile(r'[;&|`$><\n\\]|\$\(')
TRAVERSAL = re.compile(r'(^|[/\s])\.\.([/\s]|$)')
CONTROL = re.compile(r'[\x00-\x1f\x7f]')
SAFE_TASK = re.compile(r'^(test|lint|check|typecheck|build|verify|validate|coverage|ci)(?:$|[:._-])', re.I)
DELIVERY_TASK = re.compile(r'(deploy|publish|release|promote|ship|upload)', re.I)
EXACT_COMMANDS = {
    ('pytest',),
    ('pytest', '-q'),
    ('npm', 'test'),
    ('prek', 'run'),
    ('prek', 'run', '--all-files'),
    ('python3', '-m', 'pytest'),
    ('python3', '-m', 'pytest', '-q'),
    ('python3', '-m', 'pytest', '--version'),
    ('python3', '-m', 'unittest'),
    ('python3', '-m', 'unittest', '-v'),
    ('python3', '-m', 'unittest', 'discover'),
    ('python3', '-m', 'unittest', '--help'),
    ('git', 'diff', '--check'),
    ('docker', 'compose', 'config'),
    ('bash', 'scripts/archgate.sh', '--mode', 'structural', '--rules', '.rules.ts', '--format', 'json'),
    ('bash', 'scripts/check-put-tenant-prefix-allowlist.sh'),
    ('python3', 'scripts/validate-obra-coverage-roadmap.py'),
    ('python3', 'scripts/validate-cross-repo-regression-fixtures.py'),
    ('mix', 'compile', '--warnings-as-errors'),
    ('mix', 'coveralls'),
    ('mix', 'credo', '--strict'),
    ('mix', 'dialyzer'),
    ('mix', 'format', '--check-formatted'),
    ('mix', 'test'),
    ('mix', 'test', '--warnings-as-errors'),
    ('cargo', 'clippy', '--all-targets', '--all-features', '--', '-D', 'warnings'),
    ('cargo', 'fmt', '--check'),
    (
        'cargo', 'llvm-cov', '--all-features', '--summary-only',
        '--ignore-filename-regex', 'src/bin/xtask.rs', '--fail-under-lines', '95',
        '--fail-under-functions', '95', '--fail-under-regions', '95',
    ),
    ('cargo', 'run', '--bin', 'xtask', '--', 'fixtures', 'verify'),
    ('cargo', 'test', '--all-features'),
    ('poetry', 'run', 'pipeline-runner', 'archgate'),
    ('poetry', 'run', 'pipeline-runner', 'check'),
    ('poetry', 'run', 'pipeline-runner', 'lint'),
    ('poetry', 'run', 'pipeline-runner', 'spec-check'),
    ('poetry', 'run', 'pipeline-runner', 'test'),
    ('poetry', 'run', 'pytest'),
    (
        'poetry', 'run', 'pytest', '-v', '--cov=solera_ai',
        '--cov-report=term-missing', '--cov-fail-under=80',
    ),
    ('poetry', 'run', 'ruff', 'check', '.'),
}


def stop(code, message):
    raise VerificationError(code, message)


def allowed(argv):
    command = tuple(argv)
    if command in EXACT_COMMANDS:
        return True
    if len(argv) == 3 and argv[:2] == ['npm', 'run']:
        target = argv[2]
        return SAFE_TASK.match(target) is not None and DELIVERY_TASK.search(target) is None
    if len(argv) >= 2 and argv[0] == 'bash' and argv[1].startswith('tests/'):
        return argv[1] != 'tests/'
    if len(argv) == 3 and argv[:2] == ['moon', 'run']:
        target = argv[2]
        task = target.rsplit(':', 1)[-1]
        return SAFE_TASK.match(task) is not None and DELIVERY_TASK.search(target) is None
    return False


def find_executable(name, cwd):
    for directory in os.environ.get('PATH', '').split(os.pathsep):
        base = Path(directory) if directory and Path(directory).is_absolute() else cwd / directory
        candidate = base / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate.resolve())
    return None


class VerificationError(ValueError):
    def __init__(self, code, message):
        super().__init__(message)
        self.code = code


def validate(root, entries):
    root = Path(root).resolve(strict=True)
    if not isinstance(entries, list) or not entries:
        stop(2, 'goal record has no non-empty verification[] array')

    validated = []
    for index, entry in enumerate(entries):
        if isinstance(entry, str):
            cwd_text = '.'
            command_raw = entry
            command_text = entry.strip()
        elif isinstance(entry, dict):
            if set(entry) != {'cwd', 'command'}:
                stop(2, f'verification[{index}] object must have exactly cwd and command keys')
            cwd_text = entry['cwd']
            command_raw = entry['command']
            command_text = command_raw
            if not isinstance(cwd_text, str) or not cwd_text.strip():
                stop(2, f'verification[{index}].cwd must be a non-empty string')
            if not isinstance(command_text, str) or not command_text.strip():
                stop(2, f'verification[{index}].command must be a non-empty string')
            if cwd_text != cwd_text.strip():
                stop(3, f'verification[{index}].cwd must be normalized')
            command_text = command_text.strip()
        else:
            stop(2, f'verification[{index}] must be a non-empty string or exact object')

        if not command_text:
            stop(2, f'verification[{index}] command must be a non-empty string')
        if CONTROL.search(command_raw) or CONTROL.search(cwd_text):
            stop(3, f'verification[{index}] contains an ASCII control character')
        if FORBIDDEN.search(command_text):
            stop(3, f'verification[{index}] command contains shell metacharacters')
        if TRAVERSAL.search(command_text):
            stop(3, f'verification[{index}] command contains path traversal')

        if cwd_text == '.':
            command_cwd = root
        else:
            cwd_path = PurePosixPath(cwd_text)
            if (
                cwd_path.is_absolute()
                or cwd_path.as_posix() != cwd_text
                or '\\' in cwd_text
                or any(part in ('', '.', '..') for part in cwd_text.split('/'))
            ):
                stop(3, f'verification[{index}].cwd must be a normalized relative descendant')
            try:
                command_cwd = (root / cwd_path).resolve(strict=True)
            except OSError as error:
                stop(3, f'verification[{index}].cwd is unreadable: {error}')
            if not command_cwd.is_dir() or root not in command_cwd.parents:
                stop(3, f'verification[{index}].cwd escapes the owning root')

        try:
            argv = shlex.split(command_text, posix=True)
        except ValueError as error:
            stop(2, f'verification[{index}] command cannot be parsed: {error}')
        if not argv or not allowed(argv):
            stop(3, f'verification[{index}] command is not allowlisted: {command_text!r}')

        script_arg = None
        if argv[0] == 'bash':
            script_arg = argv[1]
        elif len(argv) >= 2 and argv[0] == 'python3' and argv[1].startswith('scripts/'):
            script_arg = argv[1]
        if script_arg is not None:
            try:
                script = (command_cwd / script_arg).resolve(strict=True)
            except OSError as error:
                stop(3, f'verification[{index}] script is unreadable: {error}')
            if not script.is_file() or (script != root and root not in script.parents):
                stop(3, f'verification[{index}] script escapes the owning root')

        executable = find_executable(argv[0], command_cwd)
        if executable is None:
            stop(3, f'verification[{index}] executable is unavailable: {argv[0]}')
        argv[0] = executable
        validated.append((command_text, argv, command_cwd))

    return validated
