#!/bin/bash
# Regression coverage for the fail-closed Northstar semantic handoff writer.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

python3 - "$REPO_ROOT" <<'PY'
import copy
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

repo = Path(sys.argv[1])
writer = repo / "02-govern-plan/northstar/handoff-write.sh"
fixture = repo / "reference/fixtures/v3/standalone"
spec = "docs/specifications/ACTIVE/init-ai-repo-workflow-surfaces.md"
slug = "ship-the-thing"
goals = ".omx/plans/ship-the-thing-goals.json"
passed = failed = skipped = 0

def report(ok, label, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  PASS: {label}")
    else:
        failed += 1
        suffix = f" ({detail})" if detail else ""
        print(f"  FAIL: {label}{suffix}")

def skip(label, reason):
    global skipped
    skipped += 1
    print(f"  SKIP: {label} ({reason})")

def make_root():
    root = Path(tempfile.mkdtemp())
    shutil.copytree(fixture, root, dirs_exist_ok=True)
    goal_file = root / goals
    goal_file.parent.mkdir(parents=True)
    goal_file.write_text(json.dumps({
        "schema_version": "1.0",
        "kind": "northstar-sliced-goals",
        "slug": slug,
        "target_spec": spec,
        "goals": [{"id": "G001", "title": "Tracer bullet", "status": "blocked"}],
    }, indent=2) + "\n")
    return root

def invoke(root, *extra, timeout=2):
    args = ["bash", str(writer), "--root", str(root), "--spec", spec,
            "--goals", goals, "--slug", slug, *extra]
    return subprocess.run(args, text=True, capture_output=True, timeout=timeout)

def snapshot(root):
    result = {}
    for relative in [".ai/workflows/repo-workflow.json",
                     ".ai/traceability/graph.json",
                     f".ai/handoff/northstar-{slug}.md"]:
        path = root / relative
        if path.is_file():
            result[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
        elif path.exists():
            result[relative] = "<non-file>"
        else:
            result[relative] = None
    result["handoff_dir"] = sorted(p.name for p in (root / ".ai/handoff").iterdir())
    return result

def mutate_graph(root, fn):
    path = root / ".ai/traceability/graph.json"
    graph = json.loads(path.read_text())
    fn(graph)
    path.write_text(json.dumps(graph, indent=2) + "\n")

# Valued CLI flags must fail promptly rather than shifting forever or crashing.
for flag in ["--root", "--spec", "--goals", "--slug", "--issue"]:
    try:
        result = subprocess.run(["bash", str(writer), flag], text=True,
                                capture_output=True, timeout=2)
        ok = result.returncode == 2 and "usage:" in result.stderr.lower()
        detail = f"rc={result.returncode} stderr={result.stderr!r}"
    except subprocess.TimeoutExpired:
        ok, detail = False, "timed out"
    report(ok, f"missing {flag} value returns usage exit 2 promptly", detail)

# Required goals is an intentional fail-closed interface correction.
root = make_root()
try:
    result = subprocess.run(["bash", str(writer), "--root", str(root),
                             "--spec", spec, "--slug", slug],
                            text=True, capture_output=True, timeout=2)
    report(result.returncode == 2, "omitting required --goals fails closed")
finally:
    shutil.rmtree(root)

# Exact PRD selection must ignore an earlier unrelated PRD.
root = make_root()
try:
    def add_decoy(g):
        g["schema_version"] = "1.1"
        g["nodes"].insert(0, {
            "id": "prd:standalone-root:decoy", "type": "prd",
            "title": "Decoy", "status": "active", "repo_id": "standalone-root",
            "path": "docs/specifications/ACTIVE/brd-business-need.md",
        })
        g["nodes"].insert(0, {
            "id": "repo:standalone-root", "type": "repo", "label": "standalone-root",
            "title": "standalone-root", "status": "active", "repo_id": "standalone-root",
            "path": ".",
        })
    mutate_graph(root, add_decoy)
    result = invoke(root)
    graph = json.loads((root / ".ai/traceability/graph.json").read_text())
    nodes = {node["id"]: node for node in graph["nodes"]}
    plan_id = f"plan:standalone-root:northstar-{slug}"
    handoff_id = f"handoff:standalone-root:northstar-{slug}"
    handoff = (root / f".ai/handoff/northstar-{slug}.md").read_text() if result.returncode == 0 else ""
    report(result.returncode == 0, "valid semantic handoff succeeds", result.stderr)
    report(nodes.get(plan_id, {}).get("path") == goals,
           "plan node resolves the concrete goals file, never the handoff")
    report("prd:standalone-root:init-ai-repo-workflow-surfaces" in nodes.get(plan_id, {}).get("backlinks", []),
           "unique exact-spec PRD is selected rather than first PRD")
    report(f"`{goals}`" in handoff and f"`{spec}`" in handoff,
           "handoff directly references concrete contained spec and goals")
    report(nodes.get(handoff_id, {}).get("path") == f".ai/handoff/northstar-{slug}.md",
           "handoff node resolves the handoff file")
    report("backlinks" not in nodes.get("prd:standalone-root:decoy", {}),
           "unrelated nodes without backlinks remain structurally unchanged")
    report(nodes.get("repo:standalone-root") == {
               "id": "repo:standalone-root", "type": "repo", "label": "standalone-root",
               "title": "standalone-root", "status": "active", "repo_id": "standalone-root",
               "path": "."},
           "bounded informational repo anchor is accepted and preserved exactly")
    generated = {"manifest": json.loads((root / ".ai/workflows/repo-workflow.json").read_text()),
                 "graph": graph}
    forbidden_promotion_keys = {"execution_ready", "host_authorized", "deploy_authorized",
                                "payment_authorized", "merge_authorized", "auth_promoted"}
    def contains_forbidden_key(value):
        if isinstance(value, dict):
            return bool(forbidden_promotion_keys.intersection(value)) or any(
                contains_forbidden_key(child) for child in value.values())
        if isinstance(value, list):
            return any(contains_forbidden_key(child) for child in value)
        return False
    report(not contains_forbidden_key(generated),
           "planning handoff never promotes execution, host, deploy, payment, merge, or auth authority")
    first = snapshot(root)
    second = invoke(root)
    report(second.returncode == 0 and snapshot(root) == first,
           "successful rerun is byte-idempotent", second.stderr)
    handoff_path = root / f".ai/handoff/northstar-{slug}.md"
    if handoff_path.exists():
        handoff_path.unlink()
        recovery = invoke(root)
        recovered = recovery.returncode == 0 and handoff_path.exists()
        recovery_detail = recovery.stderr
    else:
        recovered, recovery_detail = False, "initial write did not create handoff"
    report(recovered, "lost completion marker is recovered on rerun", recovery_detail)
    leftovers = list((root / ".ai").rglob("*.tmp"))
    report(not leftovers, "atomic writes leave no temporary files")
finally:
    shutil.rmtree(root)

# Every semantic preflight rejection must be mutation-free.
cases = []
cases.append(("unsafe slug", lambda r: None,
              lambda r: invoke(r, "--slug", "../escape")))
cases.append(("traversing spec", lambda r: None, lambda r: subprocess.run(
    ["bash", str(writer), "--root", str(r), "--spec", "../outside.md",
     "--goals", goals, "--slug", slug], text=True, capture_output=True, timeout=2)))

def invalid_goals(r):
    (r / goals).write_text(json.dumps({"goals": []}) + "\n")
cases.append(("invalid empty goals", invalid_goals, invoke))

for field in ["schema_version", "kind", "target_spec", "slug"]:
    def missing_wrapper(r, field=field):
        doc = json.loads((r / goals).read_text())
        doc.pop(field)
        (r / goals).write_text(json.dumps(doc) + "\n")
    cases.append((f"missing goals {field}", missing_wrapper, invoke))

def wrong_goal_schema(r):
    doc = json.loads((r / goals).read_text())
    doc["schema_version"] = "2.0"
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("wrong goals schema", wrong_goal_schema, invoke))

def wrong_goal_kind(r):
    doc = json.loads((r / goals).read_text())
    doc["kind"] = "other"
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("wrong goals kind", wrong_goal_kind, invoke))

def wrong_goal_spec(r):
    doc = json.loads((r / goals).read_text())
    doc["target_spec"] = "docs/specifications/ACTIVE/brd-business-need.md"
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("goals bound to a different spec", wrong_goal_spec, invoke))

def wrong_goal_slug(r):
    doc = json.loads((r / goals).read_text())
    doc["slug"] = "different-work"
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("goals bound to a different slug", wrong_goal_slug, invoke))

def duplicate_goal_ids(r):
    doc = json.loads((r / goals).read_text())
    doc["goals"].append(copy.deepcopy(doc["goals"][0]))
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("duplicate goal ids", duplicate_goal_ids, invoke))

def malformed_goal(r):
    doc = json.loads((r / goals).read_text())
    doc["goals"] = [{"title": "missing id"}]
    (r / goals).write_text(json.dumps(doc) + "\n")
cases.append(("malformed goal identity", malformed_goal, invoke))

def ambiguous_prd(r):
    def change(g):
        g["nodes"].append({
            "id": "prd:standalone-root:duplicate", "type": "prd",
            "title": "Duplicate", "status": "active", "repo_id": "standalone-root",
            "path": spec, "backlinks": [],
        })
    mutate_graph(r, change)
cases.append(("ambiguous exact-spec PRD", ambiguous_prd, invoke))

def missing_identity(r):
    def change(g):
        g.pop("root_repo_id", None)
        next(n for n in g["nodes"] if n.get("path") == spec).pop("repo_id", None)
    mutate_graph(r, change)
cases.append(("missing repository identity", missing_identity, invoke))

def conflicting_identity(r):
    mutate_graph(r, lambda g: g.__setitem__("root_repo_id", "different-root"))
cases.append(("conflicting graph-root and PRD identity", conflicting_identity, invoke))

def conflicting_manifest_identity(r):
    path = r / ".ai/workflows/repo-workflow.json"
    doc = json.loads(path.read_text())
    doc["repo"] = "different-root"
    path.write_text(json.dumps(doc, indent=2) + "\n")
cases.append(("conflicting manifest and PRD identity", conflicting_manifest_identity, invoke))

def conflicting_manifest_repo_id(r):
    path = r / ".ai/workflows/repo-workflow.json"
    doc = json.loads(path.read_text())
    doc["repo_id"] = "different-root"
    path.write_text(json.dumps(doc, indent=2) + "\n")
cases.append(("conflicting manifest repo_id and PRD identity", conflicting_manifest_repo_id, invoke))

def invalid_graph_schema(r):
    mutate_graph(r, lambda g: g.__setitem__("schema_version", "1.0.5"))
cases.append(("unsupported graph schema", invalid_graph_schema, invoke))

def missing_graph_schema(r):
    mutate_graph(r, lambda g: g.pop("schema_version"))
cases.append(("missing graph schema", missing_graph_schema, invoke))

def malformed_graph_node(r):
    mutate_graph(r, lambda g: g["nodes"][0].pop("title"))
cases.append(("malformed graph node", malformed_graph_node, invoke))

def unknown_graph_node_type(r):
    mutate_graph(r, lambda g: g["nodes"][0].__setitem__("type", "mystery"))
cases.append(("unknown graph node type", unknown_graph_node_type, invoke))

def malformed_repo_anchor(r):
    def change(g):
        g["schema_version"] = "1.1"
        g["nodes"].append({"id": "repo:standalone-root", "type": "repo",
                           "title": "standalone-root", "status": "active",
                           "repo_id": "standalone-root", "path": ".",
                           "merge_authorized": True})
    mutate_graph(r, change)
cases.append(("authority-bearing repo anchor", malformed_repo_anchor, invoke))

def unsafe_repo_anchor_identity(r):
    def change(g):
        g["schema_version"] = "1.1"
        g["nodes"].append({"id": "repo:../escape", "type": "repo",
                           "title": "escape", "status": "active",
                           "repo_id": "../escape", "path": "."})
    mutate_graph(r, change)
cases.append(("unsafe repo anchor identity", unsafe_repo_anchor_identity, invoke))

def malformed_repo_anchor_fields(r):
    def change(g):
        g["schema_version"] = "1.1"
        g["nodes"].append({"id": "repo:standalone-root", "type": "repo",
                           "title": "standalone-root", "label": 42, "status": "active",
                           "repo_id": "standalone-root", "path": "."})
    mutate_graph(r, change)
cases.append(("malformed repo anchor fields", malformed_repo_anchor_fields, invoke))

def invalid_matching_branch(r):
    path = r / ".ai/workflows/repo-workflow.json"
    doc = json.loads(path.read_text())
    doc["optional_branches"].append({"id": f"northstar-handoff-{slug}",
                                     "enabled_when": "always", "status": "blocked"})
    path.write_text(json.dumps(doc, indent=2) + "\n")
cases.append(("incompatible existing branch", invalid_matching_branch, invoke))

for label, setup, action in cases:
    root = make_root()
    try:
        setup(root)
        before = snapshot(root)
        result = action(root)
        report(result.returncode == 2 and snapshot(root) == before,
               f"{label} fails preflight without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

# Inputs must never alias any atomic output target, directly or through a contained symlink.
def invoke_paths(root, spec_arg=spec, goals_arg=goals):
    return subprocess.run(["bash", str(writer), "--root", str(root), "--spec", spec_arg,
                           "--goals", goals_arg, "--slug", slug],
                          text=True, capture_output=True, timeout=2)

# Path spelling is not filesystem identity on default macOS filesystems.
# Exercise altered-case aliases only where the temporary root is case-insensitive.
root = make_root()
try:
    probe = root / ".case-identity-probe"
    probe.write_text("probe\n")
    case_insensitive = (root / ".CASE-IDENTITY-PROBE").is_file()
    probe.unlink()
    if case_insensitive:
        target = root / f".ai/handoff/northstar-{slug}.md"
        target.write_bytes((root / goals).read_bytes())
        before = snapshot(root)
        result = invoke_paths(root, goals_arg=f".AI/HANDOFF/NORTHSTAR-{slug.upper()}.MD")
        report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
               "altered-case goals alias of handoff output fails without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    else:
        skip("altered-case goals alias of handoff output", "case-sensitive filesystem")
finally:
    shutil.rmtree(root)

root = make_root()
try:
    probe = root / ".case-identity-probe"
    probe.write_text("probe\n")
    case_insensitive = (root / ".CASE-IDENTITY-PROBE").is_file()
    probe.unlink()
    if case_insensitive:
        target = root / f".ai/handoff/northstar-{slug}.md"
        target.write_text("# irreplaceable specification\n")
        before = snapshot(root)
        result = invoke_paths(root, spec_arg=f".AI/HANDOFF/NORTHSTAR-{slug.upper()}.MD")
        report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
               "altered-case spec alias of handoff output fails without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    else:
        skip("altered-case spec alias of handoff output", "case-sensitive filesystem")
finally:
    shutil.rmtree(root)

# Hardlinks are distinct paths to the same mutable object and are rejected too.
for label, argument in [("goals", "goals_arg"), ("spec", "spec_arg")]:
    root = make_root()
    try:
        target = root / f".ai/handoff/northstar-{slug}.md"
        source = root / (goals if label == "goals" else spec)
        os.link(source, target)
        before = snapshot(root)
        kwargs = {argument: str(source.relative_to(root))}
        result = invoke_paths(root, **kwargs)
        report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
               f"{label} hardlink alias of handoff output fails without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

for label, target in [
    ("goals direct handoff-output collision", f".ai/handoff/northstar-{slug}.md"),
    ("goals direct manifest-output collision", ".ai/workflows/repo-workflow.json"),
    ("goals direct graph-output collision", ".ai/traceability/graph.json"),
]:
    root = make_root()
    try:
        target_path = root / target
        goals_doc = json.loads((root / goals).read_text())
        if target.endswith(".json"):
            existing = json.loads(target_path.read_text())
            existing.update(goals_doc)
            target_path.write_text(json.dumps(existing, indent=2) + "\n")
        else:
            target_path.write_text(json.dumps(goals_doc, indent=2) + "\n")
        before = snapshot(root)
        result = invoke_paths(root, goals_arg=target)
        report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
               f"{label} fails preflight without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

root = make_root()
try:
    handoff_target = root / f".ai/handoff/northstar-{slug}.md"
    handoff_target.write_bytes((root / goals).read_bytes())
    (root / goals).unlink()
    (root / goals).symlink_to(Path("../../.ai/handoff") / handoff_target.name)
    before = snapshot(root)
    result = invoke_paths(root)
    report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
           "contained goals symlink alias of handoff output fails without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)

root = make_root()
try:
    collision_spec = f".ai/handoff/northstar-{slug}.md"
    target = root / collision_spec
    target.write_text("# irreplaceable specification\n")
    graph_path = root / ".ai/traceability/graph.json"
    graph = json.loads(graph_path.read_text())
    next(n for n in graph["nodes"] if n["type"] == "prd" and n.get("path") == spec)["path"] = collision_spec
    graph_path.write_text(json.dumps(graph, indent=2) + "\n")
    goals_doc = json.loads((root / goals).read_text())
    goals_doc["target_spec"] = collision_spec
    (root / goals).write_text(json.dumps(goals_doc, indent=2) + "\n")
    before = snapshot(root)
    result = invoke_paths(root, spec_arg=collision_spec)
    report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
           "spec direct handoff-output collision fails preflight without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)

for label, collision_spec in [
    ("spec direct manifest-output collision", ".ai/workflows/repo-workflow.json"),
    ("spec direct graph-output collision", ".ai/traceability/graph.json"),
]:
    root = make_root()
    try:
        graph_path = root / ".ai/traceability/graph.json"
        graph = json.loads(graph_path.read_text())
        next(n for n in graph["nodes"] if n["type"] == "prd" and n.get("path") == spec)["path"] = collision_spec
        graph_path.write_text(json.dumps(graph, indent=2) + "\n")
        goals_doc = json.loads((root / goals).read_text())
        goals_doc["target_spec"] = collision_spec
        (root / goals).write_text(json.dumps(goals_doc, indent=2) + "\n")
        before = snapshot(root)
        result = invoke_paths(root, spec_arg=collision_spec)
        report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
               f"{label} fails preflight without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

root = make_root()
try:
    target = root / f".ai/handoff/northstar-{slug}.md"
    target.write_text("# irreplaceable aliased specification\n")
    alias_ref = "docs/specifications/ACTIVE/aliased-spec.md"
    alias = root / alias_ref
    alias.symlink_to(Path("../../../.ai/handoff") / target.name)
    graph_path = root / ".ai/traceability/graph.json"
    graph = json.loads(graph_path.read_text())
    next(n for n in graph["nodes"] if n["type"] == "prd" and n.get("path") == spec)["path"] = alias_ref
    graph_path.write_text(json.dumps(graph, indent=2) + "\n")
    goals_doc = json.loads((root / goals).read_text())
    goals_doc["target_spec"] = alias_ref
    (root / goals).write_text(json.dumps(goals_doc, indent=2) + "\n")
    before = snapshot(root)
    result = invoke_paths(root, spec_arg=alias_ref)
    report(result.returncode == 2 and snapshot(root) == before and "collides" in result.stderr,
           "contained spec symlink alias of handoff output fails without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)

# A symlink that resolves outside root must fail without writes.
root = make_root()
outside = Path(tempfile.mkdtemp())
try:
    external = outside / "goals.json"
    external.write_text(json.dumps({"goals": [{"id": "G001"}]}) + "\n")
    link = root / ".omx/plans/escaping-goals.json"
    link.symlink_to(external)
    before = snapshot(root)
    result = subprocess.run(["bash", str(writer), "--root", str(root),
                             "--spec", spec, "--goals", str(link.relative_to(root)),
                             "--slug", slug], text=True, capture_output=True, timeout=2)
    report(result.returncode == 2 and snapshot(root) == before,
           "escaping goals symlink fails preflight without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)
    shutil.rmtree(outside)

root = make_root()
outside = Path(tempfile.mkdtemp())
try:
    external = outside / "spec.md"
    external.write_text("# external\n")
    link = root / "docs/specifications/ACTIVE/escaping-spec.md"
    link.symlink_to(external)
    before = snapshot(root)
    result = subprocess.run(["bash", str(writer), "--root", str(root), "--spec",
                             str(link.relative_to(root)), "--goals", goals, "--slug", slug],
                            text=True, capture_output=True, timeout=2)
    report(result.returncode == 2 and snapshot(root) == before,
           "escaping spec symlink fails preflight without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)
    shutil.rmtree(outside)

root = make_root()
try:
    shutil.rmtree(root / ".ai/handoff")
    doc = json.loads((root / goals).read_text())
    doc["kind"] = "invalid"
    (root / goals).write_text(json.dumps(doc) + "\n")
    result = invoke(root)
    report(result.returncode == 2 and not (root / ".ai/handoff").exists(),
           "failed preflight does not create an absent handoff directory", result.stderr)
finally:
    shutil.rmtree(root)

# Mutation targets must be real files/directories, never symlinks or collisions.
for label, setup in [
    ("manifest symlink", lambda r: ((r / ".ai/workflows/repo-workflow.json").rename(r / ".ai/workflows/manifest-real.json"),
                                    (r / ".ai/workflows/repo-workflow.json").symlink_to("manifest-real.json"))),
    ("graph symlink", lambda r: ((r / ".ai/traceability/graph.json").rename(r / ".ai/traceability/graph-real.json"),
                                 (r / ".ai/traceability/graph.json").symlink_to("graph-real.json"))),
    ("handoff directory symlink", lambda r: ((r / ".ai/handoff").rename(r / ".ai/handoff-real"),
                                              (r / ".ai/handoff").symlink_to("handoff-real", target_is_directory=True))),
    ("handoff file symlink", lambda r: ((r / ".ai/handoff/existing.md").write_text("existing\n"),
                                         (r / f".ai/handoff/northstar-{slug}.md").symlink_to("existing.md"))),
    ("handoff path directory collision", lambda r: (r / f".ai/handoff/northstar-{slug}.md").mkdir()),
]:
    root = make_root()
    try:
        setup(root)
        before = snapshot(root)
        result = invoke(root)
        report(result.returncode == 2 and snapshot(root) == before,
               f"{label} fails preflight without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

# Bounded migration of the exact legacy root IDs preserves audit state/fields.
root = make_root()
try:
    manifest_path = root / ".ai/workflows/repo-workflow.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["optional_branches"].append({
        "id": f"northstar-handoff-{slug}", "enabled_when": "northstar_handoff_present",
        "status": "blocked", "audit_note": "preserve me",
    })
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    def add_legacy(g):
        g.pop("root_repo_id", None)
        prd = "prd:standalone-root:init-ai-repo-workflow-surfaces"
        g["nodes"].extend([
            {"id": f"plan:root:northstar-{slug}", "type": "plan",
             "title": f"northstar sliced plan: {slug}", "status": "blocked", "repo_id": "root",
             "path": f".ai/handoff/northstar-{slug}.md", "backlinks": [prd],
             "audit_note": "plan preserved"},
            {"id": f"handoff:root:northstar-{slug}", "type": "handoff",
             "title": f"northstar A->B handoff: {slug}", "status": "blocked", "repo_id": "root",
             "path": f".ai/handoff/northstar-{slug}.md",
             "backlinks": [f"plan:root:northstar-{slug}"],
             "audit_note": "handoff preserved"},
        ])
        g["edges"].append({"source": f"plan:root:northstar-{slug}",
                           "target": f"handoff:root:northstar-{slug}",
                           "relation": "summarized-by", "created_by": "northstar",
                           "evidence_path": f".ai/handoff/northstar-{slug}.md"})
        g["edges"].append({"source": prd,
                           "target": f"plan:root:northstar-{slug}",
                           "relation": "planned-by", "created_by": "northstar",
                           "evidence_path": f".ai/handoff/northstar-{slug}.md"})
    mutate_graph(root, add_legacy)
    result = invoke(root)
    graph = json.loads((root / ".ai/traceability/graph.json").read_text())
    nodes = {n["id"]: n for n in graph["nodes"]}
    current_plan = f"plan:standalone-root:northstar-{slug}"
    current_handoff = f"handoff:standalone-root:northstar-{slug}"
    branch = next(b for b in json.loads(manifest_path.read_text())["optional_branches"]
                  if b["id"] == f"northstar-handoff-{slug}")
    migrated = (result.returncode == 0 and current_plan in nodes and current_handoff in nodes
                and not any(":root:northstar-" in n for n in nodes))
    report(migrated, "exact legacy generated IDs migrate without duplicates", result.stderr)
    report(nodes.get(current_plan, {}).get("status") == "blocked"
           and nodes.get(current_handoff, {}).get("status") == "blocked"
           and branch.get("status") == "blocked",
           "legacy migration never promotes blocked statuses")
    report(nodes.get(current_plan, {}).get("audit_note") == "plan preserved"
           and nodes.get(current_handoff, {}).get("audit_note") == "handoff preserved"
           and branch.get("audit_note") == "preserve me",
           "legacy migration preserves unrelated audit fields")
    refs = [(e.get("source"), e.get("target")) for e in graph["edges"]]
    report((current_plan, current_handoff) in refs,
           "legacy migration rewrites graph references to corrected IDs")
finally:
    shutil.rmtree(root)

# Existing compatible records preserve audit state, while malformed collisions fail closed.
root = make_root()
try:
    initial = invoke(root)
    manifest_path = root / ".ai/workflows/repo-workflow.json"
    graph_path = root / ".ai/traceability/graph.json"
    manifest = json.loads(manifest_path.read_text())
    branch = next(b for b in manifest["optional_branches"] if b["id"] == f"northstar-handoff-{slug}")
    branch.update({"status": "blocked", "audit_note": "branch preserved"})
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    graph = json.loads(graph_path.read_text())
    for node in graph["nodes"]:
        if node["id"] in (f"plan:standalone-root:northstar-{slug}",
                          f"handoff:standalone-root:northstar-{slug}"):
            node.update({"status": "blocked", "audit_note": f"{node['type']} preserved"})
    graph_path.write_text(json.dumps(graph, indent=2) + "\n")
    result = invoke(root)
    graph = json.loads(graph_path.read_text())
    nodes = {n["id"]: n for n in graph["nodes"]}
    branch = next(b for b in json.loads(manifest_path.read_text())["optional_branches"]
                  if b["id"] == f"northstar-handoff-{slug}")
    report(initial.returncode == 0 and result.returncode == 0
           and branch.get("status") == "blocked" and branch.get("audit_note") == "branch preserved"
           and nodes[f"plan:standalone-root:northstar-{slug}"].get("status") == "blocked"
           and nodes[f"handoff:standalone-root:northstar-{slug}"].get("status") == "blocked"
           and nodes[f"plan:standalone-root:northstar-{slug}"].get("audit_note") == "plan preserved"
           and nodes[f"handoff:standalone-root:northstar-{slug}"].get("audit_note") == "handoff preserved",
           "compatible current records preserve blocked status and audit fields", result.stderr)
finally:
    shutil.rmtree(root)

def corrupt_current_plan_backlink(g):
    next(n for n in g["nodes"] if n["id"] == f"plan:standalone-root:northstar-{slug}")["backlinks"] = []

def corrupt_current_handoff_path(g):
    next(n for n in g["nodes"] if n["id"] == f"handoff:standalone-root:northstar-{slug}")["path"] = "other.md"

def corrupt_current_edge(g):
    edge = next(e for e in g["edges"]
                if e.get("source") == f"plan:standalone-root:northstar-{slug}"
                and e.get("target") == f"handoff:standalone-root:northstar-{slug}")
    edge["created_by"] = "other"

for label, corrupt in [
    ("current plan backlink collision", corrupt_current_plan_backlink),
    ("current handoff path collision", corrupt_current_handoff_path),
    ("current canonical edge collision", corrupt_current_edge),
]:
    root = make_root()
    try:
        invoke(root)
        mutate_graph(root, corrupt)
        before = snapshot(root)
        result = invoke(root)
        report(result.returncode == 2 and snapshot(root) == before,
               f"{label} fails without mutation",
               f"rc={result.returncode} stderr={result.stderr!r}")
    finally:
        shutil.rmtree(root)

# Refuse to guess when both legacy and corrected generated records exist.
root = make_root()
try:
    def duplicate_legacy_current(g):
        prd = "prd:standalone-root:init-ai-repo-workflow-surfaces"
        for rid in ("root", "standalone-root"):
            g["nodes"].extend([
                {"id": f"plan:{rid}:northstar-{slug}", "type": "plan",
                 "title": "plan", "status": "blocked", "repo_id": rid,
                 "path": goals, "backlinks": [prd]},
                {"id": f"handoff:{rid}:northstar-{slug}", "type": "handoff",
                 "title": "handoff", "status": "blocked", "repo_id": rid,
                 "path": f".ai/handoff/northstar-{slug}.md",
                 "backlinks": [f"plan:{rid}:northstar-{slug}"]},
            ])
    mutate_graph(root, duplicate_legacy_current)
    before = snapshot(root)
    result = invoke(root)
    report(result.returncode == 2 and snapshot(root) == before,
           "legacy/current duplicate conflict fails without mutation",
           f"rc={result.returncode} stderr={result.stderr!r}")
finally:
    shutil.rmtree(root)

print(f"\nResults: PASS={passed} FAIL={failed} SKIP={skipped}")
raise SystemExit(0 if failed == 0 else 1)
PY
