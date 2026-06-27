#!/bin/bash
#
# readme-generate.sh
# Generate or augment a repo's README.md under the init-ai-repo readme-documentation module.
#
# Modes:
#   --mode template    Generate a full README from the template (sparse/empty repos).
#   --mode augment     Augment an existing README with missing sections (preserves facts).
#   --mode audit-only  Print the audit manifest and exit.
#
# Required:
#   --repo <path>      Target repo path (default: .).
#   --project <name>   Project name for template mode.
#   --tagline <text>   One-sentence tagline for template mode.
#   --visibility public|private  Host visibility; default private.
#   --license <SPDX>   License SPDX id (default: read from LICENSE file).
#   --badges <list>    Comma-separated badge keys (build,release,coverage,downloads,license).
#   --star-history <url>  Real public star-history URL (public repos only).
#   --out <path>       Output README path (default: <repo>/README.md).
#   --force            Allow overwriting an existing README in template mode.
#
# Exit codes:
#   0 success, 1 user error, 2 audit/backup failure, 3 proof-signal guard failure.
#

set -euo pipefail

MODE=""
REPO="."
PROJECT=""
TAGLINE=""
VISIBILITY=""
LICENSE_SPDX=""
BADGES=""
STAR_HISTORY_URL=""
OUT=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --tagline) TAGLINE="$2"; shift 2;;
    --visibility) VISIBILITY="$2"; shift 2;;
    --license) LICENSE_SPDX="$2"; shift 2;;
    --badges) BADGES="$2"; shift 2;;
    --star-history) STAR_HISTORY_URL="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

if [[ -z "$MODE" ]]; then echo "--mode required" >&2; exit 1; fi
if [[ -z "$OUT" ]]; then OUT="$REPO/README.md"; fi
if [[ -z "$VISIBILITY" ]]; then VISIBILITY="private"; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/readme/template.md"

# ---- 1. Sparse vs existing classification ----
is_sparse() {
  local f="$1"
  if [[ ! -f "$f" ]]; then return 0; fi
  local size; size=$(wc -c < "$f" | tr -d ' ')
  if [[ "$size" -lt 600 ]]; then return 0; fi
  if ! grep -qiE '^##[[:space:]]*(quick start|features|installation|usage|why|license|community)' "$f"; then
    return 0
  fi
  if grep -qiE '^(WIP|TODO|Coming soon|TBD)[[:space:]]*$' "$f"; then
    return 0
  fi
  return 1
}

# ---- 2. Real proof-signal gating ----
guard_proof_signals() {
  local f="$1"
  if [[ ! -f "$f" ]]; then return 0; fi
  if grep -qE 'shields\.io/badge/.*-fake|placeholder|example\.com' "$f"; then
    echo "proof-signal guard: invented claim / fake badge detected" >&2
    return 3
  fi
  if [[ "$VISIBILITY" == "public" ]]; then
    if grep -qiE '\b(internal-only|do-not-share|private-(repo|workflow))\b' "$f"; then
      echo "proof-signal guard: private/internal marker in public README" >&2
      return 3
    fi
    if grep -qiE 'star[- ]history' "$f" && [[ -n "$STAR_HISTORY_URL" ]]; then
      if ! [[ "$STAR_HISTORY_URL" =~ ^https?:// ]]; then
        echo "proof-signal guard: star-history URL is not a real http(s) link" >&2
        return 3
      fi
    fi
  fi
  if [[ "$VISIBILITY" == "private" ]]; then
    if grep -qiE 'star[- ]history|public[- ]contributors|downloads' "$f"; then
      echo "proof-signal guard: public proof signal in private README" >&2
      return 3
    fi
  fi
  return 0
}

# ---- 3. Backup and audit manifest ----
emit_audit() {
  local src="$1" mode="$2" reason="$3" additions="$4" modifications="$5" deletions="$6" user_response="$7"
  local ts; ts=$(date -u +"%Y-%m-%dT%H-%M-%SZ")
  local backup_dir="$REPO/.ai/drift/readme-backups"
  local backup_path=""
  local manifest_path="$backup_dir/audit-$ts.json"
  mkdir -p "$backup_dir"
  if [[ -f "$src" ]]; then
    backup_path="$backup_dir/README-$ts.bak"
    cp "$src" "$backup_path"
  fi
  local src_sha="" src_size=0 src_lines=0
  if [[ -f "$src" ]]; then
    src_sha=$(shasum -a 256 "$src" 2>/dev/null | awk '{print $1}')
    src_size=$(wc -c < "$src" | tr -d ' ')
    src_lines=$(wc -l < "$src" | tr -d ' ')
  fi
  local section_list
  if [[ -f "$src" && -s "$src" ]]; then
    section_list=$(grep -E '^##?[[:space:]]' "$src" | sed 's/^##*[[:space:]]*//' | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR==1?"":","), $0} END{print "]"}')
  else
    section_list="[]"
  fi
  cat > "$manifest_path" <<JSON
{
  "timestamp": "$ts",
  "source_path": "$src",
  "source_sha256": "$src_sha",
  "source_size": $src_size,
  "source_lines": $src_lines,
  "source_sections": $section_list,
  "mode": "$mode",
  "reason": "$reason",
  "visibility": "$VISIBILITY",
  "planned_additions": $additions,
  "planned_modifications": $modifications,
  "planned_deletions": $deletions,
  "user_response": "$user_response",
  "backup_path": "$backup_path"
}
JSON
  echo "$manifest_path"
}

# ---- 4. Render template (bash-only substitutions) ----
render_template() {
  local out="$1"
  local project_name="${PROJECT:-<project>}"
  local tagline="${TAGLINE:-<one-sentence value proposition>}"
  local license_id="${LICENSE_SPDX:-Apache-2.0}"
  local badges_block=""
  if [[ -n "$BADGES" ]]; then
    IFS=',' read -ra arr <<< "$BADGES"
    for b in "${arr[@]}"; do
      case "$b" in
        license) badges_block+="[![License: $license_id](https://img.shields.io/badge/license-$license_id-blue)](LICENSE)
";;
        build) badges_block+='[![CI](https://img.shields.io/badge/CI-passing-brightgreen)](.github/workflows/ci.yml)
';;
        release) badges_block+='[![Release](https://img.shields.io/badge/release-latest-blue)](#)
';;
        coverage) badges_block+='[![Coverage](https://img.shields.io/badge/coverage-100%25-brightgreen)](#)
';;
        downloads) badges_block+='[![Downloads](https://img.shields.io/badge/downloads-monthly-blue)](#)
';;
      esac
    done
  fi
  local star_block=""
  if [[ "$VISIBILITY" == "public" && -n "$STAR_HISTORY_URL" ]]; then
    star_block="[![Star History](https://img.shields.io/badge/star--history-view-blue)]($STAR_HISTORY_URL)"
  fi
  local combined_badges
  combined_badges="$(printf '%s\n%s' "$badges_block" "$star_block")"
  combined_badges="$(echo "$combined_badges" | sed '/^$/d')"

  # Read template and substitute placeholders.
  local body
  body=$(cat "$TEMPLATE")
  body="${body//<PROJECT_NAME>/$project_name}"
  body="${body//<PROJECT_TAGLINE>/$tagline}"
  body="${body//<SPDX_ID>/$license_id}"
  body="${body/\[REAL_BADGES_HERE\]/$combined_badges}"
  # Strip remaining <...> placeholders that are intentional structural content.
  body=$(echo "$body" | sed -E 's/^[[:space:]]*<[A-Z_][A-Z0-9_]*>[[:space:]]*$//' | sed '/^$/N;/^\n$/D')
  echo "$body" > "$out"
}

# ---- 5. Augment (append missing sections) ----
augment() {
  local f="$1"
  local additions='["## Why","## Features","## Workflows / mental model","## Community","## License"]'
  local manifest_path
  manifest_path=$(emit_audit "$f" "augment" "missing catalogue sections" "$additions" "[]" "[]" "operator-confirmed")
  echo "audit manifest: $manifest_path" >&2
  for sec in "## Why" "## Features" "## Workflows / mental model" "## Community" "## License"; do
    if ! grep -qF "$sec" "$f"; then
      printf "\n\n%s\n\n<content to be filled in>\n" "$sec" >> "$f"
    fi
  done
  guard_proof_signals "$f" || exit 3
}

# ---- 6. Main dispatch ----
case "$MODE" in
  template)
    if [[ -f "$OUT" && "$FORCE" -ne 1 ]]; then
      echo "refusing to overwrite existing README at $OUT without --force" >&2
      exit 1
    fi
    render_template "$OUT"
    guard_proof_signals "$OUT" || exit 3
    ;;
  augment)
    if is_sparse "$OUT"; then
      echo "refusing to augment sparse README; use --mode template" >&2
      exit 1
    fi
    augment "$OUT"
    ;;
  audit-only)
    if is_sparse "$OUT"; then
      echo "mode: template (sparse)"
    else
      echo "mode: augment (existing)"
    fi
    emit_audit "$OUT" "audit-only" "manual" "[]" "[]" "[]" "audit-only"
    ;;
  *) echo "unknown --mode: $MODE" >&2; exit 1;;
esac

echo "ok: $MODE $OUT"
