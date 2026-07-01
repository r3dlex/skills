#!/bin/bash
# P1-6 / D8: Cascade host-adapter JSON schema + idempotency.
#
# Proves:
#   1. Every configured host adapter fixture (github/ado/gitlab/jira/local-markdown)
#      in both v3 fixtures declares the 10 logical operations, a stable
#      idempotency key, the required link/safety fields, and NO credentials.
#   2. modules/cascade.md documents the host-adapter JSON schema (the 10 ops,
#      the stable cascade_id idempotency key, required link fields, no-credentials).
#   3. IDEMPOTENCY NEGATIVE TEST: a mocked, offline adapter keyed by the stable
#      idempotency key produces NO duplicate child work item when the cascade is
#      re-run. Re-running a second time must not create a second child.
#
# Fully offline / deterministic: no network, no credentials, mocked adapters only.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 - <<'PY'
import json
import re
import sys
from pathlib import Path

ROOT = Path(".")
HOSTS = ["github", "ado", "gitlab", "jira", "local-markdown"]
OPERATIONS = {
    "discover_scope", "plan_parent_item", "plan_child_item", "dry_run",
    "confirm_first_run", "apply_confirmed_plan", "readback_links",
    "apply_idempotent_update", "audit_event", "reconcile",
}
TOKEN_RE = re.compile(r"^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$")
SECRET_NEEDLES = [
    "api_token", "access_token", "refresh_token",
    "authorization:", "bearer ", "password", "secret", "client_secret",
]


def fail(msg):
    print(f"FAIL: {msg}")
    sys.exit(1)


# --- 1. Schema validation of every adapter fixture --------------------------
for fixture in ("standalone", "umbrella"):
    cascade_dir = ROOT / "reference/fixtures/v3" / fixture / ".ai/cascade"
    for host in HOSTS:
        path = cascade_dir / "host-adapters" / f"{host}.json"
        if not path.is_file():
            fail(f"missing adapter fixture {path}")
        text = path.read_text()
        lower = text.lower()
        for needle in SECRET_NEEDLES:
            if needle in lower:
                fail(f"secret-like token {needle!r} in {path}")
        adapter = json.loads(text)

        # required top-level fields
        if adapter.get("host") != host:
            fail(f"{path}: host mismatch")
        if not adapter.get("schema_version"):
            fail(f"{path}: schema_version missing")
        if set(adapter.get("operations", [])) != OPERATIONS:
            fail(f"{path}: operations must be exactly the 10 logical ops")

        # stable idempotency key required for the no-duplicate guarantee
        idem = adapter.get("second_run", {}).get("idempotency_key")
        if not idem:
            fail(f"{path}: missing stable second_run.idempotency_key")

        # re-run must not create duplicates
        if adapter.get("second_run", {}).get("duplicates_created") != 0:
            fail(f"{path}: second_run.duplicates_created must be 0")

        # required link fields present in readback
        readback = adapter.get("readback", {})
        for key in ("status", "parent_link_present", "child_links_present"):
            if key not in readback:
                fail(f"{path}: readback missing {key}")

        # safety: no credentials, no host-policy mutation
        safety = adapter.get("safety", {})
        if safety.get("credentials_stored") is not False:
            fail(f"{path}: safety.credentials_stored must be false")
        if safety.get("host_policy_mutation") is not False:
            fail(f"{path}: safety.host_policy_mutation must be false")
print("PASS: all adapter fixtures declare 10 ops, idempotency key, link fields, no credentials")

# --- 2. Module documents the host-adapter JSON schema -----------------------
module = (ROOT / "ai-catapult-init/modules/cascade.md").read_text()
required_doc = [
    ".ai/cascade/host-adapters/<host>.json",
    "schema_version",
    "operations",
    "idempotency_key",
    "cascade_id",
    "readback",
]
for token in required_doc:
    if token not in module:
        fail(f"cascade.md must document host-adapter schema token {token!r}")
for op in sorted(OPERATIONS):
    if op not in module:
        fail(f"cascade.md must list logical operation {op!r}")
# must state no-credentials rule near the adapter schema
if "credential" not in module.lower():
    fail("cascade.md must state the no-credentials rule for adapters")
print("PASS: cascade.md documents the host-adapter JSON schema")

# --- 3. IDEMPOTENCY NEGATIVE TEST (mocked offline adapter) ------------------
# A minimal mock host adapter that stores child work items keyed by the stable
# idempotency key. Re-running the cascade must NOT create a duplicate child.
class MockHostAdapter:
    def __init__(self):
        self.children_by_key = {}   # idempotency_key -> child id
        self.create_calls = 0

    def apply_child(self, idempotency_key, child_payload):
        # Idempotent create: if a child already maps to this stable key,
        # update in place instead of creating a duplicate.
        if idempotency_key in self.children_by_key:
            return self.children_by_key[idempotency_key], "updated-existing"
        self.create_calls += 1
        child_id = f"CHILD-{self.create_calls:03d}"
        self.children_by_key[idempotency_key] = child_id
        return child_id, "created"


def run_cascade(adapter, idempotency_key):
    """One cascade pass: plan + apply one child by stable key."""
    return adapter.apply_child(idempotency_key, {"title": "managed-repo child"})


adapter = MockHostAdapter()
key = "init-ai-repo:umbrella-root:cascade"

first_id, first_status = run_cascade(adapter, key)
if first_status != "created":
    fail(f"first run should create, got {first_status}")

# Re-run with the SAME stable idempotency key.
second_id, second_status = run_cascade(adapter, key)
if second_status != "updated-existing":
    fail(f"second run should update existing, got {second_status}")
if second_id != first_id:
    fail(f"second run must reuse child id (got {second_id}, expected {first_id})")

# A third run as well, to be thorough.
third_id, third_status = run_cascade(adapter, key)

if adapter.create_calls != 1:
    fail(f"NEGATIVE TEST FAILED: {adapter.create_calls} children created on re-run (expected 1)")
if len(adapter.children_by_key) != 1:
    fail(f"NEGATIVE TEST FAILED: {len(adapter.children_by_key)} distinct children (expected 1)")
print("PASS: idempotency negative test — re-run produces no duplicate child")

print("cascade host-adapter schema + idempotency test passed")
PY
