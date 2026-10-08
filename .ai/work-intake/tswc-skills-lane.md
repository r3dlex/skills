# Work Item: TSWC skills lane (`skills`, plan `tswc-skills-lane`)

- **Traceability node:** `issue:skills:tswc-skills-lane`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** umbrella intake `typescript-wikiskill-convergence` in `r3dlex/ai-tool-workspace`
  (`.ai/work-intake/typescript-wikiskill-convergence.md`, sha256 `242fb2c9…`), scoped by
  `.ai/work-intake/tswc-skills.md` (sha256 `8b5b38aa…`), both read from root `origin/main`
  `575d3edf…`.
- **Delivery posture:** one readiness-contract/2 generation (`tswc-skills-lane`) with one
  goal, `tswc-sk-b2`, in one PR. E5-H1/H3/H4 follow in the successor plan
  `tswc-skills-lane-matrix`, published after E6's `e6-sk-01-py-leaf` merges. Planning
  complete is not implementation readiness; implementation needs one verified plan approval.
- **Hard boundaries:**
  - Never touch `04-validate-handoff/autobahn/**`, frozen v1 bytes or the retained policy
    JSON files.
  - `.ai/ci/local-ci.json` changes only the existing hash value for
    `tests/readiness_v2_migrate_test.py`. E6 goals that edit that file wait for B2's merge.
  - Legacy py/sh conversion, A4 and A5 belong to E6 (`e6-skills-legacy-ts`).
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created.

## Traceability

- Spec: [TSWC skills lane — plan-scoped planning specification](../../docs/specifications/ACTIVE/typescript-wikiskill-convergence-tswc-skills-lane.md)
  (graph node `prd:skills:tswc-skills-lane`).
- Handoff: `.ai/handoff/readiness-v2/tswc-skills-lane/<generation>/` and
  `.ai/workflows/northstar-readiness-v2.json`.

## Interview record (deep-interview; agent-run)

Master §8 pre-answers every input. Rows 1–16 date from 2026-10-04. Rows 17–19 record the
2026-10-07 user decisions. Rows 20–23 record the 2026-10-08 coordinator decisions.

| # | Input | Confirmation / decision | Source |
|---|---|---|---|
| 1 | Lane scope | B2 in this plan; E5-H1/H3/H4 in the successor plan; A4/A5 moved (row 17) | rows 17, 20 |
| 2 | A4 shape | Moved to E6 `e6-sk-00-ledger` | user 2026-10-07 |
| 3 | Gate values | Unchanged master §5 values; E6 owns the legacy stack | master §5 |
| 4 | TS depth | Everything new is strict TS; new test logic is plain bash (row 18) | user 2026-10-07 |
| 5 | Complexity | Cyclomatic 10 / cognitive 15 single numbers | master §4.2 |
| 6 | Blindness | Environment-enforced (wiki-stripped export + path denial); prompt-grep is a pre-check only | master §0-F3, §6-B2 |
| 7 | Spend / judge | $100/cycle (user 2026-10-04); judges run human out-of-band | master §4.4, §4.5, §5.5 |
| 8 | Paper boundary | The WikiSkill paper sources the loop only, never thresholds | master §3a |
| 9 | Harness set | Successor plan (E5-H1) | master §3e |
| 10 | Red leg | Negative fixture or mutation; evidence in `.ai/evidence/` | master §4.7 |
| 11 | `local_ci` | Only the existing hash value of `tests/readiness_v2_migrate_test.py` (SKILL.md guard re-pin) | master §4.8, round-2 critic H-1 |
| 12 | Publication | `handoff-goals/2` + `readiness-sidecar/1`, readiness-contract/2 live mode | umbrella R1 |
| 13 | A5 preset | Moved to E6 with A5; preset values at `efa30b1` are E6 input | user 2026-10-07 |
| 14 | B2 placement | All three roles in `02-govern-plan/` | D-2 |
| 15 | E5-H1 shape | Alias/mapping layer (successor plan) | master §9.2 FU-4 |
| 16 | Catalog batching | `catalog.json` serializes with the successor's H1; the lock-bump batch is the successor's concern because B2 ships no hosts | D-13 |
| 17 | A4/A5 owner | E6 (`r3dlex/skills#120`) owns A4 and A5 | user 2026-10-07 |
| 18 | Language | "Change it all to TypeScript": no new non-test `.py`/`.sh`; no embedded Python in new tests | user 2026-10-07 |
| 19 | Regime | Born v2; v1 corpus frozen (ADR-0016) | umbrella R1 |
| 20 | Split | B2 only; E5-H1/H3/H4 move to `tswc-skills-lane-matrix` after `e6-sk-01-py-leaf` | coordinator 2026-10-08 |
| 21 | Lifecycle | `experimental` with `supported_hosts: []` until `tswc-ac-b1` and `tswc-ac-b3` land; promotion lists the hosts later | coordinator 2026-10-08 |
| 22 | Retained policies | Historical evidence; the currency assertion is live-only; both test files are narrowed, never the JSON | coordinator 2026-10-08 |
| 23 | SKILL.md guard | Re-pin `tests/readiness_v2_migrate_test.py` in #118's digest form; whichever of #118 and B2 lands first sets it | coordinator 2026-10-08 |

Ambiguity threshold met: every input is confirmed or decided.

## Adversarial pass (grill-with-docs then grill-me; agent-run)

**grill-with-docs:** the pass was run against AGENTS.md, CONTEXT.md, ADR-0015,
ADR-0016, ADR-0017, `modules/readiness-v2.md` and `modules/handoff.md` on skills main
`4ff1d933` (rechecked on `de949f90` and `7863e64`), and then against the round-1 and round-2
critic reviews. Findings and dispositions:

- (a) The v1 corpus is frozen, so the plan is published as v2.
- (b) `handoff-write.sh` refuses verification scripts a goal would create, so B2 names
  existing suites and its new test runs through `run-tests.sh`.
- (c) Regenerating `AGENTS.md` breaks two tests pinned to retained policy bytes. Both
  tests are narrowed (row 22).
- (d) `tests/catalog_contract_test.sh` hard-codes the default count, so it becomes
  data-driven.
- (e) `--write-audit` also rewrites `.ai/skills/modernization-report.md`, so that file
  joins the scope.
- (f) The traceability schema has no `spec` type, so the spec node is `prd`.

**grill-me:**

- "Does B2 block E6?" Partly. B2 converts nothing E6 converts, but it edits one
  `.ai/ci/local-ci.json` hash, so `e6-sk-00-ledger` and every other E6 goal that edits that
  file wait for B2's merge. At #120 head `a514f18` that is all eight E6 goals. The waits are
  one-way, because B2 has no dependency.
- "Can the proof drift from the procedure?" No. The test executes the skill's fenced
  `bash blindness-sandbox` block.
- "Does `experimental` still regenerate `AGENTS.md`?" Yes, the generator lists every
  entry. Row 22 covers that.
- "Does `experimental` keep the skills out of plugin payloads?" No. ai-catapult's
  resolver bundles every non-deprecated entry by `supported_hosts`, so B2 ships no hosts
  (row 21).
- "Does an untracked simulation prove green?" No. The SKILL.md guard only sees committed
  files, so every simulation commits first. Committed without the re-pin, B2 fails
  `bash tests/readiness_v2_migrate_test.sh`, and so `run-tests.sh`.

Committed throwaway simulations of B2's scope on main `de949f90` and `7863e64` are
reported in the planning PR.

## Ralplan consensus slicing (tracer bullets, one PR each)

| Goal | Slice | In-plan edges | Cross-plan / cross-lane |
|---|---|---|---|
| `tswc-sk-b2` | three role skills + environment-enforced blindness | — | ← `tswc-ac-b1` (vocabulary, non-blocking); serializes with XSKP-P5-02 (#118) either way; E6's `local-ci.json`, py-lib, v1-port and test-harness goals wait for B2 |
| successor `tswc-skills-lane-matrix` | E5-H1, E5-H3 (← H1), E5-H4 (← H1, ← H3) | — | published after `e6-sk-01-py-leaf`; M-4/M-5/M-6 open |

## Decision log

- **D-1 (confirmed):** every master §8 input is accepted as pre-answered.
- **D-2 (agent-run):** the role skills live in `02-govern-plan/`.
- **D-3 (superseded 2026-10-07):** the A5 preset pin moved to E6.
- **D-4 (agent-run):** E5-H1 is an alias layer, now in the successor plan.
- **D-5 (revised):** cross-plan contention resolves through registered scopes and
  same-file serialization. The v1-era (2a)/(2b) check is moot.
- **D-6 (revised):** the plan is born readiness-contract/2 with no post-S-05 migration.
  The withdrawn candidates `81b1d4ea…` (v1), `c5e7de57…` (round-1 v2) and `27acc095…`
  (round-2 v2) were never on main.
- **D-7 (agent-run):** `dependencies[]` carry in-plan edges only.
- **D-8 (user 2026-10-07):** E6 owns A4 and A5.
- **D-9 (user 2026-10-07):** everything new is TypeScript; new test logic is plain bash.
- **D-10 (agent-run):** verification names existing focused suites, `prek run --all-files`
  and `git diff --check`, plus the aggregate runner that discovers the new test.
- **D-11 (coordinator 2026-10-08):** the role skills ship as `experimental` with
  `supported_hosts: []` (the pre-G-03 `edit-article` precedent) until B1 and B3 land.
  Promotion lists the hosts.
- **D-12 (coordinator 2026-10-08):** the retained-policy tests narrow to live-only source
  currency. Both review lanes must accept this explicitly, and E6's v1-port goal ports the
  narrowed form.
- **D-13 (coordinator 2026-10-08, premise corrected):** B2 does not carry the B2/H1
  `skills.lock` batch; it only serializes on `catalog.json`.
  - The round-2 premise was false. `experimental` does not keep a skill out of plugin
    payloads: ai-catapult's `src/skill-resolver.js:122-128` (`origin/main` `f31de08`)
    bundles every non-deprecated entry whose `supported_hosts` names the host, or that
    omits the field.
  - B2 therefore ships `supported_hosts: []`. A lock bump that vendors B2 puts it in no
    payload, so no batch is needed.
  - Cross-lane follow-up (not a dependency): the ai-catapult resolver should exclude
    `experimental` by default.
- **D-14 (coordinator 2026-10-08):** the plan is split; E5-H1/H3/H4 move to
  `tswc-skills-lane-matrix` with the critic's notes M-4, M-5 and M-6 carried forward.
- **D-15 (coordinator 2026-10-08):** B2 re-pins the ACH-S-05 SKILL.md no-growth guard in
  #118's digest form, and edits only that test's existing hash in `.ai/ci/local-ci.json`.
  - XSKP-P5-02 (#118, digest form at `9299b7c`) serializes with B2 in either order. It
    also edits `.ai/skills/catalog-audit.json`.
  - E6's `local-ci.json` goals, py-lib goal, v1-port goal and test-harness goal wait for
    B2's merge.
  - B2 has no dependency, so these one-way waits form no cycle.
- **D-16 (agent-run):** E6's node/npm policy amendment voids existing approvals when it
  merges. If B2 is approved before it lands, B2 must be re-signed; the live-mode
  generation keeps its identity, so the same generation is re-signed.
