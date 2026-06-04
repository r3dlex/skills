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
7. **Validate** — ensure `SKILL.md` body is under 100 lines, references have when-to-read context, and terminology matches the repo.

## Structure

```text
skill-name/
├── SKILL.md
├── REFERENCE.md
├── EXAMPLES.md
└── scripts/
```

## Rules

- Keep Layer 2 under 100 body lines.
- Put one concern per reference file; avoid vague names like `details.md`.
- Do not bury common workflow steps in references.
- Do not include time-sensitive claims unless they can be maintained.
- Prefer concrete examples over generic advice, but move long examples out of `SKILL.md`.
