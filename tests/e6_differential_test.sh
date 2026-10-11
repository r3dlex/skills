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
	if [[ -n "${7:-}" ]]; then
		node -e '
const { spawn } = require("node:child_process");
const fs = require("fs");
const [script, corpus, repo, ms] = process.argv.slice(1);
const child = spawn(process.execPath, [script, corpus, repo], { stdio: ["ignore", "pipe", "pipe"] });
const out = [];
const err = [];
child.stdout.on("data", (chunk) => out.push(chunk));
child.stderr.on("data", (chunk) => err.push(chunk));
const timer = setTimeout(() => child.kill("SIGKILL"), Number(ms));
child.on("exit", (code, signal) => {
  clearTimeout(timer);
  fs.writeFileSync("/tmp/e6-diff.out", Buffer.concat(out));
  fs.writeFileSync("/tmp/e6-diff.err", Buffer.concat(err));
  if (signal) process.exit(124);
  process.exit(code === null ? 1 : code);
});
' "$REPO_ROOT/scripts/lib/differential.mjs" "$corpus" "$repo" "$7" || status=$?
	else
		node "$REPO_ROOT/scripts/lib/differential.mjs" "$corpus" "$repo" >/tmp/e6-diff.out 2>/tmp/e6-diff.err || status=$?
	fi
	if [[ "$status" -eq 124 ]]; then
		bad "$name timed out"
	elif [[ "$expect" == pass && "$status" -eq 0 ]]; then
		ok "$name"
	elif [[ "$expect" == fail && "$status" -ne 0 ]]; then
		if [[ -n "${8:-}" ]] && ! grep -F -q -- "${8}" /tmp/e6-diff.err; then
			bad "$name expected '${8}' got $(cat /tmp/e6-diff.err)"
		else
			ok "$name"
		fi
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

json_repo="$(mktemp -d)"
git -C "$json_repo" init -q
git -C "$json_repo" config user.email fixture@example.com
git -C "$json_repo" config user.name fixture
node -e '
const fs = require("fs");
const dir = process.argv[1];
const write = (name, body) => fs.writeFileSync(dir + "/" + name, "#!/bin/sh\nprintf %s " + JSON.stringify(body) + "\n", {mode: 0o755});
write("reference.sh", "{\"error\": \"boom\"} ");
write("masked.sh", "{\"error\": \"other\"} ");
write("trimmed.sh", "{\"error\": \"boom\"}");
' "$json_repo"
git -C "$json_repo" add reference.sh
git -C "$json_repo" commit -q -m json
jblob="$(git -C "$json_repo" rev-parse HEAD:reference.sh)"
jsha="$(git -C "$json_repo" cat-file blob "$jblob" | shasum -a 256 | awk '{print $1}')"
run_json() {
	local name="$1" expect="$2" candidate="$3"
	run_case "$name" "$expect" "$candidate" "$jblob" "$jsha" '{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","jsonPointer":"/error"}]}]}'
}
# run_case uses $repo. Point it at the json repo for these two calls.
repo="$json_repo"
commit="$(git -C "$json_repo" rev-parse HEAD)"
run_json "json mask keeps surrounding bytes" pass "$json_repo/masked.sh"
run_json "json mask does not hide outside bytes" fail "$json_repo/trimmed.sh"
rm -rf "$json_repo"

byte_repo="$(mktemp -d)"
git -C "$byte_repo" init -q
git -C "$byte_repo" config user.email fixture@example.com
git -C "$byte_repo" config user.name fixture
printf '%s\n' '#!/bin/sh' 'printf "\200"' >"$byte_repo/reference.sh"
chmod +x "$byte_repo/reference.sh"
git -C "$byte_repo" add reference.sh
git -C "$byte_repo" commit -q -m bytes
printf '%s\n' '#!/bin/sh' 'printf "\201"' >"$byte_repo/other.sh"
chmod +x "$byte_repo/other.sh"
repo="$byte_repo"
commit="$(git -C "$byte_repo" rev-parse HEAD)"
bblob="$(git -C "$byte_repo" rev-parse HEAD:reference.sh)"
bsha="$(git -C "$byte_repo" cat-file blob "$bblob" | shasum -a 256 | awk '{print $1}')"
run_case "raw bytes 0x80 and 0x81 diverge" fail "$byte_repo/other.sh" "$bblob" "$bsha" '{}'
rm -rf "$byte_repo"

omit_repo="$(mktemp -d)"
git -C "$omit_repo" init -q
git -C "$omit_repo" config user.email fixture@example.com
git -C "$omit_repo" config user.name fixture
printf '%s\n' '#!/bin/sh' ': > empty' >"$omit_repo/reference.sh"
chmod +x "$omit_repo/reference.sh"
git -C "$omit_repo" add reference.sh
git -C "$omit_repo" commit -q -m omit
printf '%s\n' '#!/bin/sh' 'exit 0' >"$omit_repo/omit.sh"
chmod +x "$omit_repo/omit.sh"
repo="$omit_repo"
commit="$(git -C "$omit_repo" rev-parse HEAD)"
oblob="$(git -C "$omit_repo" rev-parse HEAD:reference.sh)"
osha="$(git -C "$omit_repo" cat-file blob "$oblob" | shasum -a 256 | awk '{print $1}')"
run_case "missing empty file is a divergence" fail "$omit_repo/omit.sh" "$oblob" "$osha" '{}'
rm -rf "$omit_repo"

mask_byte_repo="$(mktemp -d)"
git -C "$mask_byte_repo" init -q
git -C "$mask_byte_repo" config user.email fixture@example.com
git -C "$mask_byte_repo" config user.name fixture
printf '%s\n' '#!/bin/sh' 'printf "error: boom\nraw: \200" >&2' >"$mask_byte_repo/reference.sh"
chmod +x "$mask_byte_repo/reference.sh"
git -C "$mask_byte_repo" add reference.sh
git -C "$mask_byte_repo" commit -q -m bytes
printf '%s\n' '#!/bin/sh' 'printf "error: other\nraw: \200" >&2' >"$mask_byte_repo/same.sh"
printf '%s\n' '#!/bin/sh' 'printf "error: boom\nraw: \201" >&2' >"$mask_byte_repo/other.sh"
chmod +x "$mask_byte_repo/same.sh" "$mask_byte_repo/other.sh"
repo="$mask_byte_repo"
commit="$(git -C "$mask_byte_repo" rev-parse HEAD)"
mblob="$(git -C "$mask_byte_repo" rev-parse HEAD:reference.sh)"
msha="$(git -C "$mask_byte_repo" cat-file blob "$mblob" | shasum -a 256 | awk '{print $1}')"
mask_extra='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stderr","prefix":"error: "}]}]}'
run_case "masked diagnostic keeps a trailing 0x80" pass "$mask_byte_repo/same.sh" "$mblob" "$msha" "$mask_extra"
run_case "masked diagnostic does not hide 0x80 versus 0x81" fail "$mask_byte_repo/other.sh" "$mblob" "$msha" "$mask_extra"
rm -rf "$mask_byte_repo"

trunc_mask='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","jsonPointer":"/error"}]}]}'
seed_trunc() {
	local dir="$1" body="$2"
	git -C "$dir" init -q
	git -C "$dir" config user.email fixture@example.com
	git -C "$dir" config user.name fixture
	node -e '
const fs = require("fs");
const dir = process.argv[1];
const body = process.argv[2];
fs.writeFileSync(dir + "/reference.sh", "#!/bin/sh\nprintf %s " + JSON.stringify(body) + "\n", { mode: 0o755 });
' "$dir" "$body"
	git -C "$dir" add reference.sh
	git -C "$dir" commit -q -m trunc
}
run_trunc() {
	local name="$1" body="$2"
	local dir
	dir="$(mktemp -d)"
	seed_trunc "$dir" "$body"
	repo="$dir"
	commit="$(git -C "$dir" rev-parse HEAD)"
	local blob sha
	blob="$(git -C "$dir" rev-parse HEAD:reference.sh)"
	sha="$(git -C "$dir" cat-file blob "$blob" | shasum -a 256 | awk '{print $1}')"
	run_case "$name" fail "$dir/reference.sh" "$blob" "$sha" "$trunc_mask" 2000
	rm -rf "$dir"
}
run_trunc "truncated json mask finishes" '{"error": "boom"'
run_trunc "truncated compact json mask finishes" '{"error":"boom"'

span_repo="$(mktemp -d)"
git -C "$span_repo" init -q
git -C "$span_repo" config user.email fixture@example.com
git -C "$span_repo" config user.name fixture
printf '%s\n' '#!/bin/sh' 'printf "error: abcX\n"' >"$span_repo/reference.sh"
chmod +x "$span_repo/reference.sh"
git -C "$span_repo" add reference.sh
git -C "$span_repo" commit -q -m span
printf '%s\n' '#!/bin/sh' 'printf "error: abcY\n"' >"$span_repo/other.sh"
chmod +x "$span_repo/other.sh"
repo="$span_repo"
commit="$(git -C "$span_repo" rev-parse HEAD)"
sblob="$(git -C "$span_repo" rev-parse HEAD:reference.sh)"
ssha="$(git -C "$span_repo" cat-file blob "$sblob" | shasum -a 256 | awk '{print $1}')"
partial_span='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","prefix":"error: "}]}],"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":7,"end":8}]}'
covered_span='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","prefix":"error: "}]}],"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":10,"end":11}]}'
run_case "supplied span does not hide outside bytes" fail "$span_repo/other.sh" "$sblob" "$ssha" "$partial_span" "" "output divergence"
run_case "supplied span masks its own bytes" pass "$span_repo/other.sh" "$sblob" "$ssha" "$covered_span"
rm -rf "$span_repo"

json_span_repo="$(mktemp -d)"
git -C "$json_span_repo" init -q
git -C "$json_span_repo" config user.email fixture@example.com
git -C "$json_span_repo" config user.name fixture
node -e '
const fs = require("fs");
const dir = process.argv[1];
const write = (name, body) => fs.writeFileSync(dir + "/" + name, "#!/bin/sh\nprintf %s " + JSON.stringify(body) + "\n", { mode: 0o755 });
write("reference.sh", "{\"error\":\"boom\",\"status\":\"blocked\"}\n");
' "$json_span_repo"
git -C "$json_span_repo" add reference.sh
git -C "$json_span_repo" commit -q -m json-span
repo="$json_span_repo"
commit="$(git -C "$json_span_repo" rev-parse HEAD)"
jsblob="$(git -C "$json_span_repo" rev-parse HEAD:reference.sh)"
jssha="$(git -C "$json_span_repo" cat-file blob "$jsblob" | shasum -a 256 | awk '{print $1}')"
status_span='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","jsonPointer":"/error"}]}],"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":17,"end":35}]}'
run_case "json mask span must sit inside its field" fail "$json_span_repo/reference.sh" "$jsblob" "$jssha" "$status_span" "" "mask reaches outside declared sites"
rm -rf "$json_span_repo"

json_partial_repo="$(mktemp -d)"
git -C "$json_partial_repo" init -q
git -C "$json_partial_repo" config user.email fixture@example.com
git -C "$json_partial_repo" config user.name fixture
node -e '
const fs = require("fs");
const dir = process.argv[1];
const write = (name, body) => fs.writeFileSync(dir + "/" + name, "#!/bin/sh\nprintf %s " + JSON.stringify(body) + "\n", { mode: 0o755 });
write("reference.sh", "{\"error\":\"abcX\"}\n");
write("other.sh", "{\"error\":\"abcY\"}\n");
' "$json_partial_repo"
git -C "$json_partial_repo" add reference.sh
git -C "$json_partial_repo" commit -q -m json-partial
repo="$json_partial_repo"
commit="$(git -C "$json_partial_repo" rev-parse HEAD)"
jpblob="$(git -C "$json_partial_repo" rev-parse HEAD:reference.sh)"
jpsha="$(git -C "$json_partial_repo" cat-file blob "$jpblob" | shasum -a 256 | awk '{print $1}')"
json_partial='{"normalizations":[{"name":"interpreter-diagnostic","mask":"<interpreter-diagnostic>","sites":[{"stream":"stdout","jsonPointer":"/error"}]}],"applyMasks":[{"name":"interpreter-diagnostic","stream":"stdout","start":10,"end":11}]}'
run_case "supplied json span does not hide outside bytes" fail "$json_partial_repo/other.sh" "$jpblob" "$jpsha" "$json_partial" "" "output divergence"
rm -rf "$json_partial_repo"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
