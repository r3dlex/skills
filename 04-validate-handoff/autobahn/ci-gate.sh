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
    re.compile(r'^name: [A-Za-z0-9_. -]+$'),
    re.compile(r'^on: (?:[A-Za-z_][A-Za-z0-9_]*|\[[A-Za-z_][A-Za-z0-9_]*(?:, *[A-Za-z_][A-Za-z0-9_]*)*\])$'),
)
EXEC_JOB = re.compile(r'^  [A-Za-z0-9_.-]+\s*:\s*$')
EXEC_RUNNER = re.compile(r'^    runs-on\s*:\s*[A-Za-z0-9_.-]+\s*$')
EXEC_STEPS = re.compile(r'^    steps\s*:\s*$')
EXEC_RUN = re.compile(r'^      - run: (.*)$')
EXEC_CHECKOUT = re.compile(r'^      - uses: actions/checkout@v4$')


def validate_executable_github(path, lines):
    """Admit only syntax whose local execution semantics are explicit."""
    jobs_seen = False
    top_keys = set()
    job_ids = set()
    current_job = None
    has_runner = False
    has_steps = False
    scalar_body = False
    scalar_has_content = False
    scalar_indent = None
    in_steps = False
    step_count = 0

    def finish_job(line_number):
        if current_job is not None and (not has_runner or not has_steps or not step_count):
            sys.stderr.write(
                f'{path.name}: executable subset requires runs-on and nonempty steps '
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
                if line.strip():
                    if indent < 9 or (scalar_indent is not None and indent < scalar_indent):
                        sys.stderr.write(f'{path.name}: invalid block indentation at line {line_number}\n')
                        raise SystemExit(3)
                    if scalar_indent is None:
                        scalar_indent = indent
                    scalar_has_content = True
                continue
            if not scalar_has_content:
                sys.stderr.write(f'{path.name}: empty run block before line {line_number}\n')
                raise SystemExit(3)
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
            current_job = line.strip()[:-1].strip()
            if current_job in job_ids:
                sys.stderr.write(f'{path.name}: duplicate job id at line {line_number}\n')
                raise SystemExit(3)
            job_ids.add(current_job)
            has_runner = False
            has_steps = False
            in_steps = False
            step_count = 0
            continue
        if current_job is None:
            sys.stderr.write(f'{path.name}: jobs must contain a named job at line {line_number}\n')
            raise SystemExit(3)
        if EXEC_RUNNER.match(line):
            if has_runner:
                sys.stderr.write(f'{path.name}: duplicate runs-on at line {line_number}\n')
                raise SystemExit(3)
            has_runner = True
            in_steps = False
            continue
        if EXEC_STEPS.match(line):
            if has_steps:
                sys.stderr.write(f'{path.name}: duplicate steps at line {line_number}\n')
                raise SystemExit(3)
            has_steps = True
            in_steps = True
            continue
        if in_steps and EXEC_CHECKOUT.match(line):
            step_count += 1
            # The repository is already checked out at the exact local root.
            # `with:` and every other packaged action remain unsupported.
            continue
        run = EXEC_RUN.match(line) if in_steps else None
        if run:
            step_count += 1
            raw = run.group(1).strip()
            if ((raw.startswith(('|', '>')) and not re.fullmatch(r'[|>][-+]?', raw))
                    or (not raw.startswith(("'", '"')) and ': ' in raw)):
                sys.stderr.write(f'{path.name}: unsupported YAML run scalar at line {line_number}\n')
                raise SystemExit(3)
            if raw.startswith(("'", '"')) and (
                len(raw) < 2 or raw[-1] != raw[0]
                or raw[0] in raw[1:-1] or chr(92) in raw
            ):
                sys.stderr.write(f'{path.name}: YAML quoted escapes are unsupported at line {line_number}\n')
                raise SystemExit(3)
            if BLOCK_MARKER.match(raw):
                scalar_body = True
                scalar_has_content = False
                scalar_indent = None
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
    if scalar_body and not scalar_has_content:
        sys.stderr.write(f'{path.name}: empty final run block\n')
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
AUTOBAHN_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib" ROOT="$ROOT" RECORD="$RECORD" python3 -B - <<'PY'
import json, os, subprocess, sys
from pathlib import Path
sys.path.insert(0, os.environ['AUTOBAHN_LIB'])
from verification import validate, VerificationError

def stop(code, message):
    print(message, file=sys.stderr)
    raise SystemExit(code)

try:
    root = Path(os.environ['ROOT']).resolve(strict=True)
    record = json.loads(Path(os.environ['RECORD']).read_text(encoding='utf-8'))
    validated = validate(root, record.get('verification') if isinstance(record, dict) else None)
except VerificationError as error:
    stop(error.code, str(error))
except (OSError, ValueError, UnicodeDecodeError) as error:
    stop(2, str(error))

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
