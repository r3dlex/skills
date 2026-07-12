#!/bin/bash
#
# eval_a_skill_test.sh  (P2-1)
#
# Offline, deterministic, discoverable validation of the `eval-a-skill`
# capability. NO model or network access is used anywhere in this test: every
# assertion is pure-shell + python3 JSON parsing. The LM-judge runner the skill
# documents is OUT-OF-BAND only and is NEVER invoked here or in CI.
#
# The skill, given a TARGET skill, scaffolds an eval triplet under
# `.ai/evals/<skill>/` matching the P0 eval shape (modules/evals.md +
# reference/fixtures/v3/standalone/.ai/evals/example-output-eval/):
#   - evalset.json     : schema_version, set_id, kind, cases (non-empty)
#   - rubric.md        : non-empty scoring rubric
#   - judge-config.json: schema_version, judge (tier/mode/harness/evaluates/
#                        execution=out-of-band)
#
# This test asserts:
#   1. 04-validate-handoff/eval-a-skill/SKILL.md exists with valid frontmatter (name + description).
#   2. The skill documents the structural-CI-vs-out-of-band split: a
#      structurally-valid triplet matching the P0 shape (structure-only in CI)
#      AND an opt-in out-of-band runner that actually invokes the judge, never in
#      CI.
#   3. If the skill ships a generator script, that script produces a structurally
#      valid triplet for a sample target skill, fully offline.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

SKILL_DIR="$REPO_ROOT/04-validate-handoff/eval-a-skill"
SKILL_MD="$SKILL_DIR/SKILL.md"

echo "eval-a-skill Capability Tests"
echo "============================="
echo ""

# -----------------------------------------------------------------------------
# Shared structural validators (mirror tests/eval_coverage_test.sh, offline).
# -----------------------------------------------------------------------------
parse_json() { python3 -m json.tool "$1" >/dev/null 2>&1; }

json_has_key() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
data = json.load(open(sys.argv[1]))
v = data.get(sys.argv[2])
sys.exit(0 if v not in (None, "", [], {}) else 1)
PY
}

# A structurally valid eval triplet (P0 shape): evalset.json + rubric.md +
# judge-config.json, each well-formed.
triplet_is_valid() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local evalset="$dir/evalset.json" rubric="$dir/rubric.md" judge="$dir/judge-config.json"
  [ -f "$evalset" ] && [ -f "$rubric" ] && [ -f "$judge" ] || return 1
  parse_json "$evalset" || return 1
  parse_json "$judge"   || return 1
  [ -s "$rubric" ]      || return 1
  json_has_key "$evalset" "schema_version" || return 1
  json_has_key "$evalset" "set_id"         || return 1
  json_has_key "$evalset" "kind"           || return 1
  json_has_key "$evalset" "cases"          || return 1
  json_has_key "$judge"   "schema_version" || return 1
  json_has_key "$judge"   "judge"          || return 1
  return 0
}

# -----------------------------------------------------------------------------
# 1. SKILL.md exists with valid frontmatter (name + description).
# -----------------------------------------------------------------------------
if [ -f "$SKILL_MD" ]; then
  ok "04-validate-handoff/eval-a-skill/SKILL.md exists"
else
  bad "04-validate-handoff/eval-a-skill/SKILL.md must exist ($SKILL_MD)"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

if python3 - "$SKILL_MD" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---", text, re.S)
if not m:
    sys.exit(1)
fm = m.group(1)
has_name = any(re.match(r"name:\s*\S", l) for l in fm.splitlines())
has_desc = any(re.match(r"description:\s*\S", l) for l in fm.splitlines())
sys.exit(0 if (has_name and has_desc) else 1)
PY
then
  ok "SKILL.md frontmatter declares name + description"
else
  bad "SKILL.md frontmatter must declare name + description"
fi

# -----------------------------------------------------------------------------
# 2. The skill documents the structural-CI-vs-out-of-band split.
# -----------------------------------------------------------------------------
# The triplet it produces must match the P0 shape (three named artifacts).
for token in "evalset.json" "rubric.md" "judge-config.json" ".ai/evals/"; do
  if grep -Fq "$token" "$SKILL_MD"; then
    ok "SKILL.md documents the P0 eval artifact: $token"
  else
    bad "SKILL.md must document the P0 eval artifact: $token"
  fi
done

# Structure-only in CI: the skill must state that CI checks structure only.
if grep -Eiq "structur(e|al)[^.]*(only|in ci|ci)" "$SKILL_MD"; then
  ok "SKILL.md states CI validates structure only"
else
  bad "SKILL.md must state CI validates the triplet structurally only"
fi

# Out-of-band judge: the skill must document an opt-in runner that invokes the
# judge OUTSIDE CI, and explicitly never in CI.
if grep -Fiq "out-of-band" "$SKILL_MD"; then
  ok "SKILL.md documents an out-of-band judge runner"
else
  bad "SKILL.md must document an out-of-band judge runner"
fi
if grep -Eiq "(never|not) (in|invoked in|run in) ci|ci never" "$SKILL_MD"; then
  ok "SKILL.md states the judge is never invoked in CI"
else
  bad "SKILL.md must state the judge runner is never invoked in CI"
fi

# -----------------------------------------------------------------------------
# 3. If the skill ships a generator script, it produces a valid triplet offline.
# -----------------------------------------------------------------------------
GEN=""
for cand in "$SKILL_DIR"/scaffold-eval.py "$SKILL_DIR"/*.py; do
  [ -f "$cand" ] && { GEN="$cand"; break; }
done

if [ -z "$GEN" ]; then
  ok "no generator script shipped (documentation-only skill is acceptable)"
else
  ok "generator script shipped: $(basename "$GEN")"
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  # The generator must produce a valid triplet for a sample target, offline,
  # writing under <root>/.ai/evals/<target>/. Invocation contract:
  #   scaffold-eval.py --skill <target> --root <dir>
  if python3 "$GEN" --skill sample-target --root "$WORK" >/dev/null 2>&1; then
    ok "generator runs offline for a sample target"
  else
    bad "generator must run offline for a sample target"
  fi
  if triplet_is_valid "$WORK/.ai/evals/sample-target"; then
    ok "generated triplet for sample-target is structurally valid"
  else
    bad "generated triplet for sample-target must be structurally valid"
  fi
  # Re-run must not corrupt or duplicate (idempotent / additive).
  if python3 "$GEN" --skill sample-target --root "$WORK" >/dev/null 2>&1 \
     && triplet_is_valid "$WORK/.ai/evals/sample-target"; then
    ok "generator is safe to re-run (idempotent)"
  else
    bad "generator must be safe to re-run"
  fi
  # judge-config must declare out-of-band execution (CI never invokes it).
  JC="$WORK/.ai/evals/sample-target/judge-config.json"
  if [ -f "$JC" ] && python3 - "$JC" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
j = d.get("judge", {})
sys.exit(0 if j.get("execution") == "out-of-band" else 1)
PY
  then
    ok "generated judge-config declares execution=out-of-band"
  else
    bad "generated judge-config must declare execution=out-of-band"
  fi
fi

# -----------------------------------------------------------------------------
# 4. A committed `kind: trajectory` evalset fixture exists, parses, and is
#    structurally valid; and (if the generator supports it) `--kind trajectory`
#    produces a matching valid triplet offline.
# -----------------------------------------------------------------------------
TRAJ_FIXTURE="$REPO_ROOT/reference/fixtures/v3/standalone/.ai/evals/example-trajectory-eval"
if triplet_is_valid "$TRAJ_FIXTURE"; then
  ok "committed trajectory-kind fixture is structurally valid"
else
  bad "committed trajectory-kind fixture must be structurally valid ($TRAJ_FIXTURE)"
fi

# evalset.json must declare kind: trajectory.
if [ -f "$TRAJ_FIXTURE/evalset.json" ] && python3 - "$TRAJ_FIXTURE/evalset.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("kind") == "trajectory" else 1)
PY
then
  ok "committed trajectory fixture declares kind: trajectory"
else
  bad "committed trajectory fixture must declare kind: trajectory"
fi

# Generator must produce a matching valid triplet for --kind trajectory, offline.
if [ -n "$GEN" ]; then
  TWORK="$(mktemp -d)"
  trap 'rm -rf "$WORK" "$TWORK"' EXIT
  if python3 "$GEN" --skill traj-target --root "$TWORK" --kind trajectory >/dev/null 2>&1 \
     && triplet_is_valid "$TWORK/.ai/evals/traj-target"; then
    ok "generator produces a valid triplet for --kind trajectory"
  else
    bad "generator must produce a valid triplet for --kind trajectory"
  fi
  if [ -f "$TWORK/.ai/evals/traj-target/evalset.json" ] && python3 - "$TWORK/.ai/evals/traj-target/evalset.json" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("kind") == "trajectory" else 1)
PY
  then
    ok "generated --kind trajectory triplet declares kind: trajectory"
  else
    bad "generated --kind trajectory triplet must declare kind: trajectory"
  fi
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
