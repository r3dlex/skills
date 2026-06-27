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

| Skill | When to Use |
|-------|-------------|
| `write-agent-docs` | Creating or auditing agent-facing .md files |
| `write-a-skill` | Creating new skills |
| `design-an-api-or-interface` | Designing APIs, interfaces, modules |
| `improve-codebase-architecture` | Finding refactoring opportunities, deepening modules |
| `tdd` | Test-driven development with red-green-refactor |
| `edit-article` | Editing articles, tightening prose |
| `ubiquitous-language` | Building DDD-style glossaries |
| `using-git-worktrees` | Setting up isolated workspaces |
| `publish-semver` | Publishing packages with semver, GitHub Actions, and multi-ecosystem registries |
| `init-ai-repo` | Initialize AI-ready repo governance, traceability, cascade, catalog audit, and validation; deprecated alias: `ai-sdlc-init` |
| `to-prd` | Turning conversation context into a PRD on the issue tracker |
| `to-issues` | Breaking a plan or PRD into independently-grabbable tracker issues |
| `triage` | Triaging issues through a role-driven state machine |
| `diagnose` | Disciplined diagnosis loop for hard bugs and performance regressions |
| `grill-me` | Stress-testing a plan or design through relentless interview |
| `grill-with-docs` | Stress-testing a plan against repo docs, ADRs, and CONTEXT.md |
| `setup-skills` | Configuring AGENTS/CLAUDE and docs/agents before issue, PRD, triage, TDD, or diagnosis skills |
| `prototype` | Building a throwaway terminal or UI prototype to test state, logic, or design options |
| `zoom-out` | Explaining broader code or product context before local changes |
| `handoff` | Compacting the conversation into a handoff document for another agent |
| `eval-a-skill` | Scaffolding a structurally valid eval triplet for a target skill; CI checks structure, the judge runs out-of-band |

## Writing Rules

Description budget: target <=180 characters; hard-fail >280 characters unless `.ai/skills/description-exceptions.json` records an audited exception. Run `python3 scripts/validate-skill-catalog.py` after changing skill metadata.

All skills follow Layer 2 guidelines:
- Quick Start first
- Numbered steps for workflows
- Bullet points for options
- Reference deeper files with "when to read" context
- No "Overview" or "Background" sections
- Under 100 lines

### Codex parity

Skill bodies must be tool-agnostic across Claude Code and Codex. Do not hard-depend on Claude/OMC-only invocations (`AskUserQuestion`, `Task(subagent_type=...)`, `Skill(...)`, `subagent_type:`, `TodoWrite`, `mcp__*`); use plain-markdown prose instead. `scripts/check-codex-parity.sh` enforces this and scans real invocations only (mentions inside backticks or fenced code blocks are ignored). When a Claude-only construct is unavoidable, annotate it with the `<!-- codex:optional -->` marker on the construct line (or the line directly above it, with no blank line between) and describe a plain-markdown fallback adjacent to it. See `write-a-skill/SKILL.md` for the convention.

## Layers

| Layer | File | Size |
|-------|------|------|
| 1 – Signal | frontmatter `description` | < 150 words |
| 2 – Core | SKILL.md body | < 100 lines |
| 3 – Detail | REFERENCE.md | unlimited |

## Domain Language

[CONTEXT.md](CONTEXT.md) defines the canonical vocabulary for the skills ecosystem — terms like _skill_, _progressive disclosure_, _AFK_, _HITL_, _tracer bullet_, _deep module_. Use these terms exactly in all agent output. When skills operate on target repos, they read that repo's CONTEXT.md and use its vocabulary.

See [write-agent-docs/SKILL.md](write-agent-docs/SKILL.md) for full audit and refactor workflow.

<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This repository uses the init-ai-repo methodology. The deprecated `ai-sdlc-init` alias remains valid during path migration.

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
This repo follows the v3 AI-SDLC layout. See `.ai/matrix.json`, `.memory/human-override/`, and `docs/architecture/adr/`. Modules at `r3dlex/skills/init-ai-repo/modules/`.
<!-- v3-ai-sdlc-init:end -->
