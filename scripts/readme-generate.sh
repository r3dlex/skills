#!/bin/bash
#
# readme-generate.sh
# Generate or augment a repo's README.md under the ai-catapult-init readme-documentation module.
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
#   --archetype cli-tool|skill-catalog  README shape for executable onboarding.
#   --install-command <command>  Recommended installation command.
#   --first-success-command <command>  Representative first-use command.
#   --success-evidence <text>  Observable output or artifact proving first success.
#   --requirements <text>  Optional requirements summary.
#   --update-command <command>  Optional update command.
#   --visibility public|private  Host visibility; default private.
#   --license <SPDX>   License SPDX id (default: read from LICENSE file).
#   --badges <list>    Comma-separated badge keys. Only repository-backed license is generated;
#                      dynamic build/release/coverage/download badges fail closed.
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
ARCHETYPE=""
INSTALL_COMMAND=""
FIRST_SUCCESS_COMMAND=""
SUCCESS_EVIDENCE=""
REQUIREMENTS=""
UPDATE_COMMAND=""
OUT=""
FORCE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2;;
    --repo) REPO="$2"; shift 2;;
    --project) PROJECT="$2"; shift 2;;
    --tagline) TAGLINE="$2"; shift 2;;
    --archetype) ARCHETYPE="$2"; shift 2;;
    --install-command) INSTALL_COMMAND="$2"; shift 2;;
    --first-success-command) FIRST_SUCCESS_COMMAND="$2"; shift 2;;
    --success-evidence) SUCCESS_EVIDENCE="$2"; shift 2;;
    --requirements) REQUIREMENTS="$2"; shift 2;;
    --update-command) UPDATE_COMMAND="$2"; shift 2;;
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
  if grep -qiE 'shields\.io/badge/.*-fake|CI-passing|release-latest|coverage-100%25|downloads-monthly|<[[:alnum:]_][^>]*>|content to be filled in|example\.com' "$f"; then
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

validate_onboarding_inputs() {
  local missing=()
  [[ "$ARCHETYPE" == "cli-tool" || "$ARCHETYPE" == "skill-catalog" ]] || missing+=("--archetype cli-tool|skill-catalog")
  [[ -n "$PROJECT" ]] || missing+=("--project")
  [[ -n "$TAGLINE" ]] || missing+=("--tagline")
  [[ -n "$INSTALL_COMMAND" && ! "$INSTALL_COMMAND" =~ ^[[:space:]]*# ]] || missing+=("--install-command with an executable command")
  [[ -n "$FIRST_SUCCESS_COMMAND" && ! "$FIRST_SUCCESS_COMMAND" =~ ^[[:space:]]*# ]] || missing+=("--first-success-command with an executable command")
  [[ -n "$SUCCESS_EVIDENCE" ]] || missing+=("--success-evidence with observable output or artifact")
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'missing canonical README input: %s\n' "$(IFS=', '; echo "${missing[*]}")" >&2
    return 1
  fi
}

detect_license() {
  [[ -f "$REPO/LICENSE" ]] || return 0
  if grep -q 'Apache License' "$REPO/LICENSE"; then
    echo "Apache-2.0"
  elif grep -q 'MIT License' "$REPO/LICENSE"; then
    echo "MIT"
  fi
}

archetype_section() {
  case "$ARCHETYPE" in
    cli-tool)
      cat <<'EOF'
## How it works

1. Install the tool with the recommended command above.
2. Run the representative command against your target.
3. Confirm the documented result before moving to advanced options.

EOF
      ;;
    skill-catalog)
      cat <<'EOF'
## How it works

1. Install the catalog into the supported agent host.
2. The host discovers each skill from its `SKILL.md` metadata.
3. Invoke a matching skill and confirm the documented result before using additional workflows.

EOF
      ;;
  esac
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
  local project_name="$PROJECT"
  local tagline="$TAGLINE"
  local detected_license; detected_license=$(detect_license)
  local license_id="${LICENSE_SPDX:-$detected_license}"
  if [[ -n "$LICENSE_SPDX" && -n "$detected_license" && "$LICENSE_SPDX" != "$detected_license" ]]; then
    echo "proof-signal guard: supplied license '$LICENSE_SPDX' does not match detected '$detected_license'" >&2
    return 3
  fi
  local badges_block=""
  if [[ -n "$BADGES" ]]; then
    IFS=',' read -ra arr <<< "$BADGES"
    for b in "${arr[@]}"; do
      case "$b" in
        license)
          if [[ -z "$license_id" || ! -f "$REPO/LICENSE" ]]; then
            echo "proof-signal guard: license badge requires a real LICENSE file and detected or supplied SPDX id" >&2
            return 3
          fi
          badges_block+="[![License: $license_id](https://img.shields.io/badge/license-$license_id-blue)](LICENSE)
"
          ;;
        build|release|coverage|downloads)
          echo "proof-signal guard: '$b' badge requires a verified external source; omit it or add it manually from repository evidence" >&2
          return 3
          ;;
        *) echo "unknown badge key: $b" >&2; return 1;;
      esac
    done
  fi
  local star_section=""
  if [[ "$VISIBILITY" == "public" && -n "$STAR_HISTORY_URL" ]]; then
    star_section=$'## Project history\n\n[View the public star history]('"$STAR_HISTORY_URL"$').\n\n'
  fi

  local requirements_section="" update_section="" community_section="" license_section="" governance_section=""
  [[ -z "$REQUIREMENTS" ]] || requirements_section=$'## Requirements\n\n- '"$REQUIREMENTS"$'\n\n'
  [[ -z "$UPDATE_COMMAND" ]] || update_section=$'## Update\n\n```sh\n'"$UPDATE_COMMAND"$'\n```\n\n'
  [[ ! -f "$REPO/CONTRIBUTING.md" ]] || community_section=$'## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to propose changes or report repository-specific problems.\n\n'
  [[ -z "$license_id" || ! -f "$REPO/LICENSE" ]] || license_section=$'## License\n\n'"$license_id"$' — see [LICENSE](LICENSE).\n\n'
  if [[ -f "$REPO/AGENTS.md" ]]; then
    governance_section=$'<!-- AI-SDLC:start -->\nThis repository follows the AI-SDLC methodology. See [AGENTS.md](AGENTS.md) for the operating contract'
    [[ ! -d "$REPO/docs/architecture/adr" ]] || governance_section+=', and [docs/architecture/adr/](docs/architecture/adr/) for architectural decisions'
    governance_section+=$'.\n<!-- AI-SDLC:end -->\n'
  fi

  # Read template and substitute placeholders.
  local body
  body=$(cat "$TEMPLATE")
  body="${body//@@PROJECT_NAME@@/$project_name}"
  body="${body//@@PROJECT_TAGLINE@@/$tagline}"
  body="${body//@@BADGES_BLOCK@@/$badges_block}"
  body="${body//@@INSTALL_COMMAND@@/$INSTALL_COMMAND}"
  body="${body//@@FIRST_SUCCESS_COMMAND@@/$FIRST_SUCCESS_COMMAND}"
  body="${body//@@SUCCESS_EVIDENCE@@/$SUCCESS_EVIDENCE}"
  body="${body//@@REQUIREMENTS_SECTION@@/$requirements_section}"
  body="${body//@@WHY_SECTION@@/$'## Why\n\n'"$tagline"$'\n\n'}"
  body="${body//@@ARCHETYPE_SECTION@@/$(archetype_section)}"
  body="${body//@@UPDATE_SECTION@@/$update_section}"
  body="${body//@@COMMUNITY_SECTION@@/$community_section}"
  body="${body//@@LICENSE_SECTION@@/$license_section}"
  body="${body//@@STAR_HISTORY_SECTION@@/$star_section}"
  body="${body//@@GOVERNANCE_SECTION@@/$governance_section}"
  if grep -qE '@@[A-Z_]+@@|<[[:alnum:]_][^>]*>|content to be filled in' <<< "$body"; then
    echo "README rendering left unresolved template content" >&2
    return 1
  fi
  printf '%s\n' "$body" > "$out"
}

# ---- 5. Augment (append missing sections) ----
augment() {
  local f="$1"
  local additions='["canonical onboarding sections missing from source"]'
  local manifest_path
  local candidate; candidate=$(mktemp)
  cp "$f" "$candidate"
  if ! grep -qiE '^##[[:space:]]+Quick Start' "$candidate"; then
    printf '\n\n## Quick Start\n\n```sh\n%s\n%s\n```\n' "$INSTALL_COMMAND" "$FIRST_SUCCESS_COMMAND" >> "$candidate"
  fi
  if ! grep -qiE '(expected|verify|success).*(result|output|evidence)|result.*(expected|success)' "$candidate"; then
    printf '\n\n## First success\n\n**Expected result:** %s\n' "$SUCCESS_EVIDENCE" >> "$candidate"
  fi
  grep -qiE '^##[[:space:]]+Why' "$candidate" || printf '\n\n## Why\n\n%s\n' "$TAGLINE" >> "$candidate"
  grep -qiE '^##[[:space:]]+(How it works|Workflows|Mental model)' "$candidate" || printf '\n\n%s\n' "$(archetype_section)" >> "$candidate"
  if [[ -f "$REPO/CONTRIBUTING.md" ]] && ! grep -qiE '^##[[:space:]]+Community' "$candidate"; then
    printf '\n\n## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.\n' >> "$candidate"
  fi
  guard_proof_signals "$candidate" || { rm -f "$candidate"; return 3; }
  manifest_path=$(emit_audit "$f" "augment" "missing canonical onboarding" "$additions" "[]" "[]" "operator-confirmed")
  echo "audit manifest: $manifest_path" >&2
  mv "$candidate" "$f"
}

# ---- 6. Main dispatch ----
case "$MODE" in
  template)
    validate_onboarding_inputs || exit 1
    if [[ -f "$OUT" && "$FORCE" -ne 1 ]]; then
      echo "refusing to overwrite existing README at $OUT without --force" >&2
      exit 1
    fi
    candidate=$(mktemp)
    render_template "$candidate" || exit $?
    guard_proof_signals "$candidate" || exit 3
    mv "$candidate" "$OUT"
    ;;
  augment)
    validate_onboarding_inputs || exit 1
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
