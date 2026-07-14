#!/bin/bash
# Shared argument parsing and selection for host installers.
CATALOG_INCLUDES=()
CATALOG_REST=()
parse_catalog_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-lifecycle)
        [[ $# -ge 2 ]] || { echo "--include-lifecycle requires a value" >&2; return 2; }
        case "$2" in stable|compatibility|experimental|deprecated) CATALOG_INCLUDES+=("$2");; *) echo "unknown lifecycle: $2" >&2; return 2;; esac
        shift 2;;
      *) CATALOG_REST+=("$1"); shift;;
    esac
  done
}
catalog_rows() {
  local host="$1"; shift
  local args=(--root "$SKILLS_DIR" --host "$host") value
  if [[ ${#CATALOG_INCLUDES[@]} -gt 0 ]]; then
    for value in "${CATALOG_INCLUDES[@]}"; do args+=(--include-lifecycle "$value"); done
  fi
  python3 "$SCRIPT_DIR/catalog-query.py" "${args[@]}" "$@"
}

flattened_skill_body() {
  sed -n '/^---$/,/^---$/d; /modules\//d; /REFERENCE\.md/d; p' "$1"
}
