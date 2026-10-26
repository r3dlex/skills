#!/usr/bin/env bash
#
# Regression test for the CPython traceback anchor band probe in
# scripts/lib/leaf/validate-cascade-fixtures.mjs.
#
# The port asks the running interpreter which PEP 657 anchor band it renders:
# nothing below 3.11, "^" only on 3.11-3.12, and from 3.13 the surrounding
# expression is marked with "~" plus an anchor row on every frame. The probe's
# stdout is not guaranteed to be a single clean token - a sitecustomize.py that
# prints, or any other stdout pollution, prepends noise to it. The port must
# read the band off the LAST non-empty line of the probe output and accept it
# only when it is exactly one of the three known bands. Anything else - noise,
# an unrecognised token, a probe that could not run - falls back to band 0, the
# pre-3.11 rendering this port emitted before the probe existed.
#
# The shims below stand in for python3 on PATH. Each one is a /bin/sh script,
# so this file embeds no python3 program of its own.
#
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
export PYTHONDONTWRITEBYTECODE=1
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

PORT="scripts/lib/leaf/validate-cascade-fixtures.mjs"
WORK="$(mktemp -d)"
cleanup() {
	rm -rf "$WORK"
}
trap cleanup EXIT

expect_present() {
	local file="$1" needle="$2" label="$3"
	if [[ -z "$needle" ]]; then
		return 0
	fi
	if grep -Fq -- "$needle" "$file"; then
		ok "$label"
	else
		bad "$label (missing: $needle)"
	fi
}
expect_absent() {
	local file="$1" needle="$2" label="$3"
	if [[ -z "$needle" ]]; then
		return 0
	fi
	if grep -Fq -- "$needle" "$file"; then
		bad "$label (unexpected: $needle)"
	else
		ok "$label"
	fi
}

REAL_PYTHON="$(command -v python3 || true)"
if [[ -z "$REAL_PYTHON" ]]; then
	bad "a python3 interpreter is on PATH"
	echo ""
	echo "Results: PASS=$PASS FAIL=$FAIL"
	exit 1
fi
ok "a python3 interpreter is on PATH"
export REAL_PYTHON

if ! command -v node >/dev/null 2>&1; then
	bad "node is on PATH"
	echo ""
	echo "Results: PASS=$PASS FAIL=$FAIL"
	exit 1
fi
ok "node is on PATH"

# The band the running interpreter actually renders, derived from its own
# version rather than from the port, so the expectation does not restate the
# rule the port has to implement.
version_line="$("$REAL_PYTHON" -V 2>&1)"
band=0
if [[ "$version_line" =~ Python[[:space:]]+([0-9]+)\.([0-9]+) ]]; then
	major="${BASH_REMATCH[1]}"
	minor="${BASH_REMATCH[2]}"
	if ((major > 3 || (major == 3 && minor >= 13))); then
		band=2
	elif ((major == 3 && minor >= 11)); then
		band=1
	fi
fi
if [[ "$band" -ge 1 ]]; then
	ok "the interpreter renders anchor band $band ($version_line)"
else
	ok "the interpreter renders anchor band $band ($version_line)"
fi

# The anchor rows the port emits, byte for byte as the port spells them.
module_row_2="             ~~~~^^"
module_row_1="             ^^^^^^"
intermediate_row_2="    ~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^"
assertion_row_2="           ~~~~~~~~~~~~~~~~~~^^"
carets_row="           ^^^^^^^^^^^^^^^^^^^^"

if [[ "$band" == "2" ]]; then
	present_module="$module_row_2"
	present_intermediate="$intermediate_row_2"
	present_assertion="$assertion_row_2"
	absent_assertion="$carets_row"
elif [[ "$band" == "1" ]]; then
	present_module="$module_row_1"
	present_intermediate=""
	present_assertion="$carets_row"
	absent_assertion="$assertion_row_2"
else
	present_module=""
	present_intermediate=""
	present_assertion=""
	absent_assertion="$carets_row"
fi

# A root whose cascade fixture is missing its audit trail, so the port
# refuses and renders the traceback this probe governs.
ROOT="$WORK/root"
mkdir -p "$ROOT/scripts" "$ROOT/reference/fixtures/v3/standalone/.ai/cascade"
printf 'placeholder for the compat-shim path the traceback names\n' >"$ROOT/scripts/validate-cascade-fixtures.py"
printf '%s\n' 'import { pathToFileURL } from "node:url";' 'const { main } = await import(pathToFileURL(process.env.PORT_MODULE).href);' 'process.exit(main(process.env.PORT_ROOT));' >"$WORK/driver.mjs"

BIN="$WORK/bin"
mkdir -p "$BIN"
PY_NAME="python3"
write_shim() {
	printf '%s\n' '#!/bin/sh' "$@" >"$BIN/$PY_NAME"
	chmod +x "$BIN/$PY_NAME"
}
run_port() {
	PATH="$BIN:$PATH" PORT_MODULE="$REPO_ROOT/$PORT" PORT_ROOT="$ROOT" \
		node "$WORK/driver.mjs" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt"
}

# 1. A pristine interpreter: the probe answers with one clean token.
write_shim 'exec "$REAL_PYTHON" "$@"'
run_port
clean_status=$?
cp "$WORK/stderr.txt" "$WORK/clean.txt"
if [[ "$clean_status" -eq 1 ]]; then
	ok "the pristine probe refuses the broken fixture"
else
	bad "the pristine probe refuses the broken fixture (exit $clean_status)"
fi
expect_present "$WORK/clean.txt" "$present_module" "the pristine probe renders the band $band module-frame anchor"
expect_present "$WORK/clean.txt" "$present_intermediate" "the pristine probe renders the band $band intermediate-frame anchor"
expect_present "$WORK/clean.txt" "$present_assertion" "the pristine probe renders the band $band assertion anchor"
expect_absent "$WORK/clean.txt" "$absent_assertion" "the pristine probe renders no anchor row of another band"

# 2. The same interpreter with stdout pollution: the probe's answer is no
#    longer the only thing on stdout.
write_shim 'printf "%s\n" "sitecustomize noise"' 'exec "$REAL_PYTHON" "$@"'
run_port
noisy_status=$?
cp "$WORK/stderr.txt" "$WORK/noisy.txt"
if [[ "$noisy_status" -eq 1 ]]; then
	ok "the polluted probe refuses the broken fixture"
else
	bad "the polluted probe refuses the broken fixture (exit $noisy_status)"
fi
expect_present "$WORK/noisy.txt" "$present_module" "the polluted probe renders the band $band module-frame anchor"
expect_present "$WORK/noisy.txt" "$present_intermediate" "the polluted probe renders the band $band intermediate-frame anchor"
expect_present "$WORK/noisy.txt" "$present_assertion" "the polluted probe renders the band $band assertion anchor"
expect_absent "$WORK/noisy.txt" "$absent_assertion" "the polluted probe renders no anchor row of another band"
if cmp -s "$WORK/clean.txt" "$WORK/noisy.txt"; then
	ok "stdout pollution does not change the rendered traceback"
else
	bad "stdout pollution does not change the rendered traceback"
fi

# 3. A probe whose answer is unrecognisable: the band falls back to 0.
write_shim 'printf "%s\n" "sitecustomize noise"' 'exit 0'
run_port
garbage_status=$?
cp "$WORK/stderr.txt" "$WORK/garbage.txt"
if [[ "$garbage_status" -eq 1 ]]; then
	ok "the unrecognised probe refuses the broken fixture"
else
	bad "the unrecognised probe refuses the broken fixture (exit $garbage_status)"
fi
expect_absent "$WORK/garbage.txt" "$module_row_2" "the unrecognised probe renders no module-frame anchor"
expect_absent "$WORK/garbage.txt" "$module_row_1" "the unrecognised probe renders no module-frame anchor"
expect_absent "$WORK/garbage.txt" "$intermediate_row_2" "the unrecognised probe renders no intermediate-frame anchor"
expect_absent "$WORK/garbage.txt" "$carets_row" "the unrecognised probe renders no assertion anchor"
expect_absent "$WORK/garbage.txt" "$assertion_row_2" "the unrecognised probe renders no assertion anchor"

# 4. A probe that could not run: the band falls back to 0 as well.
write_shim 'printf "%s\n" "2"' 'exit 1'
run_port
failed_status=$?
cp "$WORK/stderr.txt" "$WORK/failed.txt"
if [[ "$failed_status" -eq 1 ]]; then
	ok "the failed probe refuses the broken fixture"
else
	bad "the failed probe refuses the broken fixture (exit $failed_status)"
fi
expect_absent "$WORK/failed.txt" "$module_row_2" "the failed probe renders no module-frame anchor"
expect_absent "$WORK/failed.txt" "$module_row_1" "the failed probe renders no module-frame anchor"
expect_absent "$WORK/failed.txt" "$intermediate_row_2" "the failed probe renders no intermediate-frame anchor"
expect_absent "$WORK/failed.txt" "$carets_row" "the failed probe renders no assertion anchor"
expect_absent "$WORK/failed.txt" "$assertion_row_2" "the failed probe renders no assertion anchor"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
