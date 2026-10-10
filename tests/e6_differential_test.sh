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

repo="$(mktemp -d)"
git -C "$repo" init -q
git -C "$repo" config user.email fixture@example.com
git -C "$repo" config user.name fixture
printf '%s\n' '#!/bin/sh' 'printf "error: boom\n"' >"$repo/reference.sh"
chmod +x "$repo/reference.sh"
git -C "$repo" add reference.sh
git -C "$repo" commit -q -m reference
commit="$(git -C "$repo" rev-parse HEAD)"
blob="$(git -C "$repo" rev-parse HEAD:reference.sh)"
sha="$(git -C "$repo" cat-file blob "$blob" | shasum -a 256 | awk '{print $1}')"
printf '%s\n' '#!/bin/sh' 'printf "error: other\n"' >"$repo/other.sh"
chmod +x "$repo/other.sh"
printf '%s\n' '#!/bin/sh' 'printf "node_unavailable\n" >&2' 'exit 127' >"$repo/refuse.sh"
chmod +x "$repo/refuse.sh"

run_case() {
	local name="$1" expect="$2" candidate="$3" blob_id="$4" digest="$5" extra="$6"
	local corpus status=0
	corpus="$(mktemp)"
	node -e '
const fs = require("fs");
const [corpus, commit, blob, sha, candidate, extra] = process.argv.slice(1);
const body = {
  anchor: { commit, path: "reference.sh", blob, sha256: sha },
  candidate: candidate.split(" "),
  cases: [{ id: "one", args: [] }],
};
Object.assign(body, JSON.parse(extra || "{}"));
fs.writeFileSync(corpus, JSON.stringify(body));
' "$corpus" "$commit" "$blob_id" "$digest" "$candidate" "$extra"
	node "$REPO_ROOT/scripts/lib/differential.mjs" "$corpus" "$repo" >/tmp/e6-diff.out 2>/tmp/e6-diff.err || status=$?
	if [[ "$expect" == pass && "$status" -eq 0 ]]; then
		ok "$name"
	elif [[ "$expect" == fail && "$status" -ne 0 ]]; then
		ok "$name"
	else
		bad "$name expected $expect got $status ($(cat /tmp/e6-diff.err))"
	fi
	rm -f "$corpus"
}

run_case "matching candidate" pass "$repo/reference.sh" "$blob" "$sha" '{}'
run_case "one-byte divergence" fail "$repo/other.sh" "$blob" "$sha" '{}'
run_case "blob mismatch" fail "$repo/reference.sh" "0000000000000000000000000000000000000000" "$sha" '{}'
run_case "sha256 mismatch" fail "$repo/reference.sh" "$blob" "0000000000000000000000000000000000000000000000000000000000000000" '{}'
run_case "declared interpreter-diagnostic" pass "$repo/other.sh" "$blob" "$sha" '{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","prefix":"error: "}]}]}'
run_case "undeclared mask" fail "$repo/reference.sh" "$blob" "$sha" '{"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":7,"end":11}]}'
run_case "mask outside sites" fail "$repo/reference.sh" "$blob" "$sha" '{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","prefix":"error: "}]}],"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":0,"end":5}]}'
run_case "node_unavailable is never a pass" fail "$repo/refuse.sh" "$blob" "$sha" '{}'
rm -rf "$repo"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
