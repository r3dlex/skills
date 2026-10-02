# XSKP P5 policy rollover — independent approval pending

This is an **unsigned approval request**, not a `readiness-context/1`, receipt,
policy approval, execution admission, or merge authorization. Preparing this
configuration does not approve its digest.

## Exact subject

- Repository: `skills`, `r3dlex/skills`.
- Canonical root: `/Users/andresilvaburgstahler/Ws/Personal/AiTool/skills`.
- Registered handoff: `northstar-plan-xskp-p5-skill-producers`.
- Generation: `4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c`.
- Bundle (`goals.json`) SHA-256: `8089c7c77e5aadb62c1a003fb7b30c78465ceb65541fc5b7927b3e2a0bd58cff`.
- Selected goals: `XSKP-P5-01`, `XSKP-P5-02`, `XSKP-P5-03`, `XSKP-P5-04`.
- Requested stage: **implementation**, admitted one goal at a time in dependency
  order (`01` → `02` → `03`; `01` → `04`).
- Proposed policy: `.ai/policies/readiness-policy.json`.
- Proposed policy SHA-256: `1ef4f92900133f582cac5638384f67a10266e910e883ec44493f0555690f2444`.
- Previous policy SHA-256: `bdca65ade44ed6ab2c6d2e9bd7c54773c884998eb9a21a56a7edbcf38643f5e5`
  (retained in Git at `610baaa`).
- Proposed responsible party: Andres Silva Burgstahler, retained from the prior
  policy. This is not an owner-assignment receipt: every frozen goal still says
  `unassigned`.

| Goal | Exact proposed branch | Target | Approval subject (`goal_revision()`) |
|---|---|---|---|
| XSKP-P5-01 | `feat/knowledge-contract-copy-XSKP-P5-01` | `main` | `059499be88c7d2fa3deda7db242b33e3e6b423adba10d76f8f52c2d99e8a4808` |
| XSKP-P5-02 | `feat/knowledge-producers-planning-XSKP-P5-02` | `main` | `76fea8df567b84a0d10875f284b6bcf479093a3079abd23951630458db9a1963` |
| XSKP-P5-03 | `feat/knowledge-producers-review-XSKP-P5-03` | `main` | `0e5a0f90c86239b07f11c86f1dde18b90cd42f5fe95583033e0a7e17ee615ab9` |
| XSKP-P5-04 | `feat/knowledge-init-templates-XSKP-P5-04` | `main` | `d846d45fe622157871578e818ca4fbf952f32842721f3b72541af41ff94a20ed` |

## What changed

- Owner/implementation and reviewer/merge gates are preserved unchanged.
- The prior `branch_target` and `registration_approval` exemptions are removed:
  each goal now needs an exact branch gate and a protected approval bound to its
  goal revision.
- The single repository-wide `tool-present` (python3) gate becomes explicit
  observations for `bash`, `python3`, `git` and `prek`, plus an `executable_presence`
  gate on `scripts/validate-skill-catalog.py`.
- B5 is a machine-visible `planning-inputs-on-main` independent-result gate; no
  passing B5 result is claimed.
- `fixtures` and `harness_trust` stay exempt with P5-specific reasons.
- Source digests are refreshed: base `AGENTS.md` digest was stale
  (`ac2032a9…` recorded vs `55ff94b7…` on `main`), so the base policy could not
  admit anything.

**v1 limitation:** the policy is active-bundle-specific. Goal scopes outside an
admitted bundle are rejected, so any other handoff later registered here fails
closed until its own reviewed rollover. The new digest invalidates prior policy
receipts; no old approval is reused. `tests/xskp_p5_readiness_policy_test.sh`
pins this digest and must be updated with any later reviewed rollover.

## Independent evidence still required

An authorized owner must approve the exact policy digest, current source set,
subject, goal set and stage through an independently verifiable boundary (for
example a genuine human GitHub review). An agent posting approval under the same
credentials is **not** independent owner approval. Do not generate `pass` values
from this request or from host capability alone.

Before implementation:

1. Assign an owner through the supported planning path; do not rewrite frozen
   generation files in place.
2. Observe B5: the plan spec and contract pack planning copy on remote `main`.
3. Approve this policy revision and stage; observe the scoped branch, owner,
   approval and tooling gates and retain valid receipts.
4. Publish a reviewed readiness-only generation when prerequisites clear; current
   goals remain preparation-`blocked` and implementation-`unknown`. A new
   generation changes goal revisions and invalidates the approval subjects above.
5. Run exact admission for `XSKP-P5-01` first, from the canonical root:

```sh
bash ~/.claude/plugins/ai-catapult/skills/autobahn/prereq-check.sh \
  --root /Users/andresilvaburgstahler/Ws/Personal/AiTool/skills \
  --handoff northstar-plan-xskp-p5-skill-producers \
  --goal-id XSKP-P5-01 \
  --stage implementation \
  --context /absolute/path/to/independently-verified-context.json
```

Fresh merge-stage admission and separate merge authorization remain required.
Preparation regression evidence is not feature TDD or feature completion.
