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
#
# We capture the reader's output into a variable (no temp file): a fail-closed
# adapter must not depend on a writable TMPDIR, and must never crash ambiguously
# if one is unavailable. The reader is passed via `python3 -c` (not a heredoc
# inside $(...), which macOS bash 3.2 cannot parse) and uses only double quotes
# internally so it nests safely in this single-quoted shell string. If the reader
# cannot run at all, we FAIL CLOSED (exit 4) rather than leaving the decision
# variables unbound.
mode="" has_token="" marker=""
_reader='
import json, sys
try:
    v = json.load(open(sys.argv[1]))
except Exception:
    print("PARSE_ERROR|-|-"); sys.exit(0)
mode = v.get("mode", "") or "-"
# host-policy emits the token itself; we only note presence, never re-validate it.
token = v.get("confirmation_token")
has_token = "yes" if (isinstance(token, str) and token != "") else "no"
# outcome marker emitted by host-policy; rejection markers begin apply-rejected-.
marker = v.get("marker") or v.get("status") or "-"
# Pipe-delimited so a marker containing whitespace survives intact (a space-split
# marker could lose its apply-rejected- prefix and merge in the UNSAFE direction).
print("|".join([str(mode), has_token, str(marker)]))
'
if ! verdict_fields="$(python3 -c "$_reader" "$VERDICT")"; then
  echo "fail-closed: could not evaluate host-policy verdict '$VERDICT' (reader failed); not merging" >&2
  exit 4
fi
# Split on '|' (not whitespace) without `read <<<`, whose here-string also needs a
# writable TMPDIR under bash 3.2. Restoring IFS afterward keeps marker intact even
# if it contains spaces, so a malformed marker can never be truncated into a merge.
_saved_ifs="$IFS"
IFS='|'
# shellcheck disable=SC2086
set -- $verdict_fields
IFS="$_saved_ifs"
mode="${1:-}" has_token="${2:-}" marker="${3:-}"

if [[ "$mode" == "PARSE_ERROR" ]]; then
  echo "merge-authority: could not parse host-policy verdict '$VERDICT'" >&2
  exit 2
fi

# Rejection markers host-policy itself emits. If host-policy rejected, we honor it
# (fail closed) even when a token is present — we do not second-guess the policy.
# The broad *reject* catch is defense-in-depth: any rejection-shaped marker (even
# an out-of-contract / malformed one) fails closed rather than risking a merge.
case "$marker" in
  apply-rejected-*|*reject*)
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
