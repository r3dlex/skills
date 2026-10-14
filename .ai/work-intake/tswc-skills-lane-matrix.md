# Work Item: TSWC skills successor (`skills`, plan `tswc-skills-lane-matrix`)

- **Traceability node:** `issue:skills:tswc-skills-lane-matrix`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** `issue:skills:tswc-skills-lane` (B2 plan; successor named in its bound spec §Successor plan) ← umbrella intake `issue:aitool-root:typescript-wikiskill-convergence` (root `.ai/work-intake/typescript-wikiskill-convergence.md` sha256 `5f54c26a…` and `.ai/work-intake/tswc-skills.md` sha256 `f35bc99c…`, both at root `origin/main` `f4a6241e07bc8beddc4ff8a3e43816b71f3160f5`)
- **Delivery posture:** one readiness-contract/2 live-mode generation (`tswc-skills-lane-matrix`) with three goals, `tswc-sk-e5-h1`, `tswc-sk-e5-h3` (← H1) and `tswc-sk-e5-h4` (← H1, H3), one PR each. Fresh-plan ADD; does not replace `tswc-skills-lane`. Publication gate (after `e6-sk-01-py-leaf` merges) is met at `10a650db711f5a3fd91315ee70ac94990ce0fe7d`. Published on skills `origin/main` `823d699cb063b5cc2fe1674baf137f6b2efdb8e4` after coordinator #3 green-light 2026-10-14T07:09:32Z on the human PUB authorization of the same timestamp (root .omc/plans/hitl-answers-20261014.md); the `HELD-UNTIL-GREENLIGHT.md` conditions were re-verified first-hand at publication time. Planning complete is not implementation readiness; implementation needs one verified plan approval minted later.
- **Hard boundaries:**
  - No approval tag and no implementation from the publication lane; its only skills-repo writes are this registration's add-only files (spec, intake, generation, registry entry, traceability nodes).
  - Never edit `catalog.json`, `prek.toml`, `.ai/ci/local-ci.json`, the ledger, `tests/readiness_v2_migrate_test.py`, any workflow, moon task or SKILL.md, `04-validate-handoff/autobahn/**`, frozen v1 bytes, the bound B2 spec copy or the B2 generation.
  - `ts-tooling` and `scripts/lib` by exact file only.
  - Everything new executable is strict TypeScript; new test logic is plain bash with no embedded Python; no new non-test `.py`/`.sh`.
  - No `supported_hosts` change; no `omo-ai` host; no shim retirement; no hook wiring.
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created. Tracker writes were not authorized.

## Traceability

- Spec: `docs/specifications/ACTIVE/typescript-wikiskill-convergence-tswc-skills-lane-matrix.md` (graph node `prd:skills:tswc-skills-lane-matrix`; type `prd`, as the B2 lane recorded: the schema has no `spec` type).
- Handoff: `.ai/handoff/readiness-v2/tswc-skills-lane-matrix/<generation>/` and the appended entry `northstar-plan-tswc-skills-lane-matrix` in `.ai/workflows/northstar-readiness-v2.json`, which names the generation.
- Interview record: root `.omc/specs/deep-interview-tswc-skills-lane-matrix.md`.

## Interview record (deep-interview; agent-run, recommended path; threshold 20% default)

| # | Input | Confirmation / decision | Source |
|---|---|---|---|
| 1 | Lane scope | E5-H1, E5-H3, E5-H4 only; promotion of the role skills is a later goal | B2 spec §Successor plan; lane brief |
| 2 | Publication gate | `e6-sk-01-py-leaf` merged (#137, `10a650db`), ancestor of base `848a3dd6` | first-hand `gh pr view 137`, `git merge-base` |
| 3 | Host model shape | Alias/mapping layer in a sibling `host-matrix.json`; enum stays build truth; `catalog.json` untouched | master §9.2 FU-4; mega §2b; round 1 |
| 4 | Aliases | `omc`→`claude-code`, `omx`→`codex`; markers name payload hosts only | master §3e; round 1, round 6 |
| 5 | OpenCode v2 | consumes the `opencode` payload via ai-catapult payload merge; never the v2 `plugin` array; no skills installer | master §3e; mega §2b hard constraint |
| 6 | `omo-ai` (M-6) | dropped from H1/H3/H4; recorded under `excluded`; OMO adapter quarantined; root test is the guard | coordinator recommendation 2026-10-14; SQ-2 |
| 7 | All-host wording (M-5) | declared host set is the truth; `edit-article` stays opencode-only; role skills stay host-less | #82/G-03, SSCM S3; SQ-1 |
| 8 | Dependency (M-4) | H4 ← H3, H1; H3 ← H1 in bundle `dependencies` | critic note M-4 |
| 9 | Language | strict TS in `ts-tooling`; plain-bash tests; no embedded Python | user 2026-10-07 |
| 10 | E6 boundary | sk-06 reserves local-ci `verification` list + workflow inventory; this plan touches neither; no sk-06 wait | E6 D7, D9; round 4 |
| 11 | Shim retirement | deferred; D3 permanent shims; ledger class change red | E6 D3, D6; round 2 |
| 12 | Checker path | `ts-tooling/src/leaf/check-host-parity.mts` → `scripts/lib/leaf/check-host-parity.mjs`; invoked with `node` | ADR-0018, D4 |
| 13 | Rule set | codex/opencode frozen; claude-code empty; gemini/auggie/copilot = codex denylist + own markers | round 6 (Simplifier) |
| 14 | Verification | focused existing suites + aggregate + prek + `git diff --check`; new tests via `tests/test-scripts.sh` discovery | publisher `verification_not_at_base`; B2 D-10 |
| 15 | Red legs | each goal red-first with negative fixtures; H4's red = the README delivery-rule, carve-out and proof-reference sentences (absent after H1, which owns only the matrix rows) + seeded violations; H3's corpus = every host-declaring skill; claude-code has no unmarked fixture (empty denylist) | master §4.7; round 7; review round 1 |
| 16 | Catalog rules | never two open PRs on `catalog.json`; lock-bump batch after H4 (choke 3/7) recorded as cross-lane note | B2 spec §Successor plan |
| 17 | Regime | born readiness-contract/2, live mode; fresh-plan ADD; agent-self disclosure; no approval minted | umbrella R1; standing orders |
| 18 | Scope contention | exact-file scoping; no shared file with open #139 | first-hand `gh pr view 139 --json files` |

Ambiguity threshold met: 12.75% ≤ 20%. Every input is confirmed or decided; human-only decisions are in `stop-questions.md`.

## Adversarial pass (grill-with-docs then grill-me; agent-run)

**grill-with-docs** — run against skills `AGENTS.md`, `CONTEXT.md`, ADR-0015/0016/0017/0018, `modules/readiness-v2.md`, the bound B2 spec, the E6 spec (D1–D13), root `AGENTS.md` (OMO coexistence), the root master intake and the mega-plan §2b at the bases named in `sources.md`:

- (a) A replay cannot replace the `tswc-skills-lane` entry (B2 merged) → fresh-plan ADD with its own spec file; the bound B2 copy is not edited.
- (b) `handoff-write.sh` refuses verification scripts absent at the base → the three new tests are named in scope and ACs, not in `verification[]`.
- (c) `tests/ts_tooling_test.sh` runs only `build/test/sample.test.mjs` and is pinned in local-ci → TS unit tests are not the vehicle; plain-bash tests are.
- (d) `freeze-measure` shellchecks/shfmt-checks every tracked `.sh`; growth is red → new tests must be clean (AC).
- (e) `tests/e6_py_leaf_parity_test.sh` compares the shims against anchored Python; its unknown-host case is `nope` → alias resolution in `catalog-query.mts`, not in `select()`; the corpus stays byte-identical.
- (f) `AGENTS.md` is a policy source; editing it invalidates in-flight contexts; SKILL.md edits trip the no-growth guard digest → docs go to README's manual section only.
- (g) D7 reserves the local-ci `verification` list and workflow inventory for sk-06; `prek.toml` is in every active E6 goal's scope → no hook wiring; aggregate discovery suffices.
- (h) ai-catapult `src/skill-resolver.ts` still bundles by `supported_hosts` with no `experimental` exclusion → the empty host list stays the only guard; cross-lane note carried.
- (i) Master §3e/FU-4 call `omo-ai` first-class; M-6 says define a contract or drop it → dropped by a dated coordinator-recommended decision that wins under the precedence rule; root follow-up SQ-2.

**grill-me:**

- "Does H1 need `catalog.json`?" No. `supported_hosts` is already mandatory for every entry; the matrix is a sibling file; the hot file is not reserved.
- "Will `--host omc` leak into `supported_hosts`?" No. `catalog-model.mts` is untouched; `rejectHosts` refuses it; AC-2 tests a committed throwaway catalog listing `omc`.
- "Does the generalized checker change today's results?" No. codex/opencode rules are frozen byte-for-byte and the shims delegate; three suites prove it; H3's test asserts output equality per catalog file.
- "Will any declared (skill, host) pair fail the new default rules?" Not at the base: every skill passes the codex denylist and only `autobahn/SKILL.md:69` carries a marker, on a construct-free line. A committed simulation at the PR head is still required; a failure is cured by a marker in that skill through a separate reviewed change (SKILL.md guard), never by widening the rule silently.
- "Does the successor block E6 or vice versa?" No shared file at the base. Directory-level overlap with `e6-sk-02-v1-port` (`ts-tooling`) is file-disjoint from #139; whichever merges second rebases and rebuilds (the drift hook enforces equality with a fresh build).
- "Is H4 real work?" It is a catalog-wide gate with its own red leg (the README delivery-rule, carve-out and proof-reference sentences that H1 does not add; seeded violations) and the place where the M-5 carve-outs become test assertions.
- "What about the lock bump?" One batched ai-catapult PR after H4 merges (choke 3/7); recorded, not a dependency.

## Ralplan consensus slicing (tracer bullets, one PR each)

| Goal | Slice | In-plan edges | Cross-plan / cross-lane |
|---|---|---|---|
| `tswc-sk-e5-h1` | `host-matrix.json` + TS resolver + alias-aware `catalog-query` + plain-bash matrix test + README rows | — | after `e6-sk-00-ledger` (`a389a525`) and `e6-sk-01-py-leaf` (`10a650db`), both merged; root OMO test is the collision guard |
| `tswc-sk-e5-h3` | one rule table + `check-host-parity` entrypoint + delegating `skill-parity.mts` + fixtures + plain-bash parity test | ← H1 | shims and their suites unchanged; e6 differential test green |
| `tswc-sk-e5-h4` | plain-bash delivery gate over every payload host and alias + README delivery statement/table + lock-bump note | ← H1, ← H3 (M-4) | lock bump = later ai-catapult PR (choke 3/7); promotion = later goal (B1/B3) |

Planner / Architect / Critic consensus (agent-run, three iterations): iteration 1 proposed scoping `ts-tooling` as a directory (rejected: blocks and is blocked by the E6 chain); iteration 2 proposed putting the matrix inside `catalog.json` (rejected: hot file, schema 1.0 consumers, no need); iteration 3 accepted exact-file scopes, the sibling matrix file, frozen codex/opencode rules, deferred shim retirement and deferred hook wiring.

## Decision log

- **D-1 (confirmed):** every master §8 input is accepted as pre-answered; FU-1 re-pin to the current root bytes (`5f54c26a…`, `f35bc99c…`).
- **D-2 (agent-run):** the matrix is `host-matrix.json` at the repo root; `catalog.json` is not edited by any goal.
- **D-3 (agent-run, M-4):** H3 ← H1; H4 ← H1, H3 as bundle dependencies.
- **D-4 (agent-run, M-5):** declared host set is the truth; `edit-article` stays `["opencode"]`; role skills stay `[]`; widening is SQ-1.
- **D-5 (agent-run on the coordinator's recommendation, M-6):** `omo-ai` dropped; recorded under `excluded`; OMO adapter quarantined; root test is the guard; root follow-up is SQ-2.
- **D-6 (agent-run):** H1's predecessors are sk-00 and sk-01 only; no goal waits for sk-06; hook/workflow/local-ci-verification wiring is a later goal after sk-06.
- **D-7 (agent-run):** shim retirement deferred (E6 D3/D6); shims byte-identical; `.mts` sources delegate to one table.
- **D-8 (agent-run):** checker realized as `ts-tooling/src/leaf/check-host-parity.mts` → `scripts/lib/leaf/check-host-parity.mjs`, invoked with `node`; no shim.
- **D-9 (agent-run):** rule table defaults: codex/opencode frozen; claude-code empty; gemini/auggie/copilot = codex denylist with own markers; tighter rules are later decisions.
- **D-10 (agent-run):** `verification[]` names existing focused suites, the aggregate, `prek run --all-files` and `git diff --check`; new tests are scope + AC.
- **D-11 (agent-run):** exact-file scoping under `ts-tooling/src/leaf/` and `scripts/lib/leaf/`; README is the only shared doc surface (manual section).
- **D-12 (agent-run):** promotion of the role skills is a later goal gated on `tswc-ac-b1`/`tswc-ac-b3` and the `catalog.json` window; no id invented.
- **D-13 (agent-run):** the lock-bump batch (choke 3/7) is recorded in H4 as a cross-lane note, not a dependency.
- **D-14 (agent-run):** HELD DRAFT; publication conditions in `HELD-UNTIL-GREENLIGHT.md`; agent-self disclosure; no approval minted; readiness unknown.
- **D-15 (review round 1 cure, 2026-10-14):** H3's checker keeps the frozen labels `Codex`/`opencode` so its codex/opencode output is byte-identical to the shims; `claude-code` has no unmarked-construct fixture (empty denylist); H3's corpus is every host-declaring skill (39 at the base; the three host-less role skills carry no parity obligation until promotion); H4's README red leg is the delivery-rule, carve-out and proof-reference sentences, which H1 does not add. Scope, dependencies, decisions and authority unchanged.
- **D-16 (publication, 2026-10-14):** published through the supported publisher on skills `origin/main` `823d699cb063b5cc2fe1674baf137f6b2efdb8e4` after coordinator #3 green-light 2026-10-14T07:09:32Z on the human PUB authorization of the same timestamp (root .omc/plans/hitl-answers-20261014.md). Publication-time edits, re-reviewed with the planning PR (Architect + blind Critic): the spec header/status and publication base, the AC-1 base observation of every goal, the `agent_self`/`publication_posture`/`regime`/`e6_decisions` posture attachments, the sidecar base words, the `reviews.md` deferred-with-disclosure Risks sentence (`write-a-skill/SKILL.md:56` fenced marker), this intake's status lines, and one observation correction found first-hand at publication: ai-catapult `tswc-ac-b1` (PR #63, `3fa658b2…`, 2026-10-12T03:39:44Z) and `tswc-ac-b3` (PR #70, `a29d9e3a…`, 2026-10-12T15:47:52Z) are merged, contrary to the draft's "not merged" statement in spec decision 7, `dependency_structure` and SQ-3; the B1/B3 gate of the later promotion goal is therefore met, promotion stays a later goal (catalog.json window; own interview, review and publication), and SQ-3's rationale is for the coordinator to revisit. Scope, dependencies, verification, decisions D-1..D-15 and authority unchanged. AGENT-SELF — no human approved it.
