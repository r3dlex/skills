---
name: progressive-disclosure-docs
description: 'Write or audit agent-facing Markdown with progressive disclosure. Use when editing SKILL.md, AGENTS.md, README.md, or other agent docs.'
---

# Progressive Disclosure Docs

Agent-facing documentation has a single job: give the agent exactly what it needs to act, and nothing more. Every extra word costs tokens and increases the chance the agent misses what matters.

## The Three Layers

| Layer | File | When loaded | Size target |
|---|---|---|---|
| 1 – Signal | frontmatter `description` | Always | < 150 words |
| 2 – Core | SKILL.md / AGENTS.md body | On trigger | < 100 lines |
| 3 – Detail | REFERENCE.md, domain files | On demand | Unlimited |

Never put Layer 3 content in Layer 2. Never put Layer 2 content in Layer 1.

## Quick Start

1. **Identify the layer** — is this a trigger description, a workflow body, or reference detail?
2. **Write only what belongs in that layer.**
3. If writing a SKILL.md body: over 100 lines? **Split now.**
4. Add explicit pointers to Layer 3 files with "when to read" context.

## Writing Rules

**Layer 1 – description**
- State what the skill does. State when to trigger it.
- No examples. No background. No caveats.
- Ends with: `Use when [concrete trigger conditions].`

**Layer 2 – body**
- Start with Quick Start: the minimal working example.
- Use numbered steps for workflows. Bullet points for options.
- Every reference to a deeper file must include when to read it: `See REFERENCE.md if you need schema details.`
- No history. No rationale. No "Overview" or "Background" sections.
- Hard limit: 100 lines. If you hit it, split.

**Layer 3 – reference files**
- One file per domain or concern. Include a table of contents if over 80 lines.
- Name files for their content: `aws-deploy.md`, not `details.md`.

## Splitting Rules

Split when: body exceeds 100 lines, two distinct domains coexist, or a section is needed in fewer than half of all use cases.

Do not split when: content is under 100 lines and covers one domain, or splitting creates a reference file under 20 lines.

## Anti-Patterns

| Pattern | Why it fails | Fix |
|---|---|---|
| "Overview" or "Background" sections | Agents don't need context, they need actions | Delete or move to human-facing README |
| Nested bullets deeper than 2 levels | Agents lose the thread | Flatten or split to reference file |
| Repeated information across files | Wastes tokens, causes drift | Single source of truth, reference by path |
| Inline code examples for every variant | Bloats Layer 2 | Move variants to Layer 3 examples file |
| Vague filenames like `details.md` | Agents can't route without reading | Rename to describe the content |

For detailed examples of good vs. bad documentation at each layer, see [REFERENCE.md](REFERENCE.md).
