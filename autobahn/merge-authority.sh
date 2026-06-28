#!/bin/bash
#
# autobahn/merge-authority.sh  (PR-2, A4; C1 thin adapter)
#
# THIN ADAPTER over the init-ai-repo host-policy decision. It re-encodes NONE of
# host-policy's rules:
#   - NOT the confirmation-token regex (^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$),
#   - NOT the admin-bypass / non-admin matrix,
#   - NOT the audit format.
# Those live in init-ai-repo/modules/host-policy-automation.md.
#
# The adapter CONSUMES a host-policy verdict (the object host-policy produced —
# the same shape it writes to .ai/host-policy/<host>/audit.jsonl) verbatim, and
# wraps ONLY the fail-closed exit-code contract that maps a verdict to a merge:
#
#   host-policy "mode": apply (approved) + token present -> merge          (exit 0)
#   default / blocked / unauthorized / non-admin verdict -> ready-for-human (exit 3)
#   approved-shape but policy rejects (apply-rejected-*)  -> fail closed     (exit 4)
#
# The adapter reads the verdict's OWN approved/blocked/rejected signal and the
# token it already minted; it does not parse, regex, or re-validate the token
# string, and it does not recompute who is an admin.
#
# Usage:
#   merge-authority.sh --verdict <host-policy-verdict.json>
# Output:
#   prints the decision (merge | ready-for-human | fail-closed) + reason
# Exit:
#   0  authorized: merge
#   2  usage error
#   3  not authorized: ready-for-human (default / blocked / unauthorized)
#   4  fail closed: token present but host-policy rejected
#

set -uo pipefail

command -v python3 >/dev/null 2>&1 || { echo "merge-authority: python3 is required (fail-closed prerequisite)." >&2; exit 2; }

VERDICT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    --verdict=*) VERDICT="${1#--verdict=}"; shift ;;
    *) echo "usage: merge-authority.sh --verdict <host-policy-verdict.json>" >&2; exit 2 ;;
  esac
done

if [[ -z "$VERDICT" || ! -f "$VERDICT" ]]; then
  echo "merge-authority: --verdict file required and must exist" >&2
  exit 2
fi

# Consume the host-policy verdict verbatim. We read three signals it ALREADY
# decided: its mode, whether it carries a confirmation_token, and its outcome
# marker. We do NOT re-validate the token or recompute admin status.
_tmp_verdict="$(mktemp)"
python3 - "$VERDICT" > "$_tmp_verdict" <<'PY'
import json, sys
try:
    v = json.load(open(sys.argv[1]))
except Exception:
    print("PARSE_ERROR - -"); sys.exit(0)
mode = v.get("mode", "") or "-"
# host-policy emits the token itself; we only note presence, never re-validate it.
token = v.get("confirmation_token")
has_token = "yes" if (isinstance(token, str) and token != "") else "no"
# host-policy's own outcome marker; rejection markers begin apply-rejected-.
marker = v.get("marker") or v.get("status") or "-"
print(mode, has_token, marker)
PY
read -r mode has_token marker < "$_tmp_verdict"
rm -f "$_tmp_verdict"

if [[ "$mode" == "PARSE_ERROR" ]]; then
  echo "merge-authority: could not parse host-policy verdict '$VERDICT'" >&2
  exit 2
fi

# Rejection markers host-policy itself emits. If host-policy rejected, we honor it
# (fail closed) even when a token is present — we do not second-guess the policy.
case "$marker" in
  apply-rejected-*)
    echo "fail-closed: host-policy rejected the apply (marker=$marker); not merging" >&2
    exit 4
    ;;
esac

# Approved path: host-policy's own verdict is mode=apply AND it minted a token.
if [[ "$mode" == "apply" && "$has_token" == "yes" ]]; then
  echo "merge: host-policy authorized the apply (mode=apply, token present); merging"
  exit 0
fi

# Everything else (dry-run, blocked, missing token, unauthorized) stops at human.
echo "ready-for-human: host-policy verdict not an authorized apply (mode=$mode, token=$has_token, marker=$marker); not merging" >&2
exit 3
