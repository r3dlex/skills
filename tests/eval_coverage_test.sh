#!/bin/bash
#
# eval_coverage_test.sh
#
# Offline, deterministic structural validation of the eval-coverage gate (P0-1,
# plan decisions D1/D2). NO model or network access is used anywhere in this
# test: every assertion is pure-shell + python3 JSON parsing.
#
# The gate models the rule from ADR-0002 / plan D1:
#   - "Shippable capability" = a skill CHANGED in the PR diff that declares an
#     `eval:` key in its frontmatter.
#   - A changed shippable skill must reference a structurally valid evalset
#     (an `.ai/evals/<set>/` directory containing evalset.json + rubric.md +
#     judge-config.json, each structurally valid).
#   - An audited-exception token (mirroring the >280-char description exception)
#     lets a doc-only / non-shippable change bypass the gate.
#
# This test exercises a self-contained reference implementation of the gate
# (eval_coverage_gate below) against in-test fixtures, proving:
#   1. valid eval declaration + valid evalset -> PASS (exit 0)
#   2. eval declaration + missing/malformed evalset -> FAIL (non-zero)
#   3. audited-exception token -> PASS (exit 0)
#
# It also asserts the gate is documented with the exact required wording in the
# init-ai-repo CI policy module.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# -----------------------------------------------------------------------------
# Structural validators (pure shell + python3, offline).
# -----------------------------------------------------------------------------

# parse_json <file> -> exit 0 if the file parses as JSON, non-zero otherwise.
parse_json() {
  python3 -m json.tool "$1" >/dev/null 2>&1
}

# json_has_key <file> <key> -> exit 0 if top-level key present and non-empty.
json_has_key() {
  python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, sys
data = json.load(open(sys.argv[1]))
key = sys.argv[2]
v = data.get(key)
sys.exit(0 if v not in (None, "", [], {}) else 1)
PY
}

# evalset_is_valid <evalset_dir>
#   A structurally valid evalset directory contains:
#     - evalset.json     : parses; declares schema_version, set_id, cases (non-empty)
#     - rubric.md        : exists and is non-empty
#     - judge-config.json: parses; declares schema_version and judge
#   Returns 0 when all checks pass, non-zero otherwise.
evalset_is_valid() {
  local dir="$1"
  [ -d "$dir" ] || return 1

  local evalset="$dir/evalset.json"
  local rubric="$dir/rubric.md"
  local judge="$dir/judge-config.json"

  [ -f "$evalset" ] || return 1
  [ -f "$rubric" ]  || return 1
  [ -f "$judge" ]   || return 1

  parse_json "$evalset" || return 1
  parse_json "$judge"   || return 1

  [ -s "$rubric" ] || return 1

  json_has_key "$evalset" "schema_version" || return 1
  json_has_key "$evalset" "set_id"         || return 1
  json_has_key "$evalset" "cases"          || return 1
  json_has_key "$judge"   "schema_version" || return 1
  json_has_key "$judge"   "judge"          || return 1

  return 0
}

# skill_declares_eval <skill_md> -> 0 if frontmatter declares a non-empty eval: key.
skill_declares_eval() {
  python3 - "$1" <<'PY' 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---", text, re.S)
if not m:
    sys.exit(1)
fm = m.group(1)
for line in fm.splitlines():
    mm = re.match(r"\s*eval:\s*(\S.*)$", line)
    if mm and mm.group(1).strip():
        sys.exit(0)
sys.exit(1)
PY
}

# eval_coverage_gate <repo_dir> <changed_skill_md> [audited_exception_token]
#   Reference implementation of the offline, diff-aware eval-coverage gate.
#   - Exit 0 (pass) when:
#       * the changed skill does NOT declare eval: (not a shippable capability), OR
#       * an audited-exception token is supplied, OR
#       * the declared eval: points to a structurally valid evalset.
#   - Exit 1 (fail) when a changed skill declares eval: but the referenced
#     evalset is missing or malformed and no exception token is supplied.
eval_coverage_gate() {
  local repo_dir="$1"
  local skill_md="$2"
  local exception_token="${3:-}"

  # Audited-exception path: a non-empty token bypasses the gate (mirrors the
  # >280-char description-exception escape hatch).
  if [ -n "$exception_token" ]; then
    return 0
  fi

  # D1 trigger: only a changed skill that declares eval: is a shippable capability.
  if ! skill_declares_eval "$skill_md"; then
    return 0
  fi

  # Resolve the referenced evalset name from the eval: key.
  local set_name
  set_name="$(python3 - "$skill_md" <<'PY' 2>/dev/null
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---", text, re.S)
fm = m.group(1) if m else ""
for line in fm.splitlines():
    mm = re.match(r"\s*eval:\s*(\S.*)$", line)
    if mm:
        print(mm.group(1).strip())
        break
PY
)"

  [ -n "$set_name" ] || return 1

  evalset_is_valid "$repo_dir/.ai/evals/$set_name"
}

# -----------------------------------------------------------------------------
# Fixtures (created in a temp dir; offline; cleaned up on exit).
# -----------------------------------------------------------------------------

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

make_valid_evalset() {
  local dir="$1" set_id="$2"
  mkdir -p "$dir"
  cat > "$dir/evalset.json" <<JSON
{
  "schema_version": "1.0",
  "set_id": "$set_id",
  "kind": "output",
  "cases": [
    {
      "case_id": "case-001",
      "input": "Example task input.",
      "expected_behavior": "Produces a structurally valid artifact.",
      "trajectory": ["read", "edit", "verify"]
    }
  ]
}
JSON
  cat > "$dir/rubric.md" <<'MD'
# Rubric

| Criterion | Weight | Passing bar |
| --- | --- | --- |
| Correctness | 0.6 | Output matches expected behavior. |
| Trajectory | 0.4 | Tool-call sequence is sound. |
MD
  cat > "$dir/judge-config.json" <<'JSON'
{
  "schema_version": "1.0",
  "judge": {
    "tier": "frontier",
    "mode": "lm-judge",
    "harness": "stub",
    "evaluates": ["output", "trajectory"]
  }
}
JSON
}

# Fixture 1: shippable skill + valid evalset -> PASS.
mkdir -p "$WORK/repo1"
make_valid_evalset "$WORK/repo1/.ai/evals/example-set" "example-set"
cat > "$WORK/repo1/example-skill.md" <<'MD'
---
name: example-skill
description: A shippable example skill.
eval: example-set
---
# Example
MD

# Fixture 2: shippable skill + malformed evalset (broken JSON) -> FAIL.
mkdir -p "$WORK/repo2/.ai/evals/broken-set"
echo '{ this is not valid json' > "$WORK/repo2/.ai/evals/broken-set/evalset.json"
echo '# Rubric' > "$WORK/repo2/.ai/evals/broken-set/rubric.md"
echo '{}' > "$WORK/repo2/.ai/evals/broken-set/judge-config.json"
cat > "$WORK/repo2/example-skill.md" <<'MD'
---
name: example-skill
description: A shippable example skill with a broken evalset.
eval: broken-set
---
# Example
MD

# Fixture 3: shippable skill + MISSING evalset directory -> FAIL.
mkdir -p "$WORK/repo3/.ai/evals"
cat > "$WORK/repo3/missing-skill.md" <<'MD'
---
name: missing-skill
description: A shippable skill whose evalset does not exist.
eval: ghost-set
---
# Example
MD

# Fixture 4: doc-only changed file (no eval: key) -> PASS (not shippable).
mkdir -p "$WORK/repo4/.ai/evals"
cat > "$WORK/repo4/doc-skill.md" <<'MD'
---
name: doc-skill
description: A skill that declares no eval and is therefore not gated.
---
# Doc only
MD

# -----------------------------------------------------------------------------
# Assertions
# -----------------------------------------------------------------------------

echo "Eval Coverage Gate Tests"
echo "========================"
echo ""

# 1. Valid declaration + valid evalset PASSES.
if eval_coverage_gate "$WORK/repo1" "$WORK/repo1/example-skill.md"; then
  ok "valid eval declaration + structurally valid evalset passes"
else
  bad "valid eval declaration + structurally valid evalset should pass"
fi

# 2a. Malformed evalset FAILS (non-zero).
if eval_coverage_gate "$WORK/repo2" "$WORK/repo2/example-skill.md"; then
  bad "malformed evalset should fail the gate"
else
  ok "changed skill with malformed evalset fails (non-zero)"
fi

# 2b. Missing evalset FAILS (non-zero).
if eval_coverage_gate "$WORK/repo3" "$WORK/repo3/missing-skill.md"; then
  bad "missing evalset should fail the gate"
else
  ok "changed skill with missing evalset fails (non-zero)"
fi

# 3. Audited-exception token PASSES even with a missing evalset.
if eval_coverage_gate "$WORK/repo3" "$WORK/repo3/missing-skill.md" "AUDITED-EXCEPTION-0001"; then
  ok "audited-exception token path passes"
else
  bad "audited-exception token path should pass"
fi

# 4. Doc-only (no eval: key) changed file PASSES (not a shippable capability).
if eval_coverage_gate "$WORK/repo4" "$WORK/repo4/doc-skill.md"; then
  ok "doc-only change without eval declaration is not gated (passes)"
else
  bad "doc-only change without eval declaration should pass"
fi

# 5. The committed v3 golden fixtures carry a structurally valid evalset.
for variant in standalone umbrella; do
  set_dir="$REPO_ROOT/reference/fixtures/v3/$variant/.ai/evals/example-output-eval"
  if evalset_is_valid "$set_dir"; then
    ok "v3 $variant golden evalset is structurally valid"
  else
    bad "v3 $variant golden evalset must be structurally valid ($set_dir)"
  fi
done

# 6. The gate is documented with the required wording in the CI policy module.
CI_POLICY="$REPO_ROOT/init-ai-repo/modules/ci-policy.md"
if grep -Fq "structurally valid eval declaration required" "$CI_POLICY"; then
  ok "ci-policy.md PR-merge-gate states the eval-coverage requirement"
else
  bad "ci-policy.md must state 'structurally valid eval declaration required'"
fi
if grep -Fq "eval quality is verified via an out-of-band LM-judge run" "$CI_POLICY"; then
  ok "ci-policy.md carries the honest out-of-band LM-judge caveat"
else
  bad "ci-policy.md must carry the out-of-band LM-judge quality caveat"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
