#!/usr/bin/env bash
# D13 comparison contract checker: P1, M01-M34, O01-O09, C01-C15.
# Every fixture is synthetic test data built at run time; nothing here
# authenticates a real capture, custody receipt or hosted completion.
set -uo pipefail
export PYTHONDONTWRITEBYTECODE=1
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
CHECKER="${REPO_ROOT}/scripts/lib/d13-compare.mjs"
FIXTURES="${REPO_ROOT}/tests/fixtures/e6-d13-cc"
PASS=0
FAIL=0
WORK=""
ok() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}
bad() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}
finish() {
	echo ""
	echo "Results: PASS=$PASS FAIL=$FAIL"
	[[ "$FAIL" -eq 0 ]]
}
cleanup() {
	if [ -n "$WORK" ]; then
		rm -rf "$WORK"
	fi
}
trap cleanup EXIT

json() {
	node -e 'const fs=require("fs");const value=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));const out=process.argv[2]==="kind"?value.kind:value[process.argv[2]];process.stdout.write(typeof out==="object"?JSON.stringify(out):String(out));' "$1" "$2"
}

run_consumer_checks() {
	local plan="$1"
	local id="$2"
	local count index
	count="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).checks.length))' "$plan")"
	index=0
	while [ "$index" -lt "$count" ]; do
		local sub="${WORK}/${id}.check${index}.json"
		local cwd evidence label want actual status row remainder
		row="$(node -e '
const fs=require("fs");
const plan=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
const check=plan.checks[Number(process.argv[2])];
process.stdout.write([check.label,check.cwd,check.evidence,String(check.expect.exit)].join(" "));
' "$plan" "$index")"
		label="${row%% *}"
		remainder="${row#* }"
		cwd="${remainder%% *}"
		remainder="${remainder#* }"
		evidence="${remainder%% *}"
		want="${remainder##* }"
		actual="${WORK}/${id}.out${index}.json"
		node -e '
const fs=require("fs");
const plan=JSON.parse(fs.readFileSync(process.argv[1],"utf8"));
fs.writeFileSync(process.argv[2],JSON.stringify({case:plan.case,kind:"consumer",expect:plan.checks[Number(process.argv[3])].expect}));
' "$plan" "$sub" "$index"
		(
			cd "$cwd" || exit 1
			node "$CHECKER" --consumer-check "$evidence"
		) >"$actual" 2>"${WORK}/${id}.err${index}"
		status=$?
		if node "${FIXTURES}/verify.mjs" "$sub" "$actual" "$status"; then
			ok "${id}/${label} exit $want"
		else
			bad "${id}/${label} exit $want"
		fi
		index=$((index + 1))
	done
}

if ! command -v node >/dev/null 2>&1; then
	bad "node is required"
	finish
	exit 1
fi
ok "node is present"

if [ ! -f "$CHECKER" ]; then
	bad "compiled checker scripts/lib/d13-compare.mjs exists"
	finish
	exit 1
fi
ok "compiled checker scripts/lib/d13-compare.mjs exists"

if ! command -v git >/dev/null 2>&1; then
	bad "git is required"
	finish
	exit 1
fi
ok "git is present"

WORK="$(mktemp -d)"
node "${FIXTURES}/build.mjs" --init-world "${WORK}/world" >/dev/null || bad "shared fixture world builds"

contract_out="${WORK}/contract.json"
node "$CHECKER" --contract >"$contract_out" 2>"${WORK}/contract.err"
contract_status=$?
if [ "$contract_status" -eq 0 ] && node -e '
const fs = require("fs");
const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const want = {
  allowed_classes: ["time-field", "scratch-path", "interpreter-diagnostic"],
  consumers: [".ai/evidence/e6-sk-02-v1-port.json"],
  excluded_fields: ["/provenance"],
  permitted_sites: { "evidence-export/1": [], "merge-audit/1": [] },
  projected_schemas: ["merge-audit/1", "evidence-export/1"],
  refusal_schema: "readiness-contract/2",
  required_targets: ["skills", "aitool-root", "ai-catapult", "ai-factory"],
  schema: "d13-comparison/1",
  superseded_tool_sha256: [],
};
for (const [key, expected] of Object.entries(want)) {
  if (JSON.stringify(value[key]) !== JSON.stringify(expected)) { console.error(key); process.exit(1); }
}
if (!Array.isArray(value.argv_template) || value.argv_template.length !== 9) process.exit(1);
if (!/^[0-9a-f]{64}$/.test(value.spec_sha256_lineage)) process.exit(1);
if (!/^[0-9a-f]{64}$/.test(value.tool_sha256)) process.exit(1);
' "$contract_out"; then
	ok "--contract emits the fixed constants and exits 0"
else
	bad "--contract emits the fixed constants and exits 0"
fi

node "$CHECKER" >/dev/null 2>&1
usage_status=$?
if [ "$usage_status" -eq 2 ]; then
	ok "usage error exits 2"
else
	bad "usage error exits 2, got $usage_status"
fi

node "$CHECKER" "${WORK}/absent-run" >/dev/null 2>&1
absent_status=$?
if [ "$absent_status" -eq 2 ]; then
	ok "missing run directory exits 2"
else
	bad "missing run directory exits 2, got $absent_status"
fi

CASES="P1"
for index in $(seq 1 34); do
	CASES="${CASES} $(printf 'M%02d' "$index")"
done
for index in $(seq 1 9); do
	CASES="${CASES} $(printf 'O%02d' "$index")"
done
for index in $(seq 1 15); do
	CASES="${CASES} $(printf 'C%02d' "$index")"
done

for id in $CASES; do
	plan="${WORK}/${id}.plan.json"
	actual="${WORK}/${id}.out.json"
	if ! node "${FIXTURES}/build.mjs" "$id" "${WORK}/${id}" --repo "$REPO_ROOT" --tool "$CHECKER" --world "${WORK}/world" >"$plan" 2>"${WORK}/${id}.build.err"; then
		bad "${id} fixture builds"
		sed 's/^/    /' "${WORK}/${id}.build.err"
		continue
	fi
	ok "${id} fixture builds"
	kind="$(json "$plan" kind)"
	if [ "$kind" = "consumer" ]; then
		run_consumer_checks "$plan" "$id"
		continue
	fi
	run_dir="$(json "$plan" run)"
	node "$CHECKER" "$run_dir" >"$actual" 2>"${WORK}/${id}.err"
	status=$?
	if [ "$kind" = "observe" ]; then
		node "$CHECKER" "$run_dir" --observe >"$actual" 2>"${WORK}/${id}.err"
		status=$?
	fi
	if node "${FIXTURES}/verify.mjs" "$plan" "$actual" "$status"; then
		ok "${id} $(json "$plan" expect)"
	else
		bad "${id} $(json "$plan" expect)"
	fi
done

finish
