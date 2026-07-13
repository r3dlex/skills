#!/bin/bash
# Generate or augment a repository README with concrete onboarding evidence.
set -euo pipefail

MODE=""
REPO="."
PROJECT=""
TAGLINE=""
WHY=""
ARCHETYPE=""
PRIMARY_SURFACE=""
MENTAL_MODEL=""
INSTALL_COMMAND=""
FIRST_SUCCESS_COMMAND=""
SUCCESS_EVIDENCE=""
REQUIREMENTS=""
UPDATE_COMMAND=""
VISIBILITY="private"
LICENSE_SPDX=""
VERIFIED_LICENSE=""
BADGES=""
OUT=""
SOURCE_SHA=""
FORCE=0

usage() {
  cat <<'USAGE'
Usage: readme-generate.sh --mode template|augment|audit-only [options]

Canonical onboarding inputs for template and augment:
  --project <name>
  --tagline <text>
  --why <text>
  --archetype cli-tool|skill-catalog
  --primary-surface <text>
  --mental-model <text>
  --install-command <command>
  --first-success-command <command>
  --success-evidence <observable output or artifact>

Optional facts:
  --requirements <text>
  --update-command <command>
  --visibility public|private
  --license <SPDX>             Must match a recognized LICENSE file.
  --badges license             Only a verified license badge is deterministic.

Write controls:
  --repo <path>                Target repository (default: .).
  --out <path>                 README path (default: <repo>/README.md).
  --force                      Replace an existing README in template mode.
  --source-sha <sha256>        Required for --force and augment; must match the reviewed source.
USAGE
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || { echo "$1 requires a value" >&2; exit 1; }
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) require_value "$@"; MODE="$2"; shift 2;;
    --repo) require_value "$@"; REPO="$2"; shift 2;;
    --project) require_value "$@"; PROJECT="$2"; shift 2;;
    --tagline) require_value "$@"; TAGLINE="$2"; shift 2;;
    --why) require_value "$@"; WHY="$2"; shift 2;;
    --archetype) require_value "$@"; ARCHETYPE="$2"; shift 2;;
    --primary-surface) require_value "$@"; PRIMARY_SURFACE="$2"; shift 2;;
    --mental-model) require_value "$@"; MENTAL_MODEL="$2"; shift 2;;
    --install-command) require_value "$@"; INSTALL_COMMAND="$2"; shift 2;;
    --first-success-command) require_value "$@"; FIRST_SUCCESS_COMMAND="$2"; shift 2;;
    --success-evidence) require_value "$@"; SUCCESS_EVIDENCE="$2"; shift 2;;
    --requirements) require_value "$@"; REQUIREMENTS="$2"; shift 2;;
    --update-command) require_value "$@"; UPDATE_COMMAND="$2"; shift 2;;
    --visibility) require_value "$@"; VISIBILITY="$2"; shift 2;;
    --license) require_value "$@"; LICENSE_SPDX="$2"; shift 2;;
    --badges) require_value "$@"; BADGES="$2"; shift 2;;
    --out) require_value "$@"; OUT="$2"; shift 2;;
    --source-sha) require_value "$@"; SOURCE_SHA="$2"; shift 2;;
    --force) FORCE=1; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done

[[ -n "$MODE" ]] || { echo "--mode required" >&2; exit 1; }
[[ "$VISIBILITY" == "public" || "$VISIBILITY" == "private" ]] || {
  echo "--visibility must be public or private" >&2
  exit 1
}
[[ -n "$OUT" ]] || OUT="$REPO/README.md"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$SCRIPT_DIR/../assets/readme/template.md"

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

is_sparse() {
  local file="$1" size
  [[ -f "$file" ]] || return 0
  size=$(wc -c < "$file" | tr -d ' ')
  [[ "$size" -ge 600 ]] || return 0
  grep -qiE '^##[[:space:]]*(quick start|features|installation|usage|why|license|community)' "$file" || return 0
  grep -qiE '^(WIP|TODO|Coming soon|TBD)[[:space:]]*$' "$file" && return 0
  return 1
}

contains_unresolved_content() {
  local file="$1"
  grep -qiE '@@[A-Z_]+@@|\{\{[^}]+\}\}|\[\[[^]]+\]\]|<(your|insert|replace)[^>]*>|<(project[_ -]?name|tagline|install[_ -]?command|first[_ -]?success|success[_ -]?evidence)>|content to be filled in|(^|[[:space:]])(TODO|TBD|coming soon)([[:space:].!]|$)' "$file"
}

guard_proof_signals() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  if contains_unresolved_content "$file" || grep -qiE 'shields\.io/badge/.*-fake|CI-passing|release-latest|coverage-100%25|downloads-monthly|example\.com/(badge|release|download)' "$file"; then
    echo "proof-signal guard: unresolved content or invented claim detected" >&2
    return 3
  fi
  if [[ "$VISIBILITY" == "public" ]] && grep -qiE '(internal-only|do-not-share|private-(repo|workflow))' "$file"; then
    echo "proof-signal guard: private/internal marker in public README" >&2
    return 3
  fi
  if [[ "$VISIBILITY" == "private" ]] && grep -qiE 'star[- ]history|public[- ]contributors|downloads' "$file"; then
    echo "proof-signal guard: public proof signal in private README" >&2
    return 3
  fi
  return 0
}

validate_onboarding_inputs() {
  local missing=()
  [[ -n "$PROJECT" ]] || missing+=("--project")
  [[ -n "$TAGLINE" ]] || missing+=("--tagline")
  [[ -n "$WHY" && "$WHY" != "$TAGLINE" ]] || missing+=("--why distinct from --tagline")
  [[ "$ARCHETYPE" == "cli-tool" || "$ARCHETYPE" == "skill-catalog" ]] || missing+=("--archetype cli-tool|skill-catalog")
  [[ -n "$PRIMARY_SURFACE" ]] || missing+=("--primary-surface")
  [[ -n "$MENTAL_MODEL" ]] || missing+=("--mental-model")
  [[ -n "$INSTALL_COMMAND" && ! "$INSTALL_COMMAND" =~ ^[[:space:]]*# ]] || missing+=("--install-command with an executable command")
  [[ -n "$FIRST_SUCCESS_COMMAND" && ! "$FIRST_SUCCESS_COMMAND" =~ ^[[:space:]]*# ]] || missing+=("--first-success-command with an executable command")
  [[ -n "$SUCCESS_EVIDENCE" ]] || missing+=("--success-evidence with observable output or artifact")
  if [[ ${#missing[@]} -gt 0 ]]; then
    printf 'missing canonical README input: %s\n' "$(IFS=', '; echo "${missing[*]}")" >&2
    return 1
  fi
}

detect_license() {
  local file="$REPO/LICENSE"
  [[ -f "$file" ]] || return 0
  if grep -qi 'Apache License, Version 2\.0\|Apache License.*Version 2\.0' "$file"; then
    echo "Apache-2.0"
  elif grep -q 'MIT License' "$file"; then
    echo "MIT"
  elif grep -qi 'GNU AFFERO GENERAL PUBLIC LICENSE' "$file" && grep -qi 'Version 3' "$file"; then
    echo "AGPL-3.0-only"
  elif grep -qi 'GNU GENERAL PUBLIC LICENSE' "$file" && grep -qi 'Version 3' "$file"; then
    echo "GPL-3.0-only"
  elif grep -qi 'GNU GENERAL PUBLIC LICENSE' "$file" && grep -qi 'Version 2' "$file"; then
    echo "GPL-2.0-only"
  elif grep -qi 'Redistribution and use in source and binary forms' "$file" && grep -qi 'Neither the name' "$file"; then
    echo "BSD-3-Clause"
  elif grep -qi 'Redistribution and use in source and binary forms' "$file"; then
    echo "BSD-2-Clause"
  fi
  return 0
}

resolve_verified_license() {
  local detected
  detected=$(detect_license)
  VERIFIED_LICENSE=""
  if [[ -n "$LICENSE_SPDX" ]]; then
    if [[ ! -f "$REPO/LICENSE" || -z "$detected" ]]; then
      echo "proof-signal guard: supplied license '$LICENSE_SPDX' cannot be verified from a recognized LICENSE file" >&2
      return 3
    fi
    if [[ "$LICENSE_SPDX" != "$detected" ]]; then
      echo "proof-signal guard: supplied license '$LICENSE_SPDX' does not match detected '$detected'" >&2
      return 3
    fi
  fi
  VERIFIED_LICENSE="${LICENSE_SPDX:-$detected}"
}

archetype_section() {
  case "$ARCHETYPE" in
    cli-tool)
      cat <<EOF
## How it works

**Primary command surface:** $PRIMARY_SURFACE

**Mental model:** $MENTAL_MODEL

1. Install the CLI with the recommended command.
2. Run the documented command against one target.
3. Confirm the observable result before using additional commands.
EOF
      ;;
    skill-catalog)
      cat <<EOF
## How it works

**Skill discovery surface:** $PRIMARY_SURFACE

**Mental model:** $MENTAL_MODEL

1. Install the catalog into the supported agent host.
2. Let the host discover skill metadata from the documented surface.
3. Invoke one matching skill and confirm the observable result.
EOF
      ;;
  esac
}

governance_section() {
  local links=() joined="" link
  if [[ -f "$REPO/AGENTS.md" ]]; then
    links+=("[AGENTS.md](AGENTS.md)")
  elif [[ -f "$REPO/CLAUDE.md" ]]; then
    links+=("[CLAUDE.md](CLAUDE.md)")
  fi
  [[ ! -f "$REPO/CONTRIBUTING.md" ]] || links+=("[CONTRIBUTING.md](CONTRIBUTING.md)")
  [[ ! -d "$REPO/docs/architecture/adr" ]] || links+=("[docs/architecture/adr/](docs/architecture/adr/)")
  if [[ -d "$REPO/docs/specifications" ]]; then
    links+=("[docs/specifications/](docs/specifications/)")
  elif [[ -d "$REPO/docs/specs" ]]; then
    links+=("[docs/specs/](docs/specs/)")
  fi
  [[ ! -d "$REPO/.ai/traceability" ]] || links+=("[.ai/traceability/](.ai/traceability/)")
  [[ ${#links[@]} -gt 0 ]] || return 0
  for link in "${links[@]}"; do
    [[ -z "$joined" ]] || joined+=", "
    joined+="$link"
  done
  printf '<!-- AI-SDLC:start -->\nRepository governance and traceability: see %s.\n<!-- AI-SDLC:end -->\n' "$joined"
}

LAST_MANIFEST_PATH=""
LAST_BACKUP_PATH=""
emit_audit() {
  local src="$1" mode="$2" reason="$3" additions="$4" modifications="$5" deletions="$6" user_response="$7"
  local ts backup_dir src_sha="" src_size=0 src_lines=0 section_list="[]"
  ts="$(date -u +"%Y-%m-%dT%H-%M-%SZ")-$$"
  backup_dir="$REPO/.ai/drift/readme-backups"
  LAST_MANIFEST_PATH="$backup_dir/audit-$ts.json"
  LAST_BACKUP_PATH=""
  mkdir -p "$backup_dir"
  if [[ -f "$src" ]]; then
    src_sha=$(sha256_file "$src")
    src_size=$(wc -c < "$src" | tr -d ' ')
    src_lines=$(wc -l < "$src" | tr -d ' ')
    LAST_BACKUP_PATH="$backup_dir/README-$ts.bak"
    cp "$src" "$LAST_BACKUP_PATH"
    section_list=$({ grep -E '^##?[[:space:]]' "$src" || true; } | sed 's/^##*[[:space:]]*//' | sed 's/["\\]/_/g' | awk 'BEGIN{printf "["} {printf "%s\"%s\"", (NR==1?"":","), $0} END{print "]"}')
  fi
  cat > "$LAST_MANIFEST_PATH" <<JSON
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
  "backup_path": "$LAST_BACKUP_PATH"
}
JSON
}

validate_reviewed_source() {
  local file="$1"
  [[ "$SOURCE_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "guarded write requires --source-sha with the reviewed README SHA-256" >&2
    return 2
  }
  [[ -f "$file" && "$(sha256_file "$file")" == "$SOURCE_SHA" ]] || {
    echo "guarded write rejected: README no longer matches --source-sha" >&2
    return 2
  }
}

guarded_replace() {
  local candidate="$1" destination="$2" mode="$3" reason="$4" additions="$5" expected_sha="$6" destination_mode
  if [[ -f "$destination" ]]; then
    [[ "$(sha256_file "$destination")" == "$expected_sha" ]] || {
      echo "guarded write rejected: README changed before backup" >&2
      rm -f "$candidate"
      return 2
    }
    emit_audit "$destination" "$mode" "$reason" "$additions" '[]' '[]' 'source-sha-confirmed'
    if [[ -z "$LAST_BACKUP_PATH" || "$(sha256_file "$LAST_BACKUP_PATH")" != "$expected_sha" || "$(sha256_file "$destination")" != "$expected_sha" ]]; then
      echo "guarded write rejected: source or backup SHA changed" >&2
      rm -f "$candidate"
      return 2
    fi
    echo "audit manifest: $LAST_MANIFEST_PATH" >&2
    destination_mode=$(file_mode "$destination")
    chmod "$destination_mode" "$candidate"
  fi
  mv "$candidate" "$destination"
}

render_template() {
  local out="$1" badges_block="" requirements_section="" why_section="" archetype_block=""
  local update_section="" community_section="" license_section="" governance_section="" body badge
  if [[ -n "$BADGES" ]]; then
    IFS=',' read -ra badge_list <<< "$BADGES"
    for badge in "${badge_list[@]}"; do
      case "$badge" in
        license)
          [[ -n "$VERIFIED_LICENSE" ]] || {
            echo "proof-signal guard: license badge requires a recognized LICENSE file" >&2
            return 3
          }
          badges_block+="[![License: $VERIFIED_LICENSE](https://img.shields.io/badge/license-$VERIFIED_LICENSE-blue)](LICENSE)"
          ;;
        build|release|coverage|downloads)
          echo "proof-signal guard: '$badge' badge requires verified external repository evidence" >&2
          return 3
          ;;
        *) echo "unknown badge key: $badge" >&2; return 1;;
      esac
    done
  fi
  [[ -z "$REQUIREMENTS" ]] || requirements_section=$'## Requirements\n\n- '"$REQUIREMENTS"
  why_section=$'## Why\n\n'"$WHY"
  archetype_block=$(archetype_section)
  [[ -z "$UPDATE_COMMAND" ]] || update_section=$'## Update\n\n```sh\n'"$UPDATE_COMMAND"$'\n```'
  [[ ! -f "$REPO/CONTRIBUTING.md" ]] || community_section=$'## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to propose changes or report repository-specific problems.'
  [[ -z "$VERIFIED_LICENSE" ]] || license_section=$'## License\n\n'"$VERIFIED_LICENSE"$' — see [LICENSE](LICENSE).'
  governance_section=$(governance_section)

  body=$(cat "$TEMPLATE")
  body="${body//@@PROJECT_NAME@@/$PROJECT}"
  body="${body//@@PROJECT_TAGLINE@@/$TAGLINE}"
  body="${body//@@BADGES_BLOCK@@/$badges_block}"
  body="${body//@@INSTALL_COMMAND@@/$INSTALL_COMMAND}"
  body="${body//@@FIRST_SUCCESS_COMMAND@@/$FIRST_SUCCESS_COMMAND}"
  body="${body//@@SUCCESS_EVIDENCE@@/$SUCCESS_EVIDENCE}"
  body="${body//@@REQUIREMENTS_SECTION@@/$requirements_section}"
  body="${body//@@WHY_SECTION@@/$why_section}"
  body="${body//@@ARCHETYPE_SECTION@@/$archetype_block}"
  body="${body//@@UPDATE_SECTION@@/$update_section}"
  body="${body//@@COMMUNITY_SECTION@@/$community_section}"
  body="${body//@@LICENSE_SECTION@@/$license_section}"
  body="${body//@@GOVERNANCE_SECTION@@/$governance_section}"
  printf '%s\n' "$body" > "$out"
  contains_unresolved_content "$out" && {
    echo "README rendering left unresolved template content" >&2
    return 1
  }
  return 0
}

append_section() {
  local file="$1" content="$2"
  printf '\n\n%s\n' "$content" >> "$file"
}

augment() {
  local file="$1" candidate expected_sha="$SOURCE_SHA"
  candidate=$(mktemp)
  cp "$file" "$candidate"
  grep -qiE '^##[[:space:]]+Quick Start' "$candidate" || append_section "$candidate" $'## Quick Start\n\n```sh\n'"$INSTALL_COMMAND"$'\n'"$FIRST_SUCCESS_COMMAND"$'\n```'
  grep -qiE '(expected|verify|success).*(result|output|evidence)|result.*(expected|success)' "$candidate" || append_section "$candidate" $'## First success\n\n**Expected result:** '"$SUCCESS_EVIDENCE"
  [[ -z "$REQUIREMENTS" ]] || grep -qiE '^##[[:space:]]+Requirements' "$candidate" || append_section "$candidate" $'## Requirements\n\n- '"$REQUIREMENTS"
  grep -qiE '^##[[:space:]]+Why' "$candidate" || append_section "$candidate" $'## Why\n\n'"$WHY"
  grep -qiE '^##[[:space:]]+(How it works|Workflows|Mental model)' "$candidate" || append_section "$candidate" "$(archetype_section)"
  [[ -z "$UPDATE_COMMAND" ]] || grep -qiE '^##[[:space:]]+Update' "$candidate" || append_section "$candidate" $'## Update\n\n```sh\n'"$UPDATE_COMMAND"$'\n```'
  if [[ -f "$REPO/CONTRIBUTING.md" ]] && ! grep -qiE '^##[[:space:]]+Community' "$candidate"; then
    append_section "$candidate" $'## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.'
  fi
  [[ -z "$VERIFIED_LICENSE" ]] || grep -qiE '^##[[:space:]]+License' "$candidate" || append_section "$candidate" $'## License\n\n'"$VERIFIED_LICENSE"$' — see [LICENSE](LICENSE).'
  if ! grep -q '<!-- AI-SDLC:start -->' "$candidate"; then
    local governance_block
    governance_block=$(governance_section)
    [[ -z "$governance_block" ]] || append_section "$candidate" "$governance_block"
  fi
  guard_proof_signals "$candidate" || { rm -f "$candidate"; return 3; }
  guarded_replace "$candidate" "$file" "augment" "missing canonical onboarding" '["complete onboarding sections"]' "$expected_sha"
}

case "$MODE" in
  template)
    validate_onboarding_inputs || exit 1
    resolve_verified_license || exit 3
    if [[ -f "$OUT" ]]; then
      [[ "$FORCE" -eq 1 ]] || { echo "refusing to overwrite existing README at $OUT without --force" >&2; exit 1; }
      validate_reviewed_source "$OUT" || exit 2
    fi
    candidate=$(mktemp)
    render_template "$candidate" || { rc=$?; rm -f "$candidate"; exit "$rc"; }
    guard_proof_signals "$candidate" || { rc=$?; rm -f "$candidate"; exit "$rc"; }
    if [[ -f "$OUT" ]]; then
      guarded_replace "$candidate" "$OUT" "template-force" "operator-requested canonical replacement" '["canonical README"]' "$SOURCE_SHA" || exit $?
    else
      chmod 0644 "$candidate"
      mv "$candidate" "$OUT"
    fi
    ;;
  augment)
    validate_onboarding_inputs || exit 1
    resolve_verified_license || exit 3
    is_sparse "$OUT" && { echo "refusing to augment sparse README; use --mode template" >&2; exit 1; }
    validate_reviewed_source "$OUT" || exit 2
    augment "$OUT" || exit $?
    ;;
  audit-only)
    if is_sparse "$OUT"; then echo "mode: template (sparse)"; else echo "mode: augment (existing)"; fi
    emit_audit "$OUT" "audit-only" "manual" '[]' '[]' '[]' 'audit-only'
    echo "$LAST_MANIFEST_PATH"
    ;;
  *) echo "unknown --mode: $MODE" >&2; exit 1;;
esac

echo "ok: $MODE $OUT"
