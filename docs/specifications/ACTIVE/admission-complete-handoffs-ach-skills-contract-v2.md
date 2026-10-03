# Contract v2 (`skills`, plan `ach-skills-contract-v2`)

ID: `ACH-20261002`, plan `ach-skills-contract-v2`
Status: **Planning copy; execution unauthorized**
Execution authorization: **none**. Registration, visibility or discovery never grants approval, readiness or execution authority.

## Umbrella authority

This plan-scoped specification restates one plan of the umbrella specification
`ACH-20261002` in `r3dlex/ai-tool-workspace` (`docs/specifications/ACTIVE/admission-complete-handoffs.md`),
pinned at sha256 `fded0858d0c3aa2ba06cdc9b6d716053cb92dd82a3afa22e6a13774e30f6ddd5`. Decisions U1–U3, R1–R4,
G1–G5, K1–K2 and O1–O12, the glossary, the normative contract v2 and the
umbrella acceptance criteria AC-1 to AC-9 are defined there. If this copy and
the umbrella spec disagree, the umbrella spec at the pinned sha wins and this
plan's preparation is blocked until a new planning copy is published.

## Plan

### Contract v2 (`skills`, plan `ach-skills-contract-v2`)

The v2 contract (bootstrapped once on v1): a pure `readiness_contract_v2.py`, a
pinned `observer.py`, signed approval verification, the merge certificate,
merge refusal and the admin rule, observed identity, the context builder,
admission-complete Northstar, adoption tooling, the e2e fixture and negative
suite, and P5's migration to v2.

## Bootstrap (R4)

> **R4. Bootstrap.** One last v1 policy rollover, scoped only to skills goal
> ACH-S-01, which displaces skills' P5 v1 policy; P5 migrates to v2 later. After
> ACH-S-01 merges, the remaining skills goals are republished as a v2 generation
> and use the new path.

Only `ACH-S-01` is published on v1, once, as a one-goal readiness-v1 generation
with all three stages `ready`. Its goal revision is pinned by the rollover
policy, so the generation stays frozen until `ACH-S-01` merges; any edit needs a
new generation, a new policy pin and new contexts. `ACH-S-02` to `ACH-S-06` are
published once, in this plan's v2 generation.

## Goals

The authoritative per-goal scope, acceptance, verification and readiness of the
v1 generation live in the published
`.ai/handoff/readiness-v1/ach-skills-contract-v2/<generation>/goals.json` in
this repository, registered in `.ai/workflows/northstar-readiness-v1.json`.
Cross-repository edges to the ai-catapult, root and ai-factory plans are
preparation blockers observed at admission, never goal dependencies.
