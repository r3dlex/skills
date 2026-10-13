# E6 successor 02: v1 port to TypeScript (`skills`, plan `e6-skills-ts-02`)

> readiness-contract/2 planning publication, live mode, published against skills
> `origin/main` `10a650db711f5a3fd91315ee70ac94990ce0fe7d`. This plan registers
> **one goal, `e6-sk-02-v1-port`**. It does not replace plan `e6-skills-legacy-ts`
> or plan `e6-skills-ts-01`. Publication grants no authority. No plan approval
> is minted by this publication. Policy digest
> `d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962` voids old
> approvals. A fresh own-plan approval is still required before implementation
> admission, and is not sought here. Agent-self: no human approved this plan.

## Read first

1. Decisions D1–D13 are defined in
   `docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md` (sha256
   `981f1f80182180c02837d9eabba4f15f6383725bab89e67d713fc69dc4e01834`, the
   registered prd digest at this base). This spec cites them and does not
   restate them. A disagreement with that spec blocks until a new generation
   is published. This spec does not edit that file: it is bound to generation
   `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`.
2. This packet copies that spec's planned text for `e6-sk-02-v1-port` and the
   common successor acceptance. It changes that text only for facts observed
   at this base, and those facts are named below. It does not invent acceptance
   criteria. It does not invent `e6-sk-02-py-lib` or `e6-sk-02-py-leaf`.
3. `e6-sk-01-py-leaf` is merged. The bundle `dependencies` array is empty.
   The dependency is the predecessor merge commit, named in AC-1 and in the
   attachment `predecessor_pin`, because a bundle cannot depend on a goal of
   another plan (`bundle_dependency_unknown`).
4. The parent publication rule says this plan is published only after
   `e6-sk-01-py-leaf`'s merge commit reaches `origin/main`. That commit is
   `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, and it is `origin/main`. Scope
   is reserved from publication to merge, so deferring a planning PR's merge
   would not have satisfied the rule. This publication does not waive it.
   This lane does not implement the goal and does not mint
   `approval/e6-skills-ts-02/<generation>`.

## Text changed, and only this

The planned scope is copied as the parent's path list. Directory entries stay
directory entries. No path was added or dropped.

Acceptance text was filled in two places, both required by the parent, and
nowhere else:

- AC-1 names the predecessors' merge commits. That is the publication rule's
  required naming, filled with observations at this base. The held-goal
  exemption is not used as a publication waiver.
- AC-4 replaces the parent's `.ai/evidence/<goal>.json` placeholder with
  `.ai/evidence/e6-sk-02-v1-port.json`.

The four corpus bullets of the parent's differential-proof AC are one
acceptance string. No corpus target was added or dropped. The parent's
`steps 1–7` en-dash is kept.

## Facts observed at this base

Re-observed 2026-10-13T21:58:06Z against skills `origin/main`
`10a650db711f5a3fd91315ee70ac94990ce0fe7d`, equal to `git ls-remote origin
refs/heads/main`. These notes do not add acceptance criteria and do not drop
a path the parent planned.

- **Publication predecessor merged.** Plan `e6-skills-ts-01`, generation
  `672d3afe85eb2aa66c50098820ea2cba54c7124256521125acc4316777cf74ae`, goal
  `e6-sk-01-py-leaf`, is registered and active. Its merge commit is
  `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, the squash of PR #137
  (`feat(e6): port leaf scripts to TypeScript (e6-sk-01-py-leaf)`), parent
  `6255da27afeee8c2e9f3582793e74fbc5ff68bf3`, head
  `e353a388d3445f02ee7092e33c4d7344c612d9bb`, merged 2026-10-13T21:18:15Z.
  That commit is `origin/main`. The head is an observation, not a pin: the
  gate is the merge commit, and it is an ancestor of `origin/main`.
- **Chain predecessor merged.** Plan `e6-skills-legacy-ts`, generation
  `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`, goal
  `e6-sk-00-ledger`, is registered and active. Its merge commit is
  `a389a52528d58ba209203f582e6735c3e40fa145`, the squash of PR #135, parent
  `c886433d8950e5b4cb5563d02933b82644edf194`, head
  `5f4a9202253861a0bba6582434479ccd7e951b05`, merged 2026-10-11T18:52:28Z.
  That commit is an ancestor of this base. The head is not a pin.
- **Goal 01's reservation ended at its merge.** Goal 01's registered scope
  (43 entries) included `.ai/ci/local-ci.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`, `mypy.ini`,
  `prek.toml`, `ruff.toml`, and `ts-tooling`. That reservation ended at merge
  `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, because scope is reserved from
  publication to merge. Those paths stay in this goal's planned scope because
  the parent listed them. This goal does not claim the first `prek.toml`
  change; that was goal 01's planned text. This publication does not add a
  prek acceptance criterion.
- **O8 is already an ancestor.** PR #125 merge commit
  `f5e338b92bb754c2bfffdf542b498530258fdbc0` is an ancestor of this base.
- **B2 has merged; the fallback condition is false; the fallback text stays.**
  PR #127 merge commit `28f813bf9fd767960b96e9d54857964de8181a53` is an
  ancestor. Plan `tswc-skills-lane` is still `active`; its entry is not
  retired. No TSWC coordinator withdrawal was observed. The operative parent
  clause is the narrowed form B2 left. The fallback sentence is parent text
  and is not deleted.
- **Anchors still name the frozen bytes.** At commit
  `92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3`, and at this base, the blobs are
  `0afbebf2bebe81546270e3d1c9ee2499cd16b6d0` and
  `6e47e69a7b8dc8e55f6e89d60f2ff7c156363a8e`, with the D2 sha256 values. Line
  785 of `04-validate-handoff/autobahn/lib/readiness_contract.py` at the
  anchor and at this base is the `unavailable` / `missing` / `required` /
  `No such file` branch. The parent's "both branches of line 785" is not
  rewritten. ADR-0016 Decision line 39 and Verification lines 200–201 are
  still the unamended freeze text. The amendment has not landed.
- **Schema path, not added to scope.** D2's `schemas/readiness-contract.json`
  (`f05119f6…`) is
  `04-validate-handoff/autobahn/schemas/readiness-contract.json`, sha256
  `f05119f6d00d2d2cf58270c81073e70016d2644042e3f8185ac0371ef88aa384`. It is
  not in the planned scope. It is not added.
- **Consumer v1 heads are not pins.** The acceptance text stays "every
  registered v1 generation". Those consumer heads are not re-pinned here. A
  later registration still joins the corpus, as D2 says.
- **Policy digest voids old approvals.** Live
  `.ai/policies/readiness-policy.json` sha256 is
  `d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962`. The
  parent generation still records `policy_sha256`
  `58bcd9e7ba044479e2f9f64bedd147926e8ea706f9d9c51378294dada52b354a`. A fresh
  own-plan approval of this generation is still required before implementation
  admission. This publication does not seek it and does not mint it.
- **Paths the predecessors created are present; three planned paths stay absent.**
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`, `mypy.ini`,
  `ruff.toml`, and `ts-tooling` are present at this base. Goal 00 created
  them; goal 01's reservation of the overlapping paths ended at
  `10a650db711f5a3fd91315ee70ac94990ce0fe7d`. They stay in scope.
  `.ai/evidence/e6-sk-02-v1-port.json`, `tests/e6_v1_parity_test.sh`, and
  `tests/fixtures/e6-v1-port` are absent because this goal has not run. They
  stay in scope.
- **Verification scripts that exist.** `tests/run-tests.sh` exists.
  `git diff --check` is a git command, not a repo script. Those two are the
  bundle `verification` array. `tests/e6_v1_parity_test.sh` is absent, so it
  is named in scope and in the differential-proof AC, not in `verification`.

## Goal `e6-sk-02-v1-port`

Planned scope, copied from the parent. Directory entries are the parent's
directory entries, not globs.

- `.ai/ci/local-ci.json`
- `.ai/evidence/e6-sk-02-v1-port.json`
- `.ai/rules/legacy-freeze-baseline.json`
- `.shellcheckrc`
- `02-govern-plan/northstar/readiness-dependency-v2.json`
- `02-govern-plan/northstar/readiness-dependency.json`
- `04-validate-handoff/autobahn/contract-run.sh`
- `04-validate-handoff/autobahn/lib`
- `04-validate-handoff/autobahn/modules/readiness.md`
- `04-validate-handoff/autobahn/readiness-dependency-v2.json`
- `04-validate-handoff/autobahn/readiness-dependency.json`
- `docs/architecture/adr/0016-git-native-plan-approval.md`
- `mypy.ini`
- `prek.toml`
- `ruff.toml`
- `tests/ach_s01_readiness_policy_test.sh`
- `tests/autobahn_worktree_driver_integration_test.py`
- `tests/autobahn_worktree_driver_integration_test.sh`
- `tests/e6_v1_parity_test.sh`
- `tests/fixtures/e6-v1-port`
- `tests/readiness_contract_test.py`
- `tests/readiness_contract_test.sh`
- `tests/readiness_mapped_test.py`
- `tests/readiness_mapped_test.sh`
- `tests/readiness_scoped_test.py`
- `tests/readiness_scoped_test.sh`
- `tests/readiness_v1_freeze_test.sh`
- `tests/readiness_v2_identity_test.py`
- `tests/readiness_worktree_test.py`
- `tests/readiness_worktree_test.sh`
- `tests/xskp_p5_readiness_policy_test.sh`
- `ts-tooling`

Acceptance criteria. Criteria 1–4 are the parent's common successor acceptance.
Criterion 1 adds only the publication rule's required predecessor naming.
Criterion 4 fills the evidence-path placeholder. Criteria 5–11 are the
parent's planned text for this goal. The canonical strings are `goals.json`
`goals[0].acceptance_criteria`, in this order:

1. **Dispatch gate.** O8 and the merge commit of every predecessor goal are
   ancestors of `origin/main`, re-observed by git ancestry at prereq-check
   time. The cross-plan rule applies; held, uncredited goals are exempt.
   Beside O8, this goal names its predecessors' merge commits. Observed at
   base `10a650db711f5a3fd91315ee70ac94990ce0fe7d`: O8 is
   `f5e338b92bb754c2bfffdf542b498530258fdbc0`, the merge commit of PR #125 on
   branch `feat/ach-skills-gate-workspace-ACH-S-08`, and it is an ancestor.
   The publication-rule previous goal `e6-sk-01-py-leaf` of plan
   `e6-skills-ts-01` (generation
   `672d3afe85eb2aa66c50098820ea2cba54c7124256521125acc4316777cf74ae`) is
   merged as `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, the squash of PR
   #137, parent `6255da27afeee8c2e9f3582793e74fbc5ff68bf3`, head
   `e353a388d3445f02ee7092e33c4d7344c612d9bb`, merged 2026-10-13T21:18:15Z,
   and that merge commit is `origin/main`. The chain predecessor
   `e6-sk-00-ledger` of plan `e6-skills-legacy-ts` (generation
   `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`) is
   merged as `a389a52528d58ba209203f582e6735c3e40fa145`, the squash of PR
   #135, parent `c886433d8950e5b4cb5563d02933b82644edf194`, head
   `5f4a9202253861a0bba6582434479ccd7e951b05`, merged 2026-10-11T18:52:28Z,
   and that merge commit is an ancestor of `origin/main`. The dependency is
   recorded here and is not a bundle dependency, because a bundle cannot
   depend on a goal of another plan. The held-goal exemption does not waive
   this publication order.
2. **Same-PR maintenance (D7).** The PR deletes the ledger entries it converts,
   attaches the D5 checks to every converted or surviving file it touches,
   removes configuration its conversion makes dead, and re-pins, adds or
   removes the `.ai/ci/local-ci.json` sources keys and workflow hashes its
   changes require. It never edits the local-ci.json `verification` list or
   the workflow inventory (reserved for goal 06), and never edits af-06's
   declaration. A stale pin left for a later goal is red.
3. **Negative tests (D8).** Every negative test over a converted entrypoint
   asserts its refusal code; none is satisfied by `node_unavailable`.
4. **TDD evidence.** `.ai/evidence/e6-sk-02-v1-port.json` records an observed
   red then green for the same commands. `bash tests/run-tests.sh`,
   `prek run --all-files` and `git diff --check` pass at the PR head. No
   coverage percentage is invented.
5. **ADR-0016 amendment (D2)**, in its Decision and Verification sections. It
   includes the explicit statement that, by user decision of 2026-10-08, the
   port changes v1's emitted bytes for malformed input inside
   `interpreter-diagnostic`, and that every other v1 byte is identical. It
   records the commit-and-path anchors, the `node:`-only import rule, and that
   a tsc upgrade changing executed v1 bytes is an ADR-0016 event.
6. **Differential proof before the switch (D8).** `tests/e6_v1_parity_test.sh`
   runs the frozen Python and the TS port on the eleven-scenario golden
   corpus; every scenario of the v1 Python tests; a generated corpus reaching
   every v1 refusal code, every `verification.py` refusal, every
   `interpreter-diagnostic` site and both branches of line 785; and every
   registered v1 generation of skills, root, ai-catapult and ai-factory (D2).
   Outputs are byte-identical with only `interpreter-diagnostic` masked.
   Canonical JSON, digests and generation have dedicated fixtures. The
   evidence records corpus size, per-code coverage and per-site coverage.
7. **Freeze-test transition** as in D2, with the mask applied after the switch
   too.
8. **Switch.** `contract-run.sh` routes every non-v2 operation to the TS port.
   Both v1 `readiness-dependency.json` copies change together, pin the
   executed artifacts and stay producer-consumer equal. The unsupported,
   incomplete and fingerprint-mismatch refusals stay fail-closed, with tests.
   `prereq-check.sh`, `readiness-check.sh`, `migrate-handoff.sh`, the v1 path
   of `handoff-write.sh` and `contract-run.sh` keep their names, arguments and
   outputs. The validator is ported once, with no second allowlist.
9. **The executed v1 artifacts and exports** are as in D2.
10. **Ported v1 tests.** The tests that import `readiness_contract` directly or
    through `readiness_worktree_test` are ported, with each case mapped and the
    assertion count kept. Narrowed form (commitment carried from the
    superseded e6-sk-02 AC7): `tests/ach_s01_readiness_policy_test.sh` and
    `tests/xskp_p5_readiness_policy_test.sh` are ported in the narrowed form B2
    leaves them, after B2's goal PR merges, and the port keeps that narrowing
    exactly: each test still verifies its retained policy bytes against its
    pinned digest; "every source digest is current" is asserted for a live
    policy only, never for a retained snapshot; the contract-acceptance
    simulation relaxes only source-digest currency (as it already relaxes
    repository-root equality); the retained JSON files
    (`.ai/handoff/xskp-p5-readiness-policy.retained.json`,
    `.ai/handoff/ach-skills-contract-v2/s01-readiness-policy-v1.retained.json`)
    are never edited. The port neither widens nor narrows these assertions; a
    change to them needs its own decision and both review lanes. B2 fallback:
    if the TSWC coordinator records B2 as withdrawn, or its plan entry is
    retired, goal 02 ports the two tests in their form on main at its base.
    `tests/readiness_v2_identity_test.py` re-pins only `V1_WORKTREE_PINS`. Both
    v2 manifests re-pin the `contract-run.sh` digest; their file set is
    unchanged.
11. **Provenance.** The D13 procedure passes, steps 1–7.

## Verification

The parent verification section binds every E6 goal to `bash tests/run-tests.sh`
and `git diff --check`. Those two are the bundle `verification` array.
`prek run --all-files` is required at the implementation PR head and in
`.ai/evidence/e6-sk-02-v1-port.json` (AC-4); it is not added to the array.
`tests/e6_v1_parity_test.sh` is absent at this base, so it is named in scope
and in AC-6, not in `verification`. That check is not relaxed.

## Dependency edge

This goal names `e6-sk-01-py-leaf`'s merge commit
`10a650db711f5a3fd91315ee70ac94990ce0fe7d`, which is `origin/main`, and
`e6-sk-00-ledger`'s merge commit
`a389a52528d58ba209203f582e6735c3e40fa145`, which is an ancestor. The bundle
`dependencies` array stays empty: a bundle cannot depend on a goal of another
plan (`bundle_dependency_unknown`). The edge is AC-1 plus the
`predecessor_pin` attachment, not a cross-plan bundle dependency. O8
(`f5e338b92bb754c2bfffdf542b498530258fdbc0`) is already an ancestor. Holding a
planning PR open would not have satisfied the edge. Publication of this plan
is the registration. It is not dispatch. Dispatch still waits on a fresh
own-plan approval of this generation.

## Non-goals

- No implementation of `e6-sk-02-v1-port`. No product-code or test edit in the
  skills tree from this publication.
- No approval tag `approval/e6-skills-ts-02/<generation>`. A fresh own-plan
  approval is still required before implementation admission. This publication
  does not seek it. Policy digest
  `d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962` voids old
  approvals. A deferred planning PR merge would not have satisfied the parent
  publication rule; the predecessor merge commit is already `origin/main`.
- No edit of the bound parent spec, the parent generation, or the
  `e6-sk-01-py-leaf` implementation worktree.
- No registration of goals 03–07. No registration of `e6-sk-01-py-leaf` in
  this plan. No policy amendment.
- No invented goal id. `e6-sk-02-py-lib` and `e6-sk-02-py-leaf` are not goals
  of this plan.
- No claim that this goal delivers the first `prek.toml` change.

## What this publication does not do

- It does not edit the bound parent spec, the parent generation, or PR #137.
- It does not register goals 03–07.
- It does not amend policy, mint an approval tag, or dispatch implementation.
- It is published only because `e6-sk-01-py-leaf`'s merge commit is
  `origin/main`. The parent's rule is that boundary, not a planning PR whose
  merge is deferred. Goal 01's registered scope included the overlapping paths
  named above. That reservation ended at merge
  `10a650db711f5a3fd91315ee70ac94990ce0fe7d`. This publication reserves this
  goal's scope from publication to its own merge.
- The spec path `docs/specifications/ACTIVE/e6-skills-ts-02.md` is this file.
