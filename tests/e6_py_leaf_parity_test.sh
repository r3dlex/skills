#!/usr/bin/env bash
# Differential proof for e6-sk-01-py-leaf. The reference is the publication
# commit, checked by blob id and sha256, never the working tree.
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
export PYTHONDONTWRITEBYTECODE=1
unset COLUMNS || true
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
ANCHOR="6255da27afeee8c2e9f3582793e74fbc5ff68bf3"
RED_ONLY=""
if [[ "${1:-}" == "--red-leg" ]]; then
	RED_ONLY="${2:-}"
fi
WT="$(mktemp -d)"
git worktree add --detach "$WT" "$ANCHOR" >/dev/null
cleanup() {
	if [[ -n "${POLLUTE_BAK:-}" && -f "${POLLUTE_BAK}" && -n "${POLLUTE_REL:-}" ]]; then
		cp "$POLLUTE_BAK" "$REPO_ROOT/$POLLUTE_REL"
	fi
	if [[ -n "${GOLDEN_GUARD:-}" && -f "${GOLDEN_GUARD}" ]]; then
		cp "$GOLDEN_GUARD" "$REPO_ROOT/tests/fixtures/host-default-golden.json"
	fi
	git worktree remove --force "$WT" >/dev/null 2>&1 || true
	rm -rf "$WT"
}
trap cleanup EXIT

pin() {
	local path="$1" blob sha got
	blob="$(git rev-parse "$ANCHOR:$path")"
	sha="$(git cat-file blob "$blob" | shasum -a 256 | awk '{print $1}')"
	got="$(shasum -a 256 "$WT/$path" | awk '{print $1}')"
	if [[ "$got" != "$sha" ]]; then
		bad "anchor bytes $path"
		return 1
	fi
	if ! node scripts/lib/leaf-parity.mjs pin "$ANCHOR" "$path" "$blob" "$sha" >/dev/null; then
		bad "anchor materialize $path"
		return 1
	fi
	return 0
}

if node scripts/lib/leaf-parity.mjs pin "$ANCHOR" scripts/catalog-query.py "$(git rev-parse "$ANCHOR:scripts/catalog-query.py")" "$(printf '%064d' 0)" >/dev/null; then
	bad "bad sha256 is refused"
else
	ok "bad sha256 is refused"
fi

manifest_tree() {
	local root="$1" out="$2"
	if [[ ! -d "$root" ]]; then
		: >"$out"
		return
	fi
	(
		cd "$root" || exit 1
		find . \( -type f -o -type l \) ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path '*/Library/*' ! -path '*/.npm/*' ! -path '*/.cache/*' | sort | while IFS= read -r name; do
			if [[ -L "$name" ]]; then
				printf 'link %s -> %s\n' "$name" "$(readlink "$name")"
			else
				shasum -a 256 "$name"
			fi
		done
	) >"$out"
}

tree_same() {
	local left="$1" right="$2" lmanifest rmanifest
	lmanifest="$(mktemp)"
	rmanifest="$(mktemp)"
	manifest_tree "$left" "$lmanifest"
	manifest_tree "$right" "$rmanifest"
	cmp -s "$lmanifest" "$rmanifest"
	local rc=$?
	rm -f "$lmanifest" "$rmanifest"
	return "$rc"
}

probe_symlink_oracle() {
	local left right
	left="$(mktemp -d)"
	right="$(mktemp -d)"
	printf 'same\n' >"$left/file"
	printf 'same\n' >"$right/file"
	ln -s file "$left/link"
	ln -s file "$right/link"
	if tree_same "$left" "$right"; then
		ok "matching symlink targets compare equal"
	else
		bad "matching symlink targets compare equal"
	fi
	rm "$right/link"
	ln -s other "$right/link"
	if tree_same "$left" "$right"; then
		bad "symlink target divergence is invisible"
	else
		ok "symlink target divergence is detected"
	fi
	rm "$right/link"
	if tree_same "$left" "$right"; then
		bad "missing symlink is invisible"
	else
		ok "missing symlink is detected"
	fi
	rm -rf "$left" "$right"
}
probe_symlink_oracle

refused() {
	local err="$1"
	grep -q 'node_unavailable\|node_version_unsupported' "$err"
}

invoke_sh() {
	local _argv0="$1" script="$2" dir base
	shift 2
	dir="$(dirname "$script")"
	base="$(basename "$script")"
	(cd "$dir" && bash "./$base" "$@")
}

# compare_pair label left_cmd...  --- right_cmd... with watches in $LWATCH $RWATCH
same_outputs() {
	local lrc="$1" rrc="$2" lout="$3" rout="$4" lerr="$5" rerr="$6" lwatch="$7" rwatch="$8"
	[[ "$lrc" -eq "$rrc" ]] && cmp -s "$lout" "$rout" && cmp -s "$lerr" "$rerr" && tree_same "$lwatch" "$rwatch"
}

judge() {
	local label="$1" lrc="$2" rrc="$3" lout="$4" rout="$5" lerr="$6" rerr="$7" lwatch="$8" rwatch="$9" expect="${10:-}"
	if same_outputs "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"; then
		if [[ "$expect" == expect-diverge ]]; then
			bad "$label comparator accepted the candidate"
			return 1
		fi
		if refused "$rerr" || refused "$rout"; then
			bad "$label ended in a node refusal"
			return 1
		fi
		ok "$label"
		return 0
	fi
	if [[ "$expect" == expect-diverge ]]; then
		if refused "$rerr" || refused "$rout"; then
			bad "$label tool-unavailable is not a divergence"
			return 1
		fi
		ok "$label comparator failed"
		return 0
	fi
	bad "$label legacy=$lrc ts=$rrc"
	echo "    stdout:" >&2
	diff -u "$lout" "$rout" | head -20 >&2 || true
	echo "    stderr:" >&2
	diff -u "$lerr" "$rerr" | head -20 >&2 || true
	return 1
}

run_pair() {
	local label="$1" lwatch="$2" rwatch="$3"
	shift 3
	local lout rout lerr rerr lrc rrc
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	mkdir -p "$lwatch" "$rwatch"
	set +e
	HOME="$lwatch" "${LEFT[@]}" >"$lout" 2>"$lerr"
	lrc=$?
	HOME="$rwatch" "${RIGHT[@]}" >"$rout" 2>"$rerr"
	rrc=$?
	set +e
	judge "$label" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}

py_case() {
	local label="$1" path="$2"
	shift 2
	pin "$path" || return
	local lwatch rwatch
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	LEFT=(python3 "$WT/$path" "$@")
	RIGHT=(python3 "$REPO_ROOT/$path" "$@")
	run_pair "$label" "$lwatch" "$rwatch"
}

sh_case() {
	local label="$1" path="$2" argv0="$3"
	shift 3
	pin "$path" || return
	local lwatch rwatch
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	LEFT=(invoke_sh "$argv0" "$WT/$path" "$@")
	RIGHT=(invoke_sh "$argv0" "$REPO_ROOT/$path" "$@")
	run_pair "$label" "$lwatch" "$rwatch"
}

env_py() {
	local label="$1" path="$2"
	shift 2
	pin "$path" || return
	local lwatch rwatch
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	LEFT=(env NODE_OPTIONS=--throw-deprecation python3 "$WT/$path" "$@")
	RIGHT=(env NODE_OPTIONS=--throw-deprecation python3 "$REPO_ROOT/$path" "$@")
	run_pair "$label" "$lwatch" "$rwatch"
}

env_sh() {
	local label="$1" path="$2" argv0="$3"
	shift 3
	pin "$path" || return
	local lwatch rwatch
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	LEFT=(invoke_sh "$argv0" "$WT/$path" "$@")
	RIGHT=(invoke_sh "$argv0" "$REPO_ROOT/$path" "$@")
	NODE_OPTIONS=--throw-deprecation run_pair "$label" "$lwatch" "$rwatch"
	unset NODE_OPTIONS
}

run_legacy_tool() {
	local path="$1" watch="$2" out="$3" err="$4"
	shift 4
	if [[ "$path" == *.py ]]; then
		HOME="$watch" python3 "$WT/$path" "$@" >"$out" 2>"$err"
	else
		HOME="$watch" invoke_sh "parity-argv0/$(basename "$path")" "$WT/$path" "$@" >"$out" 2>"$err"
	fi
}

run_ts_candidate() {
	local path="$1" watch="$2" out="$3" err="$4"
	shift 4
	local fix="$REPO_ROOT/tests/fixtures/e6-py-leaf"
	case "$path" in
	scripts/catalog.py)
		HOME="$watch" node "$fix/catalog_port.mjs" "$REPO_ROOT" >"$out" 2>"$err"
		;;
	scripts/traceability_schema.py)
		HOME="$watch" node "$fix/trace_port.mjs" '{"schema_version":"1.1","nodes":[],"edges":[]}' >"$out" 2>"$err"
		;;
	scripts/validate_skill_frontmatter.py)
		HOME="$watch" node "$fix/frontmatter_port.mjs" "$REPO_ROOT/03-configure-generate/ai-catapult-init/SKILL.md" >"$out" 2>"$err"
		;;
	*.py)
		HOME="$watch" python3 "$REPO_ROOT/$path" "$@" >"$out" 2>"$err"
		;;
	*)
		HOME="$watch" invoke_sh "parity-argv0/$(basename "$path")" "$REPO_ROOT/$path" "$@" >"$out" 2>"$err"
		;;
	esac
}

red_leg() {
	local label="$1" path="$2"
	pin "$path" || return
	local lwatch rwatch lout rout lerr rerr lrc rrc seeded repo_l repo_r
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	repo_l=""
	repo_r=""
	# install-copilot with no args writes beside the catalog root. Bound both
	# runs to a directory inside the watch so the candidate still runs.
	if [[ "$path" == scripts/install-copilot.sh ]]; then
		repo_l="$lwatch/repo"
		repo_r="$rwatch/repo"
		mkdir -p "$repo_l" "$repo_r"
	fi
	set +e
	if [[ -n "$repo_l" ]]; then
		run_legacy_tool "$path" "$lwatch" "$lout" "$lerr" --repo "$repo_l"
	else
		run_legacy_tool "$path" "$lwatch" "$lout" "$lerr"
	fi
	lrc=$?
	if [[ -n "$repo_r" ]]; then
		run_ts_candidate "$path" "$rwatch" "$rout" "$rerr" --repo "$repo_r"
	else
		run_ts_candidate "$path" "$rwatch" "$rout" "$rerr"
	fi
	rrc=$?
	set +e
	if [[ "$rrc" -eq 9 ]]; then
		bad "$label red-leg fabricated status 9"
		rm -rf "$lwatch" "$rwatch"
		rm -f "$lout" "$rout" "$lerr" "$rerr"
		return
	fi
	seeded=0
	if same_outputs "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"; then
		printf 'x' >>"$rout"
		seeded=1
	fi
	judge "$label red-leg status=$rrc seeded=$seeded" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch" expect-diverge
	rm -rf "$lwatch" "$rwatch"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}

if [[ -n "$RED_ONLY" ]]; then
	red_leg "$RED_ONLY" "$RED_ONLY"
	echo ""
	echo "Results: PASS=$PASS FAIL=$FAIL"
	[[ "$FAIL" -eq 0 ]]
	exit $?
fi

PATHS=(
	scripts/catalog-query.py
	scripts/catalog.py
	scripts/check-markdown-links.py
	scripts/check-root-discovery.py
	scripts/generate-skill-docs.py
	scripts/scan-secret-material.py
	scripts/traceability_schema.py
	scripts/validate-cascade-fixtures.py
	scripts/validate-final-package.py
	scripts/validate-skill-catalog.py
	scripts/validate_skill_frontmatter.py
	scripts/catalog-install.sh
	scripts/check-codex-parity.sh
	scripts/check-opencode-parity.sh
	scripts/check-sync-staleness.sh
	scripts/install-auggie.sh
	scripts/install-claude-code.sh
	scripts/install-codex.sh
	scripts/install-copilot.sh
	scripts/install-gemini.sh
	scripts/readme-generate.sh
	scripts/regen-host-golden.sh
	scripts/verify-golden-dir.sh
	04-validate-handoff/eval-a-skill/scaffold-eval.py
	03-configure-generate/ai-catapult-init/scripts/readme-generate.sh
)
GOLDEN_GUARD="$(mktemp)"
cp "$REPO_ROOT/tests/fixtures/host-default-golden.json" "$GOLDEN_GUARD"
for path in "${PATHS[@]}"; do
	pin "$path" || true
	red_leg "$path" "$path"
	cp "$GOLDEN_GUARD" "$REPO_ROOT/tests/fixtures/host-default-golden.json"
done
rm -f "$GOLDEN_GUARD"
unset GOLDEN_GUARD

py_case "catalog-query codex" scripts/catalog-query.py --root "$REPO_ROOT" --host codex
py_case "catalog-query missing host" scripts/catalog-query.py --root "$REPO_ROOT"
py_case "catalog-query unknown flag" scripts/catalog-query.py --root "$REPO_ROOT" --host codex --nope
py_case "catalog-query missing value" scripts/catalog-query.py --host
py_case "catalog-query unknown lifecycle" scripts/catalog-query.py --root "$REPO_ROOT" --host codex --include-lifecycle unknown
env_py "catalog-query NODE_OPTIONS" scripts/catalog-query.py --root "$REPO_ROOT" --host codex
PROJ_L="$(mktemp)"
PROJ_R="$(mktemp)"
pin scripts/catalog-query.py || true
LEFT=(python3 "$WT/scripts/catalog-query.py" --root "$REPO_ROOT" --host codex --projection "$PROJ_L")
RIGHT=(python3 "$REPO_ROOT/scripts/catalog-query.py" --root "$REPO_ROOT" --host codex --projection "$PROJ_R")
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
HOME="$lwatch" run_pair "catalog-query projection streams" "$lwatch" "$rwatch"
if cmp -s "$PROJ_L" "$PROJ_R"; then
	ok "catalog-query projection bytes"
else
	bad "catalog-query projection bytes"
fi
rm -f "$PROJ_L" "$PROJ_R"

MALFORMED="$REPO_ROOT/tests/fixtures/catalog-malformed"
for fixture in "$MALFORMED"/*.json; do
	tmp="$(mktemp -d)"
	cp -R "$MALFORMED/skill" "$tmp/skill"
	cp "$fixture" "$tmp/catalog.json"
	py_case "catalog-query malformed $(basename "$fixture")" scripts/catalog-query.py --root "$tmp" --host codex
	rm -rf "$tmp"
done

py_case "markdown links repo" scripts/check-markdown-links.py --root "$REPO_ROOT"
py_case "markdown links unknown flag" scripts/check-markdown-links.py --nope
env_py "markdown links NODE_OPTIONS" scripts/check-markdown-links.py --root "$REPO_ROOT"
py_case "root discovery repo" scripts/check-root-discovery.py
py_case "root discovery unknown flag" scripts/check-root-discovery.py --nope
env_py "root discovery NODE_OPTIONS" scripts/check-root-discovery.py
py_case "skill docs check" scripts/generate-skill-docs.py --check
py_case "skill docs unknown flag" scripts/generate-skill-docs.py --nope
env_py "skill docs NODE_OPTIONS" scripts/generate-skill-docs.py --check
py_case "cascade fixtures" scripts/validate-cascade-fixtures.py
py_case "cascade fixtures extra arg" scripts/validate-cascade-fixtures.py --nope
env_py "cascade fixtures NODE_OPTIONS" scripts/validate-cascade-fixtures.py
py_case "final package" scripts/validate-final-package.py
py_case "final package extra arg" scripts/validate-final-package.py --nope
env_py "final package NODE_OPTIONS" scripts/validate-final-package.py
py_case "skill catalog repo" scripts/validate-skill-catalog.py --root "$REPO_ROOT"
py_case "skill catalog unknown flag" scripts/validate-skill-catalog.py --nope
env_py "skill catalog NODE_OPTIONS" scripts/validate-skill-catalog.py --root "$REPO_ROOT"

SECRET="$(mktemp -d)"
pin scripts/scan-secret-material.py || true
LEFT=(python3 "$WT/scripts/scan-secret-material.py")
RIGHT=(python3 "$REPO_ROOT/scripts/scan-secret-material.py")
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
(cd "$SECRET" && HOME="$lwatch" run_pair "scan-secret empty dir" "$lwatch" "$rwatch")
marker="$(printf '%s%s%s' '-----BE' 'GIN PRIVATE KEY-' '----')"
printf '%s\n%s\n' "$marker" fixture >"$SECRET/secret.txt"
(cd "$SECRET" && HOME="$lwatch" run_pair "scan-secret fixture hit" "$lwatch" "$rwatch")
env_py "scan-secret NODE_OPTIONS" scripts/scan-secret-material.py
rm -rf "$SECRET"

ARGV0_CODEX="parity-argv0/check-codex-parity.sh"
ARGV0_OPEN="parity-argv0/check-opencode-parity.sh"
ARGV0_SYNC="parity-argv0/check-sync-staleness.sh"
UNMARKED="$(mktemp)"
MARKED="$(mktemp)"
cat >"$UNMARKED" <<'EOF'
# Fixture skill

## Process

Use AskUserQuestion to confirm the destination branch before pushing.
EOF
cat >"$MARKED" <<'EOF'
# Fixture skill

## Process

<!-- codex:optional -->
Use AskUserQuestion to confirm the destination branch.
Fallback (Codex/plain markdown): print the options as a numbered list and ask
the user to reply with a number in prose.
EOF
sh_case "codex parity unmarked" scripts/check-codex-parity.sh "$ARGV0_CODEX" "$UNMARKED"
sh_case "codex parity marked" scripts/check-codex-parity.sh "$ARGV0_CODEX" "$MARKED"
sh_case "codex parity usage" scripts/check-codex-parity.sh "$ARGV0_CODEX"
env_sh "codex parity NODE_OPTIONS" scripts/check-codex-parity.sh "$ARGV0_CODEX" "$MARKED"
cat >"$MARKED" <<'EOF'
# Fixture skill

## Process

<!-- opencode:optional -->
Use AskUserQuestion to confirm the destination branch.
Fallback (opencode/plain markdown): print the options as a numbered list and
ask the user to reply with a number in prose.
EOF
sh_case "opencode parity unmarked" scripts/check-opencode-parity.sh "$ARGV0_OPEN" "$UNMARKED"
sh_case "opencode parity marked" scripts/check-opencode-parity.sh "$ARGV0_OPEN" "$MARKED"
sh_case "opencode parity usage" scripts/check-opencode-parity.sh "$ARGV0_OPEN"
env_sh "opencode parity NODE_OPTIONS" scripts/check-opencode-parity.sh "$ARGV0_OPEN" "$MARKED"
rm -f "$UNMARKED" "$MARKED"

LOCK="$(mktemp)"
printf 'source: mattpocock/skills\nvia: r3dlex/skills\npinned_sha: deadbeef0000000000000000000000000000dead\nupdated: 2020-01-01\nsync_script: scripts/sync-upstream.sh\n' >"$LOCK"
sh_case "sync staleness stale" scripts/check-sync-staleness.sh "$ARGV0_SYNC" --lock "$LOCK" --mode advisory --repo-root "$REPO_ROOT"
sh_case "sync staleness bogus" scripts/check-sync-staleness.sh "$ARGV0_SYNC" --bogus
env_sh "sync staleness NODE_OPTIONS" scripts/check-sync-staleness.sh "$ARGV0_SYNC" --bogus
rm -f "$LOCK"

for host in install-codex.sh install-auggie.sh install-gemini.sh install-claude-code.sh install-copilot.sh; do
	sh_case "$host usage" "scripts/$host" "parity-argv0/$host" --bogus
	env_sh "$host NODE_OPTIONS" "scripts/$host" "parity-argv0/$host" --bogus
done
sh_case "install-claude extra" scripts/install-claude-code.sh parity-argv0/install-claude-code.sh --user extra
sh_case "install-copilot repo missing" scripts/install-copilot.sh parity-argv0/install-copilot.sh --repo
sh_case "install-codex unknown lifecycle" scripts/install-codex.sh parity-argv0/install-codex.sh --include-lifecycle nope

install_case() {
	local label="$1" host="$2"
	shift 2
	pin "scripts/$host" || return
	local lhome rhome
	lhome="$(mktemp -d)"
	rhome="$(mktemp -d)"
	LEFT=(invoke_sh "parity-argv0/$host" "$WT/scripts/$host" "$@")
	RIGHT=(invoke_sh "parity-argv0/$host" "$REPO_ROOT/scripts/$host" "$@")
	SKILLS_CATALOG_ROOT="$REPO_ROOT" run_pair "$label" "$lhome" "$rhome"
	unset SKILLS_CATALOG_ROOT
}
install_case "install-codex skill" install-codex.sh --skill ai-catapult-init
install_case "install-claude user" install-claude-code.sh --user
install_case "install-auggie all" install-auggie.sh --all
install_case "install-gemini link" install-gemini.sh --link
COPILOT_L="$(mktemp -d)/repo"
COPILOT_R="$(mktemp -d)/repo"
mkdir -p "$COPILOT_L" "$COPILOT_R"
pin scripts/install-copilot.sh || true
LEFT=(invoke_sh parity-argv0/install-copilot.sh "$WT/scripts/install-copilot.sh" --repo "$COPILOT_L")
RIGHT=(invoke_sh parity-argv0/install-copilot.sh "$REPO_ROOT/scripts/install-copilot.sh" --repo "$COPILOT_R")
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
run_pair "install-copilot streams" "$lwatch" "$rwatch"
if tree_same "$COPILOT_L" "$COPILOT_R"; then
	ok "install-copilot written files"
else
	bad "install-copilot written files"
fi
rm -rf "$COPILOT_L" "$COPILOT_R"

ALT="$(mktemp -d)"
mkdir -p "$ALT/03-configure-generate"
cp -R "$REPO_ROOT/03-configure-generate/ai-catapult-init" "$ALT/03-configure-generate/ai-catapult-init"
python3 "$REPO_ROOT/tests/fixtures/e6-py-leaf/alt_catalog.py" "$ALT"
pin scripts/install-codex.sh || true
LHOME="$(mktemp -d)"
RHOME="$(mktemp -d)"
LEFT=(invoke_sh parity-argv0/install-codex.sh "$WT/scripts/install-codex.sh" --skill ai-catapult-init)
RIGHT=(invoke_sh parity-argv0/install-codex.sh "$REPO_ROOT/scripts/install-codex.sh" --skill ai-catapult-init)
SKILLS_CATALOG_ROOT="$ALT" run_pair "install-codex SKILLS_CATALOG_ROOT" "$LHOME" "$RHOME"
unset SKILLS_CATALOG_ROOT
rm -rf "$ALT" "$LHOME" "$RHOME"

sh_case "readme usage missing mode" scripts/readme-generate.sh parity-argv0/readme-generate.sh
sh_case "readme bad mode" scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode nope
sh_case "readme missing value" scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode
sh_case "readme unknown arg" scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode template --star-history x
env_sh "readme NODE_OPTIONS" scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode nope
sh_case "init readme missing mode" 03-configure-generate/ai-catapult-init/scripts/readme-generate.sh parity-argv0/readme-generate.sh
sh_case "init readme bad mode" 03-configure-generate/ai-catapult-init/scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode nope
env_sh "init readme NODE_OPTIONS" 03-configure-generate/ai-catapult-init/scripts/readme-generate.sh parity-argv0/readme-generate.sh --mode nope

py_case "scaffold missing skill" 04-validate-handoff/eval-a-skill/scaffold-eval.py
env_py "scaffold NODE_OPTIONS" 04-validate-handoff/eval-a-skill/scaffold-eval.py
CAFE="$(mktemp -d)"
pin 04-validate-handoff/eval-a-skill/scaffold-eval.py || true
LEFT=(python3 "$WT/04-validate-handoff/eval-a-skill/scaffold-eval.py" --skill "$(printf 'caf\303\251')" --root "$CAFE")
RIGHT=(python3 "$REPO_ROOT/04-validate-handoff/eval-a-skill/scaffold-eval.py" --skill "$(printf 'caf\303\251')" --root "$CAFE")
# Sequential same-path write so stdout paths match, with a snapshot between runs.
cafe_l="$(mktemp -d)"
cafe_r="$(mktemp -d)"
lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
set +e
"${LEFT[@]}" >"$lout" 2>"$lerr"
lrc=$?
cp -R "$CAFE/." "$cafe_l/" 2>/dev/null || true
rm -rf "$CAFE"
mkdir -p "$CAFE"
"${RIGHT[@]}" >"$rout" 2>"$rerr"
rrc=$?
cp -R "$CAFE/." "$cafe_r/" 2>/dev/null || true
set +e
judge "scaffold-eval cafe" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$cafe_l" "$cafe_r"
rm -rf "$CAFE" "$cafe_l" "$cafe_r"
rm -f "$lout" "$rout" "$lerr" "$rerr"

sh_case "verify-golden usage" scripts/verify-golden-dir.sh parity-argv0/verify-golden-dir.sh
sh_case "verify-golden skills" scripts/verify-golden-dir.sh parity-argv0/verify-golden-dir.sh "$REPO_ROOT" "$REPO_ROOT/reference/golden-skills"
sh_case "verify-golden root" scripts/verify-golden-dir.sh parity-argv0/verify-golden-dir.sh "$REPO_ROOT" "$REPO_ROOT/reference/golden-root"
sh_case "verify-golden missing" scripts/verify-golden-dir.sh parity-argv0/verify-golden-dir.sh "$REPO_ROOT" "$REPO_ROOT/reference/missing-golden"
env_sh "verify-golden NODE_OPTIONS" scripts/verify-golden-dir.sh parity-argv0/verify-golden-dir.sh

GOLDEN_BACKUP="$(mktemp)"
cp "$REPO_ROOT/tests/fixtures/host-default-golden.json" "$GOLDEN_BACKUP"
pin scripts/regen-host-golden.sh || true
lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
lfile="$(mktemp)"
rfile="$(mktemp)"
set +e
invoke_sh parity-argv0/regen-host-golden.sh "$WT/scripts/regen-host-golden.sh" >"$lout" 2>"$lerr"
lrc=$?
cp "$WT/tests/fixtures/host-default-golden.json" "$lfile"
invoke_sh parity-argv0/regen-host-golden.sh "$REPO_ROOT/scripts/regen-host-golden.sh" >"$rout" 2>"$rerr"
rrc=$?
cp "$REPO_ROOT/tests/fixtures/host-default-golden.json" "$rfile"
set +e
cp "$GOLDEN_BACKUP" "$REPO_ROOT/tests/fixtures/host-default-golden.json"
git -C "$WT" checkout -- tests/fixtures/host-default-golden.json >/dev/null 2>&1 || true
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
cp "$lfile" "$lwatch/golden.json"
cp "$rfile" "$rwatch/golden.json"
judge "regen-host-golden" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
env_sh "regen-host-golden NODE_OPTIONS" scripts/regen-host-golden.sh parity-argv0/regen-host-golden.sh
cp "$GOLDEN_BACKUP" "$REPO_ROOT/tests/fixtures/host-default-golden.json"
rm -f "$GOLDEN_BACKUP" "$lout" "$rout" "$lerr" "$rerr" "$lfile" "$rfile"
rm -rf "$lwatch" "$rwatch"

# Direct parity of retired modules and catalog-install functions.
FIX="$REPO_ROOT/tests/fixtures/e6-py-leaf"
lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
set +e
PYTHONPATH="$WT/scripts" python3 "$FIX/catalog_driver.py" "$REPO_ROOT" >"$lout" 2>"$lerr"
lrc=$?
node "$FIX/catalog_port.mjs" "$REPO_ROOT" >"$rout" 2>"$rerr"
rrc=$?
set +e
judge "catalog.py select codex" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
rm -f "$lout" "$rout" "$lerr" "$rerr"

for graph in '{"schema_version":"1.1","nodes":[],"edges":[]}' '{"nodes":[]}'; do
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	set +e
	PYTHONPATH="$WT/scripts" python3 "$FIX/trace_driver.py" "$graph" >"$lout" 2>"$lerr"
	lrc=$?
	node "$FIX/trace_port.mjs" "$graph" >"$rout" 2>"$rerr"
	rrc=$?
	set +e
	judge "traceability_schema $graph" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
done

SKILL_MD="$REPO_ROOT/03-configure-generate/ai-catapult-init/SKILL.md"
lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
set +e
PYTHONPATH="$WT/scripts" python3 "$FIX/frontmatter_driver.py" "$SKILL_MD" >"$lout" 2>"$lerr"
lrc=$?
node "$FIX/frontmatter_port.mjs" "$SKILL_MD" >"$rout" 2>"$rerr"
rrc=$?
set +e
judge "validate_skill_frontmatter name" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
rm -f "$lout" "$rout" "$lerr" "$rerr"

lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
set +e
bash -c 'set -euo pipefail; SCRIPT_DIR="$1"; SKILLS_DIR="$2"; source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args --include-lifecycle nope' bash "$WT/scripts" "$REPO_ROOT" >"$lout" 2>"$lerr"
lrc=$?
node "$FIX/install_port.mjs" --include-lifecycle nope >"$rout" 2>"$rerr"
rrc=$?
set +e
judge "catalog-install unknown lifecycle" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
rm -f "$lout" "$rout" "$lerr" "$rerr"
rm -rf "$lwatch" "$rwatch"

module_case() {
	local label="$1" lwatch rwatch
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	run_pair "$label" "$lwatch" "$rwatch"
	rm -rf "$lwatch" "$rwatch"
}

trace_graph() {
	local label="$1" graph="$2"
	LEFT=(env PYTHONPATH="$WT/scripts" python3 "$FIX/trace_driver.py" "$graph")
	RIGHT=(node "$FIX/trace_port.mjs" "$graph")
	module_case "$label"
}

for fixture in standalone umbrella; do
	for name in graph.json graph-1.1.json; do
		ver="v1.0"
		[[ "$name" == "graph-1.1.json" ]] && ver="v1.1"
		graph="$(cat "$REPO_ROOT/reference/fixtures/v3/$fixture/.ai/traceability/$name")"
		trace_graph "traceability_schema $ver $fixture" "$graph"
	done
done
unknown="$(node --input-type=module -e '
import { readFileSync } from "node:fs";
const graph = JSON.parse(readFileSync("reference/fixtures/v3/standalone/.ai/traceability/graph-1.1.json", "utf8"));
graph.nodes.push({
  id: "bogus:standalone-root:nope",
  type: "bogus-type",
  title: "unknown type",
  status: "active",
  repo_id: "standalone-root",
  path: "README.md",
});
process.stdout.write(JSON.stringify(graph));
')"
trace_graph "traceability_schema unknown node" "$unknown"

POLLUTE_REL="reference/fixtures/v3/standalone/.ai/traceability/graph-1.1.json"
POLLUTE_BAK="$(mktemp)"
wt_bak="$(mktemp)"
cp "$REPO_ROOT/$POLLUTE_REL" "$POLLUTE_BAK"
cp "$WT/$POLLUTE_REL" "$wt_bak"
node --input-type=module -e '
import { readFileSync, writeFileSync } from "node:fs";
for (const path of process.argv.slice(1)) {
  const graph = JSON.parse(readFileSync(path, "utf8"));
  graph.nodes.push({
    id: "bogus:standalone-root:shipped",
    type: "definitely-not-a-type",
    title: "x",
    status: "active",
    repo_id: "standalone-root",
    path: "README.md",
  });
  writeFileSync(path, `${JSON.stringify(graph, null, 2)}\n`);
}
' "$REPO_ROOT/$POLLUTE_REL" "$WT/$POLLUTE_REL"
LEFT=(python3 "$WT/scripts/validate-final-package.py")
RIGHT=(python3 "$REPO_ROOT/scripts/validate-final-package.py")
module_case "final package polluted unknown node"
cp "$POLLUTE_BAK" "$REPO_ROOT/$POLLUTE_REL"
cp "$wt_bak" "$WT/$POLLUTE_REL"
rm -f "$POLLUTE_BAK" "$wt_bak"
unset POLLUTE_BAK

catalog_pair() {
	local label="$1" mode="$2" root="$3" with_env="${4:-}"
	if [[ -n "$with_env" ]]; then
		LEFT=(env PYTHONPATH="$WT/scripts" NODE_OPTIONS=--throw-deprecation python3 "$FIX/catalog_driver.py" "$root" "$mode")
		RIGHT=(env NODE_OPTIONS=--throw-deprecation node "$FIX/catalog_port.mjs" "$root" "$mode")
	else
		LEFT=(env PYTHONPATH="$WT/scripts" python3 "$FIX/catalog_driver.py" "$root" "$mode")
		RIGHT=(node "$FIX/catalog_port.mjs" "$root" "$mode")
	fi
	module_case "$label"
}
catalog_pair "catalog unknown host" unknown-host "$REPO_ROOT"
catalog_pair "catalog unknown lifecycle" unknown-lifecycle "$REPO_ROOT"
catalog_pair "catalog NODE_OPTIONS" select "$REPO_ROOT" env
BADCAT="$(mktemp -d)"
mkdir -p "$BADCAT/skill"
cp "$REPO_ROOT/tests/fixtures/catalog-malformed/entry-not-object.json" "$BADCAT/catalog.json"
catalog_pair "catalog malformed entry" load "$BADCAT"
catalog_pair "catalog malformed NODE_OPTIONS" load "$BADCAT" env
rm -rf "$BADCAT"

fm_pair() {
	local label="$1" path="$2" with_env="${3:-}"
	if [[ -n "$with_env" ]]; then
		LEFT=(env PYTHONPATH="$WT/scripts" NODE_OPTIONS=--throw-deprecation python3 "$FIX/frontmatter_driver.py" "$path")
		RIGHT=(env NODE_OPTIONS=--throw-deprecation node "$FIX/frontmatter_port.mjs" "$path")
	else
		LEFT=(env PYTHONPATH="$WT/scripts" python3 "$FIX/frontmatter_driver.py" "$path")
		RIGHT=(node "$FIX/frontmatter_port.mjs" "$path")
	fi
	module_case "$label"
}
NOFM="$(mktemp)"
UNCLOSED="$(mktemp)"
QUOTED="$(mktemp)"
printf 'no frontmatter\n' >"$NOFM"
printf '%s\n' '---' 'name: open' >"$UNCLOSED"
printf '%s\n' '---' "name: 'quoted'" '---' >"$QUOTED"
fm_pair "frontmatter missing delimiter" "$NOFM"
fm_pair "frontmatter unclosed" "$UNCLOSED"
fm_pair "frontmatter quoted name" "$QUOTED"
fm_pair "frontmatter NODE_OPTIONS" "$SKILL_MD" env
fm_pair "frontmatter missing delimiter NODE_OPTIONS" "$NOFM" env
rm -f "$NOFM" "$UNCLOSED" "$QUOTED"

install_pair() {
	local label="$1"
	shift
	local lwatch rwatch lout rout lerr rerr lrc rrc
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	set +e
	bash -c 'set -euo pipefail; SCRIPT_DIR="$1"; shift; source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@"' bash "$WT/scripts" "$@" >"$lout" 2>"$lerr"
	lrc=$?
	bash "$REPO_ROOT/scripts/catalog-install.sh" "$@" >"$rout" 2>"$rerr"
	rrc=$?
	set +e
	judge "$label" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
	rm -rf "$lwatch" "$rwatch"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}
install_pair "catalog-install missing value" --include-lifecycle
install_pair "catalog-install unknown lifecycle shim" --include-lifecycle nope
NODE_OPTIONS=--throw-deprecation install_pair "catalog-install NODE_OPTIONS" --include-lifecycle nope
unset NODE_OPTIONS
lout="$(mktemp)"
rout="$(mktemp)"
lerr="$(mktemp)"
rerr="$(mktemp)"
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
set +e
bash -c 'set -euo pipefail; SCRIPT_DIR="$1"; shift; source "$SCRIPT_DIR/catalog-install.sh"; parse_catalog_args "$@"' bash "$WT/scripts" --include-lifecycle >"$lout" 2>"$lerr"
lrc=$?
env NODE_OPTIONS=--throw-deprecation node "$FIX/install_port.mjs" --include-lifecycle >"$rout" 2>"$rerr"
rrc=$?
set +e
judge "catalog-install port missing value NODE_OPTIONS" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
rm -rf "$lwatch" "$rwatch"
rm -f "$lout" "$rout" "$lerr" "$rerr"

# Class readme-stamp. Sites are the token
# YYYY-MM-DDTHH-MM-SSZ-<pid> in audit/backup filenames, audit JSON, stdout, and
# stderr. The mask replaces that token with <readme-stamp> and no other byte.
mask_readme_stamp() {
	local root="$1" out="$2" err="$3" stamp file dest tmp stream
	stamp="$(find "$root" -name 'audit-*.json' -print 2>/dev/null | head -1 || true)"
	stamp="$(basename "${stamp:-}" .json)"
	stamp="${stamp#audit-}"
	if [[ ! "$stamp" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z-[0-9]+$ ]]; then
		return 0
	fi
	for stream in "$out" "$err"; do
		tmp="$(mktemp)"
		sed "s/${stamp}/<readme-stamp>/g" "$stream" >"$tmp"
		mv "$tmp" "$stream"
	done
	while IFS= read -r file; do
		if grep -q "$stamp" "$file"; then
			tmp="$(mktemp)"
			sed "s/${stamp}/<readme-stamp>/g" "$file" >"$tmp"
			mv "$tmp" "$file"
		fi
	done < <(find "$root" -type f -print)
	while IFS= read -r file; do
		dest="${file//${stamp}/<readme-stamp>}"
		if [[ "$dest" != "$file" ]]; then
			mv "$file" "$dest"
		fi
	done < <(find "$root" -name "*${stamp}*" -print)
}

probe_stamp_mask_sites() {
	local root stream before after
	root="$(mktemp -d)"
	mkdir -p "$root/.ai"
	printf 'keep\n' >"$root/README.md"
	printf 'stamp 2026-10-12T04-40-28Z-9 here\n' >"$root/.ai/audit-2026-10-12T04-40-28Z-9.json"
	before="$(shasum -a 256 "$root/README.md" | awk '{print $1}')"
	stream="$(mktemp)"
	printf 'path audit-2026-10-12T04-40-28Z-9.json\n' >"$stream"
	mask_readme_stamp "$root" "$stream" "$stream"
	after="$(shasum -a 256 "$root/README.md" | awk '{print $1}')"
	if [[ "$before" == "$after" && -f "$root/.ai/audit-<readme-stamp>.json" && "$(cat "$stream")" == "path audit-<readme-stamp>.json" ]]; then
		ok "readme-stamp mask stays inside stamp sites"
	else
		bad "readme-stamp mask stays inside stamp sites"
	fi
	rm -rf "$root"
	rm -f "$stream"
}
probe_stamp_mask_sites

probe_refusal_divergence() {
	local lout rout lerr rerr lwatch rwatch saved_pass saved_fail rc
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	printf 'legacy\n' >"$lout"
	printf 'node_unavailable\n' >"$rerr"
	saved_pass=$PASS
	saved_fail=$FAIL
	set +e
	judge "internal node_unavailable diverge" 0 127 "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch" expect-diverge
	rc=$?
	set +e
	PASS=$saved_pass
	FAIL=$saved_fail
	if [[ "$rc" -eq 0 ]]; then
		bad "node_unavailable counted as a successful divergence"
	else
		ok "node_unavailable is not a successful divergence"
	fi
	printf 'node_version_unsupported\n' >"$rout"
	printf 'node_version_unsupported\n' >"$rerr"
	saved_pass=$PASS
	saved_fail=$FAIL
	set +e
	judge "internal node_version_unsupported diverge" 0 126 "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch" expect-diverge
	rc=$?
	set +e
	PASS=$saved_pass
	FAIL=$saved_fail
	if [[ "$rc" -eq 0 ]]; then
		bad "node_version_unsupported counted as a successful divergence"
	else
		ok "node_version_unsupported is not a successful divergence"
	fi
	printf 'different\n' >"$rout"
	: >"$rerr"
	saved_pass=$PASS
	saved_fail=$FAIL
	set +e
	judge "internal seeded diverge" 0 1 "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch" expect-diverge
	rc=$?
	set +e
	PASS=$saved_pass
	FAIL=$saved_fail
	if [[ "$rc" -eq 0 ]]; then
		ok "seeded divergence still counts"
	else
		bad "seeded divergence still counts"
	fi
	rm -rf "$lwatch" "$rwatch"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}
probe_refusal_divergence

readme_case() {
	local label="$1" script="$2" setup="$3"
	shift 3
	pin "$script" || return
	local work lsnap rsnap lout rout lerr rerr lrc rrc before
	work="$(mktemp -d)"
	lsnap="$(mktemp -d)"
	rsnap="$(mktemp -d)"
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	"$setup" "$work"
	set +e
	invoke_sh "parity-argv0/$(basename "$script")" "$WT/$script" --repo "$work" --out "$work/README.md" "$@" >"$lout" 2>"$lerr"
	lrc=$?
	cp -R "$work/." "$lsnap/" 2>/dev/null || true
	rm -rf "$work"
	mkdir -p "$work"
	"$setup" "$work"
	invoke_sh "parity-argv0/$(basename "$script")" "$REPO_ROOT/$script" --repo "$work" --out "$work/README.md" "$@" >"$rout" 2>"$rerr"
	rrc=$?
	cp -R "$work/." "$rsnap/" 2>/dev/null || true
	set +e
	before=""
	if [[ -f "$lsnap/README.md" ]]; then
		before="$(shasum -a 256 "$lsnap/README.md" | awk '{print $1}')"
	fi
	mask_readme_stamp "$lsnap" "$lout" "$lerr"
	mask_readme_stamp "$rsnap" "$rout" "$rerr"
	if [[ -n "$before" ]]; then
		if [[ "$before" == "$(shasum -a 256 "$lsnap/README.md" | awk '{print $1}')" ]]; then
			ok "$label readme-stamp mask left README.md"
		else
			bad "$label readme-stamp mask rewrote README.md"
		fi
	fi
	judge "$label" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lsnap" "$rsnap"
	rm -rf "$work" "$lsnap" "$rsnap"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}

setup_readme_template() {
	local root="$1"
	printf 'MIT License\n' >"$root/LICENSE"
}

setup_readme_existing() {
	local root="$1" i
	printf 'MIT License\n' >"$root/LICENSE"
	{
		echo "# Existing Project"
		echo
		for i in $(seq 1 30); do
			echo "Filler line $i to push the file size well over the 600 byte sparse threshold so the classifier treats this as an existing README."
		done
		echo
		echo "## Quick start"
		echo
		echo '```sh'
		echo "install-existing"
		echo "existing doctor"
		echo '```'
		echo
		echo "**Expected result:** prints ready"
		echo
		echo "## Features"
		echo
		echo "- one"
		echo
		echo "## License"
		echo
		echo "MIT"
	} >"$root/README.md"
}

README_FACTS=(
	--why "Use the CLI to verify one target before continuing."
	--primary-surface "tool <command>"
	--mental-model "One command inspects one target and reports a deterministic result."
)
for readme_script in scripts/readme-generate.sh 03-configure-generate/ai-catapult-init/scripts/readme-generate.sh; do
	if [[ "$readme_script" == scripts/* ]]; then
		readme_label="readme"
	else
		readme_label="init readme"
	fi
	readme_case "$readme_label template success" "$readme_script" setup_readme_template \
		--mode template --project T1Tool --tagline Tagline1 --archetype cli-tool \
		"${README_FACTS[@]}" --install-command install-t1tool \
		--first-success-command "t1tool doctor" --success-evidence "prints T1Tool ready" \
		--visibility public --license MIT --badges license
	readme_case "$readme_label audit-only" "$readme_script" setup_readme_existing \
		--mode audit-only
	existing_sample="$(mktemp -d)"
	setup_readme_existing "$existing_sample"
	existing_sha="$(shasum -a 256 "$existing_sample/README.md" | awk '{print $1}')"
	rm -rf "$existing_sample"
	readme_case "$readme_label augment" "$readme_script" setup_readme_existing \
		--mode augment --project Existing --tagline "Existing tool tagline" \
		--archetype cli-tool "${README_FACTS[@]}" --install-command install-existing \
		--first-success-command "existing doctor" --success-evidence "prints ready" \
		--source-sha "$existing_sha"
	readme_case "$readme_label guarded force" "$readme_script" setup_readme_existing \
		--mode template --project T2 --tagline "Second tool" --archetype cli-tool \
		"${README_FACTS[@]}" --install-command install-t2 \
		--first-success-command "t2 doctor" --success-evidence "prints ready" \
		--source-sha "$existing_sha" --force
done

readme_restricted() {
	local label="$1" script="$2" bin work lsnap rsnap lout rout lerr rerr lrc rrc cmd src sha
	pin "$script" || return
	bin="$(mktemp -d)"
	for cmd in bash node mkdir mktemp mv chmod cp grep sed awk stat tr wc date dirname cat rm; do
		src="$(command -v "$cmd" || true)"
		if [[ -n "$src" ]]; then
			ln -s "$src" "$bin/$cmd"
		fi
	done
	if PATH="$bin" command -v sha256sum >/dev/null 2>&1 || PATH="$bin" command -v shasum >/dev/null 2>&1; then
		bad "$label restricted PATH still has a SHA provider"
		rm -rf "$bin"
		return
	fi
	work="$(mktemp -d)"
	setup_readme_existing "$work"
	sha="$(shasum -a 256 "$work/README.md" | awk '{print $1}')"
	lsnap="$(mktemp -d)"
	rsnap="$(mktemp -d)"
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	set +e
	PATH="$bin" invoke_sh "parity-argv0/$(basename "$script")" "$WT/$script" --repo "$work" --out "$work/README.md" \
		--mode template --project "No SHA CLI" --tagline "Rejects unverified writes." \
		--why "Prevent guarded writes without a SHA-256 implementation." \
		--archetype cli-tool --primary-surface "no-sha <command>" \
		--mental-model "A checksum provider gates the replacement." \
		--install-command install-no-sha --first-success-command "no-sha doctor" \
		--success-evidence "prints no-sha ready" --source-sha "$sha" \
		--force >"$lout" 2>"$lerr"
	lrc=$?
	cp -R "$work/." "$lsnap/" 2>/dev/null || true
	rm -rf "$work"
	mkdir -p "$work"
	setup_readme_existing "$work"
	PATH="$bin" invoke_sh "parity-argv0/$(basename "$script")" "$REPO_ROOT/$script" --repo "$work" --out "$work/README.md" \
		--mode template --project "No SHA CLI" --tagline "Rejects unverified writes." \
		--why "Prevent guarded writes without a SHA-256 implementation." \
		--archetype cli-tool --primary-surface "no-sha <command>" \
		--mental-model "A checksum provider gates the replacement." \
		--install-command install-no-sha --first-success-command "no-sha doctor" \
		--success-evidence "prints no-sha ready" --source-sha "$sha" \
		--force >"$rout" 2>"$rerr"
	rrc=$?
	cp -R "$work/." "$rsnap/" 2>/dev/null || true
	set +e
	judge "$label" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lsnap" "$rsnap"
	rm -rf "$bin" "$work" "$lsnap" "$rsnap"
	rm -f "$lout" "$rout" "$lerr" "$rerr"
}
readme_restricted "readme restricted-PATH SHA refusal" scripts/readme-generate.sh
readme_restricted "init readme restricted-PATH SHA refusal" 03-configure-generate/ai-catapult-init/scripts/readme-generate.sh

link_root="$(mktemp -d)"
mkdir -p "$link_root/phase-a/alpha" "$link_root/phase-b/beta"
cat >"$link_root/catalog.json" <<'JSON'
{
  "schema_version": "1.0",
  "phases": ["phase-a", "phase-b"],
  "skills": [
    {"name":"alpha","source_path":"phase-a/alpha","owner_phase":"phase-a","applies_to_phases":["phase-a"],"lifecycle":"stable","supported_hosts":["codex"]},
    {"name":"beta","source_path":"phase-b/beta","owner_phase":"phase-b","applies_to_phases":["phase-b"],"lifecycle":"stable","supported_hosts":["codex"]}
  ]
}
JSON
cat >"$link_root/phase-a/alpha/SKILL.md" <<'MD'
---
name: alpha
description: alpha fixture
---
[flat beta reference](../beta/detail.md)
MD
cat >"$link_root/phase-b/beta/SKILL.md" <<'MD'
---
name: beta
description: beta fixture
---
MD
printf 'detail\n' >"$link_root/phase-b/beta/detail.md"
py_case "markdown links valid fixture" scripts/check-markdown-links.py --root "$link_root"
rm "$link_root/phase-b/beta/detail.md"
py_case "markdown links broken fixture" scripts/check-markdown-links.py --root "$link_root"
rm -rf "$link_root"

discover_root="$(mktemp -d)"
skill="$(printf '%s.%s' SKILL md)"
printf 'from pathlib import Path\nskills = list(Path('"'"'.'"'"').rglob('"'"'%s'"'"'))\n' "$skill" >"$discover_root/python.py"
printf 'for body in "$SKILLS_DIR"/*/%s; do echo "$body"; done\n' "$skill" >"$discover_root/shell.sh"
printf 'find "$SKILLS_DIR" -maxdepth 2 -name %s\n' "$skill" >"$discover_root/find.sh"
printf 'for d in "$ROOT"/*/; do\n  [ -f "${d}%s" ] && echo "$d"\ndone\n' "$skill" >"$discover_root/globfiletest.sh"
printf 'from pathlib import Path\nfor path in Path('"'"'.'"'"').iterdir():\n    body = path / '"'"'%s'"'"'\n    if body.is_file():\n        print(body)\n' "$skill" >"$discover_root/iterdir.py"
for bypass in "$discover_root"/*; do
	py_case "root discovery bypass $(basename "$bypass")" scripts/check-root-discovery.py "$bypass"
done
rm -rf "$discover_root"

for host in claude-code gemini copilot auggie opencode; do
	py_case "catalog-query host $host" scripts/catalog-query.py --root "$REPO_ROOT" --host "$host"
done
for host in codex claude-code gemini copilot auggie opencode; do
	py_case "catalog-query extended $host" scripts/catalog-query.py --root "$REPO_ROOT" --host "$host" \
		--include-lifecycle experimental --include-lifecycle deprecated
done

ALT_ALL="$(mktemp -d)"
mkdir -p "$ALT_ALL/03-configure-generate"
cp -R "$REPO_ROOT/03-configure-generate/ai-catapult-init" "$ALT_ALL/03-configure-generate/ai-catapult-init"
cat >"$ALT_ALL/catalog.json" <<'JSON'
{
  "schema_version": "1.0",
  "phases": ["03-configure-generate"],
  "skills": [
    {
      "name": "ai-catapult-init",
      "source_path": "03-configure-generate/ai-catapult-init",
      "owner_phase": "03-configure-generate",
      "applies_to_phases": ["03-configure-generate"],
      "lifecycle": "stable",
      "supported_hosts": ["codex", "claude-code", "gemini", "copilot", "auggie", "opencode"]
    }
  ]
}
JSON
alt_install() {
	local label="$1" host="$2"
	shift 2
	pin "scripts/$host" || return
	local lhome rhome
	lhome="$(mktemp -d)"
	rhome="$(mktemp -d)"
	LEFT=(invoke_sh "parity-argv0/$host" "$WT/scripts/$host" "$@")
	RIGHT=(invoke_sh "parity-argv0/$host" "$REPO_ROOT/scripts/$host" "$@")
	SKILLS_CATALOG_ROOT="$ALT_ALL" run_pair "$label" "$lhome" "$rhome"
	unset SKILLS_CATALOG_ROOT
	rm -rf "$lhome" "$rhome"
}
alt_install "install-claude SKILLS_CATALOG_ROOT" install-claude-code.sh --user
alt_install "install-auggie SKILLS_CATALOG_ROOT" install-auggie.sh --all
alt_install "install-gemini SKILLS_CATALOG_ROOT" install-gemini.sh --link
COPILOT_ALT_L="$(mktemp -d)/repo"
COPILOT_ALT_R="$(mktemp -d)/repo"
mkdir -p "$COPILOT_ALT_L" "$COPILOT_ALT_R"
pin scripts/install-copilot.sh || true
LEFT=(invoke_sh parity-argv0/install-copilot.sh "$WT/scripts/install-copilot.sh" --repo "$COPILOT_ALT_L")
RIGHT=(invoke_sh parity-argv0/install-copilot.sh "$REPO_ROOT/scripts/install-copilot.sh" --repo "$COPILOT_ALT_R")
lwatch="$(mktemp -d)"
rwatch="$(mktemp -d)"
SKILLS_CATALOG_ROOT="$ALT_ALL" run_pair "install-copilot SKILLS_CATALOG_ROOT" "$lwatch" "$rwatch"
unset SKILLS_CATALOG_ROOT
if tree_same "$COPILOT_ALT_L" "$COPILOT_ALT_R"; then
	ok "install-copilot SKILLS_CATALOG_ROOT written files"
else
	bad "install-copilot SKILLS_CATALOG_ROOT written files"
fi
rm -rf "$ALT_ALL" "$COPILOT_ALT_L" "$COPILOT_ALT_R" "$lwatch" "$rwatch"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
