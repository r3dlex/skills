# skills

A collection of reusable agent skills for Codex, Claude Code, and compatible AI agents.

Each skill is a self-contained directory with a `SKILL.md` that tells the agent what to do and when to trigger. Skills follow [progressive disclosure](write-agent-docs/SKILL.md) — lean core instructions, with detail in reference files loaded on demand.

## Skills

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

## Installation

Install the same catalog for either host:

```bash
./scripts/install-codex.sh --all
./scripts/install-claude-code.sh --user
```

Both installers copy the complete skill directory, including `SKILL.md`, references, and bundled scripts. `tests/install_cross_host_parity_test.sh` verifies identical `SKILL.md` content across both destinations.

## Structure

Each skill follows:

```
skill-name/
├── SKILL.md        # Trigger conditions + core workflow (target <=100 lines)
├── REFERENCE.md    # Deep detail, loaded on demand
└── scripts/        # Utility scripts if needed
```

The `description` frontmatter is routing metadata consumed by Codex and Claude Code. Keep it trigger-focused and <=160 characters; an audited exception may reach 180. `SKILL.md` bodies target <=100 lines, with reviewed exceptions capped at 180 in `.ai/skills/body-line-exceptions.json`.

<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This project uses the [ai-catapult-init methodology](https://github.com/r3dlex/skills/tree/main/ai-catapult-init)
to maintain architectural governance alongside AI-assisted development.

Migration note: `ai-catapult-init` is the canonical skill name and path. The
`init-ai-repo/` and `ai-sdlc-init/` directories remain only as deprecated compatibility aliases/shims
until downstream skill loaders have migrated.

Key practices:
- **Architecture Decision Records** in [`docs/architecture/adr/`](docs/architecture/adr/) — significant
  decisions are version-controlled with context and rationale.
- **Archgate rules** in [`.rules.ts`](.rules.ts) — code quality constraints
  across five domains, validated in CI.
- **Karpathy baseline** — four engineering heuristics loaded by all agents
  operating in this repo (think, simplify, be surgical, stay on goal).

Contributing? Read [`AGENTS.md`](AGENTS.md) for agent-facing methodology details.

<!-- ai-sdlc-init:end -->

<!-- v3-ai-sdlc-init:start -->
## ai-catapult-init v3
This repo follows the v3 AI-ready repository layout. See `.ai/matrix.json`, `.memory/human-override/`, and `docs/architecture/adr/`. Modules currently live at `r3dlex/skills/ai-catapult-init/modules/`; deprecated alias paths (`init-ai-repo/`, `ai-sdlc-init/`) are preserved.
<!-- v3-ai-sdlc-init:end -->
