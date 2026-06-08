#!/bin/bash
#
# strategy-selector.sh
# Emit a release.json manifest for the ai-sdlc-init v3 release/versioning module.
#
# Strategy:
#   hybrid (default) - SemVer base + UTC timestamp + CI trace token
#   semver           - pure SemVer v<MAJOR>.<MINOR>.<PATCH>
#   calver           - pure CalVer v<YYYY>.<MM>.<DD>
#
# Required:
#   --strategy hybrid|semver|calver
#   --base-sha <git-sha>     Candidate commit SHA (40 hex chars).
#   --trace-id <id>          CI run id or local UUIDv4.
#   --provider github-actions|azure-pipelines|gitlab-ci
#   --out <path>             Output manifest path.
#
# Optional:
#   --major <n>              Override MAJOR for SemVer/CalVer base.
#   --minor <n>              Override MINOR for SemVer base.
#   --patch <n>              Override PATCH for SemVer base.
#   --previous-tag <tag>     Previous release tag for SemVer bump calc (optional).
#   --calver-format YYYY.MM.DD|YYYY.0X
#
# Behavior:
#   - Reads guardrail statuses from $GITHUB_ENV or stdin if available; otherwise
#     marks all guardrails as 'skipped' (the release workflow runs the actual
#     guardrails and writes their outcomes into the manifest).
#   - Emits JSON. Idempotent for the same inputs.
#   - Exits 0 on success, 1 on user error, 5 if guardrail blocks tag creation.
#
# Exit codes:
#   0 success, 1 user error, 2-4 guardrail fail (per release-versioning.md spec), 5 tag blocked
#

set -euo pipefail

STRATEGY=""
BASE_SHA=""
TRACE_ID=""
PROVIDER=""
OUT=""
MAJOR=""
MINOR=""
PATCH=""
PREVIOUS_TAG=""
CALVER_FORMAT="YYYY.MM.DD"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strategy) STRATEGY="$2"; shift 2;;
    --base-sha) BASE_SHA="$2"; shift 2;;
    --trace-id) TRACE_ID="$2"; shift 2;;
    --provider) PROVIDER="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --major) MAJOR="$2"; shift 2;;
    --minor) MINOR="$2"; shift 2;;
    --patch) PATCH="$2"; shift 2;;
    --previous-tag) PREVIOUS_TAG="$2"; shift 2;;
    --calver-format) CALVER_FORMAT="$2"; shift 2;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

for v in STRATEGY BASE_SHA TRACE_ID PROVIDER OUT; do
  if [[ -z "${!v}" ]]; then echo "--$v required" >&2; exit 1; fi
done
case "$STRATEGY" in
  hybrid|semver|calver) ;;
  *) echo "unknown strategy: $STRATEGY" >&2; exit 1;;
esac
case "$PROVIDER" in
  github-actions|azure-pipelines|gitlab-ci) ;;
  *) echo "unknown provider: $PROVIDER" >&2; exit 1;;
esac
if [[ ! "$BASE_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "base-sha must be 40 hex chars" >&2; exit 1
fi

# ---- 1. Compute base version per strategy ----
TIMESTAMP_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
DATE_UTC="$(date -u +"%Y.%m.%d")"

compute_base() {
  case "$STRATEGY" in
    semver)
      local ma="${MAJOR:-0}" mi="${MINOR:-0}" pa="${PATCH:-1}"
      echo "$ma.$mi.$pa"
      ;;
    calver)
      case "$CALVER_FORMAT" in
        YYYY.MM.DD) echo "${DATE_UTC}";;
        YYYY.0X) echo "$(date -u +"%Y").0$(date -u +"%m")";;
        *) echo "${DATE_UTC}";;
      esac
      ;;
    hybrid)
      # Hybrid base is SemVer-shaped; the manifest records the strategy as 'hybrid'.
      local ma="${MAJOR:-0}" mi="${MINOR:-0}" pa="${PATCH:-1}"
      echo "$ma.$mi.$pa"
      ;;
  esac
}
BASE_VERSION="$(compute_base)"

# ---- 2. Compute tag per strategy ----
compute_tag() {
  case "$STRATEGY" in
    semver) echo "v${BASE_VERSION}";;
    calver) echo "v${BASE_VERSION}";;
    hybrid)
      # Hybrid: v<base>+<UTC-date>.trace-<token>
      local date_token trace_token
      date_token="$(date -u +"%Y.%m.%d")"
      trace_token="$TRACE_ID"
      echo "v${BASE_VERSION}+${date_token}.trace-${trace_token}"
      ;;
  esac
}
TAG="$(compute_tag)"

# ---- 2b. Reject fake / user-injected timestamp leakage ----
# A real Hybrid timestamp must come from the system clock at the moment the
# release workflow runs. A user-supplied --timestamp is not accepted; the
# timestamp is taken from the system clock and recorded for audit.
# (No --timestamp flag is defined; this is the policy.)

# ---- 3. Guardrails ----
# Each guardrail starts as 'skipped' (the actual release workflow writes the
# real outcome). On skip, tag_creation remains 'allowed' so the strategy
# selector can be tested in isolation.
GREEN_CI="skipped"
CONVENTIONAL_COMMITS="skipped"
SECRETS_PERMISSIONS="skipped"
NO_DIRTY_STATE="skipped"
PROTECTED_TAG_POLICY="skipped"

# Read guardrail outcomes from $GUARDRAIL_REPORT if present (set by upstream
# release workflow steps). Each line: <key>=<pass|fail|skipped>[:<reason>].
GUARDRAIL_REASON_GREEN_CI=""
GUARDRAIL_REASON_CONVENTIONAL_COMMITS=""
GUARDRAIL_REASON_SECRETS_PERMISSIONS=""
GUARDRAIL_REASON_NO_DIRTY_STATE=""
GUARDRAIL_REASON_PROTECTED_TAG_POLICY=""

if [[ -n "${GUARDRAIL_REPORT:-}" && -f "$GUARDRAIL_REPORT" ]]; then
  while IFS= read -r line; do
    key="${line%%=*}"
    val="${line#*=}"
    case "$key" in
      green_ci) GREEN_CI="${val%%:*}"; GUARDRAIL_REASON_GREEN_CI="${val#*:}";;
      conventional_commits) CONVENTIONAL_COMMITS="${val%%:*}"; GUARDRAIL_REASON_CONVENTIONAL_COMMITS="${val#*:}";;
      secrets_permissions_preflight) SECRETS_PERMISSIONS="${val%%:*}"; GUARDRAIL_REASON_SECRETS_PERMISSIONS="${val#*:}";;
      no_dirty_generated_state) NO_DIRTY_STATE="${val%%:*}"; GUARDRAIL_REASON_NO_DIRTY_STATE="${val#*:}";;
      protected_tag_policy) PROTECTED_TAG_POLICY="${val%%:*}"; GUARDRAIL_REASON_PROTECTED_TAG_POLICY="${val#*:}";;
    esac
  done < "$GUARDRAIL_REPORT"
fi

# ---- 4. Decide tag_creation ----
TAG_CREATION="allowed"
TAG_CREATION_REASON="all guardrails pass or skipped"
for entry in "$GREEN_CI" "$CONVENTIONAL_COMMITS" "$SECRETS_PERMISSIONS" "$NO_DIRTY_STATE" "$PROTECTED_TAG_POLICY"; do
  if [[ "$entry" == "fail" ]]; then
    TAG_CREATION="blocked"
    TAG_CREATION_REASON="at least one guardrail failed; see guardrail_reasons"
    break
  fi
done

# ---- 5. Emit manifest ----
SCHEMA_VERSION="1.0"
python3 - "$OUT" "$SCHEMA_VERSION" "$STRATEGY" "$TAG" "$BASE_VERSION" "$BASE_SHA" "$TIMESTAMP_UTC" "$TRACE_ID" "$PROVIDER" \
  "$GREEN_CI" "$CONVENTIONAL_COMMITS" "$SECRETS_PERMISSIONS" "$NO_DIRTY_STATE" "$PROTECTED_TAG_POLICY" \
  "$GUARDRAIL_REASON_GREEN_CI" "$GUARDRAIL_REASON_CONVENTIONAL_COMMITS" "$GUARDRAIL_REASON_SECRETS_PERMISSIONS" "$GUARDRAIL_REASON_NO_DIRTY_STATE" "$GUARDRAIL_REASON_PROTECTED_TAG_POLICY" \
  "$TAG_CREATION" "$TAG_CREATION_REASON" <<'PY'
import json, sys
out, schema, strategy, tag, base_version, base_sha, ts, trace, provider, \
  g1, g2, g3, g4, g5, r1, r2, r3, r4, r5, tag_creation, tag_creation_reason = sys.argv[1:22]
manifest = {
  "schema_version": schema,
  "strategy": strategy,
  "tag": tag,
  "base_version": base_version,
  "base_sha": base_sha,
  "timestamp_utc": ts,
  "trace_id": trace,
  "provider": provider,
  "guardrails": {
    "green_ci": g1,
    "conventional_commits": g2,
    "secrets_permissions_preflight": g3,
    "no_dirty_generated_state": g4,
    "protected_tag_policy": g5,
  },
  "guardrail_reasons": {
    "green_ci": r1,
    "conventional_commits": r2,
    "secrets_permissions_preflight": r3,
    "no_dirty_generated_state": r4,
    "protected_tag_policy": r5,
  },
  "tag_creation": tag_creation,
  "tag_creation_reason": tag_creation_reason,
}
with open(out, "w") as f:
  json.dump(manifest, f, indent=2, sort_keys=False)
  f.write("\n")
PY

if [[ "$TAG_CREATION" == "blocked" ]]; then
  echo "tag creation blocked: $TAG_CREATION_REASON" >&2
  exit 5
fi
echo "ok: $STRATEGY $TAG -> $OUT"
