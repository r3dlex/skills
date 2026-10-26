#!/usr/bin/env bash
#
# Regression test for the CPython traceback anchor band probe in
# scripts/lib/leaf/validate-cascade-fixtures.mjs.
#
# The port asks the running interpreter which PEP 657 anchor band it renders:
# nothing below 3.11, "^" only on 3.11-3.12, and from 3.13 the surrounding
# expression is marked with "~" plus an anchor row on every frame. The band is
# a property of the interpreter, so the port has to name the band the
# interpreter actually renders: a wrong band is a parity divergence against
# the reference anchor running the same interpreter.
#
# The probe's stdout is not guaranteed to carry the band token alone. Noise can
# arrive BEFORE the token - a sitecustomize.py that prints at import time - or
# AFTER it - a sitecustomize.py that registers an atexit print, which runs once
# the program itself has already printed its token. Reading the LAST non-empty
# line of the probe output survives the first shape and is destroyed by the
# second: the token is no longer the last line, the band is lost, and the port
# falls back to the pre-3.11 rendering.
#
# The port therefore runs the probe in ISOLATED mode (-I). Isolated mode
# ignores the PYTHON* environment variables and the user site directory, and
# from 3.11 on it also drops the script directory from sys.path, so a
# sitecustomize.py reached through any of them is never loaded and the probe's
# stdout carries the band token alone. The band itself depends only on
# sys.version_info, so isolation cannot change the correct band.
#
# The port still reads the verdict off the LAST non-empty line of the probe
# output and accepts it only when it is exactly one of the three known bands.
# A token with trailing whitespace still names its band, while an
# unrecognised token, a truncated token, an empty answer and a probe that
# could not run all fall back to band 0, the pre-3.11 rendering this port
# emitted before the probe existed.
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

# An assertion with an empty needle asserts nothing at all, so it is a defect
# in the test rather than a pass. Every call site below names a concrete row.
expect_present() {
	local file="$1" needle="$2" label="$3"
	if [[ -z "$needle" ]]; then
		bad "$label (vacuous assertion: the needle is empty)"
		return
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
		bad "$label (vacuous assertion: the needle is empty)"
		return
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
ok "the interpreter renders anchor band $band ($version_line)"
export EXPECTED_BAND="$band"

# The anchor rows the port emits, byte for byte as the port spells them.
module_row_2="             ~~~~^^"
module_row_1="             ^^^^^^"
intermediate_row_2="    ~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^"
assertion_row_2="           ~~~~~~~~~~~~~~~~~~^^"
carets_row="           ^^^^^^^^^^^^^^^^^^^^"

# The rows the port must render for the band this interpreter renders, and the
# rows it must not render. Every branch names concrete rows, so no assertion
# is ever vacuous and no band silently skips one.
expect_band_rendering() {
	local file="$1" label="$2"
	case "$band" in
	2)
		expect_present "$file" "$module_row_2" "$label renders the band 2 module-frame anchor"
		expect_present "$file" "$intermediate_row_2" "$label renders the band 2 intermediate-frame anchor"
		expect_present "$file" "$assertion_row_2" "$label renders the band 2 assertion anchor"
		expect_absent "$file" "$module_row_1" "$label renders no band 1 module-frame anchor"
		expect_absent "$file" "$carets_row" "$label renders no caret-only assertion anchor"
		;;
	1)
		expect_present "$file" "$module_row_1" "$label renders the band 1 module-frame anchor"
		expect_present "$file" "$carets_row" "$label renders the band 1 assertion anchor"
		expect_absent "$file" "$module_row_2" "$label renders no band 2 module-frame anchor"
		expect_absent "$file" "$intermediate_row_2" "$label renders no band 2 intermediate-frame anchor"
		expect_absent "$file" "$assertion_row_2" "$label renders no band 2 assertion anchor"
		;;
	*)
		expect_absent "$file" "$module_row_1" "$label renders no band 1 module-frame anchor"
		expect_absent "$file" "$module_row_2" "$label renders no band 2 module-frame anchor"
		expect_absent "$file" "$intermediate_row_2" "$label renders no band 2 intermediate-frame anchor"
		expect_absent "$file" "$carets_row" "$label renders no assertion anchor"
		expect_absent "$file" "$assertion_row_2" "$label renders no band 2 assertion anchor"
		;;
	esac
}

# The band 0 fallback renders no anchor row at all.
expect_no_anchor_rows() {
	local file="$1" label="$2"
	expect_absent "$file" "$module_row_1" "$label renders no band 1 module-frame anchor"
	expect_absent "$file" "$module_row_2" "$label renders no band 2 module-frame anchor"
	expect_absent "$file" "$intermediate_row_2" "$label renders no intermediate-frame anchor"
	expect_absent "$file" "$carets_row" "$label renders no assertion anchor"
	expect_absent "$file" "$assertion_row_2" "$label renders no band 2 assertion anchor"
}

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
	if [[ -n "${PROBE_PYTHONPATH:-}" ]]; then
		PYTHONPATH="$PROBE_PYTHONPATH" PATH="$BIN:$PATH" PORT_MODULE="$REPO_ROOT/$PORT" PORT_ROOT="$ROOT" \
			node "$WORK/driver.mjs" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt"
	else
		PATH="$BIN:$PATH" PORT_MODULE="$REPO_ROOT/$PORT" PORT_ROOT="$ROOT" \
			node "$WORK/driver.mjs" >"$WORK/stdout.txt" 2>"$WORK/stderr.txt"
	fi
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
expect_band_rendering "$WORK/clean.txt" "the pristine probe"

# 2. The same interpreter with stdout pollution ahead of the token: the probe's
#    answer is no longer the only thing on stdout.
write_shim 'printf "%s\n" "sitecustomize noise"' 'exec "$REAL_PYTHON" "$@"'
run_port
noisy_status=$?
cp "$WORK/stderr.txt" "$WORK/noisy.txt"
if [[ "$noisy_status" -eq 1 ]]; then
	ok "the polluted probe refuses the broken fixture"
else
	bad "the polluted probe refuses the broken fixture (exit $noisy_status)"
fi
expect_band_rendering "$WORK/noisy.txt" "the polluted probe"
if cmp -s "$WORK/clean.txt" "$WORK/noisy.txt"; then
	ok "stdout pollution does not change the rendered traceback"
else
	bad "stdout pollution does not change the rendered traceback"
fi

# 3. A sitecustomize.py that registers an atexit print. The interpreter loads
#    it at startup and the print runs when the interpreter exits, so the noise
#    lands AFTER the program has already printed its token. This is the shape
#    that destroys a "last non-empty line" read: the token is no longer the
#    last line.
POLLUTION="teardown chatter"
SITE="$WORK/site"
mkdir -p "$SITE"
printf '%s\n' 'import atexit' 'atexit.register(lambda: print("teardown chatter"))' >"$SITE/sitecustomize.py"

# The control: with PYTHONPATH pointing at the sitecustomize.py the
# interpreter really does load it and really does print the noise after the
# program's own output. Without it the interpreter never sees the file. These
# two checks keep the case below from passing vacuously on a host where the
# mechanism does not hold.
control_polluted="$(PYTHONPATH="$SITE" PATH="$BIN:$PATH" "$PY_NAME" -m this 2>&1)"
control_polluted_last="$(printf '%s\n' "$control_polluted" | grep -v '^[[:space:]]*$' | tail -1)"
control_polluted_count="$(printf '%s\n' "$control_polluted" | grep -c '[^[:space:]]')"
control_clean="$(PATH="$BIN:$PATH" "$PY_NAME" -m this 2>&1)"
control_clean_last="$(printf '%s\n' "$control_clean" | grep -v '^[[:space:]]*$' | tail -1)"
if [[ "$control_polluted_last" == "$POLLUTION" ]]; then
	ok "the sitecustomize pollution lands after the program output"
else
	bad "the sitecustomize pollution lands after the program output (last line: $control_polluted_last)"
fi
if [[ "$control_polluted_count" -gt 1 ]]; then
	ok "the sitecustomize pollution follows the program output"
else
	bad "the sitecustomize pollution follows the program output (lines: $control_polluted_count)"
fi
if [[ "$control_clean_last" != "$POLLUTION" ]]; then
	ok "a pristine interpreter is not polluted"
else
	bad "a pristine interpreter is not polluted"
fi

write_shim 'exec "$REAL_PYTHON" "$@"'
PROBE_PYTHONPATH="$SITE"
run_port
trailing_status=$?
PROBE_PYTHONPATH=""
cp "$WORK/stderr.txt" "$WORK/trailing.txt"
if [[ "$trailing_status" -eq 1 ]]; then
	ok "the trailing-polluted probe refuses the broken fixture"
else
	bad "the trailing-polluted probe refuses the broken fixture (exit $trailing_status)"
fi
expect_band_rendering "$WORK/trailing.txt" "the trailing-polluted probe"
if cmp -s "$WORK/clean.txt" "$WORK/trailing.txt"; then
	ok "trailing stdout pollution does not change the rendered traceback"
else
	bad "trailing stdout pollution does not change the rendered traceback"
fi

# 4. A band token with trailing whitespace: the token still names its band.
write_shim 'printf "%s   \n" "$EXPECTED_BAND"' 'exit 0'
run_port
spaced_status=$?
cp "$WORK/stderr.txt" "$WORK/spaced.txt"
if [[ "$spaced_status" -eq 1 ]]; then
	ok "the spaced-token probe refuses the broken fixture"
else
	bad "the spaced-token probe refuses the broken fixture (exit $spaced_status)"
fi
expect_band_rendering "$WORK/spaced.txt" "the spaced-token probe"

# 5. A token that is not a band: the band falls back to 0.
for bad_token in "02" "x2" "2x" "20" ""; do
	export BAD_TOKEN="$bad_token"
	write_shim 'printf "%s\n" "$BAD_TOKEN"' 'exit 0'
	run_port
	garbage_status=$?
	cp "$WORK/stderr.txt" "$WORK/garbage.txt"
	if [[ "$garbage_status" -eq 1 ]]; then
		ok "the unrecognised token '$bad_token' refuses the broken fixture"
	else
		bad "the unrecognised token '$bad_token' refuses the broken fixture (exit $garbage_status)"
	fi
	expect_no_anchor_rows "$WORK/garbage.txt" "the unrecognised token '$bad_token'"
done
unset BAD_TOKEN

# 6. A probe whose answer is unrecognisable: the band falls back to 0.
write_shim 'printf "%s\n" "sitecustomize noise"' 'exit 0'
run_port
garbage_status=$?
cp "$WORK/stderr.txt" "$WORK/garbage.txt"
if [[ "$garbage_status" -eq 1 ]]; then
	ok "the unrecognised probe refuses the broken fixture"
else
	bad "the unrecognised probe refuses the broken fixture (exit $garbage_status)"
fi
expect_no_anchor_rows "$WORK/garbage.txt" "the unrecognised probe"

# 7. A probe that could not run: the band falls back to 0 as well.
write_shim 'printf "%s\n" "2"' 'exit 1'
run_port
failed_status=$?
cp "$WORK/stderr.txt" "$WORK/failed.txt"
if [[ "$failed_status" -eq 1 ]]; then
	ok "the failed probe refuses the broken fixture"
else
	bad "the failed probe refuses the broken fixture (exit $failed_status)"
fi
expect_no_anchor_rows "$WORK/failed.txt" "the failed probe"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
