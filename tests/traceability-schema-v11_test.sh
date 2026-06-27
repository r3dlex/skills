#!/bin/bash
# P1-6 / D4: Traceability graph schema 1.1 (additive).
#
# Proves:
#   - The validator accepts a >= 1.1 graph carrying the new `eval-result`
#     and `trajectory-trace` node types.
#   - Existing v1.0 fixtures remain valid under the bumped validator (back-compat).
#   - An unknown node type is still rejected.
#   - `modules/traceability.md` documents schema 1.1 and the two new types.
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

# --- 2. New fixture: a >= 1.1 graph carrying an eval-result node validates ----
new_fixture = ROOT / "reference/fixtures/v3/umbrella/.ai/traceability/graph-1.1.json"
assert new_fixture.is_file(), f"missing 1.1 fixture {new_fixture}"
g11 = json.loads(new_fixture.read_text())
assert parse_version(g11["schema_version"]) >= (1, 1), (
    f"fixture must declare >= 1.1, got {g11['schema_version']}")
present_types = {n["type"] for n in g11["nodes"]}
assert "eval-result" in present_types, "1.1 fixture must carry an eval-result node"
assert "trajectory-trace" in present_types, "1.1 fixture must carry a trajectory-trace node"
validate_graph(g11)
print("PASS: 1.1 fixture with eval-result + trajectory-trace validates")

# --- 3. Negative: an unknown node type is still rejected ----------------------
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
