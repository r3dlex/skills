#!/usr/bin/env bash
# ai-catapult-templates_test.sh
# Structural checks for ai-catapult-init/templates/
#
# Checks:
#   (a) ai-catapult-init/templates/ directory exists
#   (b) boundary-manifest.json is present, parses as valid JSON, and every
#       "mechanical" path has a corresponding template file
#   (c) all *.json files under templates/ are valid JSON (placeholder tokens
#       of the form {{TOKEN}} are allowed — they are not a JSON error)
#   (d) the mechanical set covers the required v3 skeleton:
#       - the 18 .ai/ subdirs (present as dirs under templates/dot-ai/)
#       - matrix.json template
#       - thin pointer files AGENTS.md, CLAUDE.md, GEMINI.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES="$REPO_ROOT/ai-catapult-init/templates"
MANIFEST="$TEMPLATES/boundary-manifest.json"

FAIL=0
PASS=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== ai-catapult-init templates structural checks ==="
echo ""

# ─── (a) templates/ directory exists ──────────────────────────────────────────
echo "--- (a) Directory presence ---"
if [ -d "$TEMPLATES" ]; then
    pass "ai-catapult-init/templates/ exists"
else
    fail "ai-catapult-init/templates/ directory missing"
fi

# ─── (b) boundary-manifest.json present, valid JSON, mechanical paths covered ─
echo ""
echo "--- (b) Boundary manifest ---"

if [ ! -f "$MANIFEST" ]; then
    fail "boundary-manifest.json not found at $MANIFEST"
else
    pass "boundary-manifest.json present"

    # Validate JSON parses
    if python3 -c "import json,sys; json.load(open('$MANIFEST'))" 2>/dev/null; then
        pass "boundary-manifest.json is valid JSON"
    else
        fail "boundary-manifest.json is not valid JSON"
    fi

    # Check every mechanical path has a corresponding template file
    MISSING_TEMPLATES=0
    while IFS= read -r tmpl; do
        [ -z "$tmpl" ] && continue
        full_path="$TEMPLATES/$tmpl"
        if [ -f "$full_path" ]; then
            pass "template exists: $tmpl"
        else
            fail "template missing: $tmpl (listed as mechanical in boundary-manifest.json)"
            MISSING_TEMPLATES=$((MISSING_TEMPLATES + 1))
        fi
    done < <(python3 - "$MANIFEST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
for entry in data.get("paths", []):
    if entry.get("classification") == "mechanical" and entry.get("template"):
        print(entry["template"])
PYEOF
)
fi

# ─── (c) all *.json files under templates/ are valid JSON ─────────────────────
echo ""
echo "--- (c) JSON validity of all template *.json files ---"

# Run all JSON checks in one Python call to avoid heredoc quoting issues
set +e
JSON_OUTPUT=$(python3 -c "
import json, re, sys, os
templates = sys.argv[1]
manifest  = sys.argv[2]
fails = []
passes = []
for root, dirs, files in os.walk(templates):
    dirs.sort()
    for fname in sorted(files):
        if not fname.endswith('.json'):
            continue
        full = os.path.join(root, fname)
        rel  = os.path.relpath(full, templates)
        # boundary-manifest.json is validated separately in check (b)
        if full == manifest:
            continue
        text = open(full).read()
        # Quoted placeholder: '{{TOKEN}}' -> '__PH__' (keep surrounding quotes)
        sanitised = re.sub(r'\"(\{\{[A-Z0-9_]+\}\})\"', '\"__PH__\"', text)
        # Bare placeholder (numeric context): {{TOKEN}} -> 0
        sanitised = re.sub(r'\{\{[A-Z0-9_]+\}\}', '0', sanitised)
        try:
            json.loads(sanitised)
            passes.append(rel)
        except Exception as e:
            fails.append((rel, str(e)))
for rel in passes:
    print(f'  PASS: valid JSON: {rel}')
for rel, err in fails:
    print(f'  FAIL: invalid JSON ({err}): {rel}')
sys.exit(1 if fails else 0)
" "$TEMPLATES" "$MANIFEST" 2>&1)
JSON_EXIT=$?
set -e
echo "$JSON_OUTPUT"
# Tally results from output lines
while IFS= read -r line; do
    case "$line" in
        "  PASS:"*) PASS=$((PASS + 1)) ;;
        "  FAIL:"*) FAIL=$((FAIL + 1)) ;;
    esac
done <<< "$JSON_OUTPUT"

# ─── (e) manifest count self-consistency ─────────────────────────────────────
echo ""
echo "--- (e) Manifest count self-consistency ---"

set +e
COUNT_OUTPUT=$(python3 - "$MANIFEST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
mechanical_actual = sum(1 for e in data["paths"] if e["classification"] == "mechanical")
jl_actual         = sum(1 for e in data["paths"] if e["classification"] == "judgment_laden")
declared_m  = data.get("mechanical_count")
declared_jl = data.get("judgment_laden_count")
fails = []
if declared_m != mechanical_actual:
    fails.append(f"mechanical_count declared={declared_m} but actual={mechanical_actual}")
if declared_jl != jl_actual:
    fails.append(f"judgment_laden_count declared={declared_jl} but actual={jl_actual}")
if fails:
    for f in fails:
        print(f"  FAIL: {f}")
    sys.exit(1)
else:
    print(f"  PASS: mechanical_count={declared_m} matches {mechanical_actual} entries")
    print(f"  PASS: judgment_laden_count={declared_jl} matches {jl_actual} entries")
PYEOF
)
COUNT_EXIT=$?
set -e
echo "$COUNT_OUTPUT"
while IFS= read -r line; do
    case "$line" in
        "  PASS:"*) PASS=$((PASS + 1)) ;;
        "  FAIL:"*) FAIL=$((FAIL + 1)) ;;
    esac
done <<< "$COUNT_OUTPUT"

# ─── (f) orphan check: every template file on disk appears in the manifest ────
echo ""
echo "--- (f) Orphan template files (disk -> manifest direction) ---"

set +e
ORPHAN_OUTPUT=$(python3 - "$MANIFEST" "$TEMPLATES" <<'PYEOF'
import json, os, sys
data      = json.load(open(sys.argv[1]))
templates = sys.argv[2]
# Build set of template values declared in manifest
declared = set()
for e in data["paths"]:
    t = e.get("template")
    if t:
        declared.add(t)
fails  = []
passes = []
for root, dirs, files in os.walk(templates):
    dirs.sort()
    for fname in sorted(files):
        full = os.path.join(root, fname)
        rel  = os.path.relpath(full, templates)
        # Skip boundary-manifest.json itself and .gitkeep placeholders
        if fname == "boundary-manifest.json" or fname == ".gitkeep":
            continue
        if rel in declared:
            passes.append(rel)
        else:
            fails.append(rel)
for r in passes:
    print(f"  PASS: manifest covers: {r}")
for r in fails:
    print(f"  FAIL: orphan template not in manifest: {r}")
sys.exit(1 if fails else 0)
PYEOF
)
ORPHAN_EXIT=$?
set -e
echo "$ORPHAN_OUTPUT"
while IFS= read -r line; do
    case "$line" in
        "  PASS:"*) PASS=$((PASS + 1)) ;;
        "  FAIL:"*) FAIL=$((FAIL + 1)) ;;
    esac
done <<< "$ORPHAN_OUTPUT"

# ─── (d) required v3 skeleton coverage ────────────────────────────────────────
echo ""
echo "--- (d) Required v3 skeleton coverage ---"

DOT_AI="$TEMPLATES/dot-ai"

# 18 required .ai/ subdirs (from documentation-blueprint.md tree shape)
REQUIRED_AI_SUBDIRS=(
    "system-prompts"
    "skills"
    "workflows"
    "phases"
    "phases/01-discover-decide"
    "phases/02-govern-plan"
    "phases/03-configure-generate"
    "phases/04-validate-handoff"
    "handoff"
    "traceability"
    "evals"
    "policies"
    "observability"
    "mcp"
    "reviews"
    "rules"
    "drift"
    "drift/backups"
)

for subdir in "${REQUIRED_AI_SUBDIRS[@]}"; do
    if [ -d "$DOT_AI/$subdir" ]; then
        pass ".ai/$subdir dir present in templates"
    else
        fail ".ai/$subdir dir missing from templates/dot-ai/"
    fi
done

# matrix.json template
if [ -f "$DOT_AI/matrix.json" ]; then
    pass "templates/dot-ai/matrix.json present"
else
    fail "templates/dot-ai/matrix.json missing"
fi

# thin pointer templates
for f in "AGENTS.md" "CLAUDE.md" "GEMINI.md"; do
    if [ -f "$TEMPLATES/$f" ]; then
        pass "templates/$f present"
    else
        fail "templates/$f missing"
    fi
done

# ─── Summary ──────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Results: PASS=$PASS  FAIL=$FAIL"
echo "=========================================="

if [ "$FAIL" -gt 0 ]; then
    echo "  RESULT: FAILED"
    exit 1
else
    echo "  RESULT: PASSED"
    exit 0
fi
