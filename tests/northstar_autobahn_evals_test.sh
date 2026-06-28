#!/bin/bash
#
# northstar_autobahn_evals_test.sh
#
# Offline, deterministic structural validation that the northstar and autobahn
# skills each declare an `eval:` frontmatter key bound to a structurally valid
# eval triplet under .ai/evals/<set>/. This is the real-repo counterpart to the
# fixture-driven eval_coverage_test.sh: it proves the two shipped skills actually
# carry the coverage the eval-coverage gate would require for a changed skill that
# declares `eval:`.
#
# NO model or network access. Every assertion is pure shell + python3 JSON parse.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "python3 is required (fail-closed prerequisite)." >&2; exit 2; }

# eval_key <skill_md> -> prints the frontmatter eval: value (empty if none).
eval_key() {
  python3 - "$1" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
m = re.match(r"^---\n(.*?)\n---", text, re.S)
fm = m.group(1) if m else ""
for line in fm.splitlines():
    mm = re.match(r"\s*eval:\s*(\S.*)$", line)
    if mm:
        print(mm.group(1).strip()); break
PY
}

# validate_triplet <skill> <set_name>: structural validity + cross-checks.
validate_triplet() {
  local skill="$1" set_name="$2"
  local dir=".ai/evals/$set_name"

  if [[ -z "$set_name" ]]; then
    bad "$skill: declares an eval: frontmatter key"; return
  fi
  ok "$skill: declares eval: $set_name"

  for f in evalset.json rubric.md judge-config.json; do
    if [[ -f "$dir/$f" ]]; then ok "$skill: $dir/$f exists"; else bad "$skill: $dir/$f exists"; fi
  done

  python3 - "$dir" "$skill" <<'PY'
import json, sys, os
dir_, skill = sys.argv[1], sys.argv[2]
fails = []

es_path = os.path.join(dir_, "evalset.json")
try:
    es = json.load(open(es_path))
    for k in ("schema_version", "set_id", "cases"):
        if not es.get(k):
            fails.append(f"evalset missing/empty key: {k}")
    if es.get("kind") not in ("output", "trajectory"):
        fails.append(f"evalset kind {es.get('kind')!r} not in (output, trajectory)")
    cases = es.get("cases") or []
    if not isinstance(cases, list) or not cases:
        fails.append("evalset cases must be a non-empty list")
    ids = [c.get("case_id") for c in cases]
    if len(ids) != len(set(ids)):
        fails.append("duplicate case_id in evalset")
    for c in cases:
        for k in ("case_id", "input", "expected_behavior"):
            if not c.get(k):
                fails.append(f"case {c.get('case_id')!r} missing {k}")
    if es.get("skill_under_test") not in (None, skill):
        fails.append(f"skill_under_test {es.get('skill_under_test')!r} != {skill!r}")
except Exception as e:
    fails.append(f"evalset.json invalid: {e}")

jc_path = os.path.join(dir_, "judge-config.json")
try:
    jc = json.load(open(jc_path))
    if not jc.get("schema_version"):
        fails.append("judge-config missing schema_version")
    if not jc.get("judge"):
        fails.append("judge-config missing judge")
    elif jc["judge"].get("execution") != "out-of-band":
        fails.append("judge.execution must be out-of-band")
except Exception as e:
    fails.append(f"judge-config.json invalid: {e}")

rb_path = os.path.join(dir_, "rubric.md")
try:
    rb = open(rb_path).read()
    if not rb.strip():
        fails.append("rubric.md is empty")
    import re
    weights = [float(x) for x in re.findall(r"\|\s*([01]\.\d+)\s*\|\s*[^|]*\|\s*$", rb, re.M)]
    # fall back: collect weights from the 3rd column of table rows
    if not weights:
        weights = [float(m) for m in re.findall(r"\|\s*\w[^|]*\|\s*\w+\s*\|\s*([01]\.\d+)\s*\|", rb)]
    total = round(sum(weights), 4)
    if not weights:
        fails.append("rubric.md declares no parseable weights")
    elif total != 1.0:
        fails.append(f"rubric weights sum to {total}, expected 1.0")
except Exception as e:
    fails.append(f"rubric.md invalid: {e}")

if fails:
    print("FAILDETAIL:" + "; ".join(fails)); sys.exit(1)
sys.exit(0)
PY
  if [[ $? -eq 0 ]]; then
    ok "$skill: eval triplet is structurally valid (cases, judge out-of-band, weights sum to 1.0)"
  else
    bad "$skill: eval triplet structural validation"
  fi
}

validate_triplet "northstar" "$(eval_key northstar/SKILL.md)"
validate_triplet "autobahn"  "$(eval_key autobahn/SKILL.md)"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
