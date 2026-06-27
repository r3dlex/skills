#!/bin/bash
# P1-6 / D4: Traceability graph schema 1.1 (additive).
# P2-2: eval-result/trajectory-trace nodes wired to REAL eval fixtures.
#
# Proves:
#   - The validator accepts a >= 1.1 graph carrying the new `eval-result`
#     and `trajectory-trace` node types.
#   - Existing v1.0 fixtures remain valid under the bumped validator (back-compat).
#   - An unknown node type is still rejected.
#   - `modules/traceability.md` documents schema 1.1 and the two new types.
#   - P2-2 end-to-end wiring: BOTH the standalone AND umbrella 1.1 graphs
#     validate; an `eval-result` node links (via `evaluated-by`) to a
#     skill/PR/test node; a `trajectory-trace` node links (via `traced-by`)
#     to its eval-result; and every eval/trajectory node references a REAL
#     eval fixture path that exists on disk.
#
# Offline / deterministic: no network, no credentials. Uses an in-test
# reference validator that mirrors modules/traceability.md's required checks.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
import json
import re
import sys
from pathlib import Path

ROOT = Path(".")

# --- The schema-1.1 type enum (additive over v1.0) ---------------------------
V10_TYPES = {
    "brd", "prd", "adr", "plan", "issue", "pr",
    "test", "handoff", "workflow", "validation",
}
V11_ADDED_TYPES = {"eval-result", "trajectory-trace"}
KNOWN_TYPES = V10_TYPES | V11_ADDED_TYPES


def parse_version(v: str):
    return tuple(int(p) for p in str(v).split("."))


def validate_graph(graph: dict) -> None:
    """Reference validator mirroring modules/traceability.md required checks.

    Accepts schema_version >= 1.1 with the new types, and any 1.x graph whose
    node types are all in the known enum. Raises AssertionError on violation.
    """
    version = parse_version(graph["schema_version"])
    assert version >= (1, 0), f"unsupported schema_version {graph['schema_version']}"

    nodes = {n["id"]: n for n in graph["nodes"]}
    for node in nodes.values():
        assert node["type"] in KNOWN_TYPES, f"unknown node type {node['type']!r}"
        assert node["id"], "node missing id"
        assert node["title"], f"node {node['id']} missing title"
        assert node["status"], f"node {node['id']} missing status"
        assert node["repo_id"], f"node {node['id']} missing repo_id"
        assert node.get("path") or node.get("host_url"), (
            f"node {node['id']} missing path/host_url")
        for backlink in node.get("backlinks", []):
            assert backlink in nodes, f"dangling backlink {backlink}"
    for edge in graph["edges"]:
        assert edge["source"] in nodes, f"dangling edge source {edge}"
        assert edge["target"] in nodes, f"dangling edge target {edge}"


# --- 1. Back-compat: both existing v1.0 fixtures still validate ---------------
for fixture in ("standalone", "umbrella"):
    graph_path = ROOT / "reference/fixtures/v3" / fixture / ".ai/traceability/graph.json"
    graph = json.loads(graph_path.read_text())
    assert parse_version(graph["schema_version"]) >= (1, 0)
    validate_graph(graph)
print("PASS: existing v1.0 fixtures remain valid")

# --- 2. End-to-end wiring: BOTH 1.1 graphs validate with wired eval nodes -----
# The P2-2 symmetry item: standalone AND umbrella each ship a graph-1.1.json
# whose eval-result/trajectory-trace nodes are wired to REAL eval fixtures.
WORK_ITEM_TYPES = {"skill", "pr", "test", "issue", "plan"}


def fixture_eval_root(fixture: str) -> Path:
    return ROOT / "reference/fixtures/v3" / fixture / ".ai"


def assert_wired(fixture: str) -> None:
    g11_path = fixture_eval_root(fixture).parent / ".ai/traceability/graph-1.1.json"
    assert g11_path.is_file(), f"missing 1.1 fixture {g11_path}"
    graph = json.loads(g11_path.read_text())
    assert parse_version(graph["schema_version"]) >= (1, 1), (
        f"{fixture} fixture must declare >= 1.1, got {graph['schema_version']}")

    nodes = {n["id"]: n for n in graph["nodes"]}
    present_types = {n["type"] for n in graph["nodes"]}
    assert "eval-result" in present_types, (
        f"{fixture} 1.1 fixture must carry an eval-result node")
    assert "trajectory-trace" in present_types, (
        f"{fixture} 1.1 fixture must carry a trajectory-trace node")

    # Validator (schema + dangling-edge/backlink) must pass.
    validate_graph(graph)

    # Index edges by relation for the wiring assertions.
    edges = graph["edges"]

    # 2a. An eval-result node is linked to a work item (skill/PR/test/...) via
    #     an `evaluated-by` edge whose target is the eval-result node.
    eval_result_ids = {n["id"] for n in graph["nodes"] if n["type"] == "eval-result"}
    evaluated_by = [
        e for e in edges
        if e["relation"] == "evaluated-by" and e["target"] in eval_result_ids
    ]
    assert evaluated_by, (
        f"{fixture}: expected an `evaluated-by` edge into an eval-result node")
    for e in evaluated_by:
        src = nodes[e["source"]]
        assert src["type"] in WORK_ITEM_TYPES, (
            f"{fixture}: evaluated-by source {src['id']} must be a work item "
            f"(skill/pr/test/...), got {src['type']!r}")

    # 2b. A trajectory-trace node is linked to its eval-result via a
    #     `traced-by` edge (eval-result -> trajectory-trace).
    traj_ids = {n["id"] for n in graph["nodes"] if n["type"] == "trajectory-trace"}
    traced_by = [
        e for e in edges
        if e["relation"] == "traced-by"
        and e["source"] in eval_result_ids
        and e["target"] in traj_ids
    ]
    assert traced_by, (
        f"{fixture}: expected a `traced-by` edge from an eval-result to a "
        f"trajectory-trace node")

    # 2c. Every eval-result/trajectory-trace node references a REAL eval
    #     fixture path that exists on disk (relative to the fixture repo root).
    fixture_repo_root = fixture_eval_root(fixture).parent
    for node in graph["nodes"]:
        if node["type"] not in ("eval-result", "trajectory-trace"):
            continue
        rel = node.get("path")
        assert rel, f"{fixture}: {node['id']} must carry a path"
        assert rel.startswith(".ai/evals/"), (
            f"{fixture}: {node['id']} path must point into .ai/evals/, got {rel!r}")
        on_disk = fixture_repo_root / rel
        assert on_disk.is_file(), (
            f"{fixture}: {node['id']} references non-existent eval fixture {on_disk}")


for fixture in ("standalone", "umbrella"):
    assert_wired(fixture)
print("PASS: standalone + umbrella 1.1 graphs validate with wired eval nodes")
print("PASS: eval-result evaluated-by work item; trajectory-trace traced-by eval-result")
print("PASS: eval/trajectory nodes reference real on-disk eval fixtures")

# --- 3. Negative: an unknown node type is still rejected ----------------------
new_fixture = ROOT / "reference/fixtures/v3/umbrella/.ai/traceability/graph-1.1.json"
bad = json.loads(new_fixture.read_text())
bad["nodes"].append({
    "id": "bogus:umbrella-root:nope",
    "type": "bogus-type",
    "title": "unknown type",
    "status": "active",
    "repo_id": "umbrella-root",
    "path": "README.md",
})
try:
    validate_graph(bad)
except AssertionError:
    print("PASS: unknown node type rejected")
else:
    print("FAIL: unknown node type was accepted")
    sys.exit(1)

# --- 4. Module documents schema 1.1 and the two new types ---------------------
module = (ROOT / "init-ai-repo/modules/traceability.md").read_text()
assert "schema v1.1" in module or '"1.1"' in module, "module must document schema 1.1"
assert "eval-result" in module, "module must document eval-result type"
assert "trajectory-trace" in module, "module must document trajectory-trace type"
assert re.search(r"accepts?[^.]*1\.1|>=\s*1\.1|>=\s*`1\.1`", module), (
    "module must state validator accepts >= 1.1")
print("PASS: module documents schema 1.1 and new types")

print("traceability schema 1.1 test passed")
PY
