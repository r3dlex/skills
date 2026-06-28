# Cascade Issue Closure

Read when closing a goal's issue after its PR merges. Autobahn delegates to the
cascade engine (`init-ai-repo/modules/cascade.md`) and the `triage` state machine;
it reimplements neither the multi-repo orchestration nor the idempotency keying.

## What happens on merge

When a goal's PR merges, autobahn closes the goal's issue across the repos the
cascade scope covers:

1. Resolve the issue via the cascade stable `idempotency_key`
   (`init-ai-repo:<repo-id>:cascade`) — never by free-form lookup.
2. Apply the canonical `triage` status (e.g. closed/done) so issue state stays
   consistent across parent/child repos.
3. Append the closure to `.ai/cascade/audit.jsonl` and update the reconciliation
   report.

The cascade engine owns parent/child linking, host-adapter routing, and
host-policy safety for any externally visible mutation. Autobahn only requests the
closure and records the triage status.

## Idempotency

Closure is **idempotent**: re-running resolves the existing item by its stable key
and updates it in place (`status: "updated-existing"`, `duplicates_created: 0`)
rather than creating a duplicate. A second close of an already-closed issue is a
no-op that still appends an audit event — the contract that makes closure
re-runnable offline.

## Triage canonical status

Issue state changes go through `triage` so the closure status is the project's
canonical label and parent/child backlinks are preserved. Autobahn does not invent
a status string.

## Offline verification

The closure contract is provable against a mocked cascade host-adapter fixture
(the `local-markdown`/`github` adapter shapes): assert the second run created no
duplicate, the triage status was applied, and an audit event was appended — no
live host.

## Safety rules

- Never create a duplicate issue; resolve by the stable idempotency key.
- Externally visible closures still flow through host-policy confirmation.
- Record every closure as an audit event, even an idempotent no-op.
