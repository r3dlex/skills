#!/usr/bin/env bash
#
# ci-gate.sh — derive the repo's real CI commands, and execute a goal record's
# verification[] array.
#
# Two holes this closes:
#   --derive  "local CI green" named no commands. It now means the commands the
#             repo's own CI runs, read out of .github/workflows.
#   --verify  readiness-check.sh has schema-validated goal.verification[] since
#             it was written, and nothing ever read it. Now it runs.
#
# Ships inert this slice: nothing invokes it yet. See modules/ci-gate.md.
#
# Usage:
#   ci-gate.sh --derive --root <dir>
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
    --derive|--verify)
      [[ -n "$MODE" ]] && usage "only one mode may be given"
      MODE="${1#--}"; shift ;;
    --root)        ROOT="${2:-}";   shift 2 || usage "--root needs a value" ;;
    --goal-record) RECORD="${2:-}"; shift 2 || usage "--goal-record needs a value" ;;
    *) usage "unknown argument: $1" ;;
  esac
done

[[ -n "$MODE" ]] || usage "one of --derive, --verify is required"
[[ -n "$ROOT" && -d "$ROOT" ]] || usage "--root is not a directory: ${ROOT:-<empty>}"

# --- derivation -------------------------------------------------------------
#
# The reader is deliberately narrow (decision 10): this repo has no YAML
# dependency and is not gaining one. It accepts two-space-indented
# jobs:/steps:/run: and refuses anything else rather than guessing. A parser
# that guesses at a construct it does not understand produces a command list
# that looks authoritative and is wrong.
derive_commands() {
  ROOT="$ROOT" python3 - <<'PY'
import os, re, sys
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

seen = set()
for command in commands:
    if command not in seen:
        seen.add(command)
        print(command)
PY
}

if [[ "$MODE" == "derive" ]]; then
  output="$(derive_commands)"; status=$?
  case "$status" in
    0) printf '%s\n' "$output"; exit 0 ;;
    2) block "no CI commands could be derived from $ROOT — absence of CI is not a green CI" ;;
    3) block "a workflow uses a construct this reader does not support; it is refused rather than guessed at" ;;
    *) block "CI derivation failed" ;;
  esac
fi

# --- verification[] ---------------------------------------------------------
[[ -n "$RECORD" ]] || usage "--verify requires --goal-record"
[[ -f "$RECORD" ]] || block "goal record not found: $RECORD"

# The array comes from a goal record, so running it verbatim would let a record
# execute anything. The allowlist is what makes verification[] data rather than
# code: a command must start with a known prefix AND contain no shell
# metacharacter that could chain past it.
COMMANDS="$(RECORD="$RECORD" python3 - <<'PY'
import json, os, re, sys
from pathlib import Path

ALLOWED_PREFIXES = (
    'pytest',
    'npm test',
    'npm run',
    'bash tests/',
    # NOT a bare `python3 -m`: that admitted any module, and
    # `python3 -m pip install <x>` is arbitrary package installation — arbitrary
    # code execution straight from a goal record. Name the runners instead.
    'python3 -m pytest',
    'python3 -m unittest',
    'moon run',
    'prek run',
)
# Anything that could start a second command, expand, or redirect. A prefix
# check alone is defeated by `npm test && curl ... | sh`.
FORBIDDEN = re.compile(r'[;&|`$><\n\\]|\$\(')
# A prefix that names a directory is not a boundary if the path can climb out of
# it: `bash tests/../evil/x.sh` satisfies `bash tests/` and runs anything.
TRAVERSAL = re.compile(r'(^|[/\s])\.\.([/\s]|$)')

try:
    record = json.loads(Path(os.environ['RECORD']).read_text(encoding='utf-8'))
except (json.JSONDecodeError, UnicodeDecodeError) as error:
    sys.stderr.write(f'goal record is unreadable: {error}\n')
    raise SystemExit(2)

commands = record.get('verification') if isinstance(record, dict) else None
if not isinstance(commands, list) or not commands:
    sys.stderr.write('goal record has no non-empty verification[] array\n')
    raise SystemExit(2)

for command in commands:
    if not isinstance(command, str) or not command.strip():
        sys.stderr.write('verification[] entries must be non-empty strings\n')
        raise SystemExit(2)
    command = command.strip()
    if FORBIDDEN.search(command):
        sys.stderr.write(f'verification command contains shell metacharacters: {command!r}\n')
        raise SystemExit(3)
    if TRAVERSAL.search(command):
        sys.stderr.write(f'verification command climbs out of its directory with "..": {command!r}\n')
        raise SystemExit(3)
    # A prefix ending in '/' is a path fragment and matches directly
    # ('bash tests/foo.sh'); any other prefix needs a word boundary after it, so
    # 'npm test' cannot authorise 'npm testfoo'.
    def matches(prefix):
        if prefix.endswith('/'):
            return command.startswith(prefix) and len(command) > len(prefix)
        return command == prefix or command.startswith(prefix + ' ')

    if not any(matches(p) for p in ALLOWED_PREFIXES):
        sys.stderr.write(f'verification command is not allowlisted: {command!r}\n')
        raise SystemExit(3)
    print(command)
PY
)"
status=$?
case "$status" in
  0) : ;;
  2) block "goal record's verification[] is missing or malformed" ;;
  3) block "goal record's verification[] contains a command outside the allowlist" ;;
  *) block "verification[] could not be read" ;;
esac

while IFS= read -r command; do
  [[ -n "$command" ]] || continue
  echo "ci-gate: running $command"
  # No network is granted here beyond whatever the environment already allows;
  # the allowlist is the boundary that matters, since none of its prefixes
  # fetch anything on their own.
  if ! ( cd "$ROOT" && bash -euo pipefail -c "$command" ); then
    block "verification command failed: $command"
  fi
done <<< "$COMMANDS"

echo "ci-gate: all verification[] commands passed"
