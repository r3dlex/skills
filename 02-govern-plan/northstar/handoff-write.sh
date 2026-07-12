#!/bin/bash
#
# northstar/handoff-write.sh  (PR-1, N4)
#
# Writes the A->B handoff into an ai-catapult-init .ai/ tree under --root:
#   1. an optional_branches record in .ai/workflows/repo-workflow.json
#   2. plan + handoff nodes (schema_version 1.1) in .ai/traceability/graph.json
#   3. a handoff entry file in .ai/handoff/northstar-<slug>.md   (written LAST)
#
# Idempotent: re-running matches records/nodes by id and never duplicates; it
# recreates the handoff file if it was lost (partial-write recovery). Write order
# is manifest/graph first, handoff-file last so a re-run can reconcile.
#
# Usage:
#   handoff-write.sh --root <repo-root> --spec <spec-path> --slug <plan-slug>
#                    [--issue <issue-ref>]
# Exit:
#   0  handoff written/reconciled
#   1  partial write (names the unwritten artifact on stderr)
#   2  usage / prereq error
#

set -uo pipefail

ROOT="" ; SPEC="" ; SLUG="" ; ISSUE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)  ROOT="${2:-}";  shift 2 ;;
    --spec)  SPEC="${2:-}";  shift 2 ;;
    --slug)  SLUG="${2:-}";  shift 2 ;;
    --issue) ISSUE="${2:-}"; shift 2 ;;
    *) echo "usage: handoff-write.sh --root <r> --spec <s> --slug <slug> [--issue <ref>]" >&2; exit 2 ;;
  esac
done

if [[ -z "$ROOT" || -z "$SPEC" || -z "$SLUG" ]]; then
  echo "handoff-write: --root, --spec and --slug are required" >&2
  exit 2
fi
if [[ ! -d "$ROOT/.ai" ]]; then
  echo "handoff-write: '$ROOT' is not ai-catapult-init initialized (no .ai/). Run ai-catapult-init first." >&2
  exit 2
fi

MANIFEST="$ROOT/.ai/workflows/repo-workflow.json"
GRAPH="$ROOT/.ai/traceability/graph.json"
HANDOFF_DIR="$ROOT/.ai/handoff"
HANDOFF_FILE="$HANDOFF_DIR/northstar-$SLUG.md"

for required in "$MANIFEST" "$GRAPH"; do
  if [[ ! -f "$required" ]]; then
    echo "handoff-write: required artifact missing: $required" >&2
    exit 2
  fi
done
mkdir -p "$HANDOFF_DIR"

# --- 1 + 2: manifest + graph (idempotent, by id) -----------------------------
python3 - "$MANIFEST" "$GRAPH" "$SLUG" "$SPEC" "$ISSUE" <<'PY'
import json, sys

manifest_path, graph_path, slug, spec, issue = sys.argv[1:6]

# --- manifest optional_branches (idempotent by id) ---
manifest = json.load(open(manifest_path))
branch_id = f"northstar-handoff-{slug}"
branches = manifest.setdefault("optional_branches", [])
if not any(b.get("id") == branch_id for b in branches):
    branches.append({
        "id": branch_id,
        "enabled_when": "northstar_handoff_present",
        "status": "available",
    })
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

# --- traceability graph (schema 1.1; plan + handoff nodes, idempotent by id) ---
graph = json.load(open(graph_path))
def _ver(v):
    return tuple(int(p) for p in str(v).split("."))
# Bump to 1.1 only if currently below it — never downgrade a higher schema (set->max).
if _ver(graph.get("schema_version", "1.0")) < (1, 1):
    graph["schema_version"] = "1.1"
repo_id = graph.get("root_repo_id", "root")

nodes = graph.setdefault("nodes", [])
edges = graph.setdefault("edges", [])
node_ids = {n["id"] for n in nodes}

# Anchor backlinks to an existing PRD/plan node when available so edges resolve.
prd_id = next((n["id"] for n in nodes if n.get("type") == "prd"), None)

plan_id = f"plan:{repo_id}:northstar-{slug}"
handoff_id = f"handoff:{repo_id}:northstar-{slug}"

def ensure_node(node):
    if node["id"] not in node_ids:
        nodes.append(node)
        node_ids.add(node["id"])

def ensure_edge(source, target, relation):
    for e in edges:
        if e.get("source") == source and e.get("target") == target and e.get("relation") == relation:
            return
    edges.append({
        "source": source, "target": target, "relation": relation,
        "created_by": "northstar",
        "evidence_path": f".ai/handoff/northstar-{slug}.md",
    })

ensure_node({
    "id": plan_id, "type": "plan",
    "title": f"northstar sliced plan: {slug}",
    "status": "active", "repo_id": repo_id,
    "path": f".ai/handoff/northstar-{slug}.md",
    "backlinks": [prd_id] if prd_id else [],
})
ensure_node({
    "id": handoff_id, "type": "handoff",
    "title": f"northstar A->B handoff: {slug}",
    "status": "active", "repo_id": repo_id,
    "path": f".ai/handoff/northstar-{slug}.md",
    "backlinks": [plan_id],
})
if prd_id:
    ensure_edge(prd_id, plan_id, "planned-by")
ensure_edge(plan_id, handoff_id, "summarized-by")

with open(graph_path, "w") as f:
    json.dump(graph, f, indent=2)
    f.write("\n")
PY
rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "handoff-write: failed updating manifest/graph (.ai/workflows or .ai/traceability)" >&2
  exit 1
fi

# --- 3: handoff entry file (written LAST) ------------------------------------
{
  echo "# Northstar A→B Handoff: $SLUG"
  echo ""
  echo "- Spec: \`$SPEC\`"
  echo "- Sliced goals: see the \`plan:\` traceability node and \`ralplan\` output for this slug."
  if [[ -n "$ISSUE" ]]; then
    echo "- Issue: $ISSUE"
  else
    echo "- Issue: local-first markdown under \`.ai/work-intake/\` (reconcile before merge)."
  fi
  echo "- Manifest record: \`optional_branches[id=northstar-handoff-$SLUG]\` in \`.ai/workflows/repo-workflow.json\`."
  echo "- Traceability: \`plan:*:northstar-$SLUG\` and \`handoff:*:northstar-$SLUG\` (schema_version 1.1)."
  echo ""
  echo "autobahn consumes this handoff to ship each sliced goal one PR at a time."
} > "$HANDOFF_FILE"

if [[ ! -f "$HANDOFF_FILE" ]]; then
  echo "handoff-write: failed to write handoff file: $HANDOFF_FILE" >&2
  exit 1
fi

echo "handoff-write: handoff for '$SLUG' written/reconciled under '$ROOT/.ai/'."
exit 0
