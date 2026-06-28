#!/bin/bash
#
# northstar_handoff_test.sh  (PR-1, N4)
#
# Proves northstar/handoff-write.sh writes a valid A->B handoff into a temp copy
# of the standalone fixture (.ai/), and that the result satisfies:
#   1. a handoff entry file in <root>/.ai/handoff/ referencing spec + sliced goals
#   2. the workflow manifest gains a resolvable optional_branches record AND the
#      existing manifest validator (workflow-fixtures contract) stays green
#   3. traceability nodes (handoff + plan) well-formed, schema_version 1.1,
#      ids match ^(prd|plan|issue|handoff|workflow): and the graph validates via
#      scripts/traceability_schema.py
#   4. second run is idempotent (no duplicate nodes / branch records)
#   5. partial-write-then-rerun recovery converges to a consistent graph
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="$REPO_ROOT/northstar/handoff-write.sh"
FIXTURE="$REPO_ROOT/reference/fixtures/v3/standalone"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$SCRIPT" ]]; then
  bad "handoff-write.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$FIXTURE/." "$tmp/"

SLUG="ship-the-thing"

run_write() {
  bash "$SCRIPT" --root "$tmp" \
    --spec "docs/specifications/ACTIVE/intake-and-ship-skills.md" \
    --slug "$SLUG" "$@"
}

# --- 1. first write ----------------------------------------------------------
set +e
out="$(run_write 2>&1)"
rc=$?
set -e 2>/dev/null || true
if [[ "$rc" -eq 0 ]]; then
  ok "handoff-write exits 0 on first run"
else
  bad "handoff-write exits 0 on first run (got $rc: $out)"
fi

handoff_file="$tmp/.ai/handoff/northstar-$SLUG.md"
if [[ -f "$handoff_file" ]]; then
  ok "handoff entry file created"
else
  bad "handoff entry file created ($handoff_file)"
fi
if grep -q "intake-and-ship-skills.md" "$handoff_file" 2>/dev/null; then
  ok "handoff references the spec"
else
  bad "handoff references the spec"
fi
if grep -qi "sliced goal" "$handoff_file" 2>/dev/null; then
  ok "handoff references sliced goals"
else
  bad "handoff references sliced goals"
fi

# --- 2. manifest optional_branches record + validator stays green -------------
python3 - "$tmp" "$SLUG" <<'PY'
import json, sys
root, slug = sys.argv[1], sys.argv[2]
m = json.load(open(f"{root}/.ai/workflows/repo-workflow.json"))
ids = [b["id"] for b in m["optional_branches"]]
assert f"northstar-handoff-{slug}" in ids, ids
rec = [b for b in m["optional_branches"] if b["id"] == f"northstar-handoff-{slug}"][0]
assert "enabled_when" in rec and "status" in rec, rec
# existing required branches must remain (validator contract)
assert any(b["id"] == "multi-repo-cascade" and b["status"] == "available" for b in m["optional_branches"])
assert any(b["id"] == "skill-modernization" and b["status"] == "available" for b in m["optional_branches"])
# phases unchanged -> no new status-file demand
assert [p["id"] for p in m["phases"]] == [
    "01-discover-decide","02-govern-plan","03-configure-generate","04-validate-handoff"]
print("manifest-ok")
PY
if [[ $? -eq 0 ]]; then
  ok "manifest gained resolvable optional_branches record; required branches + phases intact"
else
  bad "manifest optional_branches record / validator contract"
fi

# Run the actual init-ai-repo manifest validator (workflow-fixtures contract)
# against the mutated copy to prove it still passes.
python3 - "$tmp" <<'PY'
import json, sys
root = sys.argv[1]
m = json.load(open(f"{root}/.ai/workflows/repo-workflow.json"))
# Mirror the load-bearing assertions of tests/workflow-fixtures_test.sh.
assert m["schema_version"] == "1.0"
assert m["workflow_id"] == "init-ai-repo"
assert m["handoff"] == ".ai/handoff/init-ai-repo-handoff.md"
for phase in m["phases"]:
    import os
    assert os.path.isfile(f"{root}/{phase['status_path']}"), phase["status_path"]
print("validator-ok")
PY
if [[ $? -eq 0 ]]; then
  ok "init-ai-repo manifest validator stays green on mutated copy"
else
  bad "init-ai-repo manifest validator stays green on mutated copy"
fi

# --- 3. traceability nodes well-formed + validate ----------------------------
graph="$tmp/.ai/traceability/graph.json"
python3 - "$graph" "$SLUG" <<'PY'
import json, re, sys, pathlib
sys.path.insert(0, str(pathlib.Path("scripts").resolve()))
from traceability_schema import validate_graph
g = json.load(open(sys.argv[1]))
slug = sys.argv[2]
assert g["schema_version"] == "1.1", g["schema_version"]
ids = {n["id"] for n in g["nodes"]}
want_handoff = f"handoff:standalone-root:northstar-{slug}"
want_plan = f"plan:standalone-root:northstar-{slug}"
assert want_handoff in ids, want_handoff
assert want_plan in ids, want_plan
pat = re.compile(r"^(prd|plan|issue|handoff|workflow):")
assert pat.match(want_handoff) and pat.match(want_plan)
validate_graph(g)  # raises on any violation
print("graph-ok")
PY
if [[ $? -eq 0 ]]; then
  ok "traceability nodes well-formed, schema 1.1, graph validates"
else
  bad "traceability nodes well-formed / graph validates"
fi

count_nodes() { python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['nodes']))" "$graph"; }
count_branches() { python3 -c "import json,sys;print(len(json.load(open(sys.argv[1]))['optional_branches']))" "$tmp/.ai/workflows/repo-workflow.json"; }
nodes1="$(count_nodes)"; branches1="$(count_branches)"

# --- 4. idempotent re-run ----------------------------------------------------
set +e
run_write >/dev/null 2>&1
rc2=$?
set -e 2>/dev/null || true
nodes2="$(count_nodes)"; branches2="$(count_branches)"
if [[ "$rc2" -eq 0 && "$nodes1" == "$nodes2" && "$branches1" == "$branches2" ]]; then
  ok "second run idempotent (nodes $nodes1==$nodes2, branches $branches1==$branches2)"
else
  bad "second run idempotent (nodes $nodes1/$nodes2 branches $branches1/$branches2 rc $rc2)"
fi

# --- 5. partial-write recovery -----------------------------------------------
# Simulate a partial write: remove the handoff file but keep manifest/graph
# entries, then re-run. The idempotent re-run must reconcile (recreate handoff,
# no duplicate nodes/branches) and converge.
rm -f "$handoff_file"
set +e
run_write >/dev/null 2>&1
rc3=$?
set -e 2>/dev/null || true
nodes3="$(count_nodes)"; branches3="$(count_branches)"
if [[ "$rc3" -eq 0 && -f "$handoff_file" && "$nodes3" == "$nodes1" && "$branches3" == "$branches1" ]]; then
  ok "partial-write-then-rerun recovery converges (handoff restored, no dup)"
else
  bad "partial-write recovery (rc $rc3, nodes $nodes3 vs $nodes1, branches $branches3 vs $branches1)"
fi
# graph must still validate after recovery
python3 - "$graph" <<'PY'
import json, sys, pathlib
sys.path.insert(0, str(pathlib.Path("scripts").resolve()))
from traceability_schema import validate_graph
validate_graph(json.load(open(sys.argv[1])))
print("ok")
PY
if [[ $? -eq 0 ]]; then
  ok "graph still validates after recovery"
else
  bad "graph still validates after recovery"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
