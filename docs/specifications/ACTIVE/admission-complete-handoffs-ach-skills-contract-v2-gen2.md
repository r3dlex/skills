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

**K3 supersedes every umbrella statement it contradicts.** The list below names
each one. For those statements this copy governs, and no disagreement with the
umbrella blocks this plan.

For any other disagreement, the umbrella spec at the pinned sha wins, and this
plan's preparation is blocked until a new planning copy is published.

This is the planning copy for the plan's `readiness-contract/2` generation
(`ACH-S-02` to `ACH-S-06`). The first copy,
`admission-complete-handoffs-ach-skills-contract-v2.md` (sha256
`f588f9b02370e4a3b5d80a708f7bc92a05ddc8f704c30e25f34ad691af36f3a9`), is not
re-derived. It stays byte-frozen because two things pin it: the merged
readiness-v1 generation of `ACH-S-01` and `tests/ach_s01_readiness_policy_test.sh`.

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
- **Amending a policy** requires an approval form that both the live policy's
  `accept` list and the candidate's `accept` list contain (rule d).

## Plan amendment K3b: agent-self policy approval

> **K3b** (user decision 2026-10-04, accepted risk). Agent-self approval may
> also approve bootstrap and policy-amendment generations. That includes changes
> to `anchor_sha256`, `accept`, `default_mode` or required checks.

- **When.** Only when `agent-self` is in both the live policy's `accept` list
  and the candidate's (rule d).
- **How it is recorded.** Each such approval carries `assurance: agent-self`. It
  emits the distinct notice code `agent_self_policy_change` in the admission and
  merge reports, and `audit-merges` lists it. It is never upgraded to
  `in-session` or human.
- **Accepted risk.** An agent can approve a policy that drops a required check,
  then merge under it.
- **Unchanged.** The per-merge certificate bar stays as it is: exact head, every
  required hosted check `SUCCESS`, local CI, an independent review lane signed
  by a principal distinct from the certifier, zero unresolved threads, and
  merge-stage admission.
- **Bootstrap.** A v1 or absent live policy counts as an empty live `accept`
  list. An agent-self approval of a bootstrap generation is therefore refused
  with `agent_self_bootstrap_refused`. Every repository's first policy/2
  (`ACH-C-01`, `ACH-R-01`, `ACH-F-01`, and this generation) needs an in-session
  or ssh-tag approval.
- `ACH-S-02` carries K3b verbatim as an acceptance criterion.

### What K3 supersedes in the umbrella spec

| Umbrella statement | Under K3 |
|---|---|
| U1: "Agent keys may sign review records and certificates, never approvals." | An agent key signs an `agent`-mode approval under `ai-catapult-agent-approval`, never under the human namespace. |
| Contract v2, Approval, Commands (umbrella line 130): "`autobahn` verifies the signature but never signs." | In `agent` mode, Autobahn issues and signs the approval with the agent key. |
| Outcome: "exactly **one** human approval per plan generation". | Exactly one approval per plan generation: `agent-self` by default, human-confirmed in `prompt` mode, human-signed with `ssh-tag`. |
| AC-1: "an asserted human-prompt count of 1". | Count 1 for an `in-session` approval, 0 for an `agent-self` approval (ACH-S-06 runs both). |
| Policy fields: `approval{anchor_sha256, max_age_days: 14, accept: ["ssh-tag", "in-session"]}`. | `accept` may also hold `agent-self`, and `approval` gains an optional `default_mode`. |
| Adoption: "approve one `readiness-policy/2` per repository … with one signature each". | One approval each, in the repository's mode. A signature is required only in `ssh-tag` mode. |
| O2: baseline `accept` is `["ssh-tag", "in-session"]`, with ssh-tag preferred. | The baseline is `agent` mode. `ssh-tag` is optional, and `prompt` is used only on request. |
| K1: assurance is `user-presence`, `key-held` or `in-session`. | Adds `agent-self`. |
| K2: every report must show `assurance: in-session` prominently, and no code may present `in-session` or `key-held` as `user-presence`. | `agent-self` is reported just as prominently. It is never shown as, or upgraded to, any other level. |

G2 (a bundle never relaxes a gate), U2 and U3 stand unchanged.

### Order of K3 work

1. **Now, before this republish.** The anchor
   `~/.config/ai-catapult/allowed_signers` was edited on 2026-10-04 by the
   coordinating agent, on the user's explicit instruction. That edit is a
   user-instructed exception to R2, and `ACH-S-02` records it in ADR-0016.
   Otherwise only the user edits the anchor. This generation binds the edited
   anchor, which holds four principals, one line each:
   - `approver@human` and `approver-rsa@human`: plan approval;
   - `agent@autobahn`: review, certificate and agent approval (the certifier);
   - `reviewer@autobahn`: review only, the independent review lane.

   The previous anchor `52c61dc5…` held only one agent principal, so
   `review_lane_not_independent` refused every certificate.
2. **`ACH-S-02` implements K3** in the validator, observer, schema, ADR-0016 and
   the baseline template.
3. **This generation does not use K3.**
   - Its candidate keeps `approval.accept` `["ssh-tag", "in-session"]` and
     declares no `default_mode`, because merged `readiness-contract/2` accepts
     no other form.
   - Its plan approval is `in-session`.
4. **After `ACH-S-06` merges, strictly, and before any XSKP P5 approval:** a
   `policy-amendment` generation moves skills to `default_mode: agent`, adding
   `agent-self` to `accept`.
   - The live `accept` list does not yet contain `agent-self` (rule d), so this
     amendment is approved in-session or by ssh-tag.
   - Every later plan or policy change can then be approved agent-self (K3b).
5. **Then** the P5 generation that `ACH-S-05` publishes is republished against
   the amended policy, and only then approved.
6. **Umbrella follow-up.** Recording K3 in the umbrella spec is an
   `aitool-root` follow-up. After that umbrella amendment, plan-scoped copies
   derived from it are re-pinned to the new umbrella digest. The skills gen1
   and gen2 copies stay byte-frozen, because their generations pin them.

## Merge routing once v2 is live

`ACH-S-02` delivers this routing.

- **Reserved branch namespace.** It is defined per registered active plan: its
  policy `branch_pattern`, with that `plan_id` and any goal id, matched
  case-insensitively.
- **Goal branches.** An exact goal branch merges only on a re-observed merge
  certificate. For v2 merges, the merge certificate is the host-policy audit
  record (O4).
- **Active goal.** A goal of an `active` registry entry whose goal-branch PR
  merge commit is not yet an ancestor of `origin/<target>`. The reserved set is
  the union of what is active at the PR's base commit and what is active at the
  current `origin/<target>`.
- **Reserved paths.** These never take the v1 verdict lane, except through the
  two lanes below:
  - the policy file `.ai/policies/readiness-policy.json`, never covered by any
    exception;
  - the v2 registry `.ai/workflows/northstar-readiness-v2.json`;
  - `.ai/handoff/readiness-v2/**`;
  - every active goal's other scope paths.
- **Planning-publication paths**, enumerated:
  - reserved: the v2 registry and `.ai/handoff/readiness-v2/**`;
  - free: `.ai/traceability/graph.json`, plan-scoped spec copies under
    `docs/specifications/ACTIVE/`, and the request documents
    `.ai/handoff/<plan_id>-plan-approval-request.json` and
    `.ai/handoff/<plan_id>-plan-approval.md`.

  These paths and `.ai/ci/local-ci.json` are never reserved through goal
  scope.
- **Replay exception.** A non-goal PR whose reserved-path changes are exactly a
  publish-v2 replay takes the v1 lane.
  - The replay runs the pinned `origin/<target>` publish-v2 driver, never the
    PR's own code. Its inputs are the PR head's new `goals.json`,
    `sidecar.json` and optional `policy-candidate.json`.
  - Only the reserved-path part of the diff (the registry and
    `.ai/handoff/readiness-v2/**`) is byte-compared. The other paths are free
    and not compared.
  - The diff may add a new plan id. It may replace an existing registry entry
    only when that plan has no merged and no open goal PR. Every replacement is
    reported as `v2_plan_entry_replaced`. This still permits the planned P5
    republish.
- **Sidecar-tighten lane.** A diff limited to existing generations'
  `sidecar.json` takes the v1 lane when each base-to-head change passes the
  merged tighten-only check (O1). Any loosening is refused with
  `v2_sidecar_not_tightening`.
- **Diff observation.**
  - The diff is read as the merge-base (three-dot) diff, or as the hosted
    changed-files list with renames checked. A file renamed into a reserved
    path counts as touching it.
  - A truncated or unobservable list fails closed (GitHub caps the list at
    3000).
  - A v1-lane decision binds the observed head, and the merge uses
    `--match-head-commit` at that head.
- **Refusal.** Any other non-goal touch of a reserved path is refused with
  `v2_scope_outside_goal`. `audit-merges` (`ACH-S-06`) flags such merges using
  the same reserved set and the same exceptions.

### Freeze between #99 and `ACH-S-02`

From this PR's merge until `ACH-S-02` merges:
- No non-goal PR that touches the policy file, the v2 registry or
  `.ai/handoff/readiness-v2/**` merges.
- The interim audit PR below touches none of them, so it is not affected.

### Interim audit branches, until `ACH-S-02`'s route guard lands

Until `ACH-S-02` merges, the merged S-01 routing refuses every non-goal
`feat|fix|chore/<x>-<y>` head once this registry is on `main`. During that
interval a host-policy audit PR uses the head `audit/host-policy-skills-<PR>`.
That name applies only when all of these hold:
- the diff is an append-only change to `.ai/host-policy/github/audit.jsonl`;
- every required check is green at the exact head;
- an independent review is recorded;
- the merge goes through `merge-authority.sh --pr <N> --verdict <file>`.

## Goals

The authoritative per-goal scope, acceptance criteria, dependencies and
verification live in the published
`.ai/handoff/readiness-v2/ach-skills-contract-v2/<generation>/goals.json` in
this repository. The holds-only sidecar sits beside it in `sidecar.json`, and
the generation is registered in `.ai/workflows/northstar-readiness-v2.json`.
Owner and reviewer lane are recorded once, in the plan approval.

`ACH-S-05` is this plan's only v2 path for XSKP P5. Draft `r3dlex/skills#100`
belongs to another owner, and this plan never merges it.

Edges to the ai-catapult, root and ai-factory plans cross repositories. They
are preparation blockers observed at admission, never goal dependencies.
