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

run_consumer_check() {
	local plan="$1" id="$2" index="$3"
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
const check=plan.checks[Number(process.argv[3])];
fs.writeFileSync(process.argv[2],JSON.stringify({case:plan.case,label:check.label,environment:check.env,kind:"consumer",expect:check.expect}));
' "$plan" "$sub" "$index"
	(
		cd "$cwd" || exit 1
		node "${FIXTURES}/invoke.mjs" "$plan" "$CHECKER" "$index"
	) >"$actual" 2>"${WORK}/${id}.err${index}"
	status=$?
	if node "${FIXTURES}/verify.mjs" "$sub" "$actual" "$status"; then
		ok "${id}/${label} exit $want"
	else
		bad "${id}/${label} exit $want"
	fi
}

run_consumer_checks() {
	local plan="$1" id="$2"
	local count index
	count="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).checks.length))' "$plan")"
	index=0
	while [ "$index" -lt "$count" ]; do
		run_consumer_check "$plan" "$id" "$index"
		index=$((index + 1))
	done
	if [ "$id" = "C15" ]; then
		if node "${FIXTURES}/integration.mjs" "$plan"; then
			ok "C15 actual suite propagation, present-red and absent-reported"
		else
			bad "C15 suite propagation"
		fi
	fi
}

check_consumer_files() {
	local contract="${WORK}/consumers-contract.json" evidence
	if ! node "$CHECKER" --contract >"$contract"; then
		bad "consumer contract cannot be read"
		return
	fi
	while IFS= read -r evidence; do
		if [ -e "$evidence" ] || [ -L "$evidence" ]; then
			if node "$CHECKER" --consumer-check "$evidence"; then
				ok "consumer $evidence mechanical consistency only; readiness unready"
			else
				bad "consumer $evidence"
			fi
		else
			echo "  ABSENT: consumer $evidence; unrelated-main check skipped, no consumer readiness"
		fi
	done < <(node -e 'for (const path of JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).consumers) console.log(path)' "$contract")
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
WORK="$(cd "$WORK" && pwd -P)"
if [ "${1-}" = "--consumer-files-only" ]; then
	check_consumer_files
	finish
	exit $?
fi
if node "${FIXTURES}/verifier-test.mjs" "${FIXTURES}/verify.mjs" "$WORK"; then
	ok "verifier rejects empty and null stdout even at the expected exit"
else
	bad "verifier accepted a missing result envelope"
fi
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
  spec_sha256_lineage: "151f2d22541ede2819338f75536a9d11b5d18beb9820a6e51f55894d4f286839",
  superseded_tool_sha256: [],
  argv_template: ["bash","04-validate-handoff/autobahn/contract-run.sh","<operation>","--root","<target.root>","--target","<target.target>","--plan","<plan_id>"],
};
for (const [key, expected] of Object.entries(want)) {
  if (JSON.stringify(value[key]) !== JSON.stringify(expected)) { console.error(key); process.exit(1); }
}
if (!Array.isArray(value.argv_template) || value.argv_template.length !== 9) process.exit(1);
if (!/^[0-9a-f]{64}$/.test(value.spec_sha256_lineage)) process.exit(1);
const digest=require("crypto").createHash("sha256").update(fs.readFileSync(process.argv[2])).digest("hex");
if (value.tool_sha256 !== digest) process.exit(1);
' "$contract_out" "$CHECKER"; then
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

CASES="$(node "${FIXTURES}/build.mjs" --list)"

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
	node "${FIXTURES}/invoke.mjs" "$plan" "$CHECKER" >"$actual" 2>"${WORK}/${id}.err"
	status=$?
	if node "${FIXTURES}/verify.mjs" "$plan" "$actual" "$status"; then
		ok "${id} $(json "$plan" expect)"
	else
		bad "${id} $(json "$plan" expect)"
	fi
done

check_consumer_files
finish
