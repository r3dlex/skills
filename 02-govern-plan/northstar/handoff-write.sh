#!/bin/bash
# Write/reconcile a Northstar A->B handoff after a mutation-free preflight.
# Replacements are atomic per file (not a cross-file transaction); rerunning
# recovers an interruption between replacements without duplicating records.
set -uo pipefail

usage() {
  echo "usage: handoff-write.sh --root <r> --spec <s> --goals <g> --slug <slug> [--issue <ref>]" >&2
}

ROOT="" SPEC="" GOALS="" SLUG="" ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root|--spec|--goals|--slug|--issue)
      [[ $# -ge 2 && -n "${2:-}" ]] || { usage; exit 2; }
      case "$1" in
        --root) ROOT="$2" ;;
        --spec) SPEC="$2" ;;
        --goals) GOALS="$2" ;;
        --slug) SLUG="$2" ;;
        --issue) ISSUE="$2" ;;
      esac
      shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
if [[ -z "$ROOT" || -z "$SPEC" || -z "$GOALS" || -z "$SLUG" ]]; then
  echo "handoff-write: --root, --spec, --goals and --slug are required" >&2
  usage
  exit 2
fi
command -v python3 >/dev/null 2>&1 || { echo "handoff-write: python3 is required" >&2; exit 2; }

python3 - "$ROOT" "$SPEC" "$GOALS" "$SLUG" "$ISSUE" <<'PY'
import copy
import json
import os
from pathlib import Path
import re
import sys
import tempfile

root_arg, spec_arg, goals_arg, slug, issue = sys.argv[1:6]

def fail(message):
    print(f"handoff-write: {message}", file=sys.stderr)
    raise SystemExit(2)

def existing_file(label, raw, root):
    candidate = Path(raw) if Path(raw).is_absolute() else root / raw
    lexical = Path(os.path.abspath(candidate))
    try:
        relative = lexical.relative_to(root)
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (FileNotFoundError, RuntimeError, ValueError):
        fail(f"{label} must be an existing file contained by --root: {raw!r}")
    if not resolved.is_file():
        fail(f"{label} is not a regular file: {raw!r}")
    return lexical, resolved, relative.as_posix()

def load_json(label, path):
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"invalid {label} JSON at {path}: {exc}")

def normalized_ref(value):
    if not isinstance(value, str) or not value or Path(value).is_absolute():
        return None
    value = Path(os.path.normpath(value)).as_posix()
    return None if value == ".." or value.startswith("../") else value

def version_tuple(value):
    try:
        text = str(value)
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", text):
            raise ValueError
        return tuple(int(part) for part in text.split("."))
    except (TypeError, ValueError):
        fail(f"invalid traceability schema_version: {value!r}")

def atomic_write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o644
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent,
                                         prefix=f".{path.name}.", suffix=".tmp",
                                         delete=False) as handle:
            temp_name = handle.name
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_name, mode)
        os.replace(temp_name, path)
    except OSError as exc:
        if temp_name:
            try: os.unlink(temp_name)
            except FileNotFoundError: pass
        print(f"handoff-write: failed atomic write {path}: {exc}", file=sys.stderr)
        raise SystemExit(1)

try:
    root = Path(root_arg).resolve(strict=True)
except (FileNotFoundError, RuntimeError):
    fail(f"--root does not exist: {root_arg!r}")
if not root.is_dir():
    fail(f"--root is not a directory: {root_arg!r}")
if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", slug):
    fail("--slug must contain lowercase letters/digits separated by single hyphens")
if any(char in issue for char in ("\n", "\r", "\x00")):
    fail("--issue must be a single-line reference")

ai_dir = root / ".ai"
try:
    ai_resolved = ai_dir.resolve(strict=True)
    ai_resolved.relative_to(root)
except (FileNotFoundError, RuntimeError, ValueError):
    fail(f"{root_arg!r} is not safely ai-catapult-init initialized (missing/escaping .ai/)")
if not ai_resolved.is_dir():
    fail(".ai is not a directory")

manifest_path = root / ".ai/workflows/repo-workflow.json"
graph_path = root / ".ai/traceability/graph.json"
spec_lexical, spec_path, spec_ref = existing_file("--spec", spec_arg, root)
goals_lexical, goals_path, goals_ref = existing_file("--goals", goals_arg, root)
manifest_lexical, manifest_real, _ = existing_file("workflow manifest", str(manifest_path), root)
graph_lexical, graph_real, _ = existing_file("traceability graph", str(graph_path), root)
if manifest_path.is_symlink() or graph_path.is_symlink():
    fail("workflow manifest and traceability graph must not be symlinks")

handoff_dir = root / ".ai/handoff"
if os.path.lexists(handoff_dir):
    if handoff_dir.is_symlink(): fail(".ai/handoff must not be a symlink")
    try: handoff_dir.resolve(strict=True).relative_to(root)
    except (RuntimeError, ValueError): fail("handoff directory escapes --root")
    if not handoff_dir.resolve().is_dir(): fail(".ai/handoff is not a directory")
handoff_path = handoff_dir / f"northstar-{slug}.md"
if os.path.lexists(handoff_path):
    if handoff_path.is_symlink(): fail("handoff target must not be a symlink")
    try: handoff_path.resolve(strict=True).relative_to(root)
    except (RuntimeError, ValueError): fail("handoff file escapes --root")
    if not handoff_path.is_file(): fail("handoff target is not a regular file")

# Inputs are immutable evidence. Refuse every lexical, resolved, or filesystem
# identity alias of a file this command may atomically replace.
handoff_lexical = Path(os.path.abspath(handoff_path))
handoff_real = handoff_path.resolve(strict=False)
output_identities = {
    "workflow manifest": ({manifest_lexical, manifest_real}, manifest_real),
    "traceability graph": ({graph_lexical, graph_real}, graph_real),
    "handoff": ({handoff_lexical, handoff_real}, handoff_path),
}
for input_label, input_path, identities in (
        ("--spec", spec_path, {spec_lexical, spec_path}),
        ("--goals", goals_path, {goals_lexical, goals_path})):
    for output_label, (outputs, output_path) in output_identities.items():
        same_file = False
        if output_path.exists():
            try:
                same_file = os.path.samefile(input_path, output_path)
            except OSError as exc:
                fail(f"cannot compare {input_label} with {output_label} output target: {exc}")
        if identities & outputs or same_file:
            fail(f"{input_label} collides with {output_label} output target")

manifest = load_json("workflow manifest", manifest_real)
graph = load_json("traceability graph", graph_real)
goals_doc = load_json("sliced goals", goals_path)
if not isinstance(manifest, dict): fail("workflow manifest must be a JSON object")
branches = manifest.get("optional_branches", [])
if not isinstance(branches, list) or not all(isinstance(branch, dict) for branch in branches):
    fail("workflow manifest optional_branches must be a list of objects")
if not isinstance(graph, dict) or not isinstance(graph.get("nodes"), list) or not isinstance(graph.get("edges"), list):
    fail("traceability graph must contain nodes and edges arrays")
if not isinstance(goals_doc, dict) or not isinstance(goals_doc.get("goals"), list) or not goals_doc["goals"]:
    fail("--goals must be a JSON object with a non-empty goals array")
if goals_doc.get("schema_version") != "1.0":
    fail("sliced goals schema_version must be '1.0'")
if goals_doc.get("kind") != "northstar-sliced-goals":
    fail("sliced goals kind must be 'northstar-sliced-goals'")
goal_ids = [goal.get("id") for goal in goals_doc["goals"] if isinstance(goal, dict)]
if len(goal_ids) != len(goals_doc["goals"]) or any(not isinstance(goal_id, str) or not goal_id.strip() for goal_id in goal_ids):
    fail("every sliced goal must be an object with a non-empty id")
if len(goal_ids) != len(set(goal_ids)):
    fail("sliced goal ids must be unique")
if goals_doc.get("target_spec") != spec_ref:
    fail("sliced goals target_spec does not match --spec")
if "slug" not in goals_doc or goals_doc["slug"] != slug:
    fail("sliced goals slug does not match --slug")

nodes, edges = graph["nodes"], graph["edges"]
if "schema_version" not in graph:
    fail("traceability graph missing schema_version")
graph_version = version_tuple(graph["schema_version"])
if graph_version < (1, 0) or ((1, 0) < graph_version < (1, 1)):
    fail(f"unsupported traceability schema_version: {graph['schema_version']!r}")
v10_types = {"brd", "prd", "adr", "plan", "issue", "pr", "test", "handoff", "workflow", "validation"}
known_types = v10_types | {"repo", "eval-result", "trajectory-trace"}
repo_anchor_fields = {"id", "type", "label", "title", "status", "repo_id", "path", "backlinks"}
if not all(isinstance(node, dict) and isinstance(node.get("id"), str) and node["id"] for node in nodes):
    fail("every traceability node must be an object with a non-empty id")
node_ids = [node["id"] for node in nodes]
if len(node_ids) != len(set(node_ids)): fail("traceability graph contains duplicate node ids")
if not all(isinstance(edge, dict) for edge in edges): fail("every traceability edge must be an object")
known_ids = set(node_ids)
for node in nodes:
    if node.get("type") not in known_types:
        fail(f"traceability node {node['id']!r} has unknown type")
    if node.get("type") in {"repo", "eval-result", "trajectory-trace"} and graph_version < (1, 1):
        fail(f"traceability node {node['id']!r} type requires schema_version >= 1.1")
    for field in ("title", "status", "repo_id"):
        if not isinstance(node.get(field), str) or not node[field]:
            fail(f"traceability node {node['id']!r} has missing/invalid {field}")
    if not ((isinstance(node.get("path"), str) and node["path"])
            or (isinstance(node.get("host_url"), str) and node["host_url"])):
        fail(f"traceability node {node['id']!r} requires path or host_url")
    if node.get("type") == "repo":
        anchor_repo_id = node.get("repo_id")
        if not isinstance(anchor_repo_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", anchor_repo_id):
            fail(f"repository anchor {node['id']!r} has unsafe repo_id")
        if node["id"] != f"repo:{anchor_repo_id}" or node.get("path") != "." or node.get("status") != "active":
            fail(f"repository anchor {node['id']!r} must use id repo:<repo_id>, path '.', and status 'active'")
        unexpected = set(node) - repo_anchor_fields
        if unexpected:
            fail(f"repository anchor {node['id']!r} has unsupported fields {sorted(unexpected)!r}")
        if "label" in node and (not isinstance(node["label"], str) or not node["label"]):
            fail(f"repository anchor {node['id']!r} has invalid label")
    backlinks = node.get("backlinks", [])
    if not isinstance(backlinks, list) or any(not isinstance(ref, str) or ref not in known_ids for ref in backlinks):
        fail(f"traceability node {node['id']!r} has invalid/dangling backlinks")
for edge in edges:
    if edge.get("source") not in known_ids or edge.get("target") not in known_ids:
        fail("traceability graph contains a dangling edge")

matching_prds = [node for node in nodes if node.get("type") == "prd" and normalized_ref(node.get("path")) == spec_ref]
if len(matching_prds) != 1:
    fail(f"expected exactly one PRD node whose path matches --spec; found {len(matching_prds)}")
prd = matching_prds[0]
repo_id = prd.get("repo_id")
if not isinstance(repo_id, str) or not re.fullmatch(r"[A-Za-z0-9._-]+", repo_id):
    fail("matching PRD has no safe repository identity")
if not prd["id"].startswith(f"prd:{repo_id}:"): fail("matching PRD id conflicts with its repo_id")
root_repo_id = graph.get("root_repo_id")
if root_repo_id is not None and root_repo_id != repo_id:
    fail("traceability root_repo_id conflicts with matching PRD repo_id")
for manifest_identity in ("repo", "repo_id"):
    value = manifest.get(manifest_identity)
    if value is not None and value != repo_id:
        fail(f"workflow manifest {manifest_identity} conflicts with matching PRD repo_id")
if manifest.get("repo") is not None and manifest.get("repo_id") is not None \
        and manifest["repo"] != manifest["repo_id"]:
    fail("workflow manifest repo and repo_id conflict")

branch_id = f"northstar-handoff-{slug}"
matching_branches = [branch for branch in branches if branch.get("id") == branch_id]
if len(matching_branches) > 1: fail(f"workflow manifest contains duplicate branch id {branch_id!r}")
if matching_branches:
    existing_branch = matching_branches[0]
    if existing_branch.get("enabled_when") != "northstar_handoff_present":
        fail(f"workflow manifest branch {branch_id!r} has incompatible enabled_when")
    if not isinstance(existing_branch.get("status"), str) or not existing_branch["status"]:
        fail(f"workflow manifest branch {branch_id!r} has missing/invalid status")

plan_id = f"plan:{repo_id}:northstar-{slug}"
handoff_id = f"handoff:{repo_id}:northstar-{slug}"
legacy_plan_id = f"plan:root:northstar-{slug}"
legacy_handoff_id = f"handoff:root:northstar-{slug}"
by_id = {node["id"]: node for node in nodes}
has_legacy = legacy_plan_id != plan_id and (legacy_plan_id in by_id or legacy_handoff_id in by_id)
has_current = plan_id in by_id or handoff_id in by_id
if has_legacy:
    if not (legacy_plan_id in by_id and legacy_handoff_id in by_id):
        fail("incomplete legacy Northstar node pair requires manual reconciliation")
    if has_current: fail("legacy and corrected Northstar nodes both exist; refusing ambiguous merge")
    legacy_plan, legacy_handoff = by_id[legacy_plan_id], by_id[legacy_handoff_id]
    handoff_ref = f".ai/handoff/northstar-{slug}.md"
    if ((legacy_plan.get("type"), legacy_handoff.get("type")) != ("plan", "handoff")
            or legacy_plan.get("repo_id") != "root" or legacy_handoff.get("repo_id") != "root"
            or legacy_plan.get("title") != f"northstar sliced plan: {slug}"
            or legacy_handoff.get("title") != f"northstar A->B handoff: {slug}"
            or legacy_plan.get("path") != handoff_ref or legacy_handoff.get("path") != handoff_ref
            or legacy_plan.get("backlinks") != [prd["id"]]
            or legacy_handoff.get("backlinks") != [legacy_plan_id]):
        fail("legacy Northstar nodes do not match the generated-compatible shape")
elif has_current and not (plan_id in by_id and handoff_id in by_id):
    fail("incomplete current Northstar node pair requires manual reconciliation")

def has_edge(source, target, relation):
    return any(edge.get("source") == source and edge.get("target") == target
               and edge.get("relation") == relation
               and edge.get("created_by") == "northstar"
               and edge.get("evidence_path") == f".ai/handoff/northstar-{slug}.md"
               for edge in edges)

if has_legacy:
    if not has_edge(prd["id"], legacy_plan_id, "planned-by") \
            or not has_edge(legacy_plan_id, legacy_handoff_id, "summarized-by"):
        fail("legacy Northstar nodes lack canonical generated edges")
if has_current:
    current_plan, current_handoff = by_id[plan_id], by_id[handoff_id]
    handoff_ref = f".ai/handoff/northstar-{slug}.md"
    if ((current_plan.get("type"), current_handoff.get("type")) != ("plan", "handoff")
            or current_plan.get("repo_id") != repo_id or current_handoff.get("repo_id") != repo_id
            or current_plan.get("title") != f"northstar sliced plan: {slug}"
            or current_handoff.get("title") != f"northstar A->B handoff: {slug}"
            or current_plan.get("path") not in (goals_ref, handoff_ref)
            or current_handoff.get("path") != handoff_ref
            or current_plan.get("backlinks") != [prd["id"]]
            or current_handoff.get("backlinks") != [plan_id]
            or not has_edge(prd["id"], plan_id, "planned-by")
            or not has_edge(plan_id, handoff_id, "summarized-by")):
        fail("current Northstar nodes do not match the generated-compatible shape")

# Preflight is complete. Build every artifact in memory before first mutation.
manifest_out, graph_out = copy.deepcopy(manifest), copy.deepcopy(graph)
if not matching_branches:
    manifest_out.setdefault("optional_branches", []).append({
        "id": branch_id, "enabled_when": "northstar_handoff_present", "status": "available"})
nodes_out, edges_out = graph_out["nodes"], graph_out["edges"]
if graph_version < (1, 1): graph_out["schema_version"] = "1.1"

if has_legacy:
    replacements = {legacy_plan_id: plan_id, legacy_handoff_id: handoff_id}
    for node in nodes_out:
        if node["id"] in replacements:
            node["id"] = replacements[node["id"]]
            node["repo_id"] = repo_id
        if "backlinks" in node:
            node["backlinks"] = [replacements.get(ref, ref) for ref in node["backlinks"]]
    for edge in edges_out:
        edge["source"] = replacements.get(edge.get("source"), edge.get("source"))
        edge["target"] = replacements.get(edge.get("target"), edge.get("target"))

by_id_out = {node["id"]: node for node in nodes_out}
if plan_id not in by_id_out:
    by_id_out[plan_id] = {"id": plan_id, "type": "plan", "title": f"northstar sliced plan: {slug}",
                          "status": "active", "repo_id": repo_id, "path": goals_ref,
                          "backlinks": [prd["id"]]}
    nodes_out.append(by_id_out[plan_id])
plan = by_id_out[plan_id]
plan["repo_id"], plan["path"] = repo_id, goals_ref
plan.setdefault("backlinks", [])
if prd["id"] not in plan["backlinks"]: plan["backlinks"].append(prd["id"])

handoff_ref = f".ai/handoff/northstar-{slug}.md"
if handoff_id not in by_id_out:
    by_id_out[handoff_id] = {"id": handoff_id, "type": "handoff",
                             "title": f"northstar A->B handoff: {slug}", "status": "active",
                             "repo_id": repo_id, "path": handoff_ref, "backlinks": [plan_id]}
    nodes_out.append(by_id_out[handoff_id])
handoff = by_id_out[handoff_id]
handoff["repo_id"], handoff["path"] = repo_id, handoff_ref
handoff.setdefault("backlinks", [])
if plan_id not in handoff["backlinks"]: handoff["backlinks"].append(plan_id)

def ensure_edge(source, target, relation):
    if not any(edge.get("source") == source and edge.get("target") == target and edge.get("relation") == relation
               for edge in edges_out):
        edges_out.append({"source": source, "target": target, "relation": relation,
                          "created_by": "northstar", "evidence_path": handoff_ref})
ensure_edge(prd["id"], plan_id, "planned-by")
ensure_edge(plan_id, handoff_id, "summarized-by")

manifest_text = json.dumps(manifest_out, indent=2) + "\n"
graph_text = json.dumps(graph_out, indent=2) + "\n"
issue_line = f"- Issue: {issue}" if issue else "- Issue: local-first markdown under `.ai/work-intake/` (reconcile before merge)."
handoff_text = "\n".join([
    f"# Northstar A→B Handoff: {slug}", "", f"- Spec: `{spec_ref}`",
    f"- Sliced goals: `{goals_ref}`", issue_line,
    f"- Manifest record: `optional_branches[id={branch_id}]` in `.ai/workflows/repo-workflow.json`.",
    f"- Traceability plan: `{plan_id}`.",
    f"- Traceability handoff: `{handoff_id}` (schema_version >=1.1).", "",
    "`autobahn` consumes this handoff to ship each sliced goal one PR at a time.", ""])

atomic_write(manifest_path, manifest_text)
atomic_write(graph_path, graph_text)
atomic_write(handoff_path, handoff_text)
print(f"handoff-write: handoff {slug!r} written/reconciled under {str(root / '.ai')!r}.")
PY
