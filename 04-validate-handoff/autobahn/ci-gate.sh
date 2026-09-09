#!/usr/bin/env bash
#
# ci-gate.sh — derive the repo's real CI commands, and execute a goal record's
# verification[] array.
#
# `--derive` is inventory only. `--derive-json` exposes a strict safe local
# subset for local-ci.sh; `--verify` prevalidates and executes verification[].
#
# Usage:
#   ci-gate.sh --derive --root <dir>       # inventory only
#   ci-gate.sh --derive-json --root <dir>  # strict executable subset
#   ci-gate.sh --verify --root <dir> --goal-record <path>
#
# Exit codes: 0 success; 1 blocked (fail closed); 2 usage error.

set -uo pipefail

MODE=""
ROOT="."
RECORD=""

usage() { echo "ci-gate: $1" >&2; exit 2; }
block() { echo "ci-gate: BLOCKED — $1" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --derive|--derive-json|--verify)
      [[ -n "$MODE" ]] && usage "only one mode may be given"
      MODE="${1#--}"; shift ;;
    --root)        ROOT="${2:-}";   shift 2 || usage "--root needs a value" ;;
    --goal-record) RECORD="${2:-}"; shift 2 || usage "--goal-record needs a value" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$MODE" ]] || usage "one of --derive, --derive-json, --verify is required"
[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"

# --- derivation -------------------------------------------------------------
#
# The reader is deliberately narrow (decision 10): this repo has no YAML
# dependency and is not gaining one. It accepts two-space-indented
# jobs:/steps:/run: and refuses anything else rather than guessing. A parser
# that guesses at a construct it does not understand produces a command list
# that looks authoritative and is wrong.
derive_commands() {
  ROOT="$ROOT" DERIVE_FORMAT="$1" python3 - <<'PY'
import json, os, re, sys
from pathlib import Path

root = Path(os.environ['ROOT'])

# Provider precedence: GitHub first. Where several exist, GitHub's checks are
# the ones gating the PR, so deriving another provider's commands would verify
# something the merge does not depend on.
github = sorted((root / '.github' / 'workflows').glob('*.y*ml')) \
    if (root / '.github' / 'workflows').is_dir() else []
providers = [
    ('github', github),
    ('azure', [p for p in (root / 'azure-pipelines.yml', root / '.azure-pipelines.yml') if p.is_file()]),
    ('gitlab', [p for p in (root / '.gitlab-ci.yml',) if p.is_file()]),
]
provider, files = next(((name, paths) for name, paths in providers if paths), (None, []))
if not provider:
    sys.stderr.write('no CI configuration found (.github/workflows, azure-pipelines.yml, .gitlab-ci.yml)\n')
    raise SystemExit(2)

# The narrow-reader rule is provider-independent: a guessed ADO command is
# exactly as wrong as a guessed GitHub one.
UNSUPPORTED = (
    (re.compile(r'^\s*\S+\s*:\s*&\S+'), 'YAML anchors'),
    (re.compile(r'^\s*(<<\s*:|-\s*<<\s*:)'), 'YAML merge keys'),
    (re.compile(r'^\s*\*\S+\s*$'), 'YAML aliases'),
    (re.compile(r'^---\s*$'), 'multi-document YAML'),
    (re.compile(r'^\t'), 'tab indentation'),
)

# A block scalar's body sits on following lines. Matching only the marker used to
# drop those commands entirely while --derive still exited 0 — an incomplete list
# presented as the repo's CI. `run: |` is how nearly every real workflow writes a
# multi-command step, so refusing it would make the gate unusable; the body has
# to be read.
BLOCK_MARKER = re.compile(r'^[|>][-+]?\d*$')

# A trailing YAML comment is not part of the command. Only strip ` #...` with
# preceding whitespace: a bare `#` inside a command (a fragment, a sed pattern)
# is not a comment.
COMMENT = re.compile(r'\s+#.*$')

EXEC_TOP = (
    re.compile(r'^name\s*:\s*\S.*$'),
    re.compile(r'^on\s*:\s*(?:\[[^]]+\]|[^:]+)$'),
)
EXEC_JOB = re.compile(r'^  [A-Za-z0-9_.-]+\s*:\s*$')
EXEC_RUNNER = re.compile(r'^    runs-on\s*:\s*[A-Za-z0-9_.-]+\s*$')
EXEC_STEPS = re.compile(r'^    steps\s*:\s*$')
EXEC_RUN = re.compile(r'^      -\s*run\s*:\s*(.*)$')
EXEC_CHECKOUT = re.compile(r'^      -\s*uses\s*:\s*actions/checkout@v4\s*$')


def validate_executable_github(path, lines):
    """Admit only syntax whose local execution semantics are explicit."""
    jobs_seen = False
    top_keys = set()
    job_ids = set()
    current_job = None
    has_runner = False
    has_steps = False
    scalar_body = False

    def finish_job(line_number):
        if current_job is not None and (not has_runner or not has_steps):
            sys.stderr.write(
                f'{path.name}: executable subset requires runs-on and steps '
                f'for job {current_job!r} before line {line_number}\n'
            )
            raise SystemExit(3)

    index = 0
    while index < len(lines):
        line = lines[index]
        line_number = index + 1
        index += 1
        if '\t' in line:
            sys.stderr.write(f'{path.name}: tabs are unsupported at line {line_number}\n')
            raise SystemExit(3)
        if '${{' in line:
            sys.stderr.write(f'{path.name}: expressions are unsupported at line {line_number}\n')
            raise SystemExit(3)

        indent = len(line) - len(line.lstrip())
        if scalar_body:
            if not line.strip() or indent > 6:
                continue
            scalar_body = False

        stripped = line.strip()
        if not stripped or stripped.startswith('#'):
            continue
        if not jobs_seen:
            if line == 'jobs:':
                jobs_seen = True
                continue
            if any(pattern.match(line) for pattern in EXEC_TOP):
                key = line.split(':', 1)[0].strip()
                if key in top_keys:
                    sys.stderr.write(f'{path.name}: duplicate {key} mapping at line {line_number}\n')
                    raise SystemExit(3)
                top_keys.add(key)
                continue
            sys.stderr.write(
                f'{path.name}: unsupported executable workflow structure at line {line_number}\n'
            )
            raise SystemExit(3)

        if EXEC_JOB.match(line):
            finish_job(line_number)
            current_job = line.strip()[:-1]
            if current_job in job_ids:
                sys.stderr.write(f'{path.name}: duplicate job id at line {line_number}\n')
                raise SystemExit(3)
            job_ids.add(current_job)
            has_runner = False
            has_steps = False
            continue
        if current_job is None:
            sys.stderr.write(f'{path.name}: jobs must contain a named job at line {line_number}\n')
            raise SystemExit(3)
        if EXEC_RUNNER.match(line):
            if has_runner:
                sys.stderr.write(f'{path.name}: duplicate runs-on at line {line_number}\n')
                raise SystemExit(3)
            has_runner = True
            continue
        if EXEC_STEPS.match(line):
            if has_steps:
                sys.stderr.write(f'{path.name}: duplicate steps at line {line_number}\n')
                raise SystemExit(3)
            has_steps = True
            continue
        if has_steps and EXEC_CHECKOUT.match(line):
            # The repository is already checked out at the exact local root.
            # `with:` and every other packaged action remain unsupported.
            continue
        run = EXEC_RUN.match(line) if has_steps else None
        if run:
            raw = run.group(1).strip()
            if BLOCK_MARKER.match(raw):
                scalar_body = True
            elif not scalar(raw):
                sys.stderr.write(f'{path.name}: run step is empty at line {line_number}\n')
                raise SystemExit(3)
            continue
        sys.stderr.write(
            f'{path.name}: unsupported executable workflow context at line {line_number}\n'
        )
        raise SystemExit(3)

    if not jobs_seen or current_job is None:
        sys.stderr.write(f'{path.name}: executable subset requires jobs\n')
        raise SystemExit(3)
    finish_job(len(lines) + 1)

def scalar(value):
    value = value.strip()
    if not value or BLOCK_MARKER.match(value):
        return ''
    value = COMMENT.sub('', value).strip()
    # Only unwrap a value that is FULLY quoted. Stripping quote characters off
    # both ends unconditionally corrupted real commands: it turned
    # `echo "x" >> "$GITHUB_OUTPUT"` into a line with an unbalanced quote.
    if len(value) >= 2 and value[0] == value[-1] and value[0] in '"\'':
        return value[1:-1]
    return value

derive_format = os.environ.get('DERIVE_FORMAT', 'text')
if derive_format == 'json':
    if provider != 'github':
        sys.stderr.write('only GitHub workflows have a supported executable local subset\n')
        raise SystemExit(3)
    for path in files:
        validate_executable_github(path, path.read_text(encoding='utf-8').splitlines())

# GitHub `- run:`; Azure `- script:` / `- bash:`.
INLINE = {
    'github': re.compile(r'^\s*-?\s*run\s*:\s*(.*)$'),
    'azure': re.compile(r'^\s*-?\s*(?:script|bash)\s*:\s*(.*)$'),
    'gitlab': re.compile(r'^\s*(?:before_script|script|after_script)\s*:\s*(.*)$'),
}
# GitLab keeps its commands as a list under a script key, so the reader has to
# know when it is inside one.
GITLAB_KEY = re.compile(r'^(\s*)(?:before_script|script|after_script)\s*:\s*$')
LIST_ITEM = re.compile(r'^(\s*)-\s+(.*)$')

commands = []
for path in files:
    lines = path.read_text(encoding='utf-8').splitlines()
    for index, line in enumerate(lines):
        for pattern, label in UNSUPPORTED:
            # A leading `---` on line 1 is a document start, not a separator.
            if pattern.match(line) and not (label == 'multi-document YAML' and index == 0):
                sys.stderr.write(f'{path.name}: unsupported construct ({label}) at line {index + 1}\n')
                raise SystemExit(3)

    block_indent = None
    scalar_indent = None
    body = []
    for line in lines:
        if provider == 'gitlab':
            key = GITLAB_KEY.match(line)
            if key:
                block_indent = len(key.group(1))
                continue
            if block_indent is not None:
                item = LIST_ITEM.match(line)
                if item and len(item.group(1)) > block_indent:
                    value = scalar(item.group(2))
                    if value:
                        commands.append(value)
                    continue
                if line.strip():
                    block_indent = None

        # Inside a block scalar body. Keep the body WHOLE as one entry: a step is
        # one shell invocation, and splitting it per line turns a heredoc or an
        # if/then into a list of fragments that reads like separate commands and
        # is not one. Verified against this repo's own workflows, where splitting
        # produced nonsense.
        if scalar_indent is not None:
            indent = len(line) - len(line.lstrip())
            if not line.strip() or indent > scalar_indent:
                body.append(line[scalar_indent:] if len(line) > scalar_indent else line.strip())
                continue
            joined = '\n'.join(body).strip()
            if joined:
                commands.append(joined)
            body = []
            scalar_indent = None

        match = INLINE[provider].match(line)
        if match:
            raw = match.group(1).strip()
            if BLOCK_MARKER.match(raw):
                # Body lines are indented deeper than the key that opened it.
                scalar_indent = len(line) - len(line.lstrip())
                body = []
                continue
            value = scalar(raw)
            if value:
                commands.append(value)

    if scalar_indent is not None:
        joined = '\n'.join(body).strip()
        if joined:
            commands.append(joined)

if not commands:
    sys.stderr.write(f'{provider} CI configuration contains no runnable steps\n')
    raise SystemExit(2)

if derive_format == 'json':
    print(json.dumps(commands))
else:
    # Legacy inventory output remains de-duplicated and line-oriented. It must
    # never be reparsed for execution because a block scalar contains newlines.
    seen = set()
    for command in commands:
        if command not in seen:
            seen.add(command)
            print(command)
PY
}

if [[ "$MODE" == "derive" ]]; then
  output="$(derive_commands text)"; status=$?
  case "$status" in
    0) printf '%s\n' "$output"; exit 0 ;;
    2) block "no CI commands could be derived from $ROOT — absence of CI is not a green CI" ;;
    3) block "a workflow uses a construct this reader does not support; it is refused rather than guessed at" ;;
    *) block "CI derivation failed" ;;
  esac
fi

if [[ "$MODE" == "derive-json" ]]; then
  output="$(derive_commands json)"; status=$?
  case "$status" in
    0) printf '%s\n' "$output"; exit 0 ;;
    2) block "no CI commands could be derived from $ROOT — absence of CI is not a green local check" ;;
    3) block "workflow structure is outside the safe executable local subset" ;;
    *) block "structured CI derivation failed" ;;
  esac
fi

# --- verification[] ---------------------------------------------------------
[[ -n "$RECORD" ]] || usage "--verify requires --goal-record"
[[ -f "$RECORD" ]] || block "goal record not found: $RECORD"

# The array is goal-record data, not shell source. Validate the complete plan,
# including every cwd, script, and executable, before starting any subprocess.
ROOT="$ROOT" RECORD="$RECORD" python3 - <<'PY'
import json
import os
import re
import shlex
import subprocess
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
    sys.stderr.write(f'{message}\n')
    raise SystemExit(code)


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


try:
    root = Path(os.environ['ROOT']).resolve(strict=True)
    record = json.loads(Path(os.environ['RECORD']).read_text(encoding='utf-8'))
except (OSError, json.JSONDecodeError, UnicodeDecodeError) as error:
    stop(2, f'goal record or root is unreadable: {error}')
if not root.is_dir():
    stop(2, f'owning root is not a directory: {root}')

entries = record.get('verification') if isinstance(record, dict) else None
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

for command_text, argv, command_cwd in validated:
    print(f'ci-gate: running {command_text}')
    if subprocess.run(argv, cwd=command_cwd, shell=False, check=False).returncode != 0:
        stop(4, f'verification command failed: {command_text}')
PY
status=$?
case "$status" in
  0) : ;;
  2) block "goal record's verification[] is missing or malformed" ;;
  3) block "goal record's verification[] contains a command outside the allowlist" ;;
  4) block "verification command failed" ;;
  *) block "verification[] could not be read" ;;
esac

echo "ci-gate: all verification[] commands passed"
