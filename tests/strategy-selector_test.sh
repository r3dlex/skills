#!/bin/bash
#
# strategy-selector_test.sh
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/release/strategy-selector.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
assert_eq() { if [[ "$1" == "$2" ]]; then ok "$3 (=$2)"; else bad "$3 (got=$1 want=$2)"; fi; }

SHA="0123456789abcdef0123456789abcdef01234567"

# Test 1: Hybrid default
cd "$TMPDIR"
bash "$SCRIPT" --strategy hybrid --base-sha "$SHA" --trace-id 99 --provider github-actions --out r-hybrid.json >/dev/null
[[ -f r-hybrid.json ]] && ok "hybrid creates manifest" || bad "hybrid did not create manifest"
TAG=$(python3 -c "import json; print(json.load(open('r-hybrid.json'))['tag'])")
[[ "$TAG" == v*+*trace-99 ]] && ok "hybrid tag is Hybrid-shaped (got $TAG)" || bad "hybrid tag not Hybrid-shaped (got $TAG)"
STRAT=$(python3 -c "import json; print(json.load(open('r-hybrid.json'))['strategy'])")
assert_eq "$STRAT" "hybrid" "hybrid manifest strategy"
TC=$(python3 -c "import json; print(json.load(open('r-hybrid.json'))['tag_creation'])")
assert_eq "$TC" "allowed" "hybrid tag_creation when no guardrail fails"

# Test 2: SemVer
cd "$TMPDIR"
bash "$SCRIPT" --strategy semver --base-sha "$SHA" --trace-id 99 --provider azure-pipelines --out r-semver.json --major 2 --minor 1 --patch 3 >/dev/null
TAG=$(python3 -c "import json; print(json.load(open('r-semver.json'))['tag'])")
assert_eq "$TAG" "v2.1.3" "semver tag is v<MAJOR>.<MINOR>.<PATCH>"
BV=$(python3 -c "import json; print(json.load(open('r-semver.json'))['base_version'])")
assert_eq "$BV" "2.1.3" "semver base_version"
PROV=$(python3 -c "import json; print(json.load(open('r-semver.json'))['provider'])")
assert_eq "$PROV" "azure-pipelines" "semver provider"

# Test 3: CalVer
cd "$TMPDIR"
bash "$SCRIPT" --strategy calver --base-sha "$SHA" --trace-id 99 --provider gitlab-ci --out r-calver.json >/dev/null
TAG=$(python3 -c "import json; print(json.load(open('r-calver.json'))['tag'])")
[[ "$TAG" == v????.??.?? ]] && ok "calver tag matches vYYYY.MM.DD (got $TAG)" || bad "calver tag not CalVer-shaped (got $TAG)"
PROV=$(python3 -c "import json; print(json.load(open('r-calver.json'))['provider'])")
assert_eq "$PROV" "gitlab-ci" "calver provider"

# Test 4: Guardrail-fail blocks
cd "$TMPDIR"
for key in green_ci conventional_commits secrets_permissions_preflight no_dirty_generated_state protected_tag_policy; do
  REPORT="$TMPDIR/g-$key.report"
  cat > "$REPORT" <<EOF2
green_ci=skipped:
conventional_commits=skipped:
secrets_permissions_preflight=skipped:
no_dirty_generated_state=skipped:
protected_tag_policy=skipped:
EOF2
  case "$key" in
    green_ci) echo "green_ci=fail:simulated" >> "$REPORT";;
    conventional_commits) echo "conventional_commits=fail:simulated" >> "$REPORT";;
    secrets_permissions_preflight) echo "secrets_permissions_preflight=fail:simulated" >> "$REPORT";;
    no_dirty_generated_state) echo "no_dirty_generated_state=fail:simulated" >> "$REPORT";;
    protected_tag_policy) echo "protected_tag_policy=fail:simulated" >> "$REPORT";;
  esac
  set +e
  GUARDRAIL_REPORT="$REPORT" bash "$SCRIPT" --strategy semver --base-sha "$SHA" --trace-id 1 --provider github-actions --out "r-fail-$key.json" 2>/dev/null
  ec=$?
  set -e
  assert_eq "$ec" "5" "guardrail $key=fail exits 5"
  TC=$(python3 -c "import json; print(json.load(open('r-fail-$key.json'))['tag_creation'])")
  assert_eq "$TC" "blocked" "guardrail $key=fail blocks tag_creation"
  GR=$(python3 -c "import json; print(json.load(open('r-fail-$key.json'))['guardrail_reasons']['$key'])")
  assert_eq "$GR" "simulated" "guardrail $key=fail reason recorded"
done

# Test 5: invalid base-sha
set +e
bash "$SCRIPT" --strategy hybrid --base-sha "not-40-hex" --trace-id 1 --provider github-actions --out r-bad.json 2>/dev/null
ec=$?
set -e
assert_eq "$ec" "1" "rejects non-40-hex base-sha"

# Test 6: unknown strategy
set +e
bash "$SCRIPT" --strategy bogus --base-sha "$SHA" --trace-id 1 --provider github-actions --out r-bad.json 2>/dev/null
ec=$?
set -e
assert_eq "$ec" "1" "rejects unknown strategy"

# Test 7: unknown provider
set +e
bash "$SCRIPT" --strategy hybrid --base-sha "$SHA" --trace-id 1 --provider bogus --out r-bad.json 2>/dev/null
ec=$?
set -e
assert_eq "$ec" "1" "rejects unknown provider"

# Test 8: required fields
cd "$TMPDIR"
REQUIRED_KEYS=(schema_version strategy tag base_version base_sha timestamp_utc trace_id provider guardrails guardrail_reasons tag_creation tag_creation_reason)
for k in "${REQUIRED_KEYS[@]}"; do
  if python3 -c "import json,sys; d=json.load(open('r-hybrid.json')); sys.exit(0 if '$k' in d else 1)"; then
    ok "manifest contains $k"
  else
    bad "manifest missing $k"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
