#!/bin/bash
#
# lm_judge_demo_test.sh
#
# Offline, deterministic validation of the out-of-band LM-judge DEMONSTRATION
# evidence artifact (P1-8, Minor-2a / Architect rec #3). NO model or network
# access is used anywhere in this test: every assertion is pure-shell + python3
# JSON parsing.
#
# The artifact is RECORDED out-of-band evidence (not a CI gate) proving the
# "structural-in-CI + quality-out-of-band" eval split actually works end-to-end.
# This test asserts the artifact:
#   1. exists and parses as JSON;
#   2. references a REAL fixture evalset + rubric (paths that exist on disk);
#   3. carries an aggregate score, a per-criterion judgment for EVERY rubric
#      criterion, and an aggregate-vs-threshold verdict;
#   4. carries an illustrative judge model + timestamp placeholder;
#   5. carries the explicit "recorded out-of-band demonstration, not a CI gate"
#      disclaimer;
#   6. is consistent with the rubric: one judgment per rubric criterion, and the
#      judged criteria names match the rubric's criteria names.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

EVAL_DIR="$REPO_ROOT/reference/fixtures/v3/standalone/.ai/evals/example-output-eval"
ARTIFACT="$EVAL_DIR/judgment-demo.json"
RUBRIC="$EVAL_DIR/rubric.md"
EVALSET="$EVAL_DIR/evalset.json"

echo "Out-of-Band LM-Judge Demonstration Tests"
echo "========================================"
echo ""

# -----------------------------------------------------------------------------
# 1. Artifact exists and parses as JSON.
# -----------------------------------------------------------------------------
if [ -f "$ARTIFACT" ]; then
  ok "demonstration evidence artifact exists"
else
  bad "demonstration evidence artifact must exist ($ARTIFACT)"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

if python3 -m json.tool "$ARTIFACT" >/dev/null 2>&1; then
  ok "artifact parses as JSON"
else
  bad "artifact must parse as JSON"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Referenced fixture evalset + rubric paths exist on disk.
# -----------------------------------------------------------------------------
# Extract the referenced relative paths from the artifact and resolve them
# against the repo root, asserting the targets are REAL committed files.
REF_OK="$(python3 - "$ARTIFACT" "$REPO_ROOT" "$EVALSET" "$RUBRIC" <<'PY'
import json, os, sys
artifact, repo_root, evalset, rubric = sys.argv[1:5]
data = json.load(open(artifact))
ref = data.get("eval_under_judgment", {})
ev = os.path.join(repo_root, ref.get("evalset", ""))
ru = os.path.join(repo_root, ref.get("rubric", ""))
ok = (os.path.realpath(ev) == os.path.realpath(evalset)
      and os.path.realpath(ru) == os.path.realpath(rubric)
      and os.path.isfile(ev) and os.path.isfile(ru))
print("yes" if ok else "no")
PY
)"
if [ "$REF_OK" = "yes" ]; then
  ok "artifact references the real fixture evalset + rubric (paths exist)"
else
  bad "artifact must reference the real fixture evalset.json + rubric.md"
fi

# Referenced skill_under_test must match the evalset's declared skill.
SKILL_OK="$(python3 - "$ARTIFACT" "$EVALSET" <<'PY'
import json, sys
artifact, evalset = sys.argv[1:3]
a = json.load(open(artifact))
e = json.load(open(evalset))
ref_skill = a.get("eval_under_judgment", {}).get("skill_under_test")
print("yes" if ref_skill and ref_skill == e.get("skill_under_test") else "no")
PY
)"
if [ "$SKILL_OK" = "yes" ]; then
  ok "artifact's skill_under_test matches the evalset's skill_under_test"
else
  bad "artifact's skill_under_test must match the evalset declaration"
fi

# -----------------------------------------------------------------------------
# 3. Aggregate score, per-criterion judgments, threshold verdict present.
# -----------------------------------------------------------------------------
SCORE_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
agg = d.get("aggregate_score")
thr = d.get("passing_threshold")
verdict = d.get("verdict")
ok = (isinstance(agg, (int, float)) and 0 <= agg <= 1
      and isinstance(thr, (int, float)) and 0 <= thr <= 1
      and verdict in ("pass", "fail"))
print("yes" if ok else "no")
PY
)"
if [ "$SCORE_OK" = "yes" ]; then
  ok "artifact carries aggregate_score, passing_threshold, and a verdict"
else
  bad "artifact must carry numeric aggregate_score/passing_threshold and a pass|fail verdict"
fi

# Verdict is internally consistent with score vs threshold.
VERDICT_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
agg = d.get("aggregate_score")
thr = d.get("passing_threshold")
verdict = d.get("verdict")
expected = "pass" if agg >= thr else "fail"
print("yes" if verdict == expected else "no")
PY
)"
if [ "$VERDICT_OK" = "yes" ]; then
  ok "verdict is consistent with aggregate_score vs passing_threshold"
else
  bad "verdict must equal pass iff aggregate_score >= passing_threshold"
fi

# Each judgment carries a criterion name, a numeric score, and a rationale.
JUDGE_SHAPE_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
js = d.get("criterion_judgments")
if not isinstance(js, list) or not js:
    print("no"); sys.exit()
for j in js:
    if not isinstance(j, dict): print("no"); sys.exit()
    if not j.get("criterion"): print("no"); sys.exit()
    s = j.get("score")
    if not (isinstance(s, (int, float)) and 0 <= s <= 1): print("no"); sys.exit()
    if not (isinstance(j.get("rationale"), str) and j["rationale"].strip()):
        print("no"); sys.exit()
print("yes")
PY
)"
if [ "$JUDGE_SHAPE_OK" = "yes" ]; then
  ok "every criterion judgment has a criterion, numeric score, and rationale"
else
  bad "each criterion judgment must carry criterion + numeric score + rationale"
fi

# -----------------------------------------------------------------------------
# 4. Illustrative judge model + timestamp placeholder present.
# -----------------------------------------------------------------------------
META_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
model = d.get("judge_model")
ts = d.get("recorded_at")
print("yes" if (isinstance(model, str) and model.strip()
                and isinstance(ts, str) and ts.strip()) else "no")
PY
)"
if [ "$META_OK" = "yes" ]; then
  ok "artifact carries an illustrative judge_model and recorded_at timestamp"
else
  bad "artifact must carry judge_model and recorded_at (timestamp placeholder)"
fi

# -----------------------------------------------------------------------------
# 5. Out-of-band, not-a-CI-gate disclaimer present.
# -----------------------------------------------------------------------------
if grep -Fq "recorded out-of-band demonstration, not a CI gate" "$ARTIFACT"; then
  ok "artifact carries the recorded out-of-band / not-a-CI-gate disclaimer"
else
  bad "artifact must carry the 'recorded out-of-band demonstration, not a CI gate' disclaimer"
fi

# -----------------------------------------------------------------------------
# 6. One judgment per rubric criterion; judged names match rubric criteria.
# -----------------------------------------------------------------------------
# Rubric criteria are the first table column rows (excluding the header and the
# separator row).
RUBRIC_CRITERIA="$(python3 - "$RUBRIC" <<'PY'
import re, sys
crit = []
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if not cells:
        continue
    name = cells[0]
    if name in ("", "Criterion") or set(name) <= set("- "):
        continue
    crit.append(name)
for c in crit:
    print(c)
PY
)"

CONSISTENT_OK="$(python3 - "$ARTIFACT" <<'PY' "$RUBRIC_CRITERIA"
import json, sys
d = json.load(open(sys.argv[1]))
judged = [j.get("criterion") for j in d.get("criterion_judgments", [])]
rubric = [c for c in sys.argv[2].splitlines() if c.strip()]
print("yes" if sorted(judged) == sorted(rubric) and len(judged) == len(rubric) else "no")
PY
)"
if [ "$CONSISTENT_OK" = "yes" ]; then
  ok "exactly one judgment per rubric criterion; names match the rubric"
else
  bad "criterion judgments must be one-per-rubric-criterion with matching names"
fi

# The aggregate score equals the rubric-weighted sum of per-criterion scores.
# Weights come from the rubric's Weight column (third cell of each criterion row).
RUBRIC_WEIGHTS="$(python3 - "$RUBRIC" <<'PY'
import sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line.startswith("|"):
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) < 3:
        continue
    name = cells[0]
    if name in ("", "Criterion") or set(name) <= set("- "):
        continue
    print(f"{name}\t{cells[2]}")
PY
)"
WEIGHTED_OK="$(python3 - "$ARTIFACT" <<'PY' "$RUBRIC_WEIGHTS"
import json, sys
d = json.load(open(sys.argv[1]))
weights = {}
for row in sys.argv[2].splitlines():
    if not row.strip():
        continue
    name, w = row.split("\t")
    weights[name] = float(w)
total = 0.0
for j in d.get("criterion_judgments", []):
    total += j["score"] * weights.get(j["criterion"], 0.0)
print("yes" if abs(total - d.get("aggregate_score", -1)) < 1e-6 else "no")
PY
)"
if [ "$WEIGHTED_OK" = "yes" ]; then
  ok "aggregate_score equals the rubric-weighted sum of per-criterion scores"
else
  bad "aggregate_score must equal the rubric-weighted sum of per-criterion scores"
fi

# -----------------------------------------------------------------------------
# 7. modules/evals.md references the worked example.
# -----------------------------------------------------------------------------
EVALS_MD="$REPO_ROOT/init-ai-repo/modules/evals.md"
if grep -Fq "judgment-demo.json" "$EVALS_MD"; then
  ok "modules/evals.md references the worked-example demonstration artifact"
else
  bad "modules/evals.md must reference judgment-demo.json as the worked example"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
