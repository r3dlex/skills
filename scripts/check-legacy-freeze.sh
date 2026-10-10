#!/usr/bin/env bash
# generated compat-shim — rendered from the bash template; do not edit
set -euo pipefail
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
entry="$here/lib/check-legacy-freeze.mjs"
if [[ ! -f "$entry" ]]; then
	printf 'node_unavailable\n' >&2
	exit 127
fi
node_bin="$(command -v node 2>/dev/null || true)"
if [[ -z "$node_bin" ]]; then
	printf 'node_unavailable\n' >&2
	exit 127
fi
if ! version="$("$node_bin" --version 2>/dev/null)"; then
	printf 'node_unavailable\n' >&2
	exit 127
fi
case "$version" in
v26.*)
	;;
*)
	printf 'node_version_unsupported\n' >&2
	exit 126
	;;
esac
env_args=()
if [[ "${PATH+x}" == x ]]; then env_args+=("PATH=$PATH"); fi
if [[ "${HOME+x}" == x ]]; then env_args+=("HOME=$HOME"); fi
if [[ "${LANG+x}" == x ]]; then env_args+=("LANG=$LANG"); fi
if [[ "${LC_ALL+x}" == x ]]; then env_args+=("LC_ALL=$LC_ALL"); fi
if [[ "${TMPDIR+x}" == x ]]; then env_args+=("TMPDIR=$TMPDIR"); fi
if [[ ${#env_args[@]} -gt 0 ]]; then
	exec /usr/bin/env -i "${env_args[@]}" "$node_bin" --disable-proto=throw "$entry" "$@"
fi
exec /usr/bin/env -i "$node_bin" --disable-proto=throw "$entry" "$@"
