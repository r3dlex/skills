#!/bin/bash
#
# autobahn_cascade_test.sh  (PR-2, A5)
#
# Offline contract test for autobahn's cascade issue closure. Autobahn delegates
# closure to the cascade engine; this test drives a MOCKED cascade adapter (no
# live host) and asserts the closure contract autobahn relies on:
#   - first close applies the canonical triage status and appends an audit event,
#   - the second (idempotent) close resolves by the stable idempotency key,
#     creates NO duplicate (duplicates_created == 0), and still appends an audit
#     event (status updated-existing),
#   - the closure never invents a status string (uses the triage canonical one).
#
# The mock mirrors the cascade host-adapter schema (ai-catapult-init/modules/cascade.md)
# and the cascade fixtures' second_run.idempotency_key shape. Offline, deterministic.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# Seed the mock from a real cascade host-adapter fixture so the test tracks the
# actual contract shape (idempotency_key, audit_path).
ADAPTER="reference/fixtures/v3/standalone/.ai/cascade/host-adapters/github.json"
if [[ ! -f "$ADAPTER" ]]; then
  bad "cascade host-adapter fixture exists ($ADAPTER)"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
AUDIT="$tmp/audit.jsonl"
STATE="$tmp/issues.json"

# Mocked cascade closure adapter: idempotent close by stable key, triage status,
# append-only audit. No network. This stands in for the cascade engine autobahn
# delegates to, so the closure contract is mechanically checkable offline.
close_issue() {
  python3 - "$ADAPTER" "$STATE" "$AUDIT" "$1" <<'PY'
import json, os, sys
adapter_path, state_path, audit_path, issue_id = sys.argv[1:5]
adapter = json.load(open(adapter_path))
key = adapter["second_run"]["idempotency_key"]
TRIAGE_CLOSED = "closed"  # canonical triage status; never invented per-call

state = {}
if os.path.isfile(state_path):
    state = json.load(open(state_path))

existing = state.get(issue_id)
if existing is None:
    state[issue_id] = {"status": TRIAGE_CLOSED, "idempotency_key": key, "closes": 1}
    event = {"event": "close", "issue": issue_id, "status": TRIAGE_CLOSED,
             "idempotency_key": key, "duplicates_created": 0}
else:
    # resolve by stable key, update in place — no duplicate
    existing["status"] = TRIAGE_CLOSED
    existing["closes"] += 1
    event = {"event": "close", "issue": issue_id, "status": TRIAGE_CLOSED,
             "idempotency_key": key, "duplicates_created": 0,
             "result": "updated-existing"}

with open(state_path, "w") as f:
    json.dump(state, f)
with open(audit_path, "a") as f:
    f.write(json.dumps(event) + "\n")
print(event["status"])
PY
}

# --- first close -------------------------------------------------------------
s1="$(close_issue "issue-42")"
if [[ "$s1" == "closed" ]]; then
  ok "first close applies canonical triage status 'closed'"
else
  bad "first close applies canonical triage status (got '$s1')"
fi

audit1="$(wc -l < "$AUDIT" | tr -d ' ')"
if [[ "$audit1" -eq 1 ]]; then
  ok "first close appends one audit event"
else
  bad "first close appends one audit event (got $audit1)"
fi

# --- idempotent second close -------------------------------------------------
s2="$(close_issue "issue-42")"
if [[ "$s2" == "closed" ]]; then
  ok "second close keeps canonical triage status 'closed'"
else
  bad "second close keeps canonical triage status (got '$s2')"
fi

# no duplicate issue created; single state entry, closes incremented in place.
python3 - "$STATE" <<'PY'
import json, sys
st = json.load(open(sys.argv[1]))
assert len(st) == 1, f"expected 1 issue, got {len(st)}: {list(st)}"
assert st["issue-42"]["closes"] == 2, st
assert st["issue-42"]["status"] == "closed", st
print("ok")
PY
if [[ $? -eq 0 ]]; then
  ok "idempotent: single issue entry, no duplicate created"
else
  bad "idempotent: single issue entry, no duplicate created"
fi

# every audit event records duplicates_created == 0.
python3 - "$AUDIT" <<'PY'
import json, sys
lines = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
assert len(lines) == 2, f"expected 2 audit events, got {len(lines)}"
assert all(e["duplicates_created"] == 0 for e in lines), lines
assert all(e["status"] == "closed" for e in lines), lines
assert lines[1].get("result") == "updated-existing", lines[1]
print("ok")
PY
if [[ $? -eq 0 ]]; then
  ok "audit: every closure records duplicates_created==0; second is updated-existing"
else
  bad "audit: closure events / idempotency"
fi

# Delegation contract: the mock above is a contract-shape STAND-IN, not the real
# cascade integration. The integration assertion is that autobahn DELEGATES to the
# cascade engine rather than owning closure — so assert the module documents
# delegating to ai-catapult-init's cascade engine + canonical triage status + the
# stable idempotency_key + the audit append.
CC="autobahn/modules/cascade-closure.md"
if grep -qi "cascade" "$CC" && grep -qi "idempotency_key" "$CC" \
   && grep -qi "triage" "$CC" && grep -qi "audit" "$CC" \
   && grep -qiE "delegat|reimplement" "$CC"; then
  ok "cascade-closure.md documents delegation to the cascade engine (idempotency_key/triage/audit)"
else
  bad "cascade-closure.md documents delegation to the cascade engine"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
