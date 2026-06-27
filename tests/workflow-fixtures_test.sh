#!/bin/bash
# Validate init-ai-repo workflow docs/manifests in v3 fixtures.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
import json
from pathlib import Path

fixtures = {
    "standalone": "standalone",
    "umbrella": "umbrella",
}
required_phase_ids = [
    "01-discover-decide",
    "02-govern-plan",
    "03-configure-generate",
    "04-validate-handoff",
]

for fixture, topology in fixtures.items():
    root = Path("reference/fixtures/v3") / fixture
    manifest_path = root / ".ai/workflows/repo-workflow.json"
    doc_path = root / ".ai/workflows/repo-workflow.md"
    handoff_path = root / ".ai/handoff/init-ai-repo-handoff.md"
    assert manifest_path.is_file(), f"missing {manifest_path}"
    assert doc_path.is_file(), f"missing {doc_path}"
    assert handoff_path.is_file(), f"missing {handoff_path}"

    manifest = json.loads(manifest_path.read_text())
    assert manifest["schema_version"] == "1.0"
    assert manifest["workflow_id"] == "init-ai-repo"
    assert manifest["topology_type"] == topology
    assert manifest["human_doc"] == ".ai/workflows/repo-workflow.md"
    assert manifest["manifest"] == ".ai/workflows/repo-workflow.json"
    assert manifest["handoff"] == ".ai/handoff/init-ai-repo-handoff.md"

    phase_ids = [phase["id"] for phase in manifest["phases"]]
    assert phase_ids == required_phase_ids, phase_ids
    for phase in manifest["phases"]:
        status_path = root / phase["status_path"]
        assert status_path.is_file(), f"missing status {status_path}"
        status = json.loads(status_path.read_text())
        assert status["workflow_id"] == "init-ai-repo"
        assert status["phase_id"] == phase["id"]
        assert status["required"] is True
        assert isinstance(status["outputs"], list) and status["outputs"]
        if phase["id"] == "03-configure-generate":
            required_outputs = {
                ".ai/bin/",
                ".ai/policies/",
                ".ai/commands/omx/",
                ".ai/commands/omc/",
                ".github/workflows/",
            }
            assert required_outputs.issubset(set(phase["outputs"])), phase["outputs"]
            assert required_outputs.issubset(set(status["outputs"])), status["outputs"]

    branch_status = {branch["id"]: branch["status"] for branch in manifest["optional_branches"]}
    assert branch_status["multi-repo-cascade"] == "planned-pr-6d"
    assert branch_status["skill-modernization"] == "planned-pr-6e"

    doc = doc_path.read_text()
    assert "## Mandatory steps" in doc
    assert "## Optional steps" in doc
    assert "repo-workflow.json" in doc
    assert "init-ai-repo-handoff.md" in doc
    assert ".ai/commands/omx/" in doc
    assert ".ai/commands/omc/" in doc
    assert "planned-pr-6d" in doc
    assert "planned-pr-6e" in doc

    for surface in ["AGENTS.md", "CLAUDE.md", "README.md"]:
        surface_path = root / surface
        assert surface_path.is_file(), f"missing {surface_path}"
        text = surface_path.read_text()
        assert ".ai/workflows/repo-workflow.md" in text
        assert ".ai/workflows/repo-workflow.json" in text

# Module/read-order surfaces must expose workflow as active, not planned-only.
skill = Path("init-ai-repo/SKILL.md").read_text()
modules = Path("init-ai-repo/modules/README.md").read_text()
assert "`modules/workflow.md` — read when generating repo workflow docs" in skill
assert "workflow.md` | Read when generating repo workflow docs" in modules
assert "`modules/traceability.md` — read when generating stable traceability IDs" in skill
assert "traceability.md` | Read when generating stable IDs" in modules
assert "`modules/cascade.md` (PR 6D)" in skill
PY

printf 'workflow fixture validation passed\n'
