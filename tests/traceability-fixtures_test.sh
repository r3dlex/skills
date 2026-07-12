#!/bin/bash
# Validate init-ai-repo traceability graph fixtures.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
import json
from pathlib import Path

required_types = {"brd", "prd", "adr", "plan", "issue", "pr", "test", "handoff", "workflow", "validation"}
for fixture, repo_id in {"standalone": "standalone-root", "umbrella": "umbrella-root"}.items():
    root = Path("reference/fixtures/v3") / fixture
    graph_path = root / ".ai/traceability/graph.json"
    index_path = root / ".ai/traceability/index.md"
    report_path = root / ".ai/traceability/validation-report.md"
    assert graph_path.is_file(), f"missing {graph_path}"
    assert index_path.is_file(), f"missing {index_path}"
    assert report_path.is_file(), f"missing {report_path}"

    graph = json.loads(graph_path.read_text())
    assert graph["schema_version"] == "1.0"
    assert graph["root_repo_id"] == repo_id
    nodes = {node["id"]: node for node in graph["nodes"]}
    assert required_types.issubset({node["type"] for node in nodes.values()})

    for node in nodes.values():
        assert node["id"].startswith(f"{node['type']}:{repo_id}:")
        assert node["title"]
        assert node["status"]
        assert node["repo_id"] == repo_id
        assert node.get("path") or node.get("host_url")
        if node.get("path"):
            local_path = root / node["path"]
            assert local_path.exists(), f"missing node path {local_path}"
        for backlink in node.get("backlinks", []):
            assert backlink in nodes, f"dangling backlink {backlink}"

    for edge in graph["edges"]:
        assert edge["source"] in nodes, edge
        assert edge["target"] in nodes, edge
        assert edge["relation"]
        assert edge["created_by"] == "init-ai-repo"
        assert edge["evidence_path"] == ".ai/traceability/index.md"

    index = index_path.read_text()
    for node_id in nodes:
        assert node_id in index
    report = report_path.read_text()
    assert "status: `pass`" in report
    assert "dangling_edges: `0`" in report
    assert "dangling_backlinks: `0`" in report

    workflow = (root / ".ai/workflows/repo-workflow.md").read_text()
    handoff = (root / ".ai/handoff/init-ai-repo-handoff.md").read_text()
    assert ".ai/traceability/index.md" in workflow
    assert ".ai/traceability/graph.json" in workflow
    assert ".ai/traceability/index.md" in handoff
    assert ".ai/traceability/graph.json" in handoff

module = Path("03-configure-generate/ai-catapult-init/modules/traceability.md").read_text()
for skill_name in ["to-prd", "to-issues", "triage", "setup-skills", "publish-semver", "init-ai-repo"]:
    assert skill_name in module
skill = Path("03-configure-generate/ai-catapult-init/SKILL.md").read_text()
modules = Path("03-configure-generate/ai-catapult-init/modules/README.md").read_text()
assert "`modules/traceability.md` — read when generating stable traceability IDs" in skill
assert "traceability.md` | Read when generating stable IDs" in modules
assert "`modules/cascade.md` — read when generating multi-repo cascade plans" in skill
PY

printf 'traceability fixture validation passed\n'
