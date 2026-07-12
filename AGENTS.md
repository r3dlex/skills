---
name: agents
description: Agent-facing documentation for this skills repository
---

# Skills Repository

This repository contains agent skills following progressive disclosure principles.

## Quick Start

Pick the skill matching the user's request. Each skill has:
- **name** — skill identifier
- **description** — when to trigger it
- **body** — workflow and Quick Start

## Skills

deprecated aliases: `init-ai-repo` and `ai-sdlc-init` remain compatibility entries in the generated catalog.

<!-- GENERATED:SKILL-CATALOG:START -->
| Skill | When to use | Lifecycle | Owner phase |
|---|---|---|---|
| [`ai-catapult-init`](03-configure-generate/ai-catapult-init/SKILL.md) | Bootstrap AI-ready governance, traceability, cascade, catalog audits, and validation. Use when setting up AI SDLC; aliases: init-ai-repo and ai-sdlc-init. | `stable` | `03-configure-generate` |
| [`ai-sdlc-init`](03-configure-generate/ai-sdlc-init/SKILL.md) | Deprecated compatibility alias for ai-catapult-init. Use only when legacy prompts invoke "ai-sdlc-init"; otherwise use "ai-catapult-init". | `compatibility` | `03-configure-generate` |
| [`autobahn`](04-validate-handoff/autobahn/SKILL.md) | Ship implementation-ready goals from a northstar handoff or evidence-complete direct record, with review, CI, fail-closed merge, and cascade closure. | `stable` | `04-validate-handoff` |
| [`design-an-api-or-interface`](02-govern-plan/design-an-api-or-interface/SKILL.md) | Design APIs/interfaces with Design It Twice: create alternatives, compare tradeoffs, choose one. Use when designing an API, module, class, or boundary. | `stable` | `02-govern-plan` |
| [`diagnose`](04-validate-handoff/diagnose/SKILL.md) | Run a reproduce-minimize-hypothesize-instrument-fix loop. Use when debugging bugs, failures, thrown errors, or performance regressions. | `stable` | `04-validate-handoff` |
| [`edit-article`](03-configure-generate/edit-article/SKILL.md) | Edit and improve articles by restructuring sections, improving clarity, and tightening prose | `stable` | `03-configure-generate` |
| [`eval-a-skill`](04-validate-handoff/eval-a-skill/SKILL.md) | Scaffold a structurally valid eval triplet for a target skill under .ai/evals/. CI checks structure only; the LM-judge runs out-of-band, never in CI. | `stable` | `04-validate-handoff` |
| [`grill-me`](02-govern-plan/grill-me/SKILL.md) | Interview the user to stress-test a plan or design until decisions are clear. Use when the user wants to be grilled or challenge a plan. | `stable` | `02-govern-plan` |
| [`grill-with-docs`](02-govern-plan/grill-with-docs/SKILL.md) | Stress-test a plan against repo docs and update decisions inline. Use when challenging a design against documented language, ADRs, or CONTEXT.md. | `stable` | `02-govern-plan` |
| [`handoff`](04-validate-handoff/handoff/SKILL.md) | Compact the current conversation into a handoff document for another agent to pick up. | `stable` | `04-validate-handoff` |
| [`improve-codebase-architecture`](02-govern-plan/improve-codebase-architecture/SKILL.md) | Find deepening opportunities from CONTEXT.md and ADRs. Use when refactoring shallow modules, boundaries, coupling, or testability. | `stable` | `02-govern-plan` |
| [`init-ai-repo`](03-configure-generate/init-ai-repo/SKILL.md) | Deprecated compatibility alias for ai-catapult-init. Use only when legacy prompts invoke "init-ai-repo"; otherwise use "ai-catapult-init". | `compatibility` | `03-configure-generate` |
| [`northstar`](02-govern-plan/northstar/SKILL.md) | Planning-only intake: turn intent into a tracked, sliced plan and A→B handoff; never implement product changes. Use before autobahn execution. | `stable` | `02-govern-plan` |
| [`prototype`](03-configure-generate/prototype/SKILL.md) | Build a throwaway terminal or UI prototype to test state, logic, or design options. Use when the user wants a playable prototype or design trial. | `stable` | `03-configure-generate` |
| [`publish-semver`](04-validate-handoff/publish-semver/SKILL.md) | Set up semantic or calendar versioning and package publishing across supported ecosystems. Use when configuring release automation or changelogs. | `stable` | `04-validate-handoff` |
| [`setup-skills`](03-configure-generate/setup-skills/SKILL.md) | Configure AGENTS/CLAUDE and docs/agents for tracker, triage labels, and domain docs. Use before issue, PRD, triage, TDD, or diagnosis skills. | `stable` | `03-configure-generate` |
| [`tdd`](03-configure-generate/tdd/SKILL.md) | Run red-green-refactor with one failing test, one implementation, then cleanup. Use when building features or fixes test-first. | `stable` | `03-configure-generate` |
| [`to-issues`](02-govern-plan/to-issues/SKILL.md) | Break a plan, spec, or PRD into traceable implementation issues. Use when converting requirements into tickets or agent-ready work. | `stable` | `02-govern-plan` |
| [`to-prd`](02-govern-plan/to-prd/SKILL.md) | Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context. | `stable` | `02-govern-plan` |
| [`triage`](02-govern-plan/triage/SKILL.md) | Triage issues through canonical state labels and ownership roles. Use when creating, reviewing, prioritizing, or preparing issues for agents. | `stable` | `02-govern-plan` |
| [`ubiquitous-language`](01-discover-decide/ubiquitous-language/SKILL.md) | Extract and save a DDD glossary, flag ambiguities, and propose canonical terms. Use when defining domain language or a shared vocabulary. | `stable` | `01-discover-decide` |
| [`using-git-worktrees`](03-configure-generate/using-git-worktrees/SKILL.md) | Create isolated git worktrees with safety checks and setup guidance. Use when starting feature work that needs separation from the main checkout. | `stable` | `03-configure-generate` |
| [`write-a-skill`](03-configure-generate/write-a-skill/SKILL.md) | Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill. | `stable` | `03-configure-generate` |
| [`write-agent-docs`](03-configure-generate/write-agent-docs/SKILL.md) | Write or audit agent-facing Markdown with progressive disclosure. Use when editing SKILL.md, AGENTS.md, README.md, or other agent docs. | `stable` | `03-configure-generate` |
| [`zoom-out`](01-discover-decide/zoom-out/SKILL.md) | Explain broader code or product context around a focused area. Use when the user needs a higher-level perspective before local changes. | `stable` | `01-discover-decide` |
<!-- GENERATED:SKILL-CATALOG:END -->

### Pipeline: `northstar` → `autobahn`

In an `ai-catapult-init`-initialized repo, the two compose into an intake→ship loop:

1. **`northstar "<intent>"`** — deep-interview (primary) + grill-me (adversarial, skippable) one question at a time until both are satisfied → always raises an issue (local-first markdown; hosted only if a tracker is configured and authorized, fail-closed) → `ralplan` → sliced goals. Writes the **A→B handoff** into `.ai/` (workflow manifest `optional_branches` entry, traceability nodes, `.ai/handoff/`).
2. **`autobahn`** — discovers the handoff, or accepts one evidence-complete direct-ready goal when discovery is already finished, and ships each goal as **one PR**. Before engine selection it chooses standard or legacy-safe TDD: coverage under 30% always uses legacy-safe mode, and the running agent may also select it for recorded context-specific blast-radius risk. `ultragoal` orchestrates; deterministic engine precedence is `ultraqa` > `ultrawork` > `ralph` > `team`; peer review, remote + local CI, fail-closed merge authority, and cascade closure remain mandatory.

Both are lightweight composers: they delegate to the existing skills/engines and never reimplement them. Each runs identically under OMC (`/oh-my-claudecode:<name>`) and OMX (`$<name>`) via the generated `.ai/commands/{omc,omx}/` surfaces.

## Writing Rules

Description budget: target <=160 characters; an audited exception may reach 180, the absolute maximum. Run `python3 scripts/validate-skill-catalog.py` after changing metadata.

All skills follow Layer 2 guidelines:
- Quick Start first
- Numbered steps for workflows
- Bullet points for options
- Reference deeper files with "when to read" context
- No "Overview" or "Background" sections
- Target <=100 body lines; audited exceptions may reach 180

### Codex parity

Skill bodies must be tool-agnostic across Claude Code and Codex. Do not hard-depend on Claude/OMC-only invocations (`AskUserQuestion`, `Task(subagent_type=...)`, `Skill(...)`, `subagent_type:`, `TodoWrite`, `mcp__*`); use plain-markdown prose instead. `scripts/check-codex-parity.sh` enforces this and scans real invocations only (mentions inside backticks or fenced code blocks are ignored). When a Claude-only construct is unavoidable, annotate it with the `<!-- codex:optional -->` marker on the construct line (or the line directly above it, with no blank line between) and describe a plain-markdown fallback adjacent to it. See `write-a-skill/SKILL.md` for the convention. The mechanical check is the P0/P1 bar; the P2 **verified** bar — representative skills actually run under Codex — is recorded out-of-band per `docs/learning/codex-verification.md` (never a live Codex run in CI).

## Layers

| Layer | File | Size |
|-------|------|------|
| 1 – Signal | frontmatter `description` | < 150 words |
| 2 – Core | SKILL.md body | target <=100 lines; audited maximum 180 |
| 3 – Detail | REFERENCE.md | unlimited |

## Domain Language

[CONTEXT.md](CONTEXT.md) defines the canonical vocabulary for the skills ecosystem — terms like _skill_, _progressive disclosure_, _AFK_, _HITL_, _tracer bullet_, _deep module_. Use these terms exactly in all agent output. When skills operate on target repos, they read that repo's CONTEXT.md and use its vocabulary.

See [write-agent-docs/SKILL.md](write-agent-docs/SKILL.md) for full audit and refactor workflow.

<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This repository uses the ai-catapult-init methodology. The deprecated aliases `init-ai-repo` and `ai-sdlc-init` remain valid during path migration.

### Architecture Decision Records

Significant architectural decisions are recorded in [`docs/architecture/adr/`](docs/architecture/adr/).
Before making a change that affects module boundaries, API contracts, data
schemas, or dependency direction, check whether a relevant ADR exists.
If your change contradicts an existing ADR, either update the ADR or open a
discussion before proceeding.

### Archgate Rules

Code quality rules are defined in [`.rules.ts`](.rules.ts) across five domains:
`backend`, `frontend`, `data`, `architecture`, `general`. Rules carry a severity
(`error`, `warn`, `info`). Structural validation of `.rules.ts` runs in CI via
the `validate-rules` prek hook. Semantic enforcement (did the PR violate a rule?)
is an agent behavior at PR review time.

### Karpathy Baseline

All agents operating in this repository load
[`.agents/skills/karpathy-guidelines/SKILL.md`](.agents/skills/karpathy-guidelines/SKILL.md)
as a baseline. Four rules apply to every task: Think Before Coding, Simplicity
First, Surgical Changes, Goal-Driven Execution. See the SKILL.md for violation
and correction examples.

### Drift Verification Protocol

At PR review time, the reviewing agent:
1. Loads the PR diff alongside the BRD, PRD, acceptance criteria, and any ADRs
   whose scope overlaps with the changed files.
2. Produces a drift report identifying whether changes match ACs, conflict with
   ADRs, or violate architectural constraints from `.rules.ts`.
3. Leaves the drift report as a PR comment or review summary.

This is a documented agent behavior. It is not enforced as a CI gate in this
iteration.

### Circuit Breaker Protocol

Before starting work on an issue:
1. Check whether ≥ 3 prior attempts exist without resolution (look for
   `attempts:N` labels or a comment history showing repeated failures).
2. If the circuit is tripped (≥ 3 attempts, no resolution), escalate to a
   human with a written summary of what was tried and what blocked each attempt.
3. Do not make a fourth attempt without human acknowledgement.

<!-- ai-sdlc-init:end -->

<!-- v3-ai-sdlc-init:start -->
## AI SDLC v3
This repo follows the v3 AI-SDLC layout. See `.ai/matrix.json`, `.memory/human-override/`, and `docs/architecture/adr/`. Modules at `r3dlex/skills/ai-catapult-init/modules/`.
<!-- v3-ai-sdlc-init:end -->
