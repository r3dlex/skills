#!/usr/bin/env bash
# graph-automation-templates_test.sh
# Slice 4 structural checks for 03-configure-generate/ai-catapult-init/templates/graph-automation/
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
TEMPLATES="$REPO_ROOT/03-configure-generate/ai-catapult-init/templates"
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

# ─── (b2) Every graph-automation entry's path starts with graph-automation/ ──
echo ""
echo "--- (b2) graph-automation entry path prefix ---"

if [ -f "$MANIFEST" ]; then
    set +e
    PATH_CHECK=$(python3 - "$MANIFEST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
ga_entries = [e for e in data.get("paths", []) if (e.get("template") or "").startswith("graph-automation/")]
failures = []
for e in ga_entries:
    p = e.get("path", "")
    if not p.startswith("graph-automation/"):
        failures.append(f"entry template={e['template']!r} has path={p!r} (expected graph-automation/ prefix)")
if failures:
    for f in failures:
        print(f"  FAIL: {f}")
    sys.exit(1)
else:
    print(f"  PASS: all {len(ga_entries)} graph-automation entries have path starting with graph-automation/")
PYEOF
)
    PATH_EXIT=$?
    set -e
    echo "$PATH_CHECK"
    if [ "$PATH_EXIT" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
fi

# ─── (b3) Wrapper and hook-body entries carry install_destination ─────────────
echo ""
echo "--- (b3) Wrapper and hook-body entries carry install_destination ---"

if [ -f "$MANIFEST" ]; then
    set +e
    IDEST_CHECK=$(python3 - "$MANIFEST" <<'PYEOF'
import json, sys
data = json.load(open(sys.argv[1]))
# wrapper: template=graph-automation/graph-refresh.sh
# hook-body: template=graph-automation/hook-body.sh
required = {"graph-automation/graph-refresh.sh", "graph-automation/hook-body.sh"}
found = {}
for e in data.get("paths", []):
    t = e.get("template", "")
    if t in required:
        found[t] = e.get("install_destination", "")
failures = []
for t in sorted(required):
    if t not in found:
        failures.append(f"no manifest entry found for template={t!r}")
    elif not found[t]:
        failures.append(f"template={t!r} has empty install_destination")
if failures:
    for f in failures:
        print(f"  FAIL: {f}")
    sys.exit(1)
else:
    for t in sorted(required):
        print(f"  PASS: {t} carries install_destination")
PYEOF
)
    IDEST_EXIT=$?
    set -e
    echo "$IDEST_CHECK"
    if [ "$IDEST_EXIT" -eq 0 ]; then
        PASS=$((PASS + 2))
    else
        FAIL=$((FAIL + 2))
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

    # {{ENGINE}} token present (in the default-value position only)
    if grep -q '{{ENGINE}}' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains {{ENGINE}} token"
    else
        fail "graph-refresh.sh missing {{ENGINE}} token"
    fi

    # {{ENGINE}} token is ONLY in the ENGINE default line, not in invocation
    TOKEN_LINES=$(grep -c '{{ENGINE}}' "$WRAPPER" 2>/dev/null || echo 0)
    if [ "$TOKEN_LINES" -eq 1 ]; then
        pass "graph-refresh.sh {{ENGINE}} token appears exactly once (engine default only)"
    else
        fail "graph-refresh.sh {{ENGINE}} token appears $TOKEN_LINES times (expected 1)"
    fi

    # Engine-absent guard: command -v "$ENGINE" || exit 0
    if grep -q 'command -v' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains engine-absent guard (command -v)"
    else
        fail "graph-refresh.sh missing engine-absent guard (command -v)"
    fi

    # Per-engine dispatch: _engine_run function with case block
    if grep -q '_engine_run' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains per-engine _engine_run dispatch"
    else
        fail "graph-refresh.sh missing per-engine _engine_run dispatch"
    fi

    # graphify case: python one-liner with _rebuild_code (anchor to code form, not comment)
    if grep -q 'from graphify.watch import _rebuild_code' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains graphify _rebuild_code python one-liner"
    else
        fail "graph-refresh.sh missing graphify _rebuild_code python one-liner"
    fi

    # graphwiki case: graphwiki build . --update (anchor to code form, not comment)
    if grep -q 'graphwiki build \. --update' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains graphwiki build dispatch"
    else
        fail "graph-refresh.sh missing graphwiki build dispatch"
    fi

    # GRAPH_REFRESH_ENGINE_CMD test seam present
    if grep -q 'GRAPH_REFRESH_ENGINE_CMD' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains GRAPH_REFRESH_ENGINE_CMD test seam"
    else
        fail "graph-refresh.sh missing GRAPH_REFRESH_ENGINE_CMD test seam"
    fi

    # Exits 0 always (background execution pattern)
    if grep -q 'exit 0' "$WRAPPER" 2>/dev/null; then
        pass "graph-refresh.sh contains exit 0"
    else
        fail "graph-refresh.sh missing exit 0"
    fi

    # ── (d2) Token-substitution runnability: substituted template + fake engine
    #        burst proves lock/coalesce via GRAPH_REFRESH_ENGINE_CMD seam ────────
    echo ""
    echo "--- (d2) graph-refresh.sh token-substitution + lock/coalesce runnability ---"

    TMPDIR_TEST="$(mktemp -d)"
    # Create a fake repo layout
    mkdir -p "$TMPDIR_TEST/scripts" "$TMPDIR_TEST/.git"
    # Substitute {{ENGINE}} → graphify and write to temp location
    sed 's/{{ENGINE}}/graphify/g' "$WRAPPER" > "$TMPDIR_TEST/scripts/graph-refresh.sh"
    chmod +x "$TMPDIR_TEST/scripts/graph-refresh.sh"

    # Create a fake engine binary named `graphify` so `command -v graphify` resolves
    # hermetically without relying on the host having graphify installed.
    # GRAPH_REFRESH_ENGINE_CMD bypasses the python interpreter detection block.
    FAKE_ENGINE="$TMPDIR_TEST/graphify"
    MARKER_FILE="$TMPDIR_TEST/fake-engine-ran"
    cat > "$FAKE_ENGINE" <<'FAKEEOF'
#!/usr/bin/env bash
echo "fake-engine-ran" >> "${TMPDIR_TEST_MARKER:?TMPDIR_TEST_MARKER must be set}"
FAKEEOF
    chmod +x "$FAKE_ENGINE"

    # Run with a minimal PATH that has $TMPDIR_TEST first (and nothing else that
    # might have a real graphify). The engine-absent guard `command -v graphify`
    # finds our fake binary; GRAPH_REFRESH_ENGINE_CMD routes execution through it.
    set +e
    PATH="$TMPDIR_TEST:/usr/bin:/bin" \
      ENGINE=graphify \
      GRAPH_REFRESH_ENGINE_CMD="$FAKE_ENGINE" \
      TMPDIR_TEST_MARKER="$MARKER_FILE" \
      bash "$TMPDIR_TEST/scripts/graph-refresh.sh"
    RUN1_EXIT=$?
    # Give the detached background subshell time to run
    sleep 1
    set -e

    if [ "$RUN1_EXIT" -eq 0 ]; then
        pass "substituted graph-refresh.sh exits 0 (non-blocking)"
    else
        fail "substituted graph-refresh.sh exited $RUN1_EXIT (expected 0)"
    fi

    if [ -f "$MARKER_FILE" ]; then
        RUN_COUNT=$(wc -l < "$MARKER_FILE" | tr -d ' ')
        if [ "$RUN_COUNT" -ge 1 ]; then
            pass "lock/coalesce: fake engine ran $RUN_COUNT time(s) after single trigger"
        else
            fail "lock/coalesce: fake engine marker exists but empty (engine never ran)"
        fi
    else
        fail "lock/coalesce: fake engine marker not found (engine never ran)"
    fi

    # Second trigger while first may still be running: coalesce burst test
    # (run twice concurrently — total runs must be >=1 and <=2)
    rm -f "$MARKER_FILE"
    set +e
    PATH="$TMPDIR_TEST:/usr/bin:/bin" \
      ENGINE=graphify \
      GRAPH_REFRESH_ENGINE_CMD="$FAKE_ENGINE" \
      TMPDIR_TEST_MARKER="$MARKER_FILE" \
      bash "$TMPDIR_TEST/scripts/graph-refresh.sh" &
    PATH="$TMPDIR_TEST:/usr/bin:/bin" \
      ENGINE=graphify \
      GRAPH_REFRESH_ENGINE_CMD="$FAKE_ENGINE" \
      TMPDIR_TEST_MARKER="$MARKER_FILE" \
      bash "$TMPDIR_TEST/scripts/graph-refresh.sh" &
    wait
    sleep 1
    set -e

    if [ -f "$MARKER_FILE" ]; then
        BURST_COUNT=$(wc -l < "$MARKER_FILE" | tr -d ' ')
        if [ "$BURST_COUNT" -ge 1 ] && [ "$BURST_COUNT" -le 2 ]; then
            pass "lock/coalesce: burst of 2 triggers produced $BURST_COUNT engine run(s) (1<=count<=2)"
        else
            fail "lock/coalesce: burst of 2 triggers produced $BURST_COUNT engine runs (expected 1<=count<=2)"
        fi
    else
        fail "lock/coalesce: burst test: fake engine marker not found (engine never ran)"
    fi

    rm -rf "$TMPDIR_TEST"
else
    for msg in "lockfile marker" "coalesce marker" "{{ENGINE}} token" "{{ENGINE}} token count" \
               "engine-absent guard" "_engine_run dispatch" "_rebuild_code one-liner" \
               "graphwiki build dispatch" "GRAPH_REFRESH_ENGINE_CMD seam" "exit 0"; do
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

MODULE="$REPO_ROOT/03-configure-generate/ai-catapult-init/modules/graph-automation.md"
MODULES_README="$REPO_ROOT/03-configure-generate/ai-catapult-init/modules/README.md"
SKILL_MD="$REPO_ROOT/03-configure-generate/ai-catapult-init/SKILL.md"

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
