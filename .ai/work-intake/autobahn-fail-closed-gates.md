---
name: autobahn-fail-closed-gates
status: validation-pending
---

# Work intake: Autobahn fail-closed gates

Repair local CI execution, verification command containment, and explicit merge-policy verdict approval in one bounded delivery.

- Goal: `.ai/handoff/autobahn-goals/autobahn-fail-closed-gates.json`
- Proposed successor specification: `docs/specifications/ACTIVE/autobahn-fail-closed-gates-ts-only.md`; the original flat goal/spec/evidence are historical inputs, not transferred readiness.
- Evidence: `.ai/evidence/autobahn-fail-closed-gates.json`
- Acceptance: execute supported local checks; reject unsupported or unsafe inputs before execution; require explicit matching bypass approval; retain separate exact-head hosted CI and independent review.
- Current state: implementation/review and final validation pending. Coverage is unmeasured; a conservative zero policy input selects legacy-safe TDD, not a claimed coverage measurement. The seven functional criteria remain, but TS implementation admission is blocked until separately qualified ci-gate.ts/local-ci.ts/run-gates.ts/merge-authority.ts, corresponding TS tests, build/discovery/Node-argv support and governed frozen-consumer retirement are bound. The bound TSF-01..08 contract requires no Python/handwritten JS/shell final source or tool dependency and approved Python-absent full build/tests/CI/package/install/host smoke with negative controls. Commands/evidence remain proposed; historical checks supply no changed-source approval.

One goal, one PR. These records confer no merge or policy-change authority and contain no closure claim.

## TypeScript requirement binding

- Preparation: `r3dlex/ai-tool-workspace:.omc/handoffs/ach-20261004/artifacts/consolidation-20261005/typescript-only-plan-alignment-20261008/FINAL-STATE.md` — 6603 bytes; SHA256 `3ec2814054f690631a8145ff9f6baebbf8c4c2a354c507be2ddfa3043af453e2`.
- Proposed canonical home: `r3dlex/ai-tool-workspace:docs/specifications/ACTIVE/typescript-only-final-state.md`. Adoption is pending. Canonical publication must bind its actual reviewed revision or retain this unresolved adoption dependency.
- Historical observations retain their original epoch. Proposed TypeScript sources and commands require their separately governed introducing deliveries; this working-plan correction supplies no implementation admission.
