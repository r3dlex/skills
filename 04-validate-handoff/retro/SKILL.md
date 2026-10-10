---
name: retro
description: 'Conduct a retrospective on a coding agent session: propose environment improvements ranked by severity. Invoked by the user after a session or post-merge.'
---

The user has asked for a **retrospective**. You are suggesting improvements to the coding agent's **environment** to improve future runs. This is the post-merge closure step of a shipped goal: once a PR merges, ask whether a retro is wanted before moving on.

## Steps

1. Load the `write-a-skill` skill for the writing style guide, and follow `write-agent-docs` when a finding turns into an edit of an agent-facing document.

2. Read the primary sources for the session, or the merged PR and its review thread. Sources may include session logs on this machine; default to the current session when the user does not specify one.

3. Look for candidates for improvement in these categories.

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** make it easier? _Use when_ the session took a long time to find a piece of information.
- **Automated checks**: are there automated checks that could catch errors the agent made? Linting, typing, tests, filesystem linters? Read the repo's own check command first (its `package.json`/build-tool `lint`/`check` scripts, its CI workflow), so a check that already exists but sits unwired or silently broken is the finding, not a reinvention. A repo with no **guardrail** (no pre-commit hook and no CI job running its lint/typecheck/test command) is itself a finding: an un-linted repo is a standing missed opportunity, not a neutral default. _Use when_ the agent made a mistake an automated check could have caught, or the repo has no guardrail at all.
- **Coding standards**: should the **reviewer agent** be given a new rule to enforce? Should an existing rule be removed or clarified? Classify the violation first: a **mechanical** one (a fixed syntactic pattern, a banned API, an import shape, a file-location rule) gets a deterministic check, full stop: a custom rule in the repo's own linter, a new pre-commit hook, or a new CI job, whichever the repo's language and existing guardrail make cheapest. Default to building the check over writing the rule. Reserve `CODING_STANDARDS.md` for genuine **judgement calls** (cross-file consistency, "matches the surrounding style," anything no guardrail could ever substitute for). _Use when_ the reviewer agent failed to catch a mistake.
- **Global AGENTS.md**: are there any steering instructions that should be moved to coding standards (or automated checks) instead? _Use when_ the AGENTS.md file is particularly large - in the repo OR the user's global scope.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is there any custom tooling (CLIs, MCPs) that is particularly token-inefficient? _Use when_ the agent made an expensive tool call.
- **No-ops**: look for instructions in steering files that don't modify the agent's behavior. _Use when_ the steering files are large and unwieldy.
- **Information access**: look for opportunities to increase the agent's access to information. Teeing dev server logs, readonly access to third-party services. _Use when_ a crucial piece of information was not available to the agent.

4. Present these candidates to the user, in order of severity, and record accepted ones in the retro summary.

## Reference

### Implementation vs Review

All work goes through two stages: implementation and review. The implementation agent has the most **context pressure** — it explores, writes code, and debugs failures. The review agent has the least: it receives a diff and usually needs no exploration.

This means the review agent should be responsible for imposing coding standards, not the implementation agent.

### Files

- `CLAUDE.md`/`AGENTS.md`: pushed into the context window of any agent working in this repo. Use incredibly sparingly — usually only **navigation pointers** to other files.
- `CODING_STANDARDS.md` (if present): read during review, not implementation. Add **navigation pointers** to docs folders if the standards file grows past ~1,000 lines.
- Docs: reference files pointed to by other files. Look for existing docs before writing new ones.
- Skills: the right home for reusable workflows, since the frontmatter description enters the agent's context. Follow `write-a-skill`.
- Glossary: use the repo's `CONTEXT.md` (or `GLOSSARY.md` when the upstream rename has landed) vocabulary exactly.

End by declaring knowledge kind `learning`, then reading
[ai-catapult-init/modules/knowledge-publish.md](../ai-catapult-init/modules/knowledge-publish.md) and running its host-neutral producer step — publish when a registry exists, otherwise record `unpublished: <reason>`; never fail the skill because of the registry.
