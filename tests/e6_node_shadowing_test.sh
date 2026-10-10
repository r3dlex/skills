#!/usr/bin/env bash
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
PASS=0
FAIL=0
ok() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}
bad() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}

work="$(mktemp -d)"
node scripts/lib/shim-render.mjs bash lib/sample.mjs >"$work/run.sh"
node scripts/lib/shim-render.mjs python3 lib/sample.mjs >"$work/run.py"
chmod +x "$work/run.sh" "$work/run.py"
mkdir -p "$work/lib"
cp scripts/lib/*.mjs "$work/lib/"

clean_out="$(mktemp)"
clean_err="$(mktemp)"
(cd "$work" && ./run.sh >"$clean_out" 2>"$clean_err")
clean_status=$?

probe() {
	local name="$1"
	shift
	local out err status
	out="$(mktemp)"
	err="$(mktemp)"
	(cd "$work" && "$@" >"$out" 2>"$err")
	status=$?
	if [[ "$status" -eq "$clean_status" && "$(cat "$out")" == "$(cat "$clean_out")" && "$(cat "$err")" == "$(cat "$clean_err")" ]]; then
		ok "shim unchanged under $name"
	else
		bad "shim unchanged under $name"
	fi
	rm -f "$out" "$err"
}

preload="$(mktemp).cjs"
printf '%s\n' 'process.stdout.write("preloaded\\n");' >"$preload"
probe "NODE_OPTIONS --require" env NODE_OPTIONS="--require $preload" ./run.sh
probe "NODE_OPTIONS invalid" env NODE_OPTIONS=--definitely-invalid ./run.sh
probe "NODE_DEBUG" env NODE_DEBUG=module ./run.sh
mkdir -p "$work/hostile"
printf '%s\n' '{}' >"$work/hostile/package.json"
probe "typeless ancestor package.json" sh -c 'cd hostile && ../run.sh'
printf '%s\n' '{"type":"commonjs"}' >"$work/hostile/package.json"
probe "commonjs ancestor package.json" sh -c 'cd hostile && ../run.sh'
mkdir -p "$work/node_modules/sample"
printf '%s\n' 'module.exports = { hijacked: true };' >"$work/node_modules/sample/index.js"
probe "cwd node_modules shadow" ./run.sh
probe "python3 shim PYTHONPATH" env PYTHONPATH="$work" ./run.py

# Red legs: each probe changes an unprotected run. The shim cases above stay identical.
plain="$(node scripts/lib/sample.mjs)"
preloaded="$(NODE_OPTIONS="--require $preload" node scripts/lib/sample.mjs)"
[[ "$plain" != "$preloaded" ]] && ok "unprotected node changes under --require" || bad "unprotected node changes under --require"
import_preload="$(mktemp).mjs"
printf '%s\n' 'process.stdout.write("imported\n");' >"$import_preload"
imported="$(NODE_OPTIONS="--import $import_preload" node scripts/lib/sample.mjs)"
[[ "$plain" != "$imported" ]] && ok "unprotected node changes under --import" || bad "unprotected node changes under --import"
debug_err="$(NODE_DEBUG=module node scripts/lib/sample.mjs 2>&1 >/dev/null || true)"
[[ -n "$debug_err" ]] && ok "unprotected node changes under NODE_DEBUG" || bad "unprotected node changes under NODE_DEBUG"
js_dir="$(mktemp -d)"
printf '%s\n' 'import { readFileSync } from "node:fs";' 'process.stdout.write("js-build\n");' >"$js_dir/app.js"
bare_err="$(cd "$js_dir" && node app.js 2>&1 >/dev/null || true)"
printf '%s\n' '{}' >"$js_dir/package.json"
typeless_err="$(cd "$js_dir" && node app.js 2>&1 >/dev/null || true)"
[[ "$bare_err" != "$typeless_err" ]] && ok "typeless package.json changes a .js build" || bad "typeless package.json changes a .js build"
printf '%s\n' '{"type":"commonjs"}' >"$js_dir/package.json"
if (cd "$js_dir" && node app.js >/dev/null 2>&1); then
	bad "commonjs .js build is not ESM"
else
	ok "commonjs ancestor changes a .js build"
fi
printf '%s\n' 'process.stdout.write(require("sample").tag + "\n");' >"$js_dir/require.js"
mkdir -p "$js_dir/node_modules/sample"
printf '%s\n' 'module.exports = { tag: "shadowed" };' >"$js_dir/node_modules/sample/index.js"
shadowed="$(cd "$js_dir" && node require.js)"
[[ "$shadowed" == shadowed ]] && ok "cwd node_modules shadows an unprotected require" || bad "cwd node_modules shadows an unprotected require"
site="$(mktemp -d)"
printf '%s\n' 'import sys; sys.stderr.write("sitecustomize\n")' >"$site/sitecustomize.py"
printf '%s\n' 'print("clean")' >"$site/clean.py"
site_err="$(PYTHONPATH="$site" python3 "$site/clean.py" 2>&1 >/dev/null || true)"
[[ "$site_err" == *sitecustomize* ]] && ok "PYTHONPATH changes an unprotected python3" || bad "PYTHONPATH changes an unprotected python3"
rm -rf "$js_dir" "$site" "$import_preload"

stub="$(mktemp -d)"
cat >"$stub/node" <<'EOF'
#!/bin/sh
if [ "$1" = "--version" ]; then
  echo v18.0.0
  exit 0
fi
echo should-not-run >&2
exit 99
EOF
chmod +x "$stub/node"
stub_err="$(mktemp)"
(cd "$work" && PATH="$stub:$PATH" ./run.sh >/dev/null 2>"$stub_err")
stub_status=$?
if [[ "$stub_status" -eq 126 && "$(cat "$stub_err")" == "node_version_unsupported" ]]; then
	ok "stub node outside the range is refused"
else
	bad "stub node outside the range is refused (status $stub_status err $(cat "$stub_err"))"
fi
rm -rf "$work" "$stub" "$preload" "$clean_out" "$clean_err" "$stub_err"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
