#!/usr/bin/env bash
# northstar approve: request the one plan-approval/1 of a published readiness-contract/2 generation,
# mode-aware (K3). Owner and reviewer lane are recorded once, in the approval record.
#
#   approve.sh --root R --handoff northstar-plan-<id> --owner O --reviewer-lane L [--mode M]
#   approve.sh --root R --handoff northstar-plan-<id> --confirm <digest>
#
# --mode default (when no --mode is given) resolves to the governing policy's default_mode, else agent:
#   agent    Autobahn issues the agent-self approval with the agent key (ai-catapult-agent-approval).
#   prompt   only when the user explicitly asks: prints the digest and anchor sha256; after the user
#            confirms that digest in chat, --confirm <digest> prints the in-session digest-echo record.
#   ssh-tag  optional: prints the ssh-keygen -Y sign and unsigned annotated tag commands for a human.
# Rule (d): bootstrap generations (every repository's first readiness-policy/2) need an in-session or
# ssh-tag approval; a v1 or absent live policy accepts no agent-self.
# It never signs with an approver key, never writes the anchor or a tag, and never reads a terminal.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$HERE/../autobahn/readiness-dependency-v2.json" ]]; then
  AUTOBAHN="$HERE/../autobahn"
else
  AUTOBAHN="$HERE/../../04-validate-handoff/autobahn"
fi
args=("$@")
explicit=0
for arg in "$@"; do
  case "$arg" in --mode|--mode=*|--confirm|--confirm=*) explicit=1 ;; esac
done
[[ "$explicit" -eq 1 ]] || args+=(--mode default)
exec bash "$AUTOBAHN/contract-run.sh" approval-request "${args[@]}" </dev/null
