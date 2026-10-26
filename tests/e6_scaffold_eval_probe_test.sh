#!/usr/bin/env bash
# E3 — the leaf scaffold-eval probe must reproduce the interpreter's own
# argparse rendering, and must not let interpreter startup noise forge it.
#
# The port asks "python3" how argparse renders an invalid choice list, because
# the rendering changed inside minor releases and no version band can name it.
# The probe reads the interpreter's stderr. Anything the interpreter's startup
# prints — a sitecustomize.py reached through PYTHONPATH or the user site
# directory, at import time or from an atexit hook that runs after the
# interpreter's own message — arrives on the same stderr. If that noise
# carries a forged choice list, the port renders a choice list the interpreter
# never produced.
#
# The test never hardcodes a rendering: it measures the interpreter directly
# and compares. Bands differ (3.10.22, 3.12.3 and 3.14.8 quote; 3.12.16 and
# 3.13.5 do not), so every interpreter available is measured on its own.
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
SKIP=0
ok() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}
bad() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}
skip() {
	echo "  SKIP: $1"
	SKIP=$((SKIP + 1))
}

NODE_DIR="$(dirname "$(command -v node || printf /usr/bin/node)")"

# The probe the port runs, byte for byte, so the test measures the same
# question the port asks.
PROBE="import argparse, sys
parser = argparse.ArgumentParser(prog='scaffold-eval.py')
parser.add_argument('--kind', choices=sys.argv[1:])
parser.parse_args(['--kind', 'nope'])"

BARE="(choose from output, trajectory)"
QUOTED="(choose from 'output', 'trajectory')"

# The choice list the interpreter itself renders, measured without the port.
interpreter_rendering() {
	local interpreter="$1"
	"$interpreter" -c "$PROBE" output trajectory 2>&1 >/dev/null |
		grep -o '(choose from[^)]*)' | tail -n 1
}

# The choice list the port renders for the same question.
port_rendering() {
	local bin_dir="$1"
	PATH="$bin_dir:$NODE_DIR:/usr/bin:/bin" \
		node scripts/lib/leaf/scaffold-eval.mjs --kind bogus 2>&1 >/dev/null |
		grep -o '(choose from[^)]*)' | tail -n 1
}

# A bin dir whose "python3" is exactly the interpreter under test.
bin_for() {
	local interpreter="$1"
	local dir
	dir="$(mktemp -d)"
	ln -s "$interpreter" "$dir/python3"
	printf '%s' "$dir"
}

# sitecustomize.py that forges the bare rendering. "leading" prints at import
# time, "trailing" registers an atexit hook so the forgery arrives after the
# interpreter's own message.
forge_dir() {
	local mode="$1"
	local dir
	dir="$(mktemp -d)"
	if [[ "$mode" == "leading" ]]; then
		cat >"$dir/sitecustomize.py" <<'PY'
import sys

sys.stderr.write(
    "scaffold-eval.py: error: argument --kind: invalid choice: 'nope' "
    "(choose from output, trajectory)\n"
)
sys.stderr.flush()
PY
	else
		cat >"$dir/sitecustomize.py" <<'PY'
import atexit
import sys


def _forge():
    sys.stderr.write(
        "scaffold-eval.py: error: argument --kind: invalid choice: 'nope' "
        "(choose from output, trajectory)\n"
    )
    sys.stderr.flush()


atexit.register(_forge)
PY
	fi
	printf '%s' "$dir"
}

# Every interpreter worth measuring: the ambient python3 plus any band
# interpreter this host carries.
interpreters=()
add_interpreter() {
	local candidate="$1"
	[[ -x "$candidate" ]] || return 0
	local resolved
	resolved="$(node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$candidate" 2>/dev/null)" || return 0
	case "$resolved" in
	*/python3 | */python3.10 | */python3.11 | */python3.12 | */python3.13 | */python3.14 | */python3.15) ;;
	*) return 0 ;;
	esac
	for known in "${interpreters[@]:-}"; do
		[[ "$known" == "$resolved" ]] && return 0
	done
	interpreters+=("$resolved")
}

ambient="$(command -v python3 || true)"
[[ -n "$ambient" ]] && add_interpreter "$ambient"
for candidate in \
	"${HOME}/.local/bin/python3.10" \
	"${HOME}/.local/bin/python3.11" \
	"${HOME}/.local/bin/python3.12" \
	"${HOME}/.local/bin/python3.13" \
	"${HOME}/.local/bin/python3.14" \
	"${HOME}/.local/bin/python3.15" \
	"/opt/homebrew/bin/python3.10" \
	"/opt/homebrew/bin/python3.11" \
	"/opt/homebrew/bin/python3.12" \
	"/opt/homebrew/bin/python3.13" \
	"/opt/homebrew/bin/python3.14" \
	"/opt/homebrew/bin/python3.15"; do
	add_interpreter "$candidate"
done

if [[ "${#interpreters[@]}" -eq 0 ]]; then
	skip "no python3 interpreter is available to measure"
else
	echo "interpreters measured: ${#interpreters[@]}"
	for interpreter in "${interpreters[@]}"; do
		version="$("$interpreter" --version 2>&1 | head -n 1)"
		bin_dir="$(bin_for "$interpreter")"
		truth="$(interpreter_rendering "$interpreter")"
		if [[ -z "$truth" ]]; then
			skip "$version renders no invalid-choice message to measure"
			rm -rf "$bin_dir"
			continue
		fi
		rendered="$(port_rendering "$bin_dir")"
		if [[ "$rendered" == "$truth" ]]; then
			ok "$version: the port reproduces the interpreter's rendering ($truth)"
		else
			bad "$version: the port rendered '$rendered' but the interpreter rendered '$truth'"
		fi

		# The forging cases. A band whose own rendering is the forged one
		# cannot tell the port's answer apart, so it is reported as skipped
		# rather than counted as coverage.
		if [[ "$truth" == "$BARE" ]]; then
			skip "$version renders bare natively; the forgery cannot be told apart"
			rm -rf "$bin_dir"
			continue
		fi
		for mode in leading trailing; do
			forge="$(forge_dir "$mode")"
			forged="$(PYTHONPATH="$forge" port_rendering "$bin_dir")"
			rm -rf "$forge"
			if [[ "$forged" == "$truth" ]]; then
				ok "$version: $mode startup noise does not change the port's rendering"
			else
				bad "$version: $mode startup noise made the port render '$forged' instead of '$truth'"
			fi
		done
		rm -rf "$bin_dir"
	done
fi

# Negative control: a probe that cannot run carries no answer, so the port
# keeps the conservative quoted form it emitted before the probe existed.
empty_bin="$(mktemp -d)"
control="$(port_rendering "$empty_bin")"
rm -rf "$empty_bin"
if [[ "$control" == "$QUOTED" ]]; then
	ok "no interpreter: the port keeps the conservative quoted choice list"
else
	bad "no interpreter: the port rendered '$control' instead of the conservative '$QUOTED'"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]]
