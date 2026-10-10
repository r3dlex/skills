#!/usr/bin/env bash
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
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
before="$(git status --porcelain --ignored)"
trap 'rm -rf ts-tooling/build' EXIT

for tool in ruff mypy xenon shellcheck shfmt; do
	if command -v "$tool" >/dev/null 2>&1; then
		ok "$tool is present"
	else
		bad "$tool is present"
	fi
done

if bash scripts/check-legacy-freeze.sh .; then
	ok "legacy freeze passes at this head"
else
	bad "legacy freeze passes at this head"
fi

node --input-type=module <<'JS'
import { readFileSync } from "node:fs";
const baseline = JSON.parse(readFileSync(".ai/rules/legacy-freeze-baseline.json", "utf8"));
const excludes = [
  "tests/fixtures/**", "test/fixtures/**", "vendor/**", "dist/**", "dist-snapshot/**",
  "reference/golden-*/**", "node_modules/**", ".venv/**", "site-packages/**",
];
if (JSON.stringify(baseline.excludes) !== JSON.stringify(excludes)) process.exit(1);
if (JSON.stringify(baseline.infrastructure_shells) !== JSON.stringify(["ts-tooling/bootstrap.sh"])) process.exit(1);
const kept = baseline.entries.filter((entry) => entry.class === "kept-language").map((entry) => entry.path).sort();
const want = ["scripts/matrix-contract.py", "scripts/release/strategy-selector.sh", "scripts/render-ci-adapters.py", "tests/helpers/lock_contention.py"];
if (JSON.stringify(kept) !== JSON.stringify(want)) process.exit(1);
for (const entry of baseline.entries.filter((item) => item.class === "kept-language")) {
  if (!entry.consumers || entry.consumers.length === 0) process.exit(1);
}
const flight = Object.fromEntries(baseline.entries.filter((entry) => entry.in_flight).map((entry) => [entry.path, entry.in_flight]));
if (flight["tests/local_ci_declaration_test.py"] !== 105) process.exit(1);
if (flight["tests/knowledge_producers_test.sh"] !== 118) process.exit(1);
if (baseline.measured.c901.length === 0) process.exit(1);
JS
[[ $? -eq 0 ]] && ok "ledger pins classes, excludes, consumers and in-flight entries" || bad "ledger pins"

fixture() {
	local name="$1" expect="$2"
	local dir
	dir="$(mktemp -d)"
	git -C "$dir" init -q
	git -C "$dir" config user.email fixture@example.com
	git -C "$dir" config user.name fixture
	mkdir -p "$dir/.ai/rules" "$dir/scripts"
	cp ruff.toml "$dir/ruff.toml"
	printf '%s\n' 'def ok() -> None:' '    return None' >"$dir/scripts/ok.py"
	git -C "$dir" add scripts/ok.py ruff.toml
	git -C "$dir" commit -q -m fixture
	node --input-type=module - "$dir" "$name" <<'JS'
import { writeFileSync, mkdirSync } from "node:fs";
import { spawnSync } from "node:child_process";
const dir = process.argv[2];
const name = process.argv[3];
const entry = { path: "scripts/ok.py", class: "eligible", owner: "e6-sk-01-py-leaf" };
const previousEntries = [JSON.parse(JSON.stringify(entry))];
const entries = [entry];
if (name === "kept-leave") {
  previousEntries[0] = { path: "scripts/ok.py", class: "kept-language", consumers: ["consumer"] };
}
if (name === "unlisted") {
  writeFileSync(dir + "/scripts/extra.py", "def extra() -> None:\n    return None\n");
  spawnSync("git", ["add", "scripts/extra.py"], { cwd: dir });
  spawnSync("git", ["commit", "-q", "-m", "extra"], { cwd: dir });
}
if (name === "reclass") entry.class = "scaffold-template";
if (name === "kept-leave") {
  entries[0] = { path: "scripts/ok.py", class: "eligible", owner: "e6-sk-01-py-leaf" };
}
if (name === "in-flight-mismatch") {
  previousEntries.push({ path: "scripts/flight.py", class: "eligible", owner: "e6-sk-05-test-harness", in_flight: 105 });
  entries.push({ path: "scripts/flight.py", class: "scaffold-template", in_flight: 105 });
  writeFileSync(dir + "/scripts/flight.py", "def flight() -> None:\n    return None\n");
  spawnSync("git", ["add", "scripts/flight.py"], { cwd: dir });
  spawnSync("git", ["commit", "-q", "-m", "flight"], { cwd: dir });
}
if (name === "in-flight-absent") {
  const absent = { path: "scripts/missing.py", class: "eligible", owner: "e6-sk-05-test-harness", in_flight: 105 };
  entries.push(absent);
  previousEntries.push(absent);
}
const baseline = {
  schema: "legacy-freeze-baseline/1",
  base: "fixture",
  classes: ["eligible", "compat-shim", "scaffold-template", "test-wrapper", "kept-language"],
  excludes: [],
  infrastructure_shells: [],
  entries,
  measured: { c901: [], xenon: [], mypy: [], shellcheck: [], shfmt: [], bash_n: [], xenon_average_ok: true },
};
if (name === "kept-leave") baseline.entries = entries;
mkdirSync(dir + "/.ai/rules", { recursive: true });
writeFileSync(dir + "/.ai/rules/legacy-freeze-baseline.json", JSON.stringify(baseline));
writeFileSync(dir + "/.ai/rules/previous.json", JSON.stringify({ ...baseline, entries: previousEntries }));
JS
	local status=0
	node "$REPO_ROOT/scripts/lib/check-legacy-freeze.mjs" "$dir" .ai/rules/previous.json >/tmp/e6-fixture.out 2>/tmp/e6-fixture.err || status=$?
	if [[ "$expect" == pass && "$status" -eq 0 ]]; then
		ok "fixture $name passes"
	elif [[ "$expect" == fail && "$status" -ne 0 ]]; then
		ok "fixture $name fails"
	else
		bad "fixture $name expected $expect, got $status"
		cat /tmp/e6-fixture.err
	fi
	rm -rf "$dir"
}

fixture unlisted fail
fixture reclass fail
fixture kept-leave fail
fixture in-flight-mismatch fail
fixture in-flight-absent pass

after="$(git status --porcelain --ignored)"
printf '%s\n' "$before" >/tmp/e6-before
printf '%s\n' "$after" >/tmp/e6-after
node -e '
const fs = require("fs");
const allowed = ["ts-tooling/node_modules", "ts-tooling/build"];
const rows = (text) => new Set(text.split("\n").filter((line) => line.trim()).map((line) => line.replace(/^\S+\s+/, "").replace(/\/$/, "")));
const before = rows(fs.readFileSync(process.argv[1], "utf8"));
const extra = [...rows(fs.readFileSync(process.argv[2], "utf8"))].filter((item) => !before.has(item));
process.exit(extra.some((item) => !allowed.some((name) => item === name || item.startsWith(name + "/"))) ? 1 : 0);
' /tmp/e6-before /tmp/e6-after
[[ $? -eq 0 ]] && ok "legacy freeze leaves no undeclared output" || bad "legacy freeze leaves no undeclared output"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
