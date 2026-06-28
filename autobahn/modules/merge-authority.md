# Merge Authority — Host-Policy Thin Adapter (C1)

Read when deciding whether a goal's PR may merge. `merge-authority.sh` is a
**thin adapter** over the init-ai-repo host-policy decision. It re-encodes none of
host-policy's rules.

## What the adapter does NOT own

These are owned by `init-ai-repo/modules/host-policy-automation.md` and must NOT
be re-encoded in the adapter:

- the confirmation-token regex `^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$`,
- the admin-bypass / non-admin-auto-approval-disallowed matrix,
- the audit format (`.ai/host-policy/<host>/audit.jsonl`) and verdict markers
  (`apply-blocked-no-confirmation`, `apply-rejected-non-admin`,
  `apply-rejected-dry-run-mismatch`).

The adapter **invokes the host-policy decision**, reads back its verdict +
`confirmation_token` verbatim, and decides nothing about policy itself.

## What the adapter DOES own

Only the fail-closed exit-code contract that maps a host-policy verdict to a merge
action:

| Host-policy verdict | Token | Adapter decision | Exit |
| --- | --- | --- | --- |
| `mode: apply` (approved) | valid, present | **merge** | 0 |
| default / unauthorized / `mode: blocked` / non-admin | any | **ready-for-human**, no merge | non-zero |
| approved-shape but policy rejects (e.g. `apply-rejected-*`) | present | **fail closed**, no merge | non-zero |

The token's validity is whatever host-policy reports; the adapter does not parse
or re-validate the token string. It consumes the verdict's own
approved/rejected/blocked signal.

## Honoring the merge protocol

Merge is gated by the feedback merge protocol (reviewer APPROVE + remote CI +
local CI green, all comments resolved — see review-loop.md) **before** the
authority decision. The adapter is the final gate, not a substitute for the
review/CI gate.

## How it is invoked + tested

The adapter takes a host-policy verdict input (a verdict object/file the
host-policy decision produced) and emits the merge/ready-for-human/fail-closed
outcome. Tests drive it against a **mocked verdict fixture** for each marker and
assert the adapter never recomputes the regex or admin rule — it consumes the
mock's verdict verbatim.

## Safety rules

- Default is **ready-for-human**; merge only on an approved verdict + valid token.
- A valid token the policy still rejects fails closed (never merges).
- Re-encode no host-policy rule; consume the verdict as-is.
