#!/bin/bash
#
# knowledge_producers_test.sh
#
# XSKP-P5-02 regression guard: the host-neutral knowledge publish step lives in
# ONE shared module (03-configure-generate/ai-catapult-init/modules/
# knowledge-publish.md) and each producer skill ends with a pointer of at most
# 3 lines to that module and declares its knowledge kind. Catalog limits hold
# (description <=160 chars; body <=100 lines after the frontmatter, counted like
# scripts/validate-skill-catalog.py; northstar keeps its planning-time 105-line
# whole-file budget) and the step never fails a skill because of the registry —
# it records `unpublished: <reason>` instead.
#
# The pointer must resolve where a skill is read: in this source repo (through
# the catalog, like scripts/check-markdown-links.py) and in the directories the
# repo's installers write. Codex and Claude Code copy skill directories, so the
# pointer resolves to the installed module; Auggie, Gemini and Copilot get flat
# projections that drop it. This repo ships no OpenCode installer.
#
# P5-02 covers the five first producers (northstar, to-spec, to-prd,
# to-issues, research); P5-03 extends the asserted set to all nine.
#
# The file is discovered automatically by tests/test-scripts.sh
# (find tests -name '*_test.sh') under tests/run-tests.sh.
#
# Exit 0 when all checks pass; non-zero otherwise.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

MODULE="03-configure-generate/ai-catapult-init/modules/knowledge-publish.md"
PRODUCERS="northstar to-spec to-prd to-issues research"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# line_counts <file>: "<file lines> <body lines>". File lines count a last line
# without a trailing newline; body lines follow the closing frontmatter
# delimiter, counted by the catalog validator's own parser, or "-" when the
# frontmatter does not parse.
line_counts() {
  python3 -B - "$1" 2>/dev/null <<'PY'
import importlib.util, sys
from pathlib import Path
sys.path.insert(0, 'scripts')
spec = importlib.util.spec_from_file_location('validate_skill_catalog', 'scripts/validate-skill-catalog.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
path = Path(sys.argv[1])
try:
    body = str(len(validator.frontmatter(path)[1]))
except AssertionError:
    body = '-'
print(len(path.read_text(encoding='utf-8').splitlines()), body)
PY
}

# Body-line budget for non-northstar producers: <=100 lines; a frontmatter that
# does not parse fails it.
within_body_budget() {
  local counts
  counts="$(line_counts "$1")" || return 1
  [ "${counts#* }" != "-" ] && [ "${counts#* }" -le 100 ]
}

# check_budget <producer> <file> <label>: prints the failure reason, nothing
# when the file keeps its budget. Northstar keeps its 105-line whole-file
# budget; every other producer keeps a body of at most 100 lines.
check_budget() {
  local counts
  if ! counts="$(line_counts "$2")"; then
    echo "$3 could not be read"
  elif [ "$1" = "northstar" ]; then
    [ "${counts% *}" -le 105 ] || echo "$3 is ${counts% *} lines (northstar planning budget 105, net delta 0)"
  elif [ "${counts#* }" = "-" ]; then
    echo "$3 frontmatter does not parse"
  elif [ "${counts#* }" -gt 100 ]; then
    echo "$3 body is ${counts#* } lines (>100)"
  fi
}

want_kind() {
  case "$1" in
    northstar) echo plan ;;
    to-spec) echo spec ;;
    to-prd) echo prd ;;
    to-issues) echo plan ;;
    research) echo research ;;
    handoff) echo handoff ;;
    retro) echo learning ;;
    domain-modeling) echo adr ;;
    code-review) echo review ;;
    *) echo "" ;;
  esac
}

skill_file() {
  case "$1" in
    northstar) echo "$REPO_ROOT/02-govern-plan/northstar/SKILL.md" ;;
    to-spec) echo "$REPO_ROOT/02-govern-plan/to-spec/SKILL.md" ;;
    to-prd) echo "$REPO_ROOT/02-govern-plan/to-prd/SKILL.md" ;;
    to-issues) echo "$REPO_ROOT/02-govern-plan/to-issues/SKILL.md" ;;
    research) echo "$REPO_ROOT/01-discover-decide/research/SKILL.md" ;;
    handoff) echo "$REPO_ROOT/04-validate-handoff/handoff/SKILL.md" ;;
    retro) echo "$REPO_ROOT/04-validate-handoff/retro/SKILL.md" ;;
    domain-modeling) echo "$REPO_ROOT/01-discover-decide/domain-modeling/SKILL.md" ;;
    code-review) echo "$REPO_ROOT/04-validate-handoff/code-review/SKILL.md" ;;
  esac
}

# 1. The shared module exists and defines the host-neutral step.
if [ -f "$MODULE" ]; then
  MODULE_TEXT="$(cat "$MODULE")"
  case "$MODULE_TEXT" in
    *".ai/knowledge/registry.json"*) : ;;
    *) bad "module does not mention .ai/knowledge/registry.json" ;;
  esac
  case "$MODULE_TEXT" in
    *"unpublished: no-registry"*) : ;;
    *) bad "module does not define 'unpublished: no-registry'" ;;
  esac
  case "$MODULE_TEXT" in
    *"unpublished: no-descriptor"*) : ;;
    *) bad "module does not define 'unpublished: no-descriptor'" ;;
  esac
  case "$MODULE_TEXT" in
    *"unpublished: publish-failed"*) : ;;
    *) bad "module does not define 'unpublished: publish-failed'" ;;
  esac
  case "$MODULE_TEXT" in
    *".ai/commands/<host>/knowledge.json"*) : ;;
    *) bad "module does not name the descriptor .ai/commands/<host>/knowledge.json" ;;
  esac
  case "$MODULE_TEXT" in
    *"never fails"*"because of the registry"*) : ;;
    *) bad "module does not state the never-fails guarantee" ;;
  esac
  ok "shared module defines the host-neutral publish step and its unpublished tokens"
else
  bad "shared module missing: $MODULE"
fi

# 2. The module declares a kind for every producer of the plan.
for name in northstar to-spec to-prd to-issues research handoff retro domain-modeling code-review; do
  kind="$(want_kind "$name")"
  if [ -f "$MODULE" ] && [ -n "$kind" ] && grep -q "| \`$name\` | \`$kind\` |" "$MODULE"; then
    :
  else
    bad "module does not declare kind for $name (want '$kind')"
  fi
done
if [ "$FAIL" -eq 0 ]; then
  ok "module declares kinds for all nine producers"
fi

# 3. Each covered producer skill ends with a <=3-line pointer to the module,
#    declares its kind, and keeps the catalog limits.
for name in northstar to-spec to-prd to-issues research handoff retro domain-modeling code-review; do
  file="$(skill_file "$name")"
  kind="$(want_kind "$name")"
  rel="${file#"$REPO_ROOT"/}"
  if [ ! -f "$file" ]; then
    bad "$rel missing"
    continue
  fi
  tail2="$(tail -n 2 "$file")"
  case "$tail2" in
    *"knowledge-publish.md"*) : ;;
    *) bad "$rel does not end with a pointer to knowledge-publish.md" ;;
  esac
  case "$tail2" in
    *"knowledge kind \`$kind\`"*) : ;;
    *) bad "$rel does not declare knowledge kind '$kind' at the end" ;;
  esac
  case "$tail2" in
    *"unpublished: <reason>"*) : ;;
    *) bad "$rel pointer does not state the unpublished: <reason> fallback" ;;
  esac
  desc="$(python3 - "$file" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'^description:\s*(.*)$', text, re.M)
print(str(len(m.group(1).strip().strip('"').strip("'"))) if m else '0')
PY
)"
  if [ "$desc" -le 160 ]; then
    :
  else
    bad "$rel description is $desc chars (>160)"
  fi
  reason="$(check_budget "$name" "$file" "$rel")"
  if [ -n "$reason" ]; then
    bad "$reason"
  fi
done
if [ "$FAIL" -eq 0 ]; then
  ok "all nine producers end with the kind-declaring pointer and keep catalog limits"
fi

# 4. The body budget counts body lines, not whole-file lines: a 4-line
#    frontmatter plus a 97- or 100-line body is valid; a 101-line body is not.
budget_fail=0
make_skill() {
  {
    printf -- '---\nname: budget-fixture\ndescription: Body budget edge fixture.\n---\n'
    seq 1 "$2" | sed 's/^/Body line /'
  } > "$1"
}
for body in 97 100; do
  make_skill "$SCRATCH/body-$body.md" "$body"
  if [ "$(wc -l < "$SCRATCH/body-$body.md" | tr -d ' ')" -le 100 ]; then
    bad "budget fixture with a $body-line body must exceed 100 whole-file lines"
    budget_fail=1
  fi
  if ! within_body_budget "$SCRATCH/body-$body.md"; then
    bad "a valid $body-line body under a 4-line frontmatter is rejected by the body budget"
    budget_fail=1
  fi
done
make_skill "$SCRATCH/body-101.md" 101
if within_body_budget "$SCRATCH/body-101.md"; then
  bad "a 101-line body is accepted by the body budget"
  budget_fail=1
fi
# A frontmatter that does not parse is reported as such, not as an over-long body.
printf -- '---\nname: budget-fixture\nBody line 1.\n' > "$SCRATCH/unterminated.md"
case "$(check_budget research "$SCRATCH/unterminated.md" unterminated.md)" in
  *"frontmatter does not parse"*) : ;;
  *) bad "an unterminated frontmatter is not reported as a frontmatter parse error"; budget_fail=1 ;;
esac
# The northstar whole-file count includes a last line without a trailing newline.
for count in 105 106; do
  python3 -B -c 'import sys; sys.stdout.write("\n".join("Line %d" % i for i in range(1, int(sys.argv[1]) + 1)))' \
    "$count" > "$SCRATCH/northstar-$count.md"
done
if [ -n "$(check_budget northstar "$SCRATCH/northstar-105.md" northstar-105.md)" ]; then
  bad "a 105-line northstar file without a trailing newline is rejected"
  budget_fail=1
fi
case "$(check_budget northstar "$SCRATCH/northstar-106.md" northstar-106.md)" in
  *"is 106 lines"*) : ;;
  *) bad "a 106-line northstar file without a trailing newline is not counted as 106 lines"; budget_fail=1 ;;
esac
if [ "$budget_fail" -eq 0 ]; then
  ok "budgets: 97/100-line bodies pass, 101 fails, parse errors are named, unterminated last lines count"
fi

# 5. The module names the one local document `publish <path>` takes: a
#    hosted-only output (to-prd, to-issues) is materialized under its kind's
#    canonical target first. Every harness or private path it cites is quoted
#    from the frozen policy, classified as the policy classifies it (a deny
#    path or a native_rules glob), never a broader summary such as `.omc/**`.
#    The module states the rules root's publisher (scripts/knowledge/publish.py)
#    needs from a producer, each as an exact rule sentence: write rules that
#    never clobber, leak or misjudge a revision; an undo that deletes only the
#    step's own copy; an explicit --id from the repo profile; one document per
#    producer; source records left in place; placement that copies, publishes
#    and removes an original only on success; and private-content rules for
#    handoff and retro.
module_fail=0
module_report="$(python3 -B - "$MODULE" .ai/knowledge/contract/publication-policy.json <<'PY'
import json, re, sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding='utf-8') if Path(sys.argv[1]).is_file() else ''
policy = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
deny = set(policy['deny']['paths'])
native = {rule['glob'] for rule in policy['native_rules']}

if '`publish <path>' not in text:
    print('module does not name the `publish <path>` argument it fills')
hosted = [block for block in re.split(r'\n(?=- |\d+\. |#)', text) if 'hosted-only' in block.lower()]
if not any(all(cue in block for cue in ('`to-prd`', '`to-issues`', 'materialize', '`canonical_targets`'))
           for block in hosted):
    print('module does not materialize a hosted-only to-prd/to-issues output under canonical_targets')

harness = ('.omc/', '.omx/', '.omo/', '.sisyphus/', '.memory/', '**/')
cited = [token for token in re.findall(r'`([^`\n]+)`', text) if token.startswith(harness)]
for token in cited:
    if token not in deny and token not in native:
        print(f'module cites {token!r}, which is neither a deny path nor a native_rules glob of the policy')

# Classification, not just membership: a statement that speaks of deny paths
# cites only deny paths; one that speaks of native sources cites only
# native_rules globs. Table rows and prose sentences are separate statements.
unfenced = re.sub(r'^```.*?^```[^\n]*$', '', text, flags=re.M | re.S)  # code blocks are not statements
statements = [line for line in unfenced.splitlines() if line.startswith('|')]
prose = ' '.join(line.strip() for line in unfenced.splitlines() if not line.startswith('|'))
statements += re.split(r'(?<=\.)\s+(?=[A-Z`*])', prose)
denied_cited, native_cited = set(), set()
for statement in statements:
    tokens = [token for token in re.findall(r'`([^`\n]+)`', statement) if token.startswith(harness)]
    if re.search(r'\bdeny\b|\bdenied\b', statement, re.I):
        denied_cited.update(tokens)
        for token in tokens:
            if token not in deny:
                print(f'module cites {token!r} as a deny path, but it is not in the policy deny list')
    elif re.search(r'\bnative\b', statement, re.I):
        native_cited.update(tokens)
        for token in tokens:
            if token not in native:
                print(f'module cites {token!r} as a native source, but it is not a native_rules glob')
if not any(token.startswith('.omc/') for token in denied_cited):
    print('module cites no denied .omc/ subpath from the policy')
if not any(token.startswith('.omc/') for token in native_cited):
    print('module cites no native .omc/ glob from the policy')


def section(title):
    match = re.search(r'^## ' + re.escape(title) + r'\n(.*?)(?=^## |\Z)', text, re.M | re.S)
    return match.group(1) if match else ''


def items(body):
    return re.split(r'\n(?=\d+\. |- )', body)


def flat(body):
    return ' '.join(body.split())  # markdown line wrapping never hides a cue


def require(label, body, *cues):
    if not body or not all(cue in flat(body) for cue in cues):
        print(f'module does not state: {label}')


step, write, placement = section('The step'), section('Write rules'), section('Placement')
# Cues are exact rule sentences, so a reversed rule fails (a topic word would not).
# Write rules: never clobber, never leak, never misjudge a revision.
require('refuse a path another registry entry already uses as its canonical path', write,
        'Refuse the path if an entry in `.ai/knowledge/registry.json` with another `knowledge_id` '
        'already uses it as its canonical path')
require('a revision needs a same-id file, a run that revises it, and a source that is the entry '
        'canonical path or one of its `derived_from` paths', write,
        'A run is a revision only when', '`knowledge_id: <id>`', 'this run revises that document',
        'the source is the canonical path of the entry or a `derived_from` path of one of its revisions',
        'Refuse a registered `<id>` for any other run')
require('on refusal try `<slug>-2`, `<slug>-3`, capped at `<slug>-99`', write,
        'try `<slug>-2`, then `<slug>-3`, up to `<slug>-99`',
        'If every candidate is refused, record `unpublished: publish-failed`')
require('create the file exclusively', write, 'Create a new file exclusively')
undo = [flat(item) for item in items(step) if '`unpublished: publish-failed`' in flat(item)]
if not any('delete only the copy this step made' in item and 'restore the bytes it replaced' in item
           and 'Never delete or move the producer' in item
           and item.index('delete only the copy this step made') < item.index('`unpublished: publish-failed`')
           for item in undo):
    print('module does not state: undo deletes only the copy this step made, never the producer document, '
          'before recording `unpublished: publish-failed`')
# One document per producer, an explicit id from the repo profile, only the outermost producer.
require('always pass `--id <id>` with `<id>` = `<repo_id>:<kind>:<slug>` from the title',
        step, '--id <id>', '`<repo_id>:<kind>:<slug>`', 'document title', 'Always pass `--id`')
require('`<repo_id>` comes from `.ai/init/repo-profile.json`, the value the publisher validates', step,
        '`<repo_id>` is the `repo_id` of `.ai/init/repo-profile.json`')
require('only the outermost producer runs the step; a nested producer skips it', section('Who runs the step'),
        'Only the outermost producer runs the step.', 'skips it and records nothing')
kinds = section('Declared kinds')
if '| Producer | kind | canonical target | document |' not in kinds:
    print('module does not state: a document column in Declared kinds')
rows = {row.split('|')[1].strip().strip('`'): [cell.strip() for cell in row.strip().strip('|').split('|')]
        for row in kinds.splitlines() if row.startswith('| `')}
cues = {'northstar': ('`.ai/work-intake/` record', 'source record', '`.omc/plans/*.md`'),
        'to-spec': ('written to the target',),
        'to-prd': ('`.scratch/<feature-slug>/PRD.md`', 'source record', 'tracker reference'),
        'to-issues': ('dependency order', '`.scratch/`'), 'research': ('*Placement*',),
        'handoff': ('*Private content*', 'redaction'), 'retro': ('*Private content*', 'session-log'),
        'domain-modeling': ('`<NNNN>-<slug>.md`', 'highest existing number', '*Placement*'),
        'code-review': ('*Private content*', 'written to the target')}
for name, wanted in cues.items():
    cells = rows.get(name, [])
    if len(cells) != 4 or not cells[3] or not all(cue in cells[3] for cue in wanted):
        print(f'module does not state: the one document {name} publishes ({", ".join(wanted)})')
# Placement: a non-native document lives once, at its canonical path; an earlier
# save is copied, published, and removed only on success; nothing pre-existing moves.
require('a non-native document is saved at `<target><slug>.md` in the first place', placement,
        'saves it at `<target><slug>.md` under the *Write rules* in the first place')
require('copy, publish the copy, remove the original only after success', placement,
        'Copy it to `<target><slug>.md` under the *Write rules* and publish the copy',
        'Remove the original only after the publish run succeeds',
        'update the references this run made to the new path')
require('a failed publish keeps the original', placement,
        'On a failure the step deletes only its copy; the original stays where the producer saved it')
require('never move a pre-existing or linked file; record `unpublished: needs-adoption`', placement,
        'Never move or remove a file that existed before this run', '`unpublished: needs-adoption`')
require('`unpublished: needs-adoption` is a recorded reason',
        section('Reasons recorded as `unpublished: <reason>`'), '`unpublished: needs-adoption`')
# Source records stay; the registry copy is derived from them.
require('source records stay where they are and the registry copy is derived', section('Source records'),
        'A source record stays where it is', 'never move, copy or rewrite it',
        '`.scratch/<feature-slug>/PRD.md`', '`.ai/work-intake/`', '`derived_from`')
# Private content: handoff, retro and code-review never write deny-listed content or local identities.
require('handoff, retro and code-review cite deny-listed files by name only, scrub, and redact before the write',
        section('Private content'), '`handoff`, `retro` and `code-review` write only what is safe to track',
        'A UUID is replaced only in a session path', 'cite such a file by name only',
        'replace home-directory paths with `<home>` and session ids with `<session>`',
        '`handoff` runs its redaction step before the write', '`~/**`', '`.memory/**`',
        '`.omc/project-memory.json`', '`.omx/notepad.md`')
# L1: a native source counts only with the kind of the producer.
require('a native source counts only when its first matching native_rules glob has the producer kind',
        kinds, 'first `native_rules` glob', 'same kind as the producer')
# Flat projections are not XSKP hosts; publish-failed also covers a failed write.
require('Gemini, Auggie and Copilot are not XSKP hosts', section('Who runs the step'),
        'Gemini', 'Auggie', 'Copilot', 'not XSKP hosts')
require('`unpublished: publish-failed` covers a document that could not be written',
        section('Reasons recorded as `unpublished: <reason>`'), 'could not be written')
PY
)" || module_report="module policy check could not run"
if [ -n "$module_report" ]; then
  while IFS= read -r line; do bad "$line"; done <<< "$module_report"
  module_fail=1
fi
if [ "$module_fail" -eq 0 ]; then
  ok "module states document selection, write and undo rules, placement, and the policy's path classes"
fi

# 6. Every pointer resolves to the module in the source layout (through the
#    catalog) and in the installed layouts the repo's installers write.
install_fail=0
for host in claude codex gemini auggie copilot; do mkdir -p "$SCRATCH/$host"; done
HOME="$SCRATCH/claude" bash scripts/install-claude-code.sh --user >/dev/null 2>&1 \
  || { bad "install-claude-code.sh --user failed"; install_fail=1; }
HOME="$SCRATCH/codex" bash scripts/install-codex.sh --all >/dev/null 2>&1 \
  || { bad "install-codex.sh --all failed"; install_fail=1; }
HOME="$SCRATCH/gemini" bash scripts/install-gemini.sh --all >/dev/null 2>&1 \
  || { bad "install-gemini.sh --all failed"; install_fail=1; }
HOME="$SCRATCH/auggie" bash scripts/install-auggie.sh --all >/dev/null 2>&1 \
  || { bad "install-auggie.sh --all failed"; install_fail=1; }
HOME="$SCRATCH/copilot" bash scripts/install-copilot.sh --all "$SCRATCH/copilot/repo" >/dev/null 2>&1 \
  || { bad "install-copilot.sh --all failed"; install_fail=1; }
resolve_report="$(python3 -B - "$REPO_ROOT" "$MODULE" "$SCRATCH" $PRODUCERS <<'PY'
import importlib, re, sys
from pathlib import Path

repo, module, scratch = Path(sys.argv[1]), Path(sys.argv[1]) / sys.argv[2], Path(sys.argv[3])
producers = sys.argv[4:]
sys.path.insert(0, str(repo / 'scripts'))
links = importlib.import_module('check-markdown-links')
from catalog import load_catalog

by_name = {entry['name']: entry for entry in load_catalog(repo)['skills']}
want = module.read_bytes() if module.is_file() else None
installed = {
    'Claude Code': scratch / 'claude/.claude/skills/omc-learned',
    'Codex': scratch / 'codex/.codex/skills',
}
flat = {
    'Gemini': scratch / 'gemini/.gemini/skills',
    'Auggie': scratch / 'auggie/.auggie/rules',
    'Copilot': scratch / 'copilot/repo/.github',
}
for name in producers:
    skill = repo / by_name[name]['source_path'] / 'SKILL.md'
    tail = '\n'.join(skill.read_text(encoding='utf-8').splitlines()[-2:])
    targets = re.findall(r'\]\(([^)\s]*knowledge-publish\.md)\)', tail)
    if len(targets) != 1:
        print(f'{name}: pointer carries no markdown link to knowledge-publish.md')
        continue
    target = targets[0]
    resolved, cross_skill = links.logical_target(repo, name, target, by_name)
    direct = (skill.parent / target).resolve()
    if direct != module.resolve() and (not cross_skill or resolved.resolve() != module.resolve()):
        print(f'{name}: {target} does not resolve to {sys.argv[2]} in the source layout')
    for host, root in installed.items():
        path = root / name / target
        if want is None or not path.is_file() or path.read_bytes() != want:
            print(f'{name}: {target} does not resolve to the installed module under {host}')
for host, root in flat.items():
    files = [path for path in root.rglob('*.md')] if root.is_dir() else []
    if not files:
        print(f'{host}: flat install wrote no projections')
    for path in files:
        if 'knowledge-publish.md' in path.read_text(encoding='utf-8'):
            print(f'{host}: flat projection {path.relative_to(root)} keeps an unresolvable knowledge-publish.md pointer')
PY
)" || resolve_report="pointer resolution check could not run"
if [ -n "$resolve_report" ]; then
  while IFS= read -r line; do bad "$line"; done <<< "$resolve_report"
  install_fail=1
fi
if [ "$install_fail" -eq 0 ]; then
  ok "every pointer resolves to the module in the source and Claude Code/Codex installed layouts; flat projections drop it"
fi

# 7. The module's scrub patterns (the `knowledge-scrub` block under *Private
#    content*) run on samples with exact expected outputs: every home-directory
#    form (plain, encoded Claude Code project and scratchpad dirs, Windows,
#    /root, $HOME, file URLs) and session ids in session paths (any case) are
#    replaced; repository paths, URLs, REST paths and UUIDs outside session
#    paths stay unchanged.
scrub_report="$(python3 -B - "$MODULE" <<'PY'
import re, sys
from pathlib import Path

module = Path(sys.argv[1])
text = module.read_text(encoding='utf-8') if module.is_file() else ''
block = re.search(r'^```knowledge-scrub\n(.*?)^```', text, re.M | re.S)
rules = []
for line in (block.group(1).splitlines() if block else []):
    if line.strip():
        pattern, _, replacement = line.rpartition(' -> ')
        rules.append((re.compile(pattern.strip()), replacement.strip()))
if len(rules) < 4:
    print('module has no knowledge-scrub block with home-path and session-id patterns')
    raise SystemExit
uuid, upper = '94f42008-9018-42b5-b61e-b0edc80d9a34', '94F42008-9018-42B5-B61E-B0EDC80D9A34'
back = chr(92)
replaced = [
    ('Read /Users/alice/Ws/repo/notes.md', 'Read <home>/Ws/repo/notes.md'),
    ('/home/bob/.codex/AGENTS.md', '<home>/.codex/AGENTS.md'),
    ('see ~/.claude/CLAUDE.md', 'see <home>/.claude/CLAUDE.md'),
    ('file:///Users/alice/x.md', 'file://<home>/x.md'),
    ('~/.claude/projects/-Users-alice-Ws-repo/' + uuid + '.jsonl',
     '<home>/.claude/projects/-<home>-Ws-repo/<session>.jsonl'),
    ('/private/tmp/claude-502/-Users-alice-Ws-repo/' + uuid + '/scratchpad/x.md',
     '/private/tmp/claude-502/-<home>-Ws-repo/<session>/scratchpad/x.md'),
    ('/tmp/claude-0/-home-bob_smith2-src/x.md', '/tmp/claude-0/-<home>-src/x.md'),
    ('C:' + back + 'Users' + back + 'alice' + back + 'repo', '<home>' + back + 'repo'),
    ('/root/.codex/AGENTS.md', '<home>/.codex/AGENTS.md'),
    ('$HOME/.codex/AGENTS.md', '<home>/.codex/AGENTS.md'),
    ('~/.claude/projects/-Users-alice-Ws-repo/' + upper + '.jsonl',
     '<home>/.claude/projects/-<home>-Ws-repo/<session>.jsonl'),
    ('.omc/sessions/' + upper + '/state.json', '.omc/sessions/<session>/state.json'),
    ('~/.codex/sessions/2026/10/08/rollout-2026-10-08T01-02-03-0199a7c4-1b2c-7d3e-8f40-123456789abc.jsonl',
     '<home>/.codex/sessions/2026/10/08/rollout-2026-10-08T01-02-03-<session>.jsonl'),
    ('opencode ses_ef2d3983cffefdKkTRHokBHkRq', 'opencode <session>'),
]
unchanged = [
    'GET /scim/v2/Users/2819c223-7f76-453a-919d-413861904646',
    'see https://example.com/home/docs and https://github.com/Users/x',
    'edit src/home/page.md and lib/root/x.py',
    'Azure DevOps project 6ce954b1-ce1f-45d1-b94d-e6bf2464ba2c, build ' + upper,
    'run tool --home-dir x',
    'Keep docs/plans/x.md, sha 777d12eabe93d24219007d417365674c83363446dee03ad89aa81fc3851994d6, PR #118',
]


def scrub(value):
    for pattern, replacement in rules:
        value = pattern.sub(replacement, value)
    return value


for given, wanted in replaced:
    if scrub(given) != wanted:
        print(f'scrub patterns turn {given!r} into {scrub(given)!r}, not {wanted!r}')
for given in unchanged:
    if scrub(given) != given:
        print(f'scrub patterns change {given!r} into {scrub(given)!r}; it must stay unchanged')
PY
)" || scrub_report="scrub pattern check could not run"
if [ -n "$scrub_report" ]; then
  while IFS= read -r line; do bad "$line"; done <<< "$scrub_report"
else
  ok "module scrub patterns replace every home-path form and session-path ids, and leave other paths and UUIDs"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
