#!/bin/bash
#
# mcp_a2a_test.sh
#
# Offline, deterministic structural validation of the generated MCP/A2A surface
# (P1-2, ADR-0005). NO model or network access is used: every assertion is pure
# file / JSON-parse / keyword checks, exactly like observability_test.sh.
#
# For BOTH committed v3 fixtures (standalone, umbrella) it asserts that the
# generated MCP-server registry stub (`.ai/mcp/registry.json`) parses as JSON and
# has the expected shape, and that the A2A cross-agent handoff convention doc
# (`.ai/mcp/a2a-handoff.md`) exists, is non-empty, and carries the handoff
# convention keywords.
#
# It also asserts that the Layer-3 module `modules/mcp-a2a.md` exists and is
# referenced from both the SKILL.md Module Map and the documentation blueprint.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_nonempty_file() {
  local file="$1" label="$2"
  if [ -s "$file" ]; then ok "$label"; else bad "$label (missing or empty: $file)"; fi
}

assert_file_contains() {
  local file="$1" needle="$2" label="$3"
  if [ -f "$file" ] && grep -Fq "$needle" "$file"; then
    ok "$label"
  else
    bad "$label (missing: $needle in $file)"
  fi
}

echo "MCP/A2A Surface Tests"
echo "====================="
echo ""

# --- Generated MCP/A2A surface in both v3 fixtures ---------------------------
for variant in standalone umbrella; do
  mcp_dir="reference/fixtures/v3/$variant/.ai/mcp"
  registry="$mcp_dir/registry.json"
  handoff="$mcp_dir/a2a-handoff.md"

  assert_nonempty_file "$registry" "v3 $variant MCP registry stub present + non-empty"
  assert_nonempty_file "$handoff"  "v3 $variant A2A handoff convention doc present + non-empty"

  # Registry parses as JSON and has the expected shape.
  if python3 - "$registry" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
assert data.get("schema_version"), f"{p}: schema_version missing"
assert "servers" in data and isinstance(data["servers"], list), f"{p}: servers array missing"
assert "a2a" in data and isinstance(data["a2a"], dict), f"{p}: a2a block missing"
# A2A block declares the protocol and the handoff convention pointer.
assert data["a2a"].get("protocol"), f"{p}: a2a.protocol missing"
assert data["a2a"].get("handoff_convention"), f"{p}: a2a.handoff_convention missing"
# Each server entry carries the offline stub shape (no live endpoints required).
for s in data["servers"]:
    for key in ("name", "transport", "status", "tools"):
        assert key in s, f"{p}: server entry missing key {key}"
    assert isinstance(s["tools"], list), f"{p}: server {s.get('name')} tools not a list"
    # Stub is offline/deterministic: registry declares no resolved network endpoint.
    assert s.get("status") == "stub", f"{p}: server {s.get('name')} status must be 'stub'"
    assert "endpoint" in s, f"{p}: server {s.get('name')} missing endpoint key"
    assert s["endpoint"] is None, f"{p}: server {s.get('name')} endpoint must be null (offline stub)"
PY
  then
    ok "v3 $variant MCP registry parses + has expected shape"
  else
    bad "v3 $variant MCP registry failed JSON/shape validation ($registry)"
  fi

  # A2A handoff convention doc carries the cross-agent handoff keywords.
  assert_file_contains "$handoff" "Handoff envelope"  "v3 $variant A2A doc defines the handoff envelope"
  assert_file_contains "$handoff" "correlation_id"    "v3 $variant A2A doc preserves correlation_id"
done

# --- Module + reference checks (mirrors observability static-keyword style) ---
assert_nonempty_file "03-configure-generate/ai-catapult-init/modules/mcp-a2a.md" \
  "Layer-3 module modules/mcp-a2a.md present + non-empty"
assert_file_contains "03-configure-generate/ai-catapult-init/SKILL.md" "modules/mcp-a2a.md" \
  "SKILL.md Module Map references modules/mcp-a2a.md"
assert_file_contains "03-configure-generate/ai-catapult-init/modules/documentation-blueprint.md" "mcp-a2a.md" \
  "documentation-blueprint.md references modules/mcp-a2a.md"
assert_file_contains "03-configure-generate/ai-catapult-init/modules/documentation-blueprint.md" ".ai/mcp/" \
  "documentation-blueprint.md tree names the .ai/mcp/ surface"
assert_file_contains "03-configure-generate/ai-catapult-init/modules/validation.md" ".ai/mcp/" \
  "validation.md structural check names the .ai/mcp/ surface"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
