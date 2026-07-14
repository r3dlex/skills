# skills

Portable, reusable workflows for Codex, Claude Code, and compatible AI agents.
Each skill packages trigger metadata, a focused `SKILL.md` workflow, and optional
reference material so an agent can load only the guidance needed for the task.

## Quick Start

Requirements: Git, Bash, and an installed Codex or Claude Code host.

Install one representative skill for Codex:

```bash
git clone https://github.com/r3dlex/skills.git
cd skills
./scripts/install-codex.sh --skill diagnose
test -f "$HOME/.codex/skills/diagnose/SKILL.md"
```

Start Codex and invoke the installed workflow:

```bash
codex
```

```text
$diagnose "why does this command fail?"
```

**Expected result:** Codex discovers `diagnose/SKILL.md` and begins the
reproduce-minimize-hypothesize-instrument-fix loop.

## Install for another host

| Host | Recommended command | Installed catalog |
| --- | --- | --- |
| Codex | `./scripts/install-codex.sh --all` | `~/.codex/skills/` |
| Claude Code | `./scripts/install-claude-code.sh --user` | `~/.claude/skills/omc-learned/` |
| Auggie | `./scripts/install-auggie.sh --all` | `~/.auggie/rules/` |
| Gemini | `./scripts/install-gemini.sh --all` | `~/.gemini/skills/` |
| GitHub Copilot | `./scripts/install-copilot.sh --repo /path/to/repo` | `/path/to/repo/.github/` |

Codex and Claude Code recursively install each selected skill directory,
including references and bundled scripts. Auggie, Gemini, and GitHub Copilot
receive host-specific flattened or synthesized projections suited to their
instruction surfaces. `tests/install_cross_host_parity_test.sh` verifies both
recursive-copy parity and the distinct projection shapes.
The canonical README generator is available only in the recursive Claude Code and Codex installations.

## How the catalog works

Skills are organized by the workflow stage they own:

1. **Discover and decide** — establish vocabulary and context.
2. **Govern and plan** — turn intent into reviewed, traceable work.
3. **Configure and generate** — create or modify repository artifacts.
4. **Validate and hand off** — verify, ship, or transfer completed work.

A skill's frontmatter description controls discovery. Its `SKILL.md` contains the
lean execution path; deeper detail lives in referenced files and is loaded only
when needed. See [`CONTEXT.md`](CONTEXT.md) for the shared domain language.

## Featured workflows

- [`northstar`](02-govern-plan/northstar/SKILL.md) turns intent into a tracked,
  sliced plan and A-to-B handoff without implementing it.
- [`autobahn`](04-validate-handoff/autobahn/SKILL.md) ships an implementation-ready
  handoff through TDD, review, CI, and fail-closed merge gates.
- [`write-a-skill`](03-configure-generate/write-a-skill/SKILL.md) creates a skill
  with progressive disclosure and portable host behavior.
- [`diagnose`](04-validate-handoff/diagnose/SKILL.md) runs a disciplined debugging
  loop from reproduction through verified fix.

## Complete catalog

The table below is generated from `catalog.json`. Preserve its marker comments
when editing this README.

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

## Update

Refresh the repository and reinstall the catalog for your host:

```bash
git pull --ff-only
./scripts/install-codex.sh --all
```

Use the corresponding host installer from the table above when you do not use
Codex. Each deprecated compatibility alias remains installable for legacy
prompts, but new workflows should use the canonical skill name.

## Contributing

Read [`AGENTS.md`](AGENTS.md) for repository conventions and
[`CONTRIBUTING.md`](CONTRIBUTING.md) for the protected-main delivery contract.
Validate catalog metadata with:

```bash
python3 scripts/validate-skill-catalog.py
```

Each skill follows this structure:

```text
skill-name/
├── SKILL.md        # Trigger metadata and core workflow
├── REFERENCE.md    # Optional detail loaded on demand
└── scripts/        # Optional deterministic utilities
```

## License

Apache-2.0 — see [LICENSE](LICENSE).

<!-- ai-sdlc-init:start -->
This repository follows the AI-SDLC methodology. See [`AGENTS.md`](AGENTS.md) for
the operating contract and [`docs/architecture/adr/`](docs/architecture/adr/) for
architectural decisions.
<!-- ai-sdlc-init:end -->

<!-- v3-ai-sdlc-init:start -->
The v3 scaffold is indexed by [`.ai/matrix.json`](.ai/matrix.json); human
overrides remain under [`.memory/human-override/`](.memory/human-override/).
<!-- v3-ai-sdlc-init:end -->
