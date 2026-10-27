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
# The control is the isolation, not the read rule. The probe runs with -I (the
# PYTHON* environment variables and the user site directory are ignored) and
# with -S (the site module never runs, so the interpreter's own site-packages
# stays off sys.path). Together they mean no sitecustomize.py is imported from
# anywhere: not from PYTHONPATH, not from the user site directory, and not
# from the site-packages of the interpreter the probe happens to run under.
#
# The read rule is defence in depth. The answer is an argparse invalid-choice
# message, read whole, whose trailing token is one of the two renderings. A
# message that does not carry "invalid choice:" is not an answer, so noise
# carrying a bare choice list without it cannot be adopted; a message whose
# choice list is followed by anything else is truncated and is not an answer
# either. Empty output, a probe that could not run, and any other text keep
# the quoted form this port emitted before the probe existed.
#
# Because the isolation keeps a real sitecustomize.py from ever reaching the
# interpreter, the sitecustomize cases alone would leave the read rule
# unobserved. The shims below therefore stand in for python3 on PATH and drive
# the read rule directly. Each shim is a /bin/sh script, so this file embeds
# no python3 program of its own beyond the two sitecustomize fixtures.
#
# The test never hardcodes a rendering: it measures the interpreter directly
# and compares. Bands differ (3.10.22, 3.12.3 and 3.14.8 quote; 3.12.16 and
# 3.13.5 do not), so every interpreter available is measured on its own.
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
export PYTHONDONTWRITEBYTECODE=1
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

NODE_DIR="$(dirname "$(command -v node || printf /usr/bin/node)")"

# The probe the port runs, byte for byte, so the test measures the same
# question the port asks.
PROBE="import argparse, sys
parser = argparse.ArgumentParser(prog='scaffold-eval.py')
parser.add_argument('--kind', choices=sys.argv[1:])
parser.parse_args(['--kind', 'nope'])"

BARE="(choose from output, trajectory)"
QUOTED="(choose from 'output', 'trajectory')"

# The marker the forge carries, so the controls can tell the noise apart from
# the interpreter's own message.
FORGE_MARK="sitecustomize forge"

# The choice list the interpreter itself renders, measured without the port.
interpreter_rendering() {
	local interpreter="$1"
	"$interpreter" -c "$PROBE" output trajectory 2>&1 >/dev/null |
		grep -o '(choose from[^)]*)' | tail -n 1
}

# The choice list the port renders for the same question, under an exact PATH.
port_rendering_with_path() {
	local probe_path="$1"
	PATH="$probe_path" \
		node scripts/lib/leaf/scaffold-eval.mjs --kind bogus 2>&1 >/dev/null |
		grep -o '(choose from[^)]*)' | tail -n 1
}

# The same, with the PATH the per-interpreter cases use: the bin dir holding
# the interpreter under test comes first, so it wins over every other python3.
port_rendering() {
	local bin_dir="$1"
	port_rendering_with_path "$bin_dir:$NODE_DIR:/usr/bin:/bin"
}

# A bin dir whose "python3" is exactly the interpreter under test.
bin_for() {
	local interpreter="$1"
	local dir
	dir="$(mktemp -d)"
	ln -s "$interpreter" "$dir/python3"
	printf '%s' "$dir"
}

# A bin dir holding a /bin/sh script that stands in for python3.
SHIM_BIN="$WORK/shim-bin"
write_shim() {
	mkdir -p "$SHIM_BIN"
	cat >"$SHIM_BIN/python3"
	chmod +x "$SHIM_BIN/python3"
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
    "sitecustomize forge: scaffold-eval.py: error: argument --kind: "
    "invalid choice: 'nope' (choose from output, trajectory)\n"
)
sys.stderr.flush()
PY
	else
		cat >"$dir/sitecustomize.py" <<'PY'
import atexit
import sys


def _forge():
    sys.stderr.write(
        "sitecustomize forge: scaffold-eval.py: error: argument --kind: "
        "invalid choice: 'nope' (choose from output, trajectory)\n"
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
	"/opt/homebrew/bin/python3.15" \
	"/usr/bin/python3"; do
	add_interpreter "$candidate"
done

# The suite's subject is "the port reproduces the interpreter's own rendering".
# That cannot be established with zero interpreters, so an empty inventory is a
# failure, not a skip: a vacuous pass is what this gate exists to prevent.
if [[ "${#interpreters[@]}" -eq 0 ]]; then
	bad "no python3 interpreter is available to measure: the port's rendering cannot be compared with an interpreter's"
fi

# AC-16 INTERPRETER STABILITY SNAPSHOT, taken BEFORE any interpreter is
# executed. Each interpreter's resolved realpath and its file digest are
# recorded here and re-checked after the run; a changed realpath, or a
# changed digest, is a FAILURE and never a skip.
interp_paths=()
interp_digests=()
for interpreter in "${interpreters[@]:-}"; do
	interp_paths+=("$interpreter")
	interp_digests+=("$(shasum -a 256 "$interpreter" 2>/dev/null | cut -d' ' -f1)")
done

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

# The controls for the forging cases above. Without them they could pass
# vacuously on a host where the noise never reaches the interpreter at all.
# The first control shows the trailing forge really lands on stderr after the
# interpreter's own message when nothing isolates it; the second shows a
# pristine interpreter is not polluted. Both are measured on the ambient
# interpreter, without the isolation the port applies.
if [[ "${#interpreters[@]}" -gt 0 ]]; then
	control_interpreter="${interpreters[0]}"
	trailing_forge="$(forge_dir trailing)"
	control_polluted="$(PYTHONPATH="$trailing_forge" "$control_interpreter" -c "$PROBE" output trajectory 2>&1)"
	control_polluted_last="$(printf '%s\n' "$control_polluted" | grep -v '^[[:space:]]*$' | tail -n 1)"
	rm -rf "$trailing_forge"
	if [[ "$control_polluted_last" == *"$FORGE_MARK"* ]]; then
		ok "the trailing startup noise lands after the interpreter's own message"
	else
		bad "the trailing startup noise lands after the interpreter's own message (last line: $control_polluted_last)"
	fi
	control_clean="$(env -u PYTHONPATH "$control_interpreter" -c "$PROBE" output trajectory 2>&1)"
	control_clean_last="$(printf '%s\n' "$control_clean" | grep -v '^[[:space:]]*$' | tail -n 1)"
	if [[ "$control_clean_last" != *"$FORGE_MARK"* ]]; then
		ok "a pristine interpreter is not polluted"
	else
		bad "a pristine interpreter is not polluted (last line: $control_clean_last)"
	fi
fi

# The interpreter's own site-packages is the one vector isolation mode alone
# does not close. -I drops the PYTHON* environment and the user site directory,
# but the interpreter's own site-packages stays on sys.path, so a
# sitecustomize.py planted there is imported even in isolated mode. -S is what
# removes it: with the site module disabled, site-packages never reaches
# sys.path and no sitecustomize.py can be imported from it.
#
# The mechanism, measured on every interpreter: under the flags the port uses
# no site-packages entry is left on sys.path, and under -I alone there is one.
for interpreter in "${interpreters[@]}"; do
	version="$("$interpreter" --version 2>&1 | head -n 1)"
	isolated="$("$interpreter" -I -c 'import sys; print("YES" if any("site-packages" in p for p in sys.path) else "NO")' 2>&1 | tail -n 1)"
	port_flags="$("$interpreter" -I -S -c 'import sys; print("YES" if any("site-packages" in p for p in sys.path) else "NO")' 2>&1 | tail -n 1)"
	if [[ "$port_flags" == "NO" ]]; then
		ok "$version: the port's flags leave no site-packages importable"
	else
		bad "$version: the port's flags leave no site-packages importable (got: $port_flags)"
	fi
	if [[ "$isolated" == "YES" ]]; then
		ok "$version: isolated mode alone leaves the interpreter's own site-packages importable"
	else
		skip "$version: carries no site-packages, so isolated mode alone has nothing to leave open"
	fi
done

# End to end, on the one vector isolation mode alone leaves open: a virtual
# environment gives the interpreter a site-packages of its own, and a
# sitecustomize.py planted there is imported even in isolated mode. The port
# must still render the interpreter's own answer.
venv_bin=""
for candidate in /usr/bin/python3 "${interpreters[@]:-}"; do
	[[ -x "$candidate" ]] || continue
	truth="$(interpreter_rendering "$candidate")"
	[[ "$truth" == "$QUOTED" ]] || continue
	venv="$WORK/venv"
	rm -rf "$venv"
	"$candidate" -m venv --without-pip "$venv" >/dev/null 2>&1 || continue
	site_packages="$(ls -d "$venv"/lib/python*/site-packages 2>/dev/null | head -n 1)"
	[[ -n "$site_packages" ]] || continue
	cat >"$site_packages/sitecustomize.py" <<'PY'
import atexit
import sys


def _forge():
    sys.stderr.write(
        "sitecustomize forge: scaffold-eval.py: error: argument --kind: "
        "invalid choice: 'nope' (choose from output, trajectory)\n"
    )
    sys.stderr.flush()


atexit.register(_forge)
PY
	# The control: the planted forge really is imported in isolated mode.
	if ! PATH="$venv/bin:$NODE_DIR:/usr/bin:/bin" "$venv/bin/python3" -I -c "print('x')" 2>&1 >/dev/null | grep -q "$FORGE_MARK"; then
		continue
	fi
	venv_bin="$venv/bin"
	break
done

if [[ -n "$venv_bin" ]]; then
	ok "a virtual environment's own site-packages is importable even in isolated mode"
	rendered="$(port_rendering_with_path "$venv_bin:$NODE_DIR:/usr/bin:/bin")"
	if [[ "$rendered" == "$QUOTED" ]]; then
		ok "a sitecustomize.py in the interpreter's own site-packages does not forge the port's rendering"
	else
		bad "a sitecustomize.py in the interpreter's own site-packages does not forge the port's rendering (rendered: '$rendered')"
	fi
else
	skip "no virtual environment on this host exposes a site-packages the interpreter imports"
fi

# The read rule, driven directly. The isolation keeps a real sitecustomize.py
# from reaching the interpreter, so without these cases the read rule would
# never be observed and could be broken without any assertion failing.

# 1. Noise that carries a bare choice list without an invalid-choice message
#    is not an answer: a read that accepted any occurrence of the bare
#    rendering would adopt the forgery here.
write_shim <<'SH'
#!/bin/sh
printf '%s\n' '(choose from output, trajectory)' >&2
exit 0
SH
read_rule_noise="$(PATH="$SHIM_BIN:$NODE_DIR:/usr/bin:/bin" "$SHIM_BIN/python3" 2>&1 >/dev/null)"
if [[ "$read_rule_noise" == *"$BARE"* ]]; then
	ok "the read-rule noise really carries the bare choice list"
else
	bad "the read-rule noise really carries the bare choice list (stderr: $read_rule_noise)"
fi
rendered="$(port_rendering "$SHIM_BIN")"
if [[ "$rendered" == "$QUOTED" ]]; then
	ok "a choice list without an invalid-choice message is not an answer"
else
	bad "a choice list without an invalid-choice message is not an answer (rendered: '$rendered')"
fi

# 2. A forged bare rendering ahead of the interpreter's own quoted rendering:
#    the last invalid-choice message is the answer, so the port takes the
#    quoted one and not the forged bare one.
write_shim <<'SH'
#!/bin/sh
printf '%s\n' "scaffold-eval.py: error: argument --kind: invalid choice: 'nope' (choose from output, trajectory)" >&2
printf '%s\n' "scaffold-eval.py: error: argument --kind: invalid choice: 'nope' (choose from 'output', 'trajectory')" >&2
exit 2
SH
read_rule_ahead="$(PATH="$SHIM_BIN:$NODE_DIR:/usr/bin:/bin" "$SHIM_BIN/python3" 2>&1 >/dev/null)"
if [[ "$read_rule_ahead" == *"$BARE"* && "$read_rule_ahead" == *"$QUOTED"* ]]; then
	ok "the read-rule stderr really carries both renderings"
else
	bad "the read-rule stderr really carries both renderings (stderr: $read_rule_ahead)"
fi
rendered="$(port_rendering "$SHIM_BIN")"
if [[ "$rendered" == "$QUOTED" ]]; then
	ok "the last invalid-choice message wins over a forged bare rendering ahead of it"
else
	bad "the last invalid-choice message wins over a forged bare rendering ahead of it (rendered: '$rendered')"
fi

# 3. A message whose choice list is followed by anything else is truncated,
#    and a truncated message is not an answer.
write_shim <<'SH'
#!/bin/sh
printf '%s\n' "scaffold-eval.py: error: argument --kind: invalid choice: 'nope' (choose from output, trajectory) and more" >&2
exit 2
SH
rendered="$(port_rendering "$SHIM_BIN")"
if [[ "$rendered" == "$QUOTED" ]]; then
	ok "a truncated invalid-choice message is not an answer"
else
	bad "a truncated invalid-choice message is not an answer (rendered: '$rendered')"
fi

# Negative control: a probe that cannot run carries no answer, so the port
# keeps the conservative quoted form it emitted before the probe existed. The
# PATH carries node and nothing else, and the case asserts that no python3 is
# reachable on it before it asserts the rendering, so the control cannot pass
# by finding some other interpreter.
node_only="$WORK/node-only"
mkdir -p "$node_only"
ln -s "$(command -v node)" "$node_only/node"
if PATH="$node_only" command -v python3 >/dev/null 2>&1; then
	bad "no interpreter: the control PATH resolves no python3"
else
	ok "no interpreter: the control PATH resolves no python3"
fi
control="$(port_rendering_with_path "$node_only")"
if [[ "$control" == "$QUOTED" ]]; then
	ok "no interpreter: the port keeps the conservative quoted choice list"
else
	bad "no interpreter: the port rendered '$control' instead of the conservative '$QUOTED'"
fi

# ---------------------------------------------------------------------------
# The PACKAGED public entrypoint, and the argv each shipping site actually
# spawned the probe with.
#
# The packaged copy is reached through the live public Python shim, not by
# importing its .mjs directly. The shim preserves PATH for its Node child, so
# a private PATH wrapper shadows the CHILD's python3 probe and not the shim's
# own interpreter; the shim is invoked with the explicit qualified interpreter
# so it cannot be re-exec'd into something else.
packaged_rendering_with_path() {
	local probe_path="$1"
	local interpreter="$2"
	PATH="$probe_path" \
		"$interpreter" 04-validate-handoff/eval-a-skill/scaffold-eval.py --kind bogus 2>&1 >/dev/null |
		grep -o '(choose from[^)]*)' | tail -n 1
}

# True when the recorded argv (one argument per line) carries FLAG before the
# -c that starts the probe program. The flags must PRECEDE -c, not merely be
# present somewhere in the recorded arguments.
argv_has_flag_before_c() {
	local log="$1" flag="$2"
	local seen_c=0 line
	while IFS= read -r line; do
		[[ "$line" == "-c" ]] && { seen_c=1; continue; }
		[[ "$seen_c" -eq 0 && "$line" == "$flag" ]] && return 0
	done <"$log"
	return 1
}

# A private bin dir whose "python3" RECORDS the argv it received, one argument
# per line, and then forwards it unchanged to the absolute qualified interpreter.
# It adds no flags, synthesises no answer and never re-invokes a PATH-resolved
# python3, so what is recorded is the port's own invocation.
recorder_bin() {
	local interpreter="$1"
	local dir
	dir="$(mktemp -d)"
	cat >"$dir/python3" <<SH
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a" >>"$dir/argv.log"; done
exec "$interpreter" "\$@"
SH
	chmod +x "$dir/python3"
	printf '%s' "$dir"
}

if [[ -n "$venv_bin" ]]; then
	rendered="$(packaged_rendering_with_path "$venv_bin:$NODE_DIR:/usr/bin:/bin" "$venv_bin/python3")"
	if [[ "$rendered" == "$QUOTED" ]]; then
		ok "packaged public entrypoint: a sitecustomize.py in the interpreter's own site-packages does not forge the port's rendering"
	else
		bad "packaged public entrypoint: a sitecustomize.py in the interpreter's own site-packages forged the port's rendering (rendered: '$rendered')"
	fi
fi

qualified="${interpreters[0]:-}"
if [[ -n "$qualified" ]]; then
	canon_rec="$(recorder_bin "$qualified")"
	port_rendering_with_path "$canon_rec:$NODE_DIR:/usr/bin:/bin" >/dev/null
	if [[ -f "$canon_rec/argv.log" ]] && argv_has_flag_before_c "$canon_rec/argv.log" '-I' && argv_has_flag_before_c "$canon_rec/argv.log" '-S'; then
		ok "canonical site: the probe the port spawned received -I and -S"
	else
		bad "canonical site: the probe the port spawned did not receive -I and -S (argv: $(tr '\n' ' ' <"$canon_rec/argv.log" 2>/dev/null))"
	fi

	pack_rec="$(recorder_bin "$qualified")"
	packaged_rendering_with_path "$pack_rec:$NODE_DIR:/usr/bin:/bin" "$qualified" >/dev/null
	if [[ -f "$pack_rec/argv.log" ]] && argv_has_flag_before_c "$pack_rec/argv.log" '-I' && argv_has_flag_before_c "$pack_rec/argv.log" '-S'; then
		ok "packaged site: the probe the port spawned received -I and -S"
	else
		bad "packaged site: the probe the port spawned did not receive -I and -S (argv: $(tr '\n' ' ' <"$pack_rec/argv.log" 2>/dev/null))"
	fi
fi

# ---------------------------------------------------------------------------
# AC-15 INTERPRETER AUTHENTICITY. Every interpreter the suite measures must be
# a genuine CPython BINARY: the resolved file's first bytes must be a Mach-O
# image (cf fa ed fe, fe ed fa cf, OR THE UNIVERSAL ca fe ba be), an ELF image
# (7f 45 4c 46) or a Windows PE image (4d 5a) - NEVER a #! script - and it
# must report sys.implementation.name == "cpython". A substituted interpreter
# therefore FAILS THE SUITE BY NAME instead of agreeing with the port on a
# forged rendering.
#
# DISCLOSED LIMIT: these checks assert the SHAPE AND IDENTITY of the executed
# file, NOT its provenance. A substituted native executable can pass them.
echo ""
echo "interpreter authenticity"
for interpreter in "${interpreters[@]:-}"; do
	magic="$(head -c 4 "$interpreter" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
	first2="$(head -c 2 "$interpreter" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
	if [[ "$first2" == "2321" ]]; then
		bad "interpreter authenticity: $interpreter is a #! script, not a binary image"
		continue
	fi
	case "$magic" in
	cffaedfe | feedfacf | cafebabe | 7f454c46 | 4d5a*) ;;
	*)
		bad "interpreter authenticity: $interpreter is not a binary image (first bytes: $magic)"
		continue
		;;
	esac
	impl="$("$interpreter" -c 'import sys; print(sys.implementation.name)' 2>/dev/null | tr -d '[:space:]')"
	if [[ "$impl" != "cpython" ]]; then
		bad "interpreter authenticity: $interpreter reports sys.implementation.name '$impl', not 'cpython'"
		continue
	fi
	ok "interpreter authenticity: $interpreter is a genuine CPython binary"
done

# ---------------------------------------------------------------------------
# AC-16 INTERPRETER STABILITY, re-checked AFTER the run. A changed resolved
# realpath, or a changed file digest, is a FAILURE - not a skip: the
# measurement is only valid for the file that was measured.
echo ""
echo "interpreter stability"
index=0
while [[ "$index" -lt "${#interp_paths[@]}" ]]; do
	before_path="${interp_paths[$index]}"
	before_digest="${interp_digests[$index]}"
	now_path="$(node -e 'process.stdout.write(require("fs").realpathSync(process.argv[1]))' "$before_path" 2>/dev/null || printf '%s' "$before_path")"
	now_digest="$(shasum -a 256 "$now_path" 2>/dev/null | cut -d' ' -f1)"
	if [[ "$now_path" != "$before_path" ]]; then
		bad "interpreter stability: $before_path now resolves to $now_path"
	elif [[ "$now_digest" != "$before_digest" ]]; then
		bad "interpreter stability: $before_path changed digest during the run"
	else
		ok "interpreter stability: $before_path is unchanged"
	fi
	index=$((index + 1))
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]]
