# Write a Skill Reference

Read when drafting a new skill needs templates, description guidance, script guidance, or review checklists.

## Directory shape

```text
skill-name/
├── SKILL.md           # Main instructions (required)
├── REFERENCE.md       # Detailed docs (if needed)
├── EXAMPLES.md        # Usage examples (if needed)
└── scripts/           # Utility scripts (if needed)
    └── helper.js
```

## SKILL.md template

```md
---
name: skill-name
description: Brief description of capability. Use when [specific triggers].
---

# Skill Name

## Quick Start

[Minimal working example]

## Workflow

[Step-by-step process]

## References

See [REFERENCE.md](REFERENCE.md) when you need advanced details.
```

## Description requirements

The description is the only thing the agent sees when choosing whether to load the skill.

- Max 1024 characters.
- Write in third person.
- First sentence: what it does.
- Second sentence: `Use when [specific triggers]`.
- Avoid vague descriptions such as "Helps with documents".

## When to add scripts

Add utility scripts when an operation is deterministic, repeated often, or needs explicit error handling. Prefer scripts over regenerating the same code repeatedly.

## When to split files

Split when `SKILL.md` exceeds the 100-line target, content has distinct domains, or advanced details are rarely needed. Use a reviewed exception only when splitting harms the core workflow; 180 lines is absolute.

## Review checklist

- [ ] Description includes concrete triggers.
- [ ] `SKILL.md` body is <=100 lines, or has a reviewed exception and remains <=180.
- [ ] Quick Start appears before deep detail.
- [ ] No time-sensitive claims unless sourced and maintainable.
- [ ] Terminology is consistent with the target repo.
- [ ] Examples are concrete but not bloated.
- [ ] References include when-to-read context.
