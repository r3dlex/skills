#!/bin/bash
#
# autobahn/prereq-check.sh  (PR-2, A3)
#
# Read-only, fail-closed presence gate for autobahn. Asserts BOTH:
#   1. the init-ai-repo v3 .ai/ structure exists under --root, AND
#   2. a valid northstar handoff is discoverable:
#        - a manifest optional_branches entry id-prefixed "northstar-handoff-", and
#        - the matching handoff file .ai/handoff/northstar-<slug>.md.
#
# The catalog repo root has no .ai/, so this script ALWAYS operates against an
# explicit --root. It never mutates the target.
#
# Usage:
#   prereq-check.sh --root <repo-root>
# Exit:
#   0  init-ai-repo structure present AND a valid northstar handoff present
#   1  init-ai-repo absent, or no valid handoff (guidance on stderr)
#   2  usage error
#

set -uo pipefail

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    --root=*) ROOT="${1#--root=}"; shift ;;
    *) echo "usage: prereq-check.sh --root <repo-root>" >&2; exit 2 ;;
  esac
done

if [[ -z "$ROOT" || ! -d "$ROOT" ]]; then
  echo "prereq-check: --root '$ROOT' is not a directory" >&2
  exit 2
fi

# --- 1. init-ai-repo v3 presence set (read-only) -----------------------------
REQUIRED=(
  ".ai/matrix.json"
  ".ai/workflows/repo-workflow.json"
  ".ai/handoff"
  ".ai/traceability/graph.json"
)

missing=0
for rel in "${REQUIRED[@]}"; do
  if [[ ! -e "$ROOT/$rel" ]]; then
    echo "prereq-check: missing required init-ai-repo artifact: $rel" >&2
    missing=$((missing + 1))
  fi
done

if [[ "$missing" -gt 0 ]]; then
  echo "prereq-check: $missing required init-ai-repo artifact(s) absent under '$ROOT'." >&2
  echo "prereq-check: run the init-ai-repo skill to initialize the repo, then retry." >&2
  exit 1
fi

# --- 2. valid northstar handoff (manifest entry + matching handoff file) ------
MANIFEST="$ROOT/.ai/workflows/repo-workflow.json"
HANDOFF_DIR="$ROOT/.ai/handoff"

# Read the optional_branches northstar-handoff-* ids and confirm each has a file.
# Pure stdlib python; offline; no mutation.
valid_handoff="$(python3 - "$MANIFEST" "$HANDOFF_DIR" <<'PY'
import json, os, sys
manifest_path, handoff_dir = sys.argv[1], sys.argv[2]
try:
    m = json.load(open(manifest_path))
except Exception:
    print("")
    sys.exit(0)
branches = m.get("optional_branches", []) or []
for b in branches:
    bid = b.get("id", "")
    prefix = "northstar-handoff-"
    if bid.startswith(prefix):
        slug = bid[len(prefix):]
        f = os.path.join(handoff_dir, f"northstar-{slug}.md")
        if os.path.isfile(f):
            print(slug)
            sys.exit(0)
print("")
PY
)"

if [[ -z "$valid_handoff" ]]; then
  echo "prereq-check: no valid northstar handoff found under '$ROOT/.ai/'." >&2
  echo "prereq-check: expected an optional_branches 'northstar-handoff-<slug>' entry AND" >&2
  echo "prereq-check: a matching .ai/handoff/northstar-<slug>.md file." >&2
  echo "prereq-check: run the northstar skill to produce the A->B handoff, then retry." >&2
  exit 1
fi

echo "prereq-check: init-ai-repo v3 + valid northstar handoff ('$valid_handoff') present under '$ROOT'."
exit 0
