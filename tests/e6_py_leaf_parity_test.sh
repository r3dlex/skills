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

tree_same() {
	local left="$1" right="$2" lmanifest rmanifest
	lmanifest="$(mktemp)"
	rmanifest="$(mktemp)"
	if [[ -d "$left" ]]; then
		(cd "$left" && find . -type f ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path '*/Library/*' ! -path '*/.npm/*' ! -path '*/.cache/*' | sort | while IFS= read -r name; do
			shasum -a 256 "$name"
		done) >"$lmanifest"
	fi
	if [[ -d "$right" ]]; then
		(cd "$right" && find . -type f ! -name '*.pyc' ! -path '*/__pycache__/*' ! -path '*/Library/*' ! -path '*/.npm/*' ! -path '*/.cache/*' | sort | while IFS= read -r name; do
			shasum -a 256 "$name"
		done) >"$rmanifest"
	fi
	cmp -s "$lmanifest" "$rmanifest"
	local rc=$?
	rm -f "$lmanifest" "$rmanifest"
	return "$rc"
}

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
judge() {
	local label="$1" lrc="$2" rrc="$3" lout="$4" rout="$5" lerr="$6" rerr="$7" lwatch="$8" rwatch="$9"
	if [[ "$lrc" -eq "$rrc" ]] && cmp -s "$lout" "$rout" && cmp -s "$lerr" "$rerr" && tree_same "$lwatch" "$rwatch"; then
		if refused "$rerr" || refused "$rout"; then
			bad "$label ended in a node refusal"
			return 1
		fi
		ok "$label"
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

red_leg() {
	local label="$1" path="$2"
	pin "$path" || return
	local lwatch rwatch lout rout lerr rerr lrc rrc
	lwatch="$(mktemp -d)"
	rwatch="$(mktemp -d)"
	lout="$(mktemp)"
	rout="$(mktemp)"
	lerr="$(mktemp)"
	rerr="$(mktemp)"
	set +e
	if [[ "$path" == *.py ]]; then
		HOME="$lwatch" python3 "$WT/$path" >"$lout" 2>"$lerr"
	else
		HOME="$lwatch" invoke_sh "parity-argv0/$(basename "$path")" "$WT/$path" >"$lout" 2>"$lerr"
	fi
	lrc=$?
	printf 'seeded-divergence\n' >"$rout"
	printf 'seeded\n' >"$rerr"
	printf 'seeded\n' >"$rwatch/diverged"
	rrc=9
	set +e
	if [[ "$lrc" -eq "$rrc" ]] && cmp -s "$lout" "$rout" && cmp -s "$lerr" "$rerr" && tree_same "$lwatch" "$rwatch"; then
		bad "$label red-leg missed a seeded divergence"
	else
		ok "$label red-leg detects a seeded divergence"
	fi
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
for path in "${PATHS[@]}"; do
	pin "$path" || true
	red_leg "$path" "$path"
done

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
node "$FIX/install_port.mjs" >"$rout" 2>"$rerr"
rrc=$?
set +e
judge "catalog-install unknown lifecycle" "$lrc" "$rrc" "$lout" "$rout" "$lerr" "$rerr" "$lwatch" "$rwatch"
rm -f "$lout" "$rout" "$lerr" "$rerr"
rm -rf "$lwatch" "$rwatch"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
