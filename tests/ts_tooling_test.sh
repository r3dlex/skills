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
cleanup() {
	rm -rf ts-tooling/build
}
trap cleanup EXIT

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
	bad "node and npm are required"
	echo "Results: PASS=$PASS FAIL=$FAIL"
	exit 1
fi
ok "node and npm are present"
node_major="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$node_major" == 26 ]] && ok "node major is 26" || bad "node major is 26, got $node_major"

pkg="$(node -e 'const p=require("./ts-tooling/package.json"); if (p.dependencies) process.exit(2); if (p.engines.node!==">=26.0.0 <27.0.0") process.exit(3);')"
[[ $? -eq 0 ]] && ok "package is devDependencies only with the pinned node range" || bad "package.json contract"

node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync("ts-tooling/tsconfig.json", "utf8")).compilerOptions;
const want = {
  target: "ES2023", module: "NodeNext", moduleResolution: "NodeNext", strict: true,
  noUncheckedIndexedAccess: true, noImplicitOverride: true, noFallthroughCasesInSwitch: true,
  exactOptionalPropertyTypes: true, forceConsistentCasingInFileNames: true,
  verbatimModuleSyntax: true, skipLibCheck: true, declaration: true, sourceMap: true,
  incremental: false,
};
for (const [key, value] of Object.entries(want)) {
  if (JSON.stringify(cfg[key]) !== JSON.stringify(value)) {
    console.error(key, cfg[key]);
    process.exit(1);
  }
}
if (!cfg.lib || cfg.lib.join(",") !== "ES2023") process.exit(1);
if (cfg.tsBuildInfoFile) process.exit(1);
' && ok "tsconfig preset is pinned" || bad "tsconfig preset is pinned"

grep -q 'complexity: \["error", 10\]' ts-tooling/eslint.config.mjs && ok "complexity threshold is 10" || bad "complexity threshold"
grep -q 'sonarjs/cognitive-complexity": \["error", 15\]' ts-tooling/eslint.config.mjs && ok "cognitive complexity threshold is 15" || bad "cognitive complexity threshold"
grep -q 'no-floating-promises": "error"' ts-tooling/eslint.config.mjs && ok "no-floating-promises is error" || bad "no-floating-promises"

if grep -R -n -E 'eslint-disable|@ts-ignore|@ts-nocheck' ts-tooling/src scripts/lib >/dev/null; then
	bad "converted code has no suppression comment"
else
	ok "converted code has no suppression comment"
fi
echo 'eslint-disable' >/tmp/e6-suppression-probe.txt
if grep -q 'eslint-disable' /tmp/e6-suppression-probe.txt; then
	ok "suppression scanner catches a seeded comment"
else
	bad "suppression scanner catches a seeded comment"
fi
rm -f /tmp/e6-suppression-probe.txt

grep -q 'node-version: "26"' .github/workflows/ci.yml && ok "workflow pins node 26" || bad "workflow pins node 26"
grep -q '>=26.0.0 <27.0.0' docs/architecture/adr/0018-ts-tooling-runner-and-packaging.md && ok "ADR pins the node range" || bad "ADR pins the node range"
grep -q 'name: Test Suite' .github/workflows/ci.yml && ok "Test Suite job name is unchanged" || bad "Test Suite job name"
grep -q 'npm ci --ignore-scripts' .github/workflows/ci.yml && ok "workflow runs npm ci --ignore-scripts" || bad "workflow npm ci"
grep -q 'ts-tooling/node_modules' tests/test-scripts.sh && grep -q 'ts-tooling/build' tests/test-scripts.sh && ok "test-scripts excludes tooling outputs" || bad "test-scripts exclusion"

(cd ts-tooling && npm ci --ignore-scripts >/dev/null) && ok "bootstrap install" || bad "bootstrap install"
(cd ts-tooling && npx tsc --noEmit --project tsconfig.json) && ok "tsc --noEmit" || bad "tsc --noEmit"
(cd ts-tooling && npx eslint --max-warnings 0 'src/**/*.mts') && ok "eslint --max-warnings 0" || bad "eslint"
drift="$(mktemp -d)"
mkdir -p "$drift/scripts"
rsync -a --exclude node_modules --exclude build ts-tooling "$drift/"
ln -s "$REPO_ROOT/ts-tooling/node_modules" "$drift/ts-tooling/node_modules"
if (cd "$drift/ts-tooling" && npx tsc --project tsconfig.build.json --pretty false); then
	ok "fresh build"
else
	bad "fresh build"
fi
if diff -rq "$drift/scripts/lib" scripts/lib >/dev/null; then
	ok "committed output matches a fresh build"
else
	bad "committed output matches a fresh build"
	diff -rq "$drift/scripts/lib" scripts/lib || true
fi
rm -rf "$drift"

(cd ts-tooling && npx tsc --project tsconfig.test.json --pretty false && node build/test/sample.test.mjs) && ok "sample dependency seam" || bad "sample dependency seam"

neg_dir="$(mktemp -d)"
node -e '
const fs = require("fs");
const cfg = JSON.parse(fs.readFileSync("ts-tooling/tsconfig.json", "utf8"));
cfg.include = ["*.mts"];
cfg.compilerOptions.noEmit = true;
delete cfg.compilerOptions.rootDir;
fs.writeFileSync(process.argv[1], JSON.stringify(cfg, null, 2));
' "$neg_dir/tsconfig.json"
cp ts-tooling/eslint.config.mjs "$neg_dir/eslint.config.mjs"
cp tests/fixtures/e6-sk-00-ledger/complexity.mts "$neg_dir/complexity.mts"
cp tests/fixtures/e6-sk-00-ledger/floating.mts "$neg_dir/floating.mts"
cp tests/fixtures/e6-sk-00-ledger/cognitive.mts "$neg_dir/cognitive.mts"
cp tests/fixtures/e6-sk-00-ledger/unchecked.mts "$neg_dir/unchecked.mts"
ln -s "$REPO_ROOT/ts-tooling/node_modules" "$neg_dir/node_modules"
if (cd "$neg_dir" && npx eslint --max-warnings 0 complexity.mts); then
	bad "complexity fixture fails eslint"
else
	ok "complexity fixture fails eslint"
fi
if (cd "$neg_dir" && npx eslint --max-warnings 0 floating.mts); then
	bad "floating-promise fixture fails eslint"
else
	ok "floating-promise fixture fails eslint"
fi
if (cd "$neg_dir" && npx eslint --max-warnings 0 cognitive.mts); then
	bad "cognitive-complexity fixture fails eslint"
else
	ok "cognitive-complexity fixture fails eslint"
fi
if (cd "$neg_dir" && npx tsc --noEmit --pretty false); then
	bad "unchecked index fixture fails tsc"
else
	ok "unchecked index fixture fails tsc"
fi
rm -rf "$neg_dir"

seed="$REPO_ROOT/ts-tooling/node_modules/e6-seed.sh"
printf '#!/bin/bash\n' >"$seed"
if find "$REPO_ROOT" \( -path '*/ts-tooling/node_modules' \) -prune -o -name 'e6-seed.sh' -print | grep -q e6-seed.sh; then
	bad "seeded node_modules script is excluded from syntax checks"
else
	ok "seeded node_modules script is excluded from syntax checks"
fi
rm -f "$seed"

after="$(git status --porcelain --ignored)"
printf '%s\n' "$before" >/tmp/e6-before
printf '%s\n' "$after" >/tmp/e6-after
node -e '
const fs = require("fs");
const allowed = ["ts-tooling/node_modules", "ts-tooling/build"];
const rows = (text) => new Set(text.split("\n").filter((line) => line.trim()).map((line) => line.replace(/^\S+\s+/, "").replace(/\/$/, "")));
const before = rows(fs.readFileSync(process.argv[1], "utf8"));
const extra = [...rows(fs.readFileSync(process.argv[2], "utf8"))].filter((item) => !before.has(item));
const bad = extra.filter((item) => !allowed.some((name) => item === name || item.startsWith(name + "/")));
process.exit(bad.length ? 1 : 0);
' /tmp/e6-before /tmp/e6-after
[[ $? -eq 0 ]] && ok "no undeclared workspace output" || bad "no undeclared workspace output"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
