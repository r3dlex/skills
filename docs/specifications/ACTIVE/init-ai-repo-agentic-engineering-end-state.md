# init-ai-repo Agentic-Engineering End-State Spec

Status: Active
Owner: `skills/init-ai-repo`
Date: 2026-06-27
Supersedes: `.omx/specs/deep-interview-init-ai-repo-state-of-art-ai-sdlc.md` (archived) and the PR6 RALPLAN stack scope (`.omx/plans/ralplan-init-ai-repo-state-of-art-ai-sdlc-pr6.md`)
Source context:
- Whitepaper: *The New SDLC With Vibe Coding* (Osmani, Saboo, Kartakis; May 2026) — `~/Downloads/Day_1_v3.pdf`
- Deep-interview record: `.omc/specs/deep-interview-init-ai-repo-agentic-engineering.md`
- Prior in-flight spec (absorbed): `.omx/specs/deep-interview-init-ai-repo-state-of-art-ai-sdlc.md`

## 1. Purpose

Bring the `skills` repository — and every repository `init-ai-repo` bootstraps — to the **agentic-engineering** end-state described in the Day-1 whitepaper. The paper's thesis: the differentiator between *vibe coding* and *agentic engineering* is not the model but the **harness** around it — instructions/rule files, tools, sandboxes, orchestration, guardrails/hooks, observability — and the **verification** layer of tests **and** evals.

This spec consolidates two bodies of work into a single tracked end-state:

1. The **PR6 "state-of-the-art" scope** already in flight (rename, workflow surfaces, traceability graph, cascade engine, catalog modernization, compact-description budget, validation package). Absorbed verbatim in §4.A so nothing is dropped.
2. The **whitepaper net-new** harness/verification gaps not covered by PR6: evals, observability, model routing, MCP/A2A, the six-context-types framing, `eval-a-skill`, an AI-failure-mode review checklist, full **Codex parity**, and the **AGENTS.md-single-source / CLAUDE.md+GEMINI.md thin-stub** rule.

This is a **spec-only** deliverable. Implementation is phased (P0/P1/P2) and handed to a separate, approval-gated execution pass.

## 2. Topology (confirmed components)

| Component | Status | Description |
|-----------|--------|-------------|
| A. init-ai-repo generator | active | Changes to what the `init-ai-repo` skill **generates**: evals scaffold + CI gate, observability surface, model-routing policy, MCP/A2A standards, six-context-types framing, finished `cascade.md` + skill-modernization module, plus all absorbed PR6 generator scope. |
| B. catalog authoring & quality | active | Cross-cutting changes to the skill catalog itself: progressive-disclosure/context budget in `write-a-skill`, a new `eval-a-skill` capability, an AI-failure-mode code-review checklist, and the absorbed PR6 catalog-modernization audit. |
| C. tool-agnostic harness + Codex parity | active | AGENTS.md as single source of truth; CLAUDE.md and GEMINI.md become thin pointers; every skill reaches full Codex parity (invocation surface + no Claude/OMC-only hard dependencies). |

No components deferred.

## 3. Goal

`init-ai-repo` produces, and the `skills` repo itself exemplifies, a complete agentic-engineering harness: rule files as versioned single-source context, dynamic skills with enforced context budgets, tests **and** evals gating every shippable capability, model routing and observability as first-class generated artifacts, open standards (MCP/A2A) wired in, and full portability across Claude Code and Codex.

## 4. Scope

### 4.A Absorbed PR6 scope (in scope — do not drop)

Carried forward from the archived spec; these remain required:

- Canonical `init-ai-repo` identity with `ai-sdlc-init` deprecated alias/shim and legacy-marker compatibility.
- Generated repo **workflow doc** + machine-readable **workflow/status manifest**, linked from repo entrypoints (see §4.C for the corrected linking rule).
- **Traceability graph**: stable IDs and backlinks across BRD/PRD/ADR/plans/issues/PRs/tests/validation/handoff.
- **Multi-repo cascade engine** (`modules/cascade.md`): mother/sub-repo detection, first-run confirmation, idempotent re-runs, reconciliation/audit output, all configured hosts (GitHub, ADO, GitLab, Jira, local).
- **Catalog modernization audit** (skill-modernization module): compact-description budget (target ≤180 chars, hard-fail >280 unless audited exception), progressive disclosure, clear trigger/non-trigger/fallback boundaries, link/alias/referenced-file/script validation, cross-skill workflow links.
- **Validation package**: runnable checks for frontmatter, descriptions, broken links, aliases, referenced files, scripts, generated fixtures, traceability, cascade reconciliation, AI-SDLC compatibility.

### 4.B Whitepaper net-new (in scope)

1. **Evals & verification** (paper §"Testing and quality assurance", §"Set the bar at the eval"):
   - New `init-ai-repo/modules/evals.md` and generated `.ai/evals/` scaffold (evalset structure, scoring rubric template, LM-judge harness stub).
   - **Output evaluation** (artifact: compiles/tests pass) **and trajectory evaluation** (tool-call sequence/intermediate reasoning) both represented.
   - CI **eval-coverage gate**: a shippable capability requires an eval with an explicit rubric, paralleling test-coverage gating. Wired into the PR merge gate in `init-ai-repo/SKILL.md`.
   - Traceability graph extended with **eval-result** and **trajectory-trace** node types.
2. **Observability surface** (paper §"What's in the harness", §"Observing the Harness"): generated logging/trace conventions + a token-cost & trajectory-audit checklist in `validation.md`/`ci-policy.md`.
3. **Model-routing policy** (paper §"Intelligent Model Routing", §"Economics"): generated `.ai/policies/model-routing.json` mapping task-class → model tier (frontier for requirements/architecture/initial implementation; cheap/fast for test-gen, code-review, CI monitoring). Aligns with the OMC haiku/sonnet/opus tiers.
4. **MCP/A2A open standards** (paper org-guidance #3): promote from one passing mention to a real blueprint section/module — generated MCP-server registry stub and an A2A cross-agent handoff convention.
5. **Six-context-types + static/dynamic framing** (paper §"Context engineering"): generated `AGENTS.md` carries an explicit **Harness Map** enumerating Instructions / Knowledge / Memory / Examples / Tools / Guardrails, and the static-vs-dynamic boundary is documented as a reviewed, versioned decision.

### 4.C Tool-agnostic + Codex parity (in scope)

- **AGENTS.md is the single source of truth.** `CLAUDE.md` and `GEMINI.md` are generated as **thin pointers** to `AGENTS.md` only — no content-bearing sections. This **overrides** the absorbed PR6 rule that linked workflow content into CLAUDE.md.
- Self-application fix: this repo's `skills/CLAUDE.md` currently carries an "AI SDLC" section and a stale `docs/adr/` reference; it must be reduced to a pointer (same shape as a generated `GEMINI.md`).
- **Full Codex parity** for every skill, with a **phased verification bar defined here**:
  - **P0 (mechanical, SDLC core):** `init-ai-repo`, `write-a-skill`, `to-prd`, `to-issues`, `triage`, `tdd`, `diagnose`, `publish-semver` — no Claude/OMC-only hard dependencies; discoverable via the AGENTS.md skill index; followable as plain markdown.
  - **P1 (mechanical, all skills):** same mechanical bar applied catalog-wide; Claude-only constructs (e.g. `AskUserQuestion`, `Task(subagent_type=…)`, `Skill(...)`) either abstracted behind tool-agnostic prose or marked as graceful-degradation optional. Known offender to remediate: `improve-codebase-architecture`.
  - **P2 (verified):** representative skills actually executed under Codex to confirm runnability.
- **AGENTS.md skill index lists every catalog skill — no exclusion allowlist** (resolved 2026-06-27). The index is the cross-tool discovery surface, so full index↔catalog parity is the P1 bar (P0 asserts only the SDLC-core subset). Skills currently missing from the index and to be added at P1: `diagnose`, `grill-me`, `grill-with-docs`, `handoff`, `prototype`, `setup-skills`, `to-issues`, `to-prd`, `triage`, `zoom-out`.
- Fix the legacy `docs/adr/` link in `AGENTS.md` (the AI SDLC Methodology / ADR section, currently line 66) → `docs/architecture/adr/`.

### 4.D Out of scope / non-goals

- No implementation in the spec-authoring run (this run produces specs + ADRs only).
- No hosted/branch-policy mutation without explicit, credentialed opt-in (fail closed).
- No new runtime dependencies unless justified at implementation-planning time.
- Rewriting skill *logic* beyond what portability/parity and the modernization audit require.

## 5. Phasing (P0/P1/P2)

**P0 — highest leverage (whitepaper core + your explicit requirement):**
- `modules/evals.md` + `.ai/evals/` scaffold + eval-coverage CI gate + merge-gate wiring.
- AGENTS.md single-source + CLAUDE.md/GEMINI.md thin stubs (generator rule + self-apply to this repo); fix the legacy `docs/adr/` link in `AGENTS.md` (AI SDLC Methodology section, line 66).
- Model-routing policy artifact (`.ai/policies/model-routing.json`).
- Codex parity P0 (SDLC-core skills) + AGENTS.md skill-index discoverability.

**P1 — harness completeness + catalog quality:**
- Observability surface; MCP/A2A module; six-context-types Harness Map in generated AGENTS.md.
- `write-a-skill` progressive-disclosure/context-budget enforcement; AI-failure-mode review checklist.
- Finish absorbed PR6 cascade engine + skill-modernization audit + traceability graph + validation package.
- Codex parity P1 (all skills mechanical); remediate `improve-codebase-architecture`.

**P2 — verification depth:**
- `eval-a-skill` capability (generate rubric + LM-judge eval for other skills).
- Traceability extended with eval-result/trajectory-trace nodes.
- Codex parity P2 (verified runs).

## 6. Acceptance Criteria

Absorbed PR6 criteria (still required):
- [ ] `init-ai-repo/` canonical; `ai-sdlc-init/` is alias/shim; docs/catalog point to canonical.
- [ ] Generated workflow doc + machine-readable manifest exist and validate.
- [ ] Traceability graph: stable IDs + backlinks across requirements/plans/issues/PRs/tests/handoff.
- [ ] Multi-repo cascade: first-run confirmation, idempotent, audit/reconciliation output, all configured hosts; no duplicate linked items on re-run.
- [ ] Full catalog audit runs in CI/local; description budget ≤180 target / >280 hard-fail (audited exceptions only); SKILL.md body limits enforced; trigger/non-trigger/fallback boundaries present.

Whitepaper net-new criteria:
- [ ] `modules/evals.md` + `.ai/evals/` scaffold generated; eval-coverage gate present and wired into the PR merge gate.
- [ ] Output **and** trajectory evaluation both representable; rubric required for any eval.
- [ ] Observability conventions + token-cost/trajectory-audit checklist generated.
- [ ] `.ai/policies/model-routing.json` generated with task-class → tier mapping.
- [ ] MCP-server registry stub + A2A handoff convention generated.
- [ ] Generated `AGENTS.md` includes a Harness Map (six context types) and a documented static/dynamic boundary.

Tool-agnostic / Codex parity criteria:
- [ ] Generated `CLAUDE.md` and `GEMINI.md` are thin pointers to `AGENTS.md` (no content sections); this repo's `CLAUDE.md` reduced accordingly.
- [ ] Legacy `docs/adr/` link in `AGENTS.md` (AI SDLC Methodology section, line 66) corrected to `docs/architecture/adr/`.
- [ ] AGENTS.md skill index lists every catalog skill (no exclusion allowlist) — full index↔catalog parity at P1.
- [ ] P0 SDLC-core skills meet the mechanical Codex bar and are AGENTS.md-discoverable.
- [ ] P1 catalog-wide mechanical bar met; `improve-codebase-architecture` remediated.
- [ ] P2 representative skills verified runnable under Codex.

Cross-cutting:
- [ ] Load-bearing decisions captured as ADRs (`0002`–`0005`).
- [ ] Local CI + host CI green; architect/reviewer/executor agreement before any merge.

## 7. Assumptions Exposed & Resolved

| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| "Specs" = loose planning notes | Where do they live, what format? | `docs/specifications/ACTIVE/` + ADRs in `docs/architecture/adr/`; implementation-ready, phased. |
| Specs are strategic only | Implementation-ready or direction? | Implementation-ready with P0/P1/P2 priority; spec-only this run. |
| Tool-agnostic = rule-file stubs only | How far does it reach? | Full Codex parity for every skill; bar defined per-phase here. |
| Full parity for every skill is required | Contrarian: is that habitual? | Kept; bar defined in-spec (P0 core mechanical → P1 all mechanical → P2 verified). |
| New specs are standalone | They overlap in-flight PR6 work | Supersede: one consolidated end-state spec; old `.omx` spec archived. |
| CLAUDE.md links workflow content (PR6) | Conflicts with single-source rule | Single-source AGENTS.md wins; CLAUDE.md/GEMINI.md become thin stubs. |

## 8. Technical Context (brownfield)

- Spec/ADR conventions verified against `docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md` and `docs/architecture/adr/0001-init.md`.
- Skills already use plain `name`/`description` frontmatter and are indexed in `AGENTS.md` — Codex portability is mostly present; gaps are stubs, a few Claude-only bodies, and the invocation index.
- `scripts/install-codex.sh` already exists (Codex support partially present).
- `init-ai-repo` generates AGENTS/CLAUDE/GEMINI today via `modules/documentation-blueprint.md`, `topology.md`, `workflow.md`.
- No first-class eval/observability/model-routing/MCP-A2A surface exists today (confirmed by grep).

## 9. Ontology (Key Entities)

| Entity | Type | Fields | Relationships |
|--------|------|--------|---------------|
| Spec | core | status, owner, scope, acceptance | supersedes prior specs; references ADRs |
| ADR | core | status, context, decision, consequences | records load-bearing decisions of Spec |
| Generator (init-ai-repo) | core | modules, phases, generated outputs | produces AGENTS/CLAUDE/GEMINI, .ai/*, evals, policies |
| Module | supporting | name, body, references | composes Generator |
| Skill (catalog) | core | name, description, triggers | indexed in AGENTS.md; subject to parity + budget |
| Eval | core | rubric, dataset, judge, type(output/trajectory) | gates Skill/capability; node in Traceability graph |
| Harness | core | instructions, tools, sandboxes, orchestration, guardrails, observability | wraps Model |
| AGENTS.md | core | harness map, skill index | single source; CLAUDE.md/GEMINI.md point to it |
| Model-routing policy | supporting | task-class→tier map | part of Harness/economics |
| Codex parity | core | mechanical bar, verified bar | property of every Skill |

## 10. Ontology Convergence

| Round | Entity Count | New | Changed | Stable | Stability |
|-------|-------------|-----|---------|--------|-----------|
| 1 | 8 | 8 | - | - | N/A |
| 2 | 12 | 4 | 0 | 8 | ~80% |
| 3 | 12 | 0 | 0 | 12 | ~100% |
| 4–5 | 12 | 0 | 0 | 12 | 100% (converged) |

## 11. Interview Record

Full transcript and clarity breakdown: `.omc/specs/deep-interview-init-ai-repo-agentic-engineering.md`. Final ambiguity: ~16% (threshold 20%, source: default). Rounds: 5 + Round 0 topology gate.
