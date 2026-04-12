---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when user wants to create, write, or build a new skill.
---

# Writing Skills

## Quick Start

1. Gather requirements: task/domain, use cases, need for scripts?
2. Draft SKILL.md + reference files if content exceeds 500 lines
3. Review with user: does this cover use cases? anything missing?

## Skill Structure

```
skill-name/
├── SKILL.md           # Main instructions (required)
├── REFERENCE.md       # Detailed docs (if needed)
├── EXAMPLES.md        # Usage examples (if needed)
└── scripts/           # Utility scripts (if needed)
```

## SKILL.md Template

```md
---
name: skill-name
description: Brief description. Use when [triggers].
---

# Skill Name

## Quick Start

[Minimal working example]

## Workflows

[Step-by-step processes]

## Advanced

See [REFERENCE.md](REFERENCE.md) for details.
```

## Description Requirements

The description is **the only thing your agent sees** when deciding which skill to load.

**Format**: Max 1024 chars, third person, ends with "Use when [triggers]"

**Good**: "Extract text from PDFs, fill forms, merge documents. Use when working with PDF files or when user mentions PDFs."

**Bad**: "Helps with documents."

## When to Add Scripts

Scripts save tokens and improve reliability when:
- Operation is deterministic (validation, formatting)
- Same code would be generated repeatedly
- Errors need explicit handling

## When to Split

Split into separate files when:
- SKILL.md exceeds 100 lines
- Two distinct domains coexist
- A section is needed in fewer than half of all use cases

## Review Checklist

- [ ] Description includes triggers ("Use when...")
- [ ] SKILL.md under 100 lines
- [ ] No time-sensitive info
- [ ] Consistent terminology
- [ ] Concrete examples
- [ ] References one level deep
