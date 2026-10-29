# Local issue: E6 freeze-owner preparation

- Traceability: `issue:skills:e6-skills-ts-02-owner-prep` (local-first; no hosted issue created).
- Category `enhancement`; state `needs-info` until the current-main scope, exceptions and supplier implementation edge are independently reviewed. Implementation/review owners `unassigned`.
- Plan/goal: `e6-skills-ts-02-owner-prep` / `e6-sk-02-owner-relabel`. One distinct future implementation PR; planning changes do not edit the ledger.

## Work to admit later

Retain the historical freeze owner, add the new owner, relabel exactly five eligible ledger rows and update TS-generated outputs, focused test, fresh red/green evidence and same-PR local-CI pins. The literal paths and testable boundaries are in `docs/specifications/ACTIVE/e6-skills-ts-02-owner-prep.md` and the reviewed goal record. Do not port v1 or touch the D13 checker here.

## Blocking edges

- Publish only after the supplier's **planning PR** merges, from a newly observed current-main base with independently qualified old E6 and XSKP held-scope exceptions and a successful publisher gate.
- Dispatch/implement the shared local-CI edit only after the supplier's **implementation merge** is on `origin/main`; otherwise the cross-plan path remains reserved. This preparation needs its own human approval, red/green, independent review and CI.
- Publish the replacement-port plan only after both supplier and preparation **implementation** merges. #139 and #155 do not supply those merges or approvals.

Knowledge kind: `plan`; `unpublished: no-registry` for the optional knowledge catalogue. The handoff passed its real planning publication gate; registration alone is neither a planning-PR merge nor a human generation-bound approval. Verify both separately before implementation.
