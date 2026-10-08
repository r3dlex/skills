#!/usr/bin/env bash
# Workflow fixture validation: this repository's declared local_ci surface
# (.ai/workflows/repo-workflow.json). It checks the workflow doc, the manifest,
# every phase-status file and every entry surface the manifest declares, and
# exits non-zero naming each missing or inconsistent input.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

python3 -I -B - <<'PY'
import json
import sys
from pathlib import Path

MANIFEST = ".ai/workflows/repo-workflow.json"
failures = []


def read(path, as_json=False):
    if not isinstance(path, str) or not path:
        failures.append(f"{MANIFEST}: missing path field")
        return None
    try:
        text = Path(path).read_text(encoding="utf-8")
        return json.loads(text) if as_json else text
    except (OSError, ValueError) as error:
        failures.append(f"{path}: {error}")
        return None


manifest = read(MANIFEST, as_json=True)
if manifest is not None and not isinstance(manifest, dict):
    failures.append(f"{MANIFEST}: must be a JSON object")
    manifest = None
if manifest is not None:
    if manifest.get("manifest") != MANIFEST:
        failures.append(f"{MANIFEST}: manifest must name {MANIFEST}")
    doc_path = manifest.get("human_doc")
    doc = read(doc_path)
    for needle in ("## Mandatory steps", "## Optional steps", "repo-workflow.json"):
        if doc is not None and needle not in doc:
            failures.append(f"{doc_path}: missing {needle!r}")
    phases = manifest.get("phases")
    if not isinstance(phases, list) or not phases:
        failures.append(f"{MANIFEST}: phases must be a non-empty list")
        phases = []
    for phase in phases:
        status = read(phase.get("status_path"), as_json=True)
        if not isinstance(status, dict):
            continue
        for key, expected in (("workflow_id", manifest.get("workflow_id")),
                              ("phase_id", phase.get("id")),
                              ("required", phase.get("required"))):
            if status.get(key) != expected:
                failures.append(f"{phase['status_path']}: {key} must be {expected!r}")
    rules = manifest.get("validation", {})
    surfaces = manifest.get("entry_surfaces")
    if not isinstance(surfaces, list) or not surfaces:
        failures.append(f"{MANIFEST}: entry_surfaces must be a non-empty list")
        surfaces = []
    for surface in surfaces:
        body = read(surface)
        links = ((rules.get("entry_surfaces_must_link_doc"), doc_path),
                 (rules.get("entry_surfaces_must_link_manifest"), MANIFEST))
        for required, link in links:
            if body is not None and required and isinstance(link, str) and link not in body:
                failures.append(f"{surface}: must link {link}")

if failures:
    sys.stderr.write("workflow fixture validation FAILED\n")
    sys.stderr.write("".join(f"  - {failure}\n" for failure in failures))
    sys.exit(1)
print("workflow fixture validation passed")
PY
