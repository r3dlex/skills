# E6 successor 01: Python leaf to TypeScript (`skills`, plan `e6-skills-ts-01`)

> readiness-contract/2 planning publication, live mode, published against skills
> `origin/main` `a389a52528d58ba209203f582e6735c3e40fa145`. This plan registers
> **one goal, `e6-sk-01-py-leaf`**. It does not replace plan `e6-skills-legacy-ts`.
> Publication grants no authority. No plan approval is minted by this publication.
> Agent-self: no human approved this plan.

## Read first

1. Decisions D1–D13 are defined in
   `docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md` (sha256
   `981f1f80182180c02837d9eabba4f15f6383725bab89e67d713fc69dc4e01834`, the
   registered prd digest at this base). This spec cites them and does not
   restate them. A disagreement with that spec blocks until a new generation
   is published. This spec does not edit that file: it is bound to generation
   `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`.
2. This packet copies that spec's planned text for `e6-sk-01-py-leaf` and the
   common successor acceptance. It changes that text only for facts observed
   at this base, and those facts are named below. It does not invent acceptance
   criteria.
3. `e6-sk-00-ledger` is merged. The bundle `dependencies` array is empty.
   The dependency is the predecessor merge commit, named in AC-1 and in the
   attachment `predecessor_pin`, because a bundle cannot depend on a goal of
   another plan (`bundle_dependency_unknown`).
4. The parent publication rule says this plan is published only after
   `e6-sk-00-ledger`'s merge commit reaches `origin/main`. That commit is
   `a389a52528d58ba209203f582e6735c3e40fa145`, and it is `origin/main`. Scope
   is reserved from publication to merge, so deferring a planning PR's merge
   would not have satisfied the rule. This publication does not waive it. A
   prior lane's machine publisher did not enforce it: it wrote generation
   `7c574a80ef4507a4a7dd7fcf561a0a92a163909b582cad45a6a7ec847a3edb6b` locally
   and reported `planning_complete: true`. That write was withdrawn. It is not
   a registration, it is not on a branch, and it is not on origin. This
   publication invokes the publisher only after that merge commit is
   `origin/main`. This lane does not implement the goal and does not mint
   `approval/e6-skills-ts-01/<generation>`.

## Facts observed at this base

Re-observed 2026-10-11T19:41:39Z against skills `origin/main`
`a389a52528d58ba209203f582e6735c3e40fa145`, equal to `git ls-remote origin
refs/heads/main`. These notes do not add acceptance criteria and do not drop
a path the parent planned.

- **Predecessor merged.** Plan `e6-skills-legacy-ts`, generation
  `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`, goal
  `e6-sk-00-ledger`, is registered and active (`status: active` in
  `.ai/workflows/northstar-readiness-v2.json`). Its merge commit is
  `a389a52528d58ba209203f582e6735c3e40fa145`, the squash of PR #135
  (`feat/e6-skills-legacy-ts-e6-sk-00-ledger`), parent
  `c886433d8950e5b4cb5563d02933b82644edf194`, head
  `5f4a9202253861a0bba6582434479ccd7e951b05`, merged 2026-10-11T18:52:28Z.
  That commit is `origin/main`. The head is an observation, not a pin: the
  gate is the merge commit, and it is an ancestor of `origin/main`.
- **Goal 00 reserved neither `prek.toml` nor `ci-prek.yml`.** Re-observed on
  the registered `e6-sk-00-ledger` scope at this base: 18 entries, containing
  neither `prek.toml`, `.github/workflows/ci-prek.yml`, nor
  `.github/workflows/security.yml`. Goal 00's reservation of its own scope
  ended at merge `a389a52528d58ba209203f582e6735c3e40fa145`, because scope is
  reserved from publication to merge. This goal delivers the prek
  registration, including the first `prek.toml` change (D9, parent goal-00
  scope note). Those paths stay in this goal's planned scope.
- **O8 is already an ancestor.** PR #125 merge commit
  `f5e338b92bb754c2bfffdf542b498530258fdbc0` (branch
  `feat/ach-skills-gate-workspace-ACH-S-08`, merged 2026-10-09T10:55:25Z) is an
  ancestor of this base. The live `e6-skills-node-npm` attachment
  `o8_disposition` names the same commit. The held original `ACH-S-08` of
  `ach-skills-gate-workspace` (generation `22d460b2…`) is not O8.
- **B2 has merged; goal 00 has merged.** PR #127 merge commit
  `28f813bf9fd767960b96e9d54857964de8181a53` is an ancestor. Goal 00's merge
  commit is this base. The parent assumed a successor is published only after
  goal 00, so B2 would already have merged. Both have merged. This publication
  does not add a B2 acceptance criterion.
- **Policy tools.** At this base `.ai/policies/readiness-policy.json` `tools`
  includes `node` and `npm`, added by `c886433` (PR #133), the planning
  publication of `e6-skills-node-npm` / `E6-AM-01`. No separate implementation
  PR for `E6-AM-01` is merged. This plan does not amend policy and does not
  claim that amendment goal is executed beyond what #133 landed.
- **Paths the predecessor created are present; two planned paths stay absent.**
  `.shellcheckrc`, `mypy.ini`, `ruff.toml`, `scripts/lib` and `ts-tooling` were
  absent at `c886433d8950e5b4cb5563d02933b82644edf194` because goal 00 had not
  merged. They are present at this base. Goal 00's reservation of them ended
  at the merge. They stay in scope.
  `03-configure-generate/ai-catapult-init/scripts/lib` and
  `04-validate-handoff/eval-a-skill/lib` are still absent, and goal 00 does not
  create them. They stay in scope because the parent planned them. This
  publication does not replace those paths.
- **Paths present, not added.** The eleven `scripts/*.py` tools and the twelve
  `scripts/**/*.sh` tools named below exist at this base. Other scripts exist
  (`scripts/archgate.sh`, `scripts/sync-upstream.sh`, `scripts/validate-rules.sh`,
  and the kept-language files) and are not added to this goal.

## Goal `e6-sk-01-py-leaf`

Planned scope, copied from the parent. Directory entries are the parent's
directory entries, not globs.

- `.ai/ci/local-ci.json`
- `.ai/evidence/e6-sk-01-py-leaf.json`
- `.ai/rules/legacy-freeze-baseline.json`
- `.github/workflows/ci-prek.yml`
- `.github/workflows/security.yml`
- `.moon/tasks/all.yml`
- `.shellcheckrc`
- `03-configure-generate/ai-catapult-init/scripts/lib`
- `03-configure-generate/ai-catapult-init/scripts/readme-generate.sh`
- `04-validate-handoff/eval-a-skill/lib`
- `04-validate-handoff/eval-a-skill/scaffold-eval.py`
- `mypy.ini`
- `prek.toml`
- `ruff.toml`
- `scripts/lib`
- `scripts/catalog-query.py`
- `scripts/catalog.py`
- `scripts/check-markdown-links.py`
- `scripts/check-root-discovery.py`
- `scripts/generate-skill-docs.py`
- `scripts/scan-secret-material.py`
- `scripts/traceability_schema.py`
- `scripts/validate-cascade-fixtures.py`
- `scripts/validate-final-package.py`
- `scripts/validate-skill-catalog.py`
- `scripts/validate_skill_frontmatter.py`
- `scripts/catalog-install.sh`
- `scripts/check-codex-parity.sh`
- `scripts/check-opencode-parity.sh`
- `scripts/check-sync-staleness.sh`
- `scripts/install-auggie.sh`
- `scripts/install-claude-code.sh`
- `scripts/install-codex.sh`
- `scripts/install-copilot.sh`
- `scripts/install-gemini.sh`
- `scripts/readme-generate.sh`
- `scripts/regen-host-golden.sh`
- `scripts/verify-golden-dir.sh`
- `tests/e6_py_leaf_parity_test.sh`
- `tests/fixtures/e6-py-leaf`
- `tests/northstar_handoff_test.sh`
- `tests/traceability-schema-v11_test.sh`
- `ts-tooling`

Acceptance criteria, copied from the parent's common successor acceptance and
from the planned text for this goal. AC-1 adds only the publication rule's
required predecessor naming, filled with the facts above.

1. **Dispatch gate.** O8 and the merge commit of every predecessor goal are
   ancestors of `origin/main`, re-observed by git ancestry at prereq-check
   time. The cross-plan rule applies; held, uncredited goals are exempt.
   Beside O8, this goal names its predecessor merge commit. Observed at base
   `a389a52528d58ba209203f582e6735c3e40fa145`: O8 is
   `f5e338b92bb754c2bfffdf542b498530258fdbc0`, the merge commit of PR #125 on
   branch `feat/ach-skills-gate-workspace-ACH-S-08`, and it is an ancestor.
   The predecessor `e6-sk-00-ledger` of plan `e6-skills-legacy-ts` (generation
   `3f81925f38377c3e90d6df19f75796c5652b1eb379161b1dc638dbcd38dd6c35`) is merged
   as `a389a52528d58ba209203f582e6735c3e40fa145`, the squash of PR #135, parent
   `c886433d8950e5b4cb5563d02933b82644edf194`, head
   `5f4a9202253861a0bba6582434479ccd7e951b05`, merged 2026-10-11T18:52:28Z, and
   that merge commit is `origin/main`. The dependency is recorded here and is
   not a bundle dependency, because a bundle cannot depend on a goal of
   another plan.
2. **Same-PR maintenance (D7).** The PR deletes the ledger entries it converts,
   attaches the D5 checks to every converted or surviving file it touches,
   removes configuration its conversion makes dead, and re-pins, adds or
   removes the `.ai/ci/local-ci.json` sources keys and workflow hashes its
   changes require. It never edits the local-ci.json `verification` list or
   the workflow inventory (reserved for `e6-sk-06-names-batch`), and never
   edits af-06's declaration. A stale pin left for a later goal is red.
3. **Negative tests (D8).** Every negative test over a converted entrypoint
   asserts its refusal code; none is satisfied by `node_unavailable`.
4. **TDD evidence.** `.ai/evidence/e6-sk-01-py-leaf.json` records an observed
   red then green for the same commands. `bash tests/run-tests.sh`,
   `prek run --all-files` and `git diff --check` pass at the PR head. No
   coverage percentage is invented.
5. **Conversion.** It converts the eleven `scripts/*.py` tools
   (`catalog-query.py`, `catalog.py`, `check-markdown-links.py`,
   `check-root-discovery.py`, `generate-skill-docs.py`,
   `scan-secret-material.py`, `traceability_schema.py`,
   `validate-cascade-fixtures.py`, `validate-final-package.py`,
   `validate-skill-catalog.py`, `validate_skill_frontmatter.py`), the twelve
   non-scaffold `scripts/**/*.sh` tools (`catalog-install.sh`,
   `check-codex-parity.sh`, `check-opencode-parity.sh`,
   `check-sync-staleness.sh`, `install-auggie.sh`, `install-claude-code.sh`,
   `install-codex.sh`, `install-copilot.sh`, `install-gemini.sh`,
   `readme-generate.sh`, `regen-host-golden.sh`, `verify-golden-dir.sh`),
   `scaffold-eval.py` and the init readme generator
   (`03-configure-generate/ai-catapult-init/scripts/readme-generate.sh`) to
   TypeScript under the one runner. The three scaffold mirrors and the three
   kept-language files are not converted.
6. **Differential proof before replacement (D8).**
   `tests/e6_py_leaf_parity_test.sh` runs each legacy implementation,
   materialized by its anchor, and its TS port over the existing goldens,
   every scenario its current tests exercise, a per-tool refusal corpus and a
   per-tool environment corpus (D3). Outputs are byte-identical, and each tool
   has a failing-first red leg.
7. **Compatibility (D3).** Every converted entrypoint is a template-conformant
   shim with its declared names. `scripts/validate-skill-catalog.py` stays an
   executable file for the policy fixture gate. The import-only modules retire
   once no tracked importer remains, which is recorded in the ledger.
8. **Ported tests.** `tests/traceability-schema-v11_test.sh` and
   `tests/northstar_handoff_test.sh` load a converted script as a module; they
   are ported. Tests that run a tool by its path stay unchanged and green
   through the shim. `tests/helpers/lock_contention.py` and its two callers
   stay, because they test kept-language files.
9. **prek registration (A4, D9).** `prek.toml` hooks run every TS and legacy
   check. `ci-prek.yml` installs node and the tools, and its job name
   `Pre-commit Hooks` stays byte-identical. `security.yml` installs node and
   keeps its literal line and its job name `Repository Secret Scan`. Moon
   tasks that only compile converted Python are replaced by the TS checks.

## Verification

The parent verification section binds every E6 goal to `bash tests/run-tests.sh`
and `git diff --check`. Those two are the bundle `verification` array.
`prek run --all-files` is required at the implementation PR head and in
`.ai/evidence/e6-sk-01-py-leaf.json` (AC-4); it is not added to the array.
`tests/e6_py_leaf_parity_test.sh` is absent at this base, so it is named in
scope and in AC-6, not in `verification`. That check is not relaxed.

## Dependency edge

This goal blocks on `e6-sk-00-ledger`'s merge commit being an ancestor of
`origin/main`. That commit is `a389a52528d58ba209203f582e6735c3e40fa145`, and
it is `origin/main`. The bundle `dependencies` array stays empty: a bundle
cannot depend on a goal of another plan (`bundle_dependency_unknown`). The
edge is AC-1 plus the `predecessor_pin` attachment, not a cross-plan bundle
dependency. O8 (`f5e338b92bb754c2bfffdf542b498530258fdbc0`) is already an
ancestor. Holding a planning PR open would not have satisfied the edge.
Dispatch re-observes the named merge commit by git ancestry at prereq-check.

## Non-goals

- No implementation of `e6-sk-01-py-leaf`. No product-code or test edit in the
  skills tree from this publication.
- No approval tag `approval/e6-skills-ts-01/<generation>`. A deferred planning
  PR merge would not have satisfied the parent publication rule; the
  predecessor merge commit is already `origin/main`.
- No edit of the bound parent spec, the parent generation, or the
  `e6-sk-00-ledger` worktree.
- No registration of goals 02–07. No policy amendment.
- No conversion of the three scaffold mirrors (`scripts/archgate.sh`,
  `scripts/sync-upstream.sh`, `scripts/validate-rules.sh`) or the three
  kept-language implementation files (`scripts/matrix-contract.py`,
  `scripts/render-ci-adapters.py`, `scripts/release/strategy-selector.sh`).
  `tests/helpers/lock_contention.py` stays, as the planned ported-tests text
  says. Naming them is an observation at this base, not a new acceptance
  criterion.

## What this publication does not do

- It does not edit the bound parent spec, the parent generation, or PR #135.
- It does not register goals 02–07.
- It does not amend policy, mint an approval tag, or dispatch implementation.
- It is published only because `e6-sk-00-ledger`'s merge commit is
  `origin/main`. The parent's rule is that boundary, not a planning PR whose
  merge is deferred. Goal 00's registered scope included
  `.ai/ci/local-ci.json`, `.ai/rules/legacy-freeze-baseline.json`,
  `.shellcheckrc`, `mypy.ini`, `ruff.toml`, `scripts/lib` and `ts-tooling`.
  That reservation ended at merge `a389a52528d58ba209203f582e6735c3e40fa145`.
  `prek.toml`, `ci-prek.yml` and `security.yml` were not in goal 00's
  registered scope. This publication reserves this goal's scope from
  publication to its own merge.
- The spec path `docs/specifications/ACTIVE/e6-skills-ts-01.md` is this file.
