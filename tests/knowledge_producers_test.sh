#!/bin/bash
#
# knowledge_producers_test.sh
#
# XSKP-P5-02 regression guard: the host-neutral knowledge publish step lives in
# ONE shared module (03-configure-generate/ai-catapult-init/modules/
# knowledge-publish.md) and each producer skill ends with a pointer of at most
# 3 lines to that module and declares its knowledge kind. Catalog limits hold
# (description <=160 chars, body <=100 lines; northstar keeps its planning-time
# 105-line budget) and the step never fails a skill because of the registry —
# it records `unpublished: <reason>` instead.
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

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

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
  lines="$(wc -l < "$file" | tr -d ' ')"
  if [ "$name" = "northstar" ]; then
    if [ "$lines" -le 105 ]; then
      :
    else
      bad "northstar body is $lines lines (planning budget 105, net delta 0)"
    fi
  else
    if [ "$lines" -le 100 ]; then
      :
    else
      bad "$rel body is $lines lines (>100)"
    fi
  fi
done
if [ "$FAIL" -eq 0 ]; then
  ok "all five producers end with the kind-declaring pointer and keep catalog limits"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1