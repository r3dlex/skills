#!/usr/bin/env bash
# graph-automation-templates_test.sh
# Slice 4 structural checks for ai-catapult-init/templates/graph-automation/
#
# Checks:
#   (a) Template files exist
#   (b) boundary-manifest.json lists them as mechanical with correct counts
#   (c) hook-body.sh is <=15 non-comment, non-blank lines
#   (d) graph-refresh.sh contains lockfile logic markers + {{ENGINE}} token + engine-absent guard
#   (e) config.json parses and has engine=graphify
#   (f) harness-hooks.json parses as valid JSON

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES="$REPO_ROOT/ai-catapult-init/templates"
MANIFEST="$TEMPLATES/boundary-manifest.json"
GA="$TEMPLATES/graph-automation"

FAIL=0
PASS=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

echo "=== graph-automation templates structural checks ==="
echo ""

# ─── (a) Template files exist ─────────────────────────────────────────────────
echo "--- (a) Template file presence ---"

REQUIRED_FILES=(
    "graph-automation/graph-refresh.sh"
    "graph-automation/hook-body.sh"
    "graph-automation/harness-hooks.json"
    "graph-automation/config.json"
)

for rel in "${REQUIRED_FILES[@]}"; do
    if [ -f "$TEMPLATES/$rel" ]; then
        pass "template exists: $rel"
    else
        fail "template missing: $rel"
    fi
done

# ─── (b) boundary-manifest lists them as mechanical ───────────────────────────
echo ""
echo "--- (b) Manifest mechanical classification ---"

if [ ! -f "$MANIFEST" ]; then
    fail "boundary-manifest.json not found"
else
    for rel in "${REQUIRED_FILES[@]}"; do
        set +e
        FOUND=$(python3 - "$MANIFEST" "$rel" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
needle = sys.argv[2]
for e in data.get("paths", []):
    if e.get("template") == needle and e.get("classification") == "mechanical":
        print("yes")
        break
PYEOF
)
        set -e
        if [ "$FOUND" = "yes" ]; then
            pass "manifest has mechanical entry: $rel"
        else
            fail "manifest missing mechanical entry: $rel"
        fi
    done

    # Count self-consistency (mechanical_count must match actual)
    set +e
    COUNT_OUTPUT=$(python3 - "$MANIFEST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
mechanical_actual = sum(1 for e in data["paths"] if e["classification"] == "mechanical")
declared_m = data.get("mechanical_count")
if declared_m != mechanical_actual:
    print(f"  FAIL: mechanical_count declared={declared_m} but actual={mechanical_actual}")
    sys.exit(1)
else:
    print(f"  PASS: mechanical_count={declared_m} matches {mechanical_actual} entries")
PYEOF
)
    COUNT_EXIT=$?
    set -e
    echo "$COUNT_OUTPUT"
    if [ "$COUNT_EXIT" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
fi

# ─── (c) hook-body.sh is <=15 non-comment, non-blank lines ───────────────────
echo ""
echo "--- (c) hook-body.sh line count (<=15 non-comment non-blank lines) ---"

HOOK_BODY="$GA/hook-body.sh"
if [ -f "$HOOK_BODY" ]; then
    # Count lines that are not blank and not comment-only (# ...)
    ACTIVE_LINES=$(grep -v '^\s*#' "$HOOK_BODY" | grep -v '^\s*$' | wc -l | tr -d ' ')
    if [ "$ACTIVE_LINES" -le 15 ]; then
        pass "hook-body.sh active lines=$ACTIVE_LINES (<=15)"
    else
        fail "hook-body.sh active lines=$ACTIVE_LINES exceeds 15"
    fi
else
    fail "hook-body.sh not found (cannot check line count)"
fi

# ─── (d) graph-refresh.sh content checks ─────────────────────────────────────
echo ""
echo "--- (d) graph-refresh.sh content markers ---"

WRAPPER="$GA/graph-refresh.sh"
if [ -f "$WRAPPER" ]; then
    # Lockfile logic marker
    if grep -q 'LOCK' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains lockfile marker (LOCK)"
    else
        fail "graph-refresh.sh missing lockfile marker (LOCK)"
    fi

    # Pending rerun / coalesce marker
    if grep -q 'PENDING\|pending\|rerun\|coalesce' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains coalesce/pending rerun marker"
    else
        fail "graph-refresh.sh missing coalesce/pending rerun marker"
    fi

    # {{ENGINE}} token present
    if grep -q '{{ENGINE}}' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains {{ENGINE}} token"
    else
        fail "graph-refresh.sh missing {{ENGINE}} token"
    fi

    # Engine-absent guard: command -v {{ENGINE}} || exit 0
    if grep -q 'command -v' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains engine-absent guard (command -v)"
    else
        fail "graph-refresh.sh missing engine-absent guard (command -v)"
    fi

    # Exits 0 always (background execution pattern)
    if grep -q 'exit 0' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains exit 0"
    else
        fail "graph-refresh.sh missing exit 0"
    fi
else
    for msg in "lockfile marker" "coalesce marker" "{{ENGINE}} token" "engine-absent guard" "exit 0"; do
        fail "graph-refresh.sh not found (cannot check $msg)"
    done
fi

# ─── (e) config.json parses with engine=graphify ─────────────────────────────
echo ""
echo "--- (e) config.json engine default ---"

CONFIG="$GA/config.json"
if [ -f "$CONFIG" ]; then
    set +e
    ENGINE_VAL=$(python3 -c "
import json, sys
try:
    d = json.load(open('$CONFIG'))
    print(d.get('engine', ''))
except Exception as e:
    print('PARSE_ERROR: ' + str(e), file=sys.stderr)
    sys.exit(1)
" 2>&1)
    EXIT_CODE=$?
    set -e
    if [ "$EXIT_CODE" -ne 0 ]; then
        fail "config.json failed to parse: $ENGINE_VAL"
    elif [ "$ENGINE_VAL" = "graphify" ]; then
        pass "config.json engine=graphify"
    else
        fail "config.json engine='$ENGINE_VAL' (expected 'graphify')"
    fi
else
    fail "config.json not found"
fi

# ─── (f) harness-hooks.json parses as valid JSON ──────────────────────────────
echo ""
echo "--- (f) harness-hooks.json validity ---"

HARNESS="$GA/harness-hooks.json"
if [ -f "$HARNESS" ]; then
    set +e
    python3 -c "
import json, re, sys
text = open('$HARNESS').read()
sanitised = re.sub(r'\"(\{\{[A-Z0-9_]+\}\})\"', '\"__PH__\"', text)
sanitised = re.sub(r'\{\{[A-Z0-9_]+\}\}', '0', sanitised)
try:
    json.loads(sanitised)
    print('  PASS: harness-hooks.json parses as valid JSON')
    sys.exit(0)
except Exception as e:
    print(f'  FAIL: harness-hooks.json invalid JSON: {e}')
    sys.exit(1)
" 2>&1
    HARNESS_EXIT=$?
    set -e
    if [ "$HARNESS_EXIT" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
else
    fail "harness-hooks.json not found"
fi

# ─── (g) Module prose and README reference ────────────────────────────────────
echo ""
echo "--- (g) Module prose and documentation wiring ---"

MODULE="$REPO_ROOT/ai-catapult-init/modules/graph-automation.md"
MODULES_README="$REPO_ROOT/ai-catapult-init/modules/README.md"
SKILL_MD="$REPO_ROOT/ai-catapult-init/SKILL.md"

if [ -f "$MODULE" ]; then
    pass "graph-automation.md module exists"
else
    fail "graph-automation.md module missing"
fi

if [ -f "$MODULES_README" ] && grep -q 'graph-automation' "$MODULES_README" 2>/dev/null; then
    pass "modules/README.md references graph-automation"
else
    fail "modules/README.md missing graph-automation reference"
fi

if [ -f "$SKILL_MD" ] && grep -q 'graph-automation' "$SKILL_MD" 2>/dev/null; then
    pass "SKILL.md references graph-automation module"
else
    fail "SKILL.md missing graph-automation module reference"
fi

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
