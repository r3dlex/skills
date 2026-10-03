# Contract v2 (`skills`, plan `ach-skills-contract-v2`, generation 2)

ID: `ACH-20261002`, plan `ach-skills-contract-v2`
Status: **Planning copy; execution unauthorized**
Execution authorization: **none**. Registration, visibility or discovery never grants approval, readiness or execution authority.

## Umbrella authority

This plan-scoped specification restates one plan of the umbrella specification
`ACH-20261002` in `r3dlex/ai-tool-workspace` (`docs/specifications/ACTIVE/admission-complete-handoffs.md`),
pinned at sha256 `fded0858d0c3aa2ba06cdc9b6d716053cb92dd82a3afa22e6a13774e30f6ddd5`. Decisions U1–U3, R1–R4,
G1–G5, K1–K2 and O1–O12, the glossary, the normative contract v2 and the
umbrella acceptance criteria AC-1 to AC-9 are defined there.

If this copy and the umbrella spec disagree, the umbrella spec at the pinned sha
wins, with one exception: plan amendment K3 below. This plan carries K3 by user
decision until the umbrella spec records it. Any other disagreement blocks this
plan's preparation until a new planning copy is published.

This is the planning copy for the plan's `readiness-contract/2` generation
(`ACH-S-02` to `ACH-S-06`). The first copy,
`admission-complete-handoffs-ach-skills-contract-v2.md` (sha256
`f588f9b02370e4a3b5d80a708f7bc92a05ddc8f704c30e25f34ad691af36f3a9`), stays
byte-frozen, because the merged readiness-v1 generation of `ACH-S-01` pins it.

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

- `ACH-S-01` was published once on v1. It merged as `r3dlex/skills#97` at
  `f6be8346c1254fa2fc12ad853b2bacd0e6c1056e`.
- Its completion is a B5-observed input of this generation, never a goal
  dependency.
- `ACH-S-02` to `ACH-S-06` are published once, in this generation, together with
  the skills `readiness-policy/2` candidate (O9).
- `ACH-S-02` is the policy goal, and every sibling depends on it.

## Plan amendment K3: approval modes

> **K3. Approval modes** (user decision 2026-10-04, relayed by the coordinating
> session). Agent self-approval is the default approval mode. A prompted
> (in-session) approval applies only when the user explicitly asks for it, per
> plan or per repository. An SSH signature is optional and never required.

- **Forms.** `readiness-policy/2` `approval.accept` gains an `agent-self` form.
  `approval.default_mode` takes `agent`, `prompt` or `ssh-tag`. The baseline
  template defaults to `agent`.
- **`agent` mode.**
  - Autobahn issues the `plan-approval/1` itself, signed with the agent key.
  - The namespace is the distinct `ai-catapult-agent-approval`, never the human
    `ai-catapult-plan-approval`.
  - Its assurance is `agent-self`. That level is reported in every report,
    certificate, audit entry and `audit-merges` result. It is never rendered as
    `in-session`, `key-held` or `user-presence`.
- **`prompt` mode** requires an explicit in-session human confirmation.
- **`ssh-tag`** remains optional.
- **The merge bar is unchanged:** a merge certificate, full green, an
  independent review lane, and no waiver.

What K3 amends:
- U1's "agent keys may sign review records and certificates, never approvals",
  for `agent`-mode approvals only;
- O2's baseline `accept`;
- K1 and K2, which gain the `agent-self` assurance level.

G2 (a bundle never relaxes a gate), U2 and U3 are unchanged.

How K3 is delivered:
- **`ACH-S-02` implements K3** in the validator, observer, schema, ADR-0016 and
  the baseline template, with a test for each mode.
- **This generation does not use K3.** Its candidate keeps `approval.accept`
  `["ssh-tag", "in-session"]` and declares no `default_mode`, because merged
  `readiness-contract/2` accepts no other form. Its plan approval is
  `in-session`.
- **After `ACH-S-02` merges:**
  - skills moves to `default_mode: agent` through a `policy-amendment`
    generation;
  - the user adds `ai-catapult-agent-approval` to the agent principal's line in
    `~/.config/ai-catapult/allowed_signers`. Agents never write the anchor.
- **Umbrella follow-up.** The umbrella spec at `fded0858…` does not record K3.
  Recording it there is an `aitool-root` follow-up, and it re-derives every
  pin.

## Goals

The authoritative per-goal scope, acceptance criteria, dependencies and
verification live in the published
`.ai/handoff/readiness-v2/ach-skills-contract-v2/<generation>/goals.json` in
this repository. The holds-only sidecar sits beside it in `sidecar.json`, and
the generation is registered in `.ai/workflows/northstar-readiness-v2.json`.
Owner and reviewer lane are recorded once, in the plan approval.

Edges to the ai-catapult, root and ai-factory plans cross repositories. They
are preparation blockers observed at admission, never goal dependencies.
