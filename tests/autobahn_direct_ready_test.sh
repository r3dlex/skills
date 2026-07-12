#!/bin/bash

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

READINESS="04-validate-handoff/autobahn/readiness-check.sh"
PREREQ="04-validate-handoff/autobahn/prereq-check.sh"
FIXTURE="reference/fixtures/v3/standalone"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_missing_value() {
  local output rc
  output="$(python3 - "$READINESS" <<'PY'
import subprocess, sys
try:
    result = subprocess.run(["bash", sys.argv[1], "--goal"], capture_output=True, text=True, timeout=2)
except subprocess.TimeoutExpired:
    print("124|")
else:
    print(f"{result.returncode}|{result.stderr}")
PY
)"
  rc="${output%%|*}"
  if [[ "$rc" -eq 2 && "$output" == *"usage:"* ]]; then
    ok "readiness-check missing --goal value returns usage without hanging"
  else
    bad "readiness-check missing --goal value returns usage without hanging (result: $output)"
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp -R "$FIXTURE/." "$tmp/repo"
rm -f "$tmp/repo/.ai/handoff/"northstar-*.md 2>/dev/null
python3 - "$tmp/repo/.ai/workflows/repo-workflow.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["optional_branches"] = [b for b in m.get("optional_branches", [])
                          if not str(b.get("id", "")).startswith("northstar-handoff-")]
json.dump(m, open(p, "w"), indent=2)
PY

cat > "$tmp/ready.json" <<'JSON'
{
  "id": "guardrail-parser-fix",
  "implementation_ready": true,
  "context": "Markdown-wrapped JSON reaches the strict response parser.",
  "root_causes": ["The parser sends fenced JSON directly to json.loads."],
  "evidence": ["A captured response fixture reproduces the parse failure."],
  "solutions": ["Strip one optional JSON fence before decoding."],
  "acceptance_criteria": ["Fenced and plain JSON both parse through the public interface."],
  "scope": ["guardrail/response_parser.py", "tests/test_response_parser.py"],
  "verification": ["pytest tests/test_response_parser.py"],
  "issue_ref": "local:work-intake/guardrail-parser-fix",
  "coverage_percent": 18
}
JSON

cat > "$tmp/vague.json" <<'JSON'
{
  "id": "vague-fix",
  "implementation_ready": true,
  "context": "Something is wrong.",
  "solutions": ["Fix it."],
  "acceptance_criteria": ["It works."]
}
JSON

assert_missing_value

if bash "$READINESS" --goal "$tmp/ready.json" >/dev/null 2>&1; then
  ok "evidence-complete goal is implementation-ready"
else
  bad "evidence-complete goal is implementation-ready"
fi

if bash "$READINESS" --goal "$tmp/vague.json" >/dev/null 2>&1; then
  bad "vague goal fails closed"
else
  ok "vague goal fails closed"
fi

if bash "$PREREQ" --root "$tmp/repo" --goal "$tmp/ready.json" >/dev/null 2>&1; then
  ok "autobahn accepts direct-ready goal without northstar handoff"
else
  bad "autobahn accepts direct-ready goal without northstar handoff"
fi

if bash "$PREREQ" --root "$tmp/repo" --goal "$tmp/vague.json" >/dev/null 2>&1; then
  bad "autobahn rejects vague direct goal"
else
  ok "autobahn rejects vague direct goal"
fi

# An explicit direct goal must be validated even when an unrelated handoff exists.
bash 02-govern-plan/northstar/handoff-write.sh --root "$tmp/repo" \
  --spec "docs/specifications/ACTIVE/direct-ready-test.md" --slug "other-work" >/dev/null 2>&1
if bash "$PREREQ" --root "$tmp/repo" --goal "$tmp/vague.json" >/dev/null 2>&1; then
  bad "explicit vague goal cannot fall through to an existing handoff"
else
  ok "explicit vague goal cannot fall through to an existing handoff"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
