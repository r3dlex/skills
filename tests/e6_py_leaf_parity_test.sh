#!/usr/bin/env bash
# Differential proof for e6-sk-01-py-leaf. The reference is the publication
# commit, checked by blob id and sha256, never the working tree.
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

ANCHOR="6255da27afeee8c2e9f3582793e74fbc5ff68bf3"
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

compare() {
	local label="$1" path="$2"
	shift 2
	pin "$path" || return
	local left right
	left="$(mktemp)"
	right="$(mktemp)"
	set +e
	"$@" "$WT/$path" >"$left.out" 2>"$left.err"
	local lrc=$?
	"$@" "$REPO_ROOT/$path" >"$right.out" 2>"$right.err"
	local rrc=$?
	set -e
	if [[ "$lrc" -eq "$rrc" ]] && cmp -s "$left.out" "$right.out" && cmp -s "$left.err" "$right.err"; then
		if grep -q 'node_unavailable\|node_version_unsupported' "$right.err"; then
			bad "$label ended in a node refusal"
		else
			ok "$label"
		fi
	else
		bad "$label legacy=$lrc ts=$rrc"
	fi
	rm -f "$left" "$left.out" "$left.err" "$right" "$right.out" "$right.err"
}

run_py() {
	python3 "$@"
}
run_sh() {
	bash "$@"
}

compare "catalog-query codex" scripts/catalog-query.py run_py --root "$REPO_ROOT" --host codex
compare "catalog-query missing host" scripts/catalog-query.py run_py --root "$REPO_ROOT"
compare "markdown links" scripts/check-markdown-links.py run_py --root "$REPO_ROOT"
compare "root discovery" scripts/check-root-discovery.py run_py
compare "skill docs check" scripts/generate-skill-docs.py run_py --check
compare "scan-secret clean" scripts/scan-secret-material.py run_py
SECRET="$(mktemp -d)"
marker="$(printf '%s%s%s' '-----BE' 'GIN PRIVATE KEY-' '----')"
printf '%s\n%s\n' "$marker" fixture >"$SECRET/secret.txt"
set +e
(
	cd "$SECRET"
	python3 "$WT/scripts/scan-secret-material.py" >"$SECRET/l.out" 2>"$SECRET/l.err"
	echo $? >"$SECRET/l.rc"
	python3 "$REPO_ROOT/scripts/scan-secret-material.py" >"$SECRET/r.out" 2>"$SECRET/r.err"
	echo $? >"$SECRET/r.rc"
)
set -e
lrc="$(cat "$SECRET/l.rc")"
rrc="$(cat "$SECRET/r.rc")"
if [[ "$lrc" -eq "$rrc" ]] && cmp -s "$SECRET/l.out" "$SECRET/r.out"; then
	ok "scan-secret fixture hit"
else
	bad "scan-secret fixture hit legacy=$lrc ts=$rrc"
fi
rm -rf "$SECRET"

compare "cascade fixtures" scripts/validate-cascade-fixtures.py run_py
compare "final package" scripts/validate-final-package.py run_py
compare "skill catalog" scripts/validate-skill-catalog.py run_py
compare "codex parity refusal" scripts/check-codex-parity.sh run_sh --bogus
compare "opencode parity refusal" scripts/check-opencode-parity.sh run_sh --bogus
compare "sync staleness" scripts/check-sync-staleness.sh run_sh
compare "sync staleness refusal" scripts/check-sync-staleness.sh run_sh --bogus

ENV_LEFT="$(mktemp)"
ENV_RIGHT="$(mktemp)"
set +e
NODE_OPTIONS='--throw-deprecation' python3 "$WT/scripts/catalog-query.py" --root "$REPO_ROOT" --host codex >"$ENV_LEFT.out" 2>"$ENV_LEFT.err"
NODE_OPTIONS='--throw-deprecation' python3 "$REPO_ROOT/scripts/catalog-query.py" --root "$REPO_ROOT" --host codex >"$ENV_RIGHT.out" 2>"$ENV_RIGHT.err"
set -e
if cmp -s "$ENV_LEFT.out" "$ENV_RIGHT.out" && cmp -s "$ENV_LEFT.err" "$ENV_RIGHT.err" && ! grep -q node_unavailable "$ENV_RIGHT.err"; then
	ok "catalog-query ignores NODE_OPTIONS"
else
	bad "catalog-query ignores NODE_OPTIONS"
fi
rm -f "$ENV_LEFT" "$ENV_LEFT.out" "$ENV_LEFT.err" "$ENV_RIGHT" "$ENV_RIGHT.out" "$ENV_RIGHT.err"

CAFE_L="$(mktemp -d)"
CAFE_R="$(mktemp -d)"
set +e
python3 "$WT/04-validate-handoff/eval-a-skill/scaffold-eval.py" --skill "$(printf 'caf\303\251')" --root "$CAFE_L" >/dev/null
python3 "$REPO_ROOT/04-validate-handoff/eval-a-skill/scaffold-eval.py" --skill "$(printf 'caf\303\251')" --root "$CAFE_R" >/dev/null
set -e
if diff -rq "$CAFE_L" "$CAFE_R" >/dev/null; then
	ok "scaffold-eval cafe bytes"
else
	bad "scaffold-eval cafe bytes"
fi
rm -rf "$CAFE_L" "$CAFE_R"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
