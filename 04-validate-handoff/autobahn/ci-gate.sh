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

workflows = Path(os.environ['ROOT']) / '.github' / 'workflows'
files = sorted(p for p in workflows.glob('*.y*ml')) if workflows.is_dir() else []
if not files:
    sys.stderr.write('no .github/workflows/*.yml found\n')
    raise SystemExit(2)

UNSUPPORTED = (
    (re.compile(r'^\s*\S+\s*:\s*&\S+'), 'YAML anchors'),
    (re.compile(r'^\s*(<<\s*:|-\s*<<\s*:)'), 'YAML merge keys'),
    (re.compile(r'^\s*\*\S+\s*$'), 'YAML aliases'),
    (re.compile(r'^---\s*$'), 'multi-document YAML'),
    (re.compile(r'^\t'), 'tab indentation'),
)

commands = []
for path in files:
    lines = path.read_text(encoding='utf-8').splitlines()
    for index, line in enumerate(lines):
        # A leading `---` on line 1 is a document start, not a separator.
        for pattern, label in UNSUPPORTED:
            if pattern.match(line) and not (label == 'multi-document YAML' and index == 0):
                sys.stderr.write(f'{path.name}: unsupported construct ({label}) at line {index + 1}\n')
                raise SystemExit(3)

    for line in lines:
        match = re.match(r'^\s*-?\s*run\s*:\s*(?:[|>][-+]?\s*)?(.*)$', line)
        if not match:
            continue
        command = match.group(1).strip().strip('"\'')
        # A block scalar's body sits on following lines; the marker itself
        # carries no command, and inventing one would be a guess.
        if command:
            commands.append(command)

if not commands:
    sys.stderr.write('workflows contain no run: steps\n')
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
    'pytest', 'npm test', 'npm run', 'bash tests/', 'python3 -m', 'moon run', 'prek run',
)
# Anything that could start a second command, expand, or redirect. A prefix
# check alone is defeated by `npm test && curl ... | sh`.
FORBIDDEN = re.compile(r'[;&|`$><\n\\]|\$\(')

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
