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

The adapter takes a **pre-normalized host-policy verdict object** and emits the
merge/ready-for-human/fail-closed outcome. The normalized shape is top-level
`mode` + `confirmation_token` + outcome `marker`. Normalizing the host-policy
decision into this object — in particular projecting the host-policy audit line's
`apply_results[].status` and the `apply-rejected-*`/`apply-blocked-*` markers
(owned by `init-ai-repo/modules/host-policy-automation.md`) onto the top-level
`marker` — is the **host-policy consumer's** responsibility (the step that invokes
the host-policy decision), not this adapter's. The adapter never reads
`apply_results[]` or re-derives a marker.

Tests drive it against inline mocks for each marker **and** a committed verdict
fixture (`reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json`)
so the normalized shape is anchored to a real artifact. The opaque-token case (a
non-`ct-` token that still merges on an approved verdict) proves the adapter
consumes the verdict verbatim and never recomputes the regex or admin rule.

## Safety rules

- Default is **ready-for-human**; merge only on an approved verdict + valid token.
- A valid token the policy still rejects fails closed (never merges).
- Re-encode no host-policy rule; consume the verdict as-is.
