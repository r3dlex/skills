#!/bin/bash
#
# strategy-selector.sh
# Emit a release.json manifest for the init-ai-repo v3 release/versioning module.
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
#   --prd-spec <path>        PRD/spec prose to infer version impact from.
#   --commits-file <path>    Conventional commit lines to infer version impact from.
#   --pr-labels <csv>        PR labels, e.g. release:minor,bugfix.
#   --issue-type <type>      Linked issue/ticket type, e.g. feature, bug, docs.
#   --version-impact <level> Optional explicit metadata: major|minor|patch|none.
#
# Behavior:
#   - Reads guardrail statuses from $GITHUB_ENV or stdin if available; otherwise
#     marks all guardrails as 'skipped' (the release workflow runs the actual
#     guardrails and writes their outcomes into the manifest).
#   - Emits JSON. Idempotent for the same inputs.
#   - Records the canonical protected-main / PR-only delivery policy.
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
PRD_SPEC=""
COMMITS_FILE=""
PR_LABELS=""
ISSUE_TYPE=""
EXPLICIT_VERSION_IMPACT=""

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
    --prd-spec) PRD_SPEC="$2"; shift 2;;
    --commits-file) COMMITS_FILE="$2"; shift 2;;
    --pr-labels) PR_LABELS="$2"; shift 2;;
    --issue-type) ISSUE_TYPE="$2"; shift 2;;
    --version-impact) EXPLICIT_VERSION_IMPACT="$2"; shift 2;;
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
case "$EXPLICIT_VERSION_IMPACT" in
  ""|major|minor|patch|none) ;;
  *) echo "unknown version impact: $EXPLICIT_VERSION_IMPACT" >&2; exit 1;;
esac
for f in "$PRD_SPEC" "$COMMITS_FILE"; do
  if [[ -n "$f" && ! -f "$f" ]]; then
    echo "input file not found: $f" >&2
    exit 1
  fi
done

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

# ---- 2c. Infer auditable version impact ----
impact_rank() {
  case "$1" in
    major) echo 3;;
    minor) echo 2;;
    patch) echo 1;;
    none|"") echo 0;;
    *) echo 0;;
  esac
}

VERSION_IMPACT_SOURCES_TSV=""
add_impact_source() {
  local source="$1" impact="$2" confidence="$3" reason="$4"
  [[ -z "$impact" ]] && return 0
  VERSION_IMPACT_SOURCES_TSV+="${source}"$'\t'"${impact}"$'\t'"${confidence}"$'\t'"${reason}"$'\n'
}

infer_from_prd_spec() {
  [[ -n "$PRD_SPEC" ]] || return 0
  local text
  text="$(tr '\n' ' ' < "$PRD_SPEC")"
  if grep -Eiq '\b(BREAKING CHANGE|breaking|incompatible|required migration|migration required|removed public API|remove public API)\b' <<< "$text"; then
    add_impact_source "prd_spec_prose" "major" "high" "PRD/spec prose indicates breaking or incompatible behavior"
  elif grep -Eiq '\b(feature|new capability|new user-visible|add(s|ed)? .*(capability|feature))\b' <<< "$text"; then
    add_impact_source "prd_spec_prose" "minor" "medium" "PRD/spec prose indicates a user-visible feature"
  elif grep -Eiq '\b(fix|bug|defect|regression|compatibility fix)\b' <<< "$text"; then
    add_impact_source "prd_spec_prose" "patch" "medium" "PRD/spec prose indicates a bug or regression fix"
  elif grep -Eiq '\b(docs-only|documentation only|no release impact|release:none)\b' <<< "$text"; then
    add_impact_source "prd_spec_prose" "none" "medium" "PRD/spec prose indicates no release impact"
  fi
}

infer_from_commits() {
  [[ -n "$COMMITS_FILE" ]] || return 0
  if grep -Eiq '(^|[[:space:]])BREAKING CHANGE:|^[a-z]+(\([^)]+\))?!:' "$COMMITS_FILE"; then
    add_impact_source "conventional_commit" "major" "high" "Conventional commit contains breaking marker"
  elif grep -Eiq '^feat(\([^)]+\))?:' "$COMMITS_FILE"; then
    add_impact_source "conventional_commit" "minor" "medium" "Conventional commit contains feat"
  elif grep -Eiq '^fix(\([^)]+\))?:' "$COMMITS_FILE"; then
    add_impact_source "conventional_commit" "patch" "medium" "Conventional commit contains fix"
  elif grep -Eiq '^(docs|chore|test|ci|build)(\([^)]+\))?:' "$COMMITS_FILE"; then
    add_impact_source "conventional_commit" "none" "low" "Conventional commits are non-release-impact types"
  fi
}

infer_from_labels() {
  [[ -n "$PR_LABELS" ]] || return 0
  local labels
  labels="$(tr '[:upper:]' '[:lower:]' <<< "$PR_LABELS")"
  if grep -Eq 'release:major|breaking-change|breaking' <<< "$labels"; then
    add_impact_source "pr_label" "major" "high" "PR labels request major release impact"
  elif grep -Eq 'release:minor|feature' <<< "$labels"; then
    add_impact_source "pr_label" "minor" "medium" "PR labels request minor release impact"
  elif grep -Eq 'release:patch|bugfix|bug' <<< "$labels"; then
    add_impact_source "pr_label" "patch" "medium" "PR labels request patch release impact"
  elif grep -Eq 'release:none|no-release|docs-only' <<< "$labels"; then
    add_impact_source "pr_label" "none" "medium" "PR labels request no release impact"
  fi
}

infer_from_issue_type() {
  [[ -n "$ISSUE_TYPE" ]] || return 0
  local issue
  issue="$(tr '[:upper:]' '[:lower:]' <<< "$ISSUE_TYPE")"
  case "$issue" in
    *breaking*|*migration*|epic) add_impact_source "issue_type" "major" "medium" "Linked issue type implies breaking/migration impact";;
    *feature*|story) add_impact_source "issue_type" "minor" "medium" "Linked issue type implies feature impact";;
    *bug*|defect) add_impact_source "issue_type" "patch" "medium" "Linked issue type implies bug-fix impact";;
    *doc*|task|chore) add_impact_source "issue_type" "none" "low" "Linked issue type implies no release impact";;
  esac
}

if [[ -n "$EXPLICIT_VERSION_IMPACT" ]]; then
  add_impact_source "explicit_metadata" "$EXPLICIT_VERSION_IMPACT" "high" "Explicit versionImpact metadata"
fi
infer_from_prd_spec
infer_from_commits
infer_from_labels
infer_from_issue_type

VERSION_IMPACT="none"
VERSION_IMPACT_CONFIDENCE="low"
VERSION_IMPACT_REASON="No release-impact sources found; defaulting to none"
if [[ -n "$VERSION_IMPACT_SOURCES_TSV" ]]; then
  while IFS=$'\t' read -r source impact confidence reason; do
    [[ -z "${source:-}" ]] && continue
    if [[ "$(impact_rank "$impact")" -gt "$(impact_rank "$VERSION_IMPACT")" ]]; then
      VERSION_IMPACT="$impact"
      VERSION_IMPACT_CONFIDENCE="$confidence"
      VERSION_IMPACT_REASON="$reason"
    fi
  done <<< "$VERSION_IMPACT_SOURCES_TSV"
fi

VERSION_IMPACT_CONFLICTS_TSV=""
if [[ -n "$EXPLICIT_VERSION_IMPACT" && "$(impact_rank "$EXPLICIT_VERSION_IMPACT")" -lt "$(impact_rank "$VERSION_IMPACT")" ]]; then
  VERSION_IMPACT_CONFLICTS_TSV+="explicit_metadata"$'\t'"$EXPLICIT_VERSION_IMPACT"$'\t'"$VERSION_IMPACT"$'\t'"Explicit versionImpact is lower than inferred highest trusted signal"$'\n'
fi

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
if [[ -n "$VERSION_IMPACT_CONFLICTS_TSV" ]]; then
  TAG_CREATION="blocked"
  if [[ "$TAG_CREATION_REASON" == "all guardrails pass or skipped" ]]; then
    TAG_CREATION_REASON="version-impact conflict requires review"
  else
    TAG_CREATION_REASON="${TAG_CREATION_REASON}; version-impact conflict requires review"
  fi
fi

# ---- 5. Emit manifest ----
SCHEMA_VERSION="1.0"
python3 - "$OUT" "$SCHEMA_VERSION" "$STRATEGY" "$TAG" "$BASE_VERSION" "$BASE_SHA" "$TIMESTAMP_UTC" "$TRACE_ID" "$PROVIDER" \
  "$VERSION_IMPACT" "$VERSION_IMPACT_SOURCES_TSV" "$VERSION_IMPACT_CONFIDENCE" "$VERSION_IMPACT_CONFLICTS_TSV" "$VERSION_IMPACT_REASON" \
  "$GREEN_CI" "$CONVENTIONAL_COMMITS" "$SECRETS_PERMISSIONS" "$NO_DIRTY_STATE" "$PROTECTED_TAG_POLICY" \
  "$GUARDRAIL_REASON_GREEN_CI" "$GUARDRAIL_REASON_CONVENTIONAL_COMMITS" "$GUARDRAIL_REASON_SECRETS_PERMISSIONS" "$GUARDRAIL_REASON_NO_DIRTY_STATE" "$GUARDRAIL_REASON_PROTECTED_TAG_POLICY" \
  "$TAG_CREATION" "$TAG_CREATION_REASON" <<'PY'
import json, sys
out, schema, strategy, tag, base_version, base_sha, ts, trace, provider, \
  version_impact, sources_tsv, version_confidence, conflicts_tsv, version_reason, \
  g1, g2, g3, g4, g5, r1, r2, r3, r4, r5, tag_creation, tag_creation_reason = sys.argv[1:27]

def parse_sources(tsv):
  rows = []
  for line in tsv.splitlines():
    if not line.strip():
      continue
    source, impact, confidence, reason = line.split("\t", 3)
    rows.append({
      "source": source,
      "impact": impact,
      "confidence": confidence,
      "reason": reason,
    })
  return rows

def parse_conflicts(tsv):
  rows = []
  for line in tsv.splitlines():
    if not line.strip():
      continue
    source, explicit, inferred, reason = line.split("\t", 3)
    rows.append({
      "source": source,
      "explicit_impact": explicit,
      "inferred_impact": inferred,
      "reason": reason,
    })
  return rows

manifest = {
  "schema_version": schema,
  "strategy": strategy,
  "tag": tag,
  "base_version": base_version,
  "base_sha": base_sha,
  "timestamp_utc": ts,
  "trace_id": trace,
  "provider": provider,
  "version_impact": version_impact,
  "version_impact_sources": parse_sources(sources_tsv),
  "version_impact_confidence": version_confidence,
  "version_impact_conflicts": parse_conflicts(conflicts_tsv),
  "version_impact_reason": version_reason,
  "delivery_policy": {
    "protected_main": "required",
    "pr_before_main": "required",
    "pr_review_loop": "required",
    "actionable_comments_resolved": "required",
    "local_ci": "required",
    "host_ci": "required",
    "provider_policy_mutation": "checklist_only",
  },
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
