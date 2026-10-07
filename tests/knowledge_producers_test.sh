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

# Body-line budget for non-northstar producers: <=100 lines.
within_body_budget() {
  local lines
  lines="$(wc -l < "$1" | tr -d ' ')"
  [ "$lines" -le 100 ]
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
for name in northstar to-spec to-prd to-issues research; do
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
  if [ "$name" = "northstar" ]; then
    lines="$(wc -l < "$file" | tr -d ' ')"
    if [ "$lines" -le 105 ]; then
      :
    else
      bad "northstar file is $lines lines (planning budget 105, net delta 0)"
    fi
  elif ! within_body_budget "$file"; then
    bad "$rel body exceeds 100 lines"
  fi
done
if [ "$FAIL" -eq 0 ]; then
  ok "all five producers end with the kind-declaring pointer and keep catalog limits"
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
if [ "$budget_fail" -eq 0 ]; then
  ok "body budget accepts 97- and 100-line bodies and rejects a 101-line body"
fi

# 5. The module names the one local document `publish <path>` takes: a
#    hosted-only output (to-prd, to-issues) is materialized under its kind's
#    canonical target first. Every harness or private path it cites is quoted
#    from the frozen policy (a deny path or a native_rules glob), never a
#    broader summary such as `.omc/**`.
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
if not any(token in deny and token.startswith('.omc/') for token in cited):
    print('module cites no denied .omc/ subpath from the policy')
if not any(token in native and token.startswith('.omc/') for token in cited):
    print('module cites no native .omc/ glob from the policy')
PY
)" || module_report="module policy check could not run"
if [ -n "$module_report" ]; then
  while IFS= read -r line; do bad "$line"; done <<< "$module_report"
  module_fail=1
fi
if [ "$module_fail" -eq 0 ]; then
  ok "module selects or materializes the published document and quotes the policy's path classes"
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
    if not cross_skill or resolved.resolve() != module.resolve():
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

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1