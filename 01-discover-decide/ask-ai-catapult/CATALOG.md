<!-- GENERATED:SKILL-CATALOG:START -->
## 01-discover-decide

- **`ask-ai-catapult`** — Ask which skill or flow fits your situation. Use when you know what you want to achieve but not which skills to combine, or which order to run them in.
- **`domain-modeling`** — Build and sharpen a project domain model or ubiquitous language. Use when pinning down domain terms, recording an architectural decision, or keeping a glossary.
- **`research`** — Investigate a question against high-trust primary sources and write the findings to a Markdown file. Use when a topic needs researching or API facts gathered.
- **`ubiquitous-language`** — Extract and save a DDD glossary, flag ambiguities, and propose canonical terms. Use when defining domain language or a shared vocabulary.
- **`zoom-out`** — Explain broader code or product context around a focused area. Use when the user needs a higher-level perspective before local changes.

## 02-govern-plan

- **`codebase-design`** — Shared vocabulary for designing deep modules. Use when shaping an interface, placing a seam, finding deepening opportunities, or when another skill needs it.
- **`design-an-api-or-interface`** — Design APIs/interfaces with Design It Twice: create alternatives, compare tradeoffs, choose one. Use when designing an API, module, class, or boundary.
- **`grill-me`** — Interview the user to stress-test a plan or design until decisions are clear. Use when the user wants to be grilled or challenge a plan.
- **`grill-with-docs`** — Stress-test a plan against repo docs and update decisions inline. Use when challenging a design against documented language, ADRs, or CONTEXT.md.
- **`improve-codebase-architecture`** — Find deepening opportunities from CONTEXT.md and ADRs. Use when refactoring shallow modules, boundaries, coupling, or testability.
- **`northstar`** — Planning-only intake: turn intent into a tracked, sliced plan and A→B handoff; never implement product changes. Use before autobahn execution.
- **`to-issues`** — Break a plan, spec, or PRD into traceable implementation issues. Use when converting requirements into tickets or agent-ready work.
- **`to-prd`** — Turn the current conversation context into a PRD and publish it to the project issue tracker. Use when user wants to create a PRD from the current context.
- **`to-spec`** — Turn the current conversation into a spec and raise it as an issue. Use after a design discussion — no interview, just synthesis of what was already decided.
- **`to-tickets`** — Break a plan, spec, or conversation into tracer-bullet tickets, each declaring its blocking edges. Use when turning a plan into agent-grabbable slices.
- **`triage`** — Triage issues through canonical state labels and ownership roles. Use when creating, reviewing, prioritizing, or preparing issues for agents.
- **`wayfinder`** — Chart work too big for one agent session as a map of decision tickets, resolved one at a time. Use when the way to the destination is not yet visible.

## 03-configure-generate

- **`ai-catapult-init`** — Bootstrap AI-ready governance, traceability, cascade, catalog audits, and validation. Use when setting up AI SDLC; aliases: init-ai-repo and ai-sdlc-init.
- **`ai-sdlc-init`** — Deprecated compatibility alias for ai-catapult-init. Use only when legacy prompts invoke "ai-sdlc-init"; otherwise use "ai-catapult-init".
- **`edit-article`** — Edit and improve articles by restructuring sections, improving clarity, and tightening prose
- **`implement`** — Implement a piece of work from a spec or set of tickets. Use when the decisions are already made and the work just needs building.
- **`init-ai-repo`** — Deprecated compatibility alias for ai-catapult-init. Use only when legacy prompts invoke "init-ai-repo"; otherwise use "ai-catapult-init".
- **`prototype`** — Build a throwaway prototype to answer a design question. Use when sanity-checking a state model or logic, or exploring what a UI should look like.
- **`setup-skills`** — Configure AGENTS/CLAUDE and docs/agents for tracker, triage labels, and domain docs. Use before issue, PRD, triage, TDD, or diagnosis skills.
- **`tdd`** — Run red-green-refactor with one failing test, one implementation, then cleanup. Use when building features or fixes test-first.
- **`using-git-worktrees`** — Create isolated git worktrees with safety checks and setup guidance. Use when starting feature work that needs separation from the main checkout.
- **`wizard`** — Generate an interactive bash wizard for steps only a human can do, not for steps the agent can do itself. Use when provisioning infra or capturing CI secrets.
- **`write-a-skill`** — Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
- **`write-agent-docs`** — Write or audit agent-facing Markdown with progressive disclosure. Use when editing SKILL.md, AGENTS.md, README.md, or other agent docs.

## 04-validate-handoff

- **`autobahn`** — Ship implementation-ready goals from a northstar handoff or evidence-complete direct record, with review, CI, fail-closed merge, and cascade closure.
- **`code-review`** — Review changes since a fixed point along two axes, Standards and Spec, reported side by side. Use when reviewing a branch, a PR, or work in progress.
- **`diagnose`** — Run a reproduce-minimize-hypothesize-instrument-fix loop. Use when debugging bugs, failures, thrown errors, or performance regressions.
- **`diagnosing-bugs`** — Diagnosis loop for hard bugs and performance regressions. Use when asked to diagnose or debug, or when something is broken, throwing, failing, or slow.
- **`eval-a-skill`** — Scaffold a structurally valid eval triplet for a target skill under .ai/evals/. CI checks structure only; the LM-judge runs out-of-band, never in CI.
- **`handoff`** — Compact the current conversation into a handoff document for another agent to pick up.
- **`publish-semver`** — Set up semantic or calendar versioning and package publishing across supported ecosystems. Use when configuring release automation or changelogs.
- **`resolving-merge-conflicts`** — Resolve an in-progress git merge or rebase conflict hunk by hunk. Use when a merge or rebase has stopped with conflicts that need resolving.
<!-- GENERATED:SKILL-CATALOG:END -->
