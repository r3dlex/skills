# Work Item: E6 successor 02 (`skills`, plan `e6-skills-ts-02`)

- **Traceability node:** `issue:skills:e6-skills-ts-02`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** `issue:aitool-root:e6-skills-legacy-ts-conversion` (umbrella intake; skills prd `prd:skills:e6-skills-legacy-ts`)
- **Delivery posture:** one readiness-contract/2 generation (`e6-skills-ts-02`) with one goal, `e6-sk-02-v1-port`. It is the successor of `e6-sk-01-py-leaf` and does not replace plan `e6-skills-legacy-ts` or plan `e6-skills-ts-01`. Dependency edge: names `e6-sk-01-py-leaf`'s merge commit `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, which is `origin/main` (PR #137 squash, parent `6255da27afeee8c2e9f3582793e74fbc5ff68bf3`, head `e353a388d3445f02ee7092e33c4d7344c612d9bb`, merged 2026-10-13T21:18:15Z; the head is not a pin). The chain predecessor `e6-sk-00-ledger` merged as `a389a52528d58ba209203f582e6735c3e40fa145` (PR #135) and is an ancestor. The bundle `dependencies` array is empty because a bundle cannot depend on a goal of another plan. Planning complete is not implementation readiness. Policy digest `d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962` voids old approvals. A fresh own-plan approval is still required before implementation admission. This record grants no approval and no dispatch.
- **Hard boundaries:**
  - Do not edit the bound parent spec, the parent generation, or PR #137.
  - Do not implement `e6-sk-02-v1-port` from this planning record.
  - Do not treat a deferred planning-PR merge as the publication rule. The predecessor merge commit is already `origin/main`.
  - Do not mint an approval tag in this lane. Fresh own-plan approval is a later admission, not this lane.
  - Do not invent `e6-sk-02-py-lib` or `e6-sk-02-py-leaf`.
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created. Tracker writes were not authorized.

## Traceability

Local markdown only. A graph node is added only if the publisher writes a generation and a planning PR is opened. Until then this file is the local issue.
