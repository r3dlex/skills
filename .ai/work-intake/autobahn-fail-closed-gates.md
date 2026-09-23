---
name: autobahn-fail-closed-gates
status: validation-pending
---

# Work intake: Autobahn fail-closed gates

Repair local CI execution, verification command containment, and explicit merge-policy verdict approval in one bounded delivery.

- Goal: `.ai/handoff/autobahn-goals/autobahn-fail-closed-gates.json`
- Specification: `docs/specifications/ACTIVE/autobahn-fail-closed-gates.md`
- Evidence: `.ai/evidence/autobahn-fail-closed-gates.json`
- Acceptance: execute supported local checks; reject unsupported or unsafe inputs before execution; require explicit matching bypass approval; retain separate exact-head hosted CI and independent review.
- Current state: implementation/review and final validation pending. Coverage is unmeasured; a conservative zero policy input selects legacy-safe TDD, not a claimed coverage measurement. The concrete defect and acceptance contract are implementation-ready; red/green evidence and final delivery gates remain pending.

One goal, one PR. These records confer no merge or policy-change authority and contain no closure claim.
