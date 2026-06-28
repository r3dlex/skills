# Intake-to-Goals & Ship-Goals Skills Spec

Status: Active
Owner: `skills/` (catalog) + `skills/init-ai-repo` (integration)
Date: 2026-06-28
Source context:
- Deep-interview record: `.omc/specs/deep-interview-intake-ship-skills.md`
- Composes existing skills: `deep-interview`, `grill-me`, `to-issues`, `triage`, `ralplan`/`plan`, `ultragoal`, `team`, `ralph`, `ultrawork`, `ultraqa`, `code-reviewer`/`architect`/`executor`, `init-ai-repo` (cascade, host-policy, workflow surfaces, traceability)

## 1. Purpose

Add two **lightweight, composable** skills that formalize the end-to-end developer loop this workspace already runs by hand: an **intake/plan** skill that turns intent into a tracked, sliced plan, and an **execute** skill that ships those slices one PR at a time with a peer-review gate. Both **assume the repo was already initialized with the `init-ai-repo` v3 structure** (they consume `.ai/`, never bootstrap it), stay lean (Codex-parity-clean SKILL.md, progressive disclosure, delegate to existing skills/engines — no reimplementation), and register as first-class commands in both OMX and OMC.

Skill names (chosen): **Skill A = `northstar`** (fixes direction — clarifies intent into a tracked, sliced plan), **Skill B = `autobahn`** (the fast autonomous delivery lane — one PR per goal to merge).

## 2. Topology (confirmed)

| Component | Status | Description |
|-----------|--------|-------------|
| A. `northstar` | active | deep-interview (primary) + grill-me (adversarial, skippable) loop → always raise an issue → ralplan → sliced-goal artifacts. Carries its own init-ai-repo + OMX/OMC integration. |
| B. `autobahn` | active | consume A's sliced goals → ultragoal one-PR-per-goal (auto-pick sub-engine, user-overridable) → architect+reviewer+executor peer-review loop → CI green → gated auto-merge → cascade issue closure. Carries its own integration. |

Integration into init-ai-repo + OMX/OMC is **merged into each skill** (not separate components).

## 3. Goal

A developer (or agent) runs `northstar` to converge intent into a crystal-clear, tracked, sliced plan, then `autobahn` to autonomously deliver each slice as a reviewed, CI-green, merged PR with issues closed — all within an already-`init-ai-repo` repo, lightweight, and identical across OMX and OMC.

## 4. Scope

### 4.A Skill A — `northstar`

- **Prereq (fail-closed):** verify the `init-ai-repo` v3 structure is present (`.ai/matrix.json`, workflow manifest, host-policy); abort with guidance if not.
- **Loop (HITL, one question at a time):** `deep-interview` is the **primary** driver to ambiguity ≤ threshold; `grill-me` runs as an **optional adversarial pass** the user may **skip**. "Both satisfied" = deep-interview gate met AND (grill-me decision-tree clear OR explicitly skipped). Delegates to the existing skills — does not reimplement their loops.
- **Always raise an issue** after the loop: **local-first markdown**, **hosted** (GitHub/ADO/GitLab/Jira) only when a tracker is configured **and** authorized (fail-closed, per `init-ai-repo` host-policy). Uses `to-issues` + `triage` canonical state labels/ownership. Skipping grill-me bypasses only the adversarial pass — the issue is raised regardless.
- **Then `ralplan`** (consensus) on the crystallized spec → **sliced goals**.
- **Handoff (A→B contract):** spec → `docs/specifications/ACTIVE/`; issue ref + sliced goals → `.ai/` work-intake/plans tree; a **handoff entry** in `.ai/handoff/` + the **workflow manifest** (`.ai/workflows/repo-workflow.json`). Register spec/issue/goal nodes in the **traceability graph**. B discovers work via the manifest.

### 4.B Skill B — `autobahn`

- **Prereq (fail-closed):** verify init-ai-repo structure AND a valid A-handoff (manifest entry + sliced goals); abort with guidance if absent.
- **Orchestration:** `ultragoal` is the durable per-goal driver (ledger, **one PR per goal**). Per goal it **auto-picks the sub-engine** by goal shape — default `team`; `ralph` for persistence; `ultrawork` for parallel; `ultraqa` for QA-heavy — and the **user can override** via a command arg.
- **Per goal:** implement → **architect + reviewer + executor peer-review loop** → **resolve ALL comments** → ensure **remote host CI AND local CI green** → merge.
- **Merge authority (configurable, fail-closed):** default = run the agent loop + CI green, then merge per repo branch policy; **same-actor admin-bypass ONLY when explicitly authorized** (flag/config) — otherwise stop at "ready for human approval." Honors the workspace merge protocol (reviewer APPROVE + GH CI + local CI green; loop until every comment/finding resolved).
- **Issue closure:** after merge, **update issues across all configured repo(s)** via the `init-ai-repo` **cascade engine** and close with the appropriate `triage` canonical status (idempotent, audited, first-run confirmation per host-policy).

### 4.C Cross-cutting (both skills)

- **Lightweight:** SKILL.md < 100 body lines, description ≤ 180 chars, progressive disclosure to `modules/`/`reference/`. **Delegate** to existing skills/engines via OMC `Skill()` / OMX equivalents — no duplicated loop logic.
- **Tool-agnostic / Codex parity:** pass `scripts/check-codex-parity.sh` (no Claude/OMC-only hard deps unmarked); appear in the AGENTS.md skill index (forward+reverse parity); pass the description-budget + catalog-audit gates.
- **OMX/OMC integration:** generate command-surface registration under `.ai/commands/omx/` and `.ai/commands/omc/` so both are first-class commands in both harnesses; long `autobahn` runs use the existing background-task + ultragoal durable ledger (survives sessions). **No new daemon / state system.**
- **init-ai-repo integration:** both are wired into the generated workflow surfaces (manifest phases, handoff index) so an initialized repo advertises them.

### 4.D Out of scope / non-goals

- Bootstrapping the repo (assumed already `init-ai-repo`-initialized).
- New scheduling/cron infrastructure (deferred; bg = existing task + ledger).
- A second credentialed reviewer identity (the "distinct reviewer actor" merge mode is not the default; admin-bypass-if-authorized is).
- Reimplementing deep-interview/grill-me/ralplan/ultragoal logic.

## 5. Acceptance Criteria (test-first, offline)

- [ ] Both skills exist with valid frontmatter, < 100 body lines, description ≤ 180 chars; pass `check-codex-parity.sh`; present in AGENTS.md index (forward+reverse); catalog-audit green.
- [ ] Each skill prereq-checks the init-ai-repo structure and **fails closed** with guidance when absent (test with a non-initialized fixture).
- [ ] `northstar` documents/delegates: deep-interview primary + grill-me skippable; always-raise-issue (local-first/hosted-if-authorized); ralplan → sliced goals; writes the A→B handoff (manifest entry + sliced goals + spec + traceability nodes).
- [ ] `autobahn` documents/delegates: ultragoal one-PR-per-goal; auto-engine-pick + user override; architect+reviewer+executor loop; CI-green gate; configurable merge authority (admin-bypass only if authorized, else stop); cascade issue closure with triage status.
- [ ] A→B handoff contract is validated by a fixture (manifest entry resolvable; sliced goals discoverable).
- [ ] OMX + OMC command-surface entries generated for both; both wired into the init-ai-repo workflow manifest.
- [ ] `tests/run-tests.sh` green offline; no new runtime deps; no model/network in CI.

## 6. Assumptions Exposed & Resolved

| Assumption | Challenge | Resolution |
|------------|-----------|------------|
| Merge loop is deep-interview+grill-me interleaved | which model? | deep-interview primary, grill-me adversarial+skippable |
| Issue raised only on skip | when/where? | always after loop; local-first, hosted-if-authorized (fail-closed) |
| Single fixed engine | how chosen? | ultragoal orchestrates, auto-pick sub-engine per goal, user-overridable |
| Fully autonomous auto-merge | branch protection blocks same-actor | configurable; admin-bypass only if authorized, else stop; fail-closed |
| Skills also init the repo | needed? | no — assume init-ai-repo present; prereq-check, fail closed |
| Handoff via .omc only | survivable/native? | init-ai-repo surfaces + manifest (+ traceability nodes) |
| Heavy bg infra for OMX/OMC | lightweight? | tool-agnostic SKILL.md + bg task + command-surface registration; no daemon |

## 7. Ontology (Key Entities)

| Entity | Type | Relationships |
|--------|------|---------------|
| northstar (Skill A) | core | emits spec/issue/sliced-goals + handoff manifest entry |
| autobahn (Skill B) | core | consumes handoff; emits PRs, merges, closed issues |
| sliced-goal | core | produced by ralplan; one PR per goal in B |
| handoff manifest entry | core | A→B contract; lives in .ai/handoff + workflow manifest |
| issue | core | raised by A (local/hosted); closed by B via cascade |
| engine (ultragoal/team/ralph/ultrawork/ultraqa) | supporting | B's implementation drivers |
| peer-review loop (architect+reviewer+executor) | core | B's per-PR gate |
| merge authority | supporting | configurable; admin-bypass-if-authorized |
| init-ai-repo surfaces (.ai/) | core | both skills consume; prereq |

## 8. Interview Record

Full transcript: `.omc/specs/deep-interview-intake-ship-skills.md`. Final ambiguity ~17% (threshold 20%, source default). Rounds: 6 + Round 0 topology. Contrarian (R4) challenged auto-merge → configurable/fail-closed; Simplifier (R6) minimized OMX/OMC bg integration.
