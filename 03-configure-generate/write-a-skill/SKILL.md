---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
---

# Writing Skills

## Quick Start

Create the smallest useful `SKILL.md` first, then split details into references only when needed. Read `REFERENCE.md` when you need templates, description examples, script rules, or review checklists.

## Process

1. **Gather requirements** — identify the task/domain, concrete trigger phrases, use cases, required scripts, and reference material.
2. **Draft Layer 1** — write frontmatter with `name` and a trigger-focused `description` ending in `Use when ...`.
3. **Draft Layer 2** — write the minimal workflow in `SKILL.md`: Quick Start first, numbered steps, and only essential options.
4. **Split Layer 3** — move templates, examples, schemas, provider variants, and advanced behavior into content-specific files.
5. **Add scripts when useful** — use scripts for deterministic validation, formatting, repeated transforms, or precise error handling.
6. **Review with the user** — check coverage, missing cases, unclear steps, and whether any section is too detailed or too thin.
7. **Validate** — target <=100 body lines; use a reviewed exception only when splitting cannot preserve the workflow, and never exceed 180.

## Structure

```text
skill-name/
├── SKILL.md
├── REFERENCE.md
├── EXAMPLES.md
└── scripts/
```

## Rules

- Target Layer 2 at <=100 body lines. Exceptions require owner, reason, and expiry in `.ai/skills/body-line-exceptions.json`; 180 is absolute.
- Put one concern per reference file; avoid vague names like `details.md`.
- Do not bury common workflow steps in references.
- Do not include time-sensitive claims unless they can be maintained.
- Prefer concrete examples over generic advice, but move long examples out of `SKILL.md`.

## Description Budget

The frontmatter `description` is loaded into every agent's context, so keep it compact (Codex/Claude metadata policy):

- **Target:** `description` ≤ 160 characters. Spend the budget on concrete trigger phrases, not prose.
- **Exceptional maximum:** 180 characters with owner, reason, and expiry; >180 always fails.
- **Progressive disclosure first:** if a description is growing past target, the detail belongs in the body or a reference file, not the metadata.
- **Audited exception:** only when routing clarity requires 161–180 characters, add the skill to `.ai/skills/description-exceptions.json`.

## Codex Parity

Skills must work tool-agnostically (Claude Code and Codex). Do not hard-depend on Claude/OMC-only invocations: `AskUserQuestion`, `Task(subagent_type=...)`, `Skill(...)`, `subagent_type:`, `TodoWrite`, or `mcp__*` tool calls. Prefer tool-agnostic prose — for example, ask the user a question in plain markdown instead of calling the interactive question tool. `scripts/check-codex-parity.sh` enforces this; it scans only real invocations and ignores documented mentions inside backticks or fenced code blocks.

When a Claude-only construct is genuinely needed, annotate it with the graceful-degradation marker and describe a plain-markdown fallback adjacent to it:

```markdown
<!-- codex:optional -->
Use AskUserQuestion to pick a branch.
Fallback (Codex / plain markdown): list the options as a numbered list and ask
the user to reply with a number.
```

The marker on the construct line (or the line directly above it, with no blank line between) permits that single annotated occurrence; everything else must be unmarked and tool-agnostic.
