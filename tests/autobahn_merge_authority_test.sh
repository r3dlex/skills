#!/bin/bash
#
# autobahn_merge_authority_test.sh  (PR-2, A4; C1)
#
# Drives autobahn/merge-authority.sh against MOCKED host-policy verdict fixtures
# (the same shape host-policy writes to .ai/host-policy/<host>/audit.jsonl) and
# asserts the fail-closed exit-code contract:
#   (a) approved verdict (mode=apply) + valid token -> merge          (exit 0)
#   (b) blocked / default verdict                    -> ready-for-human (exit 3)
#   (c) rejected verdict despite a token             -> fail closed     (exit 4)
#
# Critically, it asserts the adapter NEVER recomputes the token regex or admin
# rule — it consumes the mock's verdict verbatim. We prove this by feeding a
# token that does NOT match host-policy's ^ct-...$ regex but is marked approved
# by the (mocked) host-policy verdict: the adapter must still merge, because it
# trusts host-policy's decision rather than re-deriving it.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SCRIPT="autobahn/merge-authority.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

if [[ ! -f "$SCRIPT" ]]; then
  bad "merge-authority.sh exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# The adapter must NOT contain host-policy's rules (no re-encoding). Assert it
# carries neither the ct-token regex nor an admin matcher in EXECUTABLE code
# (comments may reference what host-policy owns; strip them before grepping).
code_only="$(sed -E 's/^[[:space:]]*#.*$//' "$SCRIPT")"
if printf '%s' "$code_only" | grep -Eq 'ct-\[0-9\]|\^ct-|\[0-9\]\{4\}\}?-\[0-9\]'; then
  bad "merge-authority does NOT re-encode the confirmation-token regex in code"
else
  ok "merge-authority does NOT re-encode the confirmation-token regex in code"
fi
if printf '%s' "$code_only" | grep -Eqi 'is[_-]?admin|admin[_-]?bypass|role *== *.admin'; then
  bad "merge-authority does NOT recompute the admin rule in code"
else
  ok "merge-authority does NOT recompute the admin rule in code"
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# (a) approved verdict from host-policy (mode=apply) + a token. Note the token
# deliberately does NOT match ^ct-...$ — proving the adapter consumes the
# verdict verbatim and does not re-validate the token format itself.
cat > "$tmp/approved.json" <<'JSON'
{
  "mode": "apply",
  "host": "github.com/example/repo",
  "confirmation_token": "HOSTPOLICY-MINTED-OPAQUE-TOKEN",
  "marker": "host-supported-bypass",
  "readback_status": "match"
}
JSON

# (b) blocked verdict (no confirmation), the host-policy default-stop marker.
cat > "$tmp/blocked.json" <<'JSON'
{
  "mode": "blocked",
  "host": "github.com/example/repo",
  "confirmation_token": null,
  "marker": "apply-blocked-no-confirmation"
}
JSON

# (b2) plain default dry-run verdict -> ready-for-human.
cat > "$tmp/dryrun.json" <<'JSON'
{
  "mode": "dry-run",
  "host": "github.com/example/repo",
  "confirmation_token": null,
  "marker": "dry-run"
}
JSON

# (c) host-policy REJECTED the apply despite a token present (e.g. non-admin or
# dry-run mismatch). The adapter must honor the rejection (fail closed).
cat > "$tmp/rejected.json" <<'JSON'
{
  "mode": "apply",
  "host": "github.com/example/repo",
  "confirmation_token": "ct-2026-06-28-001",
  "marker": "apply-rejected-non-admin"
}
JSON

run() { bash "$SCRIPT" --verdict "$1" >/dev/null 2>&1; echo $?; }

rc="$(run "$tmp/approved.json")"
if [[ "$rc" -eq 0 ]]; then
  ok "(a) approved verdict + token -> merge (exit 0)"
else
  bad "(a) approved verdict + token -> merge (got $rc)"
fi

rc="$(run "$tmp/blocked.json")"
if [[ "$rc" -eq 3 ]]; then
  ok "(b) blocked verdict -> ready-for-human (exit 3)"
else
  bad "(b) blocked verdict -> ready-for-human (got $rc)"
fi

rc="$(run "$tmp/dryrun.json")"
if [[ "$rc" -eq 3 ]]; then
  ok "(b2) dry-run/default verdict -> ready-for-human (exit 3)"
else
  bad "(b2) dry-run/default verdict -> ready-for-human (got $rc)"
fi

rc="$(run "$tmp/rejected.json")"
if [[ "$rc" -eq 4 ]]; then
  ok "(c) rejected verdict despite token -> fail closed (exit 4)"
else
  bad "(c) rejected verdict despite token -> fail closed (got $rc)"
fi

# Proof of delegation: the opaque (non-ct) token still merged in (a) because the
# adapter trusts host-policy's verdict rather than re-validating the token. If the
# adapter had re-encoded the regex, (a) would have been rejected.
out_a="$(bash "$SCRIPT" --verdict "$tmp/approved.json" 2>&1)"
if printf '%s' "$out_a" | grep -qi "merge"; then
  ok "adapter consumes host-policy verdict verbatim (opaque token merges)"
else
  bad "adapter consumes host-policy verdict verbatim (opaque token merges)"
fi

# Regression: the adapter must reach a decision with NO writable TMPDIR. A live
# Codex read-only-sandbox run surfaced that a mktemp/here-string dependency crashed
# the adapter ('mode: unbound variable' under set -u) instead of deciding.
#
# (d) STATIC guard — the real regression check. A TMPDIR override alone does NOT
# reproduce the bug (macOS mktemp falls back to /var/folders even when TMPDIR is
# invalid; the bug needs a fully read-only fs as in the Codex sandbox). So assert
# structurally that the EXECUTABLE code uses no temp-requiring construct: mktemp,
# a here-string (<<<), or process substitution (<(...)). This catches a future
# reintroduction on any platform.
if printf '%s' "$code_only" | grep -Eq 'mktemp|<<<|<\('; then
  bad "(d) merge-authority uses no temp-requiring construct (mktemp/<<</<()"
else
  ok "(d) merge-authority uses no temp-requiring construct (mktemp/<<</<()"
fi

# (d2) smoke: with TMPDIR pointed at a non-existent dir the approved verdict still
# merges (exit 0). Effective on Linux (CI); a no-op safety net on macOS.
rc="$(TMPDIR=/nonexistent-readonly-$$ bash "$SCRIPT" --verdict "$tmp/approved.json" >/dev/null 2>&1; echo $?)"
if [[ "$rc" -eq 0 ]]; then
  ok "(d2) approved verdict merges with TMPDIR=/nonexistent (smoke)"
else
  bad "(d2) approved verdict must merge with TMPDIR=/nonexistent (got $rc)"
fi

# (e) a malformed marker containing whitespace must NOT be truncated into a merge:
# it must fail closed (the unsafe direction is merging an intended rejection).
cat > "$tmp/reject-spaced.json" <<'JSON'
{ "mode": "apply", "confirmation_token": "ct-2026-06-28-009", "marker": "apply-rejected non-admin" }
JSON
rc="$(run "$tmp/reject-spaced.json")"
if [[ "$rc" -eq 4 ]]; then
  ok "(e) rejection marker with whitespace fails closed (exit 4), not merged"
else
  bad "(e) whitespace rejection marker must fail closed (got $rc)"
fi

# Anchor the verdict SHAPE to a committed host-policy fixture (not only inline
# mocks), so drift in the normalized-verdict object is caught in CI.
COMMITTED_VERDICT="reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json"
if [[ -f "$COMMITTED_VERDICT" ]]; then
  rc="$(run "$COMMITTED_VERDICT")"
  if [[ "$rc" -eq 0 ]]; then
    ok "committed host-policy verdict fixture -> merge (exit 0); shape anchored"
  else
    bad "committed host-policy verdict fixture -> merge (got $rc)"
  fi
else
  bad "committed host-policy verdict fixture exists ($COMMITTED_VERDICT)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
