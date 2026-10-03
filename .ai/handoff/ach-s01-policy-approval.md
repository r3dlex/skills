# ACH-S-01 policy rollover (R4) — independent approval pending

This is an **unsigned approval request**, not a `readiness-context/1`, receipt,
policy approval, `plan-approval/1`, execution admission, or merge authorization.
Preparing this configuration does not approve its digest.

## Exact subject

- Repository: `skills`, `r3dlex/skills`.
- Canonical root (identity): `/Users/andresilvaburgstahler/Ws/Personal/AiTool/skills`.
- Bound linked worktree (`git-worktree/1`):
  - root: `/private/tmp/claude-502/-Users-andresilvaburgstahler-Ws-Personal-AiTool/94f42008-9018-42b5-b61e-b0edc80d9a34/scratchpad/wt-ps1`
  - base commit: `92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3` (skills `origin/main` at authoring)
  - target ref: `refs/remotes/origin/main`
- Registered handoff: `northstar-plan-ach-skills-contract-v2`.
- Generation: `ba4a7996ca50979aa4cf21cd50892ac7dc8eb71c161547ccf8ae3d1f448a31b0`.
- Bundle (`goals.json`) SHA-256: `1c7b4837af54742374b140ed06fda2561ec62a1cc86ed847afe1029bce9a8dcd`.
- Plan-scoped spec: `docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-contract-v2.md`,
  SHA-256 `f588f9b02370e4a3b5d80a708f7bc92a05ddc8f704c30e25f34ad691af36f3a9`, pinned to the
  umbrella spec `ACH-20261002` at `fded0858d0c3aa2ba06cdc9b6d716053cb92dd82a3afa22e6a13774e30f6ddd5`.
- Selected goal: `ACH-S-01` only. Stages: **implementation** and **merge**, each
  admitted separately under `readiness-contract/1`.
- Proposed policy: `.ai/policies/readiness-policy.json`.
- Proposed policy SHA-256: `29ae6feeb3a408496095601cf4e0d58798f2445d844245c33ebcdef9a32fd9e3`.
- Previous policy SHA-256: `1ef4f92900133f582cac5638384f67a10266e910e883ec44493f0555690f2444`
  (XSKP P5), retained byte-for-byte at `.ai/handoff/xskp-p5-readiness-policy.retained.json`
  and in Git at `9286514`.
- Proposed responsible party: Andres Silva Burgstahler, retained from the prior
  policy. This is not an owner-assignment receipt: the frozen goal still says
  `unassigned`.

| Goal | Exact branch (full ref) | Target (full ref) | Approval subject (`goal_revision()`) |
|---|---|---|---|
| ACH-S-01 | `refs/heads/feat/ach-skills-contract-v2-ACH-S-01` | `refs/remotes/origin/main` | `d3f083e87a52b06691a7e3c22432e7d466642b32ef132b5a22151ef700802212` |

## What approving authorizes

Approving digest `29ae6fee…` authorizes **only** `ACH-S-01` admission under
readiness-contract v1, from the bound worktree above, at the implementation and
merge stages, once every gate below has a valid independent receipt. It does not
approve:

- any other goal: `ACH-S-02` to `ACH-S-06` publish once in the v2 generation (P-S2) under their own approval;
- XSKP P5 admission: P5 is displaced (R4) and migrates to v2 in `ACH-S-05`;
- any `readiness-policy/2`, trust anchor or `plan-approval/1`;
- a merge: merge still needs fresh merge-stage admission and the host's fail-closed merge boundary.

## What changed

- **All 7 v1 dimensions are covered.**
  - owners and reviewer: `own-execution` (implementation) and `own-review` (merge), preserved unchanged;
  - `branch_target`: `branch-ach-s-01`, in the #92 worktree **full-ref** form. v1 compares the binding with the observed `branch` and `target_ref` as full refs (`readiness_contract.py:546-547`), so a short name would fail `worktree_branch_target_mismatch` and force a second rollover;
  - `registration_approval`: `approval-ach-s-01`, goal-scope, bound to the revision above;
  - `tooling`: `bash`, `python3`, `git`, `prek` and `ssh-keygen`;
  - `fixtures`: `not_applicable`, because S-01's fixtures are disposable temporary-directory deliverables of its own tests;
  - `harness_trust`: `not_applicable`, stated honestly. ACH-S-01 is the harness: it builds the v2 gate driver, so no independently pinned prior harness commit can anchor trust. Trust rests on the independent review lane, hosted checks and the hand-written contexts.
  - v1 accepts any `not_applicable` reason (P7), so these reasons are a disclosure, not a control.
- **B5** stays a `planning-inputs-on-main` independent-result gate. No passing B5 result is claimed.
- **Worktree binding** added (`policy.worktree`). While this policy is live, v1 admission in skills works only from the bound worktree.
- **Sources** add `CLAUDE.md` and `GEMINI.md`, which worktree-mode admission requires; every digest is current at the base commit.
- **Removed:** P5's four branch and approval gates, and its `scripts/validate-skill-catalog.py` presence gate, which is outside the planned S-01 tooling set.

**v1 limitation.** The policy is active-bundle-specific and binds one worktree and
base at a time. It invalidates every P5 policy receipt; no old approval is reused.
`tests/ach_s01_readiness_policy_test.sh` pins this digest, the full refs, the goal
revision and the gate scopes. `tests/xskp_p5_readiness_policy_test.sh` now pins
the retained P5 bytes.

## Assurance (K1, K2)

No trust anchor, signing key or `plan-approval/1` exists yet; ACH-S-01 builds
them. Approval of this v1 policy is therefore a human decision recorded through
an independently verifiable boundary, such as a genuine human GitHub review or
the user's explicit approval of this exact digest. An approval relayed in an
agent session is recorded as assurance `in-session`, never as `user-presence` or
`key-held`. The K2 risk is visible here: an agent authored this policy. An agent
posting approval under the same credentials is **not** independent owner
approval. Do not generate `pass` values from this request or from host capability
alone.

## What remains

1. **Approve this digest** explicitly. The planning-input PR merges only on full
   green: independent review lane recorded, every hosted check SUCCESS at the
   exact head, the audited `merge-authority.sh` host-policy path, and an audit
   entry carrying `assurance`.
2. **Assign an owner** through the supported planning path. Do not rewrite frozen
   generation files in place; the `own-execution` and `own-review` receipts need
   named, non-placeholder people.
3. **Re-bind the worktree.** After this PR merges as `M`, remove this preparation
   worktree and cut `feat/ach-skills-contract-v2-ACH-S-01` from `M` at the same
   path. `9286514` stays an ancestor, as the worktree observation requires.
4. **Write two hand-written `readiness-context/1` records**, the last ever. An
   independent authority writes them and stores them outside every worktree:
   - implementation stage, at the start head;
   - merge stage, at the final clean head, taken only when
     `git status --ignored --porcelain` in the bound worktree is empty.

   Each binds the full worktree observation, including `head`,
   `target_revision` and `state_sha256`. A moved `origin/main` or head voids it.
   Announce a skills `main` merge freeze from the merge-stage context until
   ACH-S-01 merges. Count and report every extra context.
5. **Run v1 gates for S-01 from a detached worktree at `M`**, never from S-01's
   head, with `PYTHONDONTWRITEBYTECODE=1` for the whole lane:

```sh
bash <detached-worktree-at-M>/04-validate-handoff/autobahn/prereq-check.sh \
  --root /Users/andresilvaburgstahler/Ws/Personal/AiTool/skills \
  --worktree-root /private/tmp/claude-502/-Users-andresilvaburgstahler-Ws-Personal-AiTool/94f42008-9018-42b5-b61e-b0edc80d9a34/scratchpad/wt-ps1 \
  --base-commit 92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3 \
  --handoff northstar-plan-ach-skills-contract-v2 \
  --goal-id ACH-S-01 \
  --stage implementation \
  --context /absolute/path/outside-every-worktree/implementation-context.json
```

Preparation regression evidence is not feature TDD or feature completion.
