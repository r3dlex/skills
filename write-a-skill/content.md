# Writing Skill Content

## Token consciousness

The context window is a public good. Your skill shares it with conversation history,
other skills, CLAUDE.md, and the user's actual work. Every token you add displaces
something else.

Only add context Claude does not already have. Challenge each sentence:
Does Claude need this instruction, or would it do this anyway?

After compaction, the first 5,000 tokens of each skill survive. Put the most
important instructions in the first half of SKILL.md.

## Content types

**Reference skills** add knowledge Claude applies to current work.
Conventions, patterns, style guides, domain terms.
These run inline alongside conversation context.
Keep them factual and declarative. No workflow steps.

**Task skills** give Claude step-by-step instructions for a specific action.
Deployments, code generation, document creation.
These are procedural. Numbered steps. Clear exit conditions.

**Hybrid skills** have a short reference section followed by a task workflow.
Most skills are hybrids.

## Writing rules

Use imperative voice. "Extract the function name" not "You should extract the function name."

One instruction per sentence. Compound instructions get lost.

Do not repeat information available via --help, man pages, or standard docs.
Reference them: "Run `tool --help` for the full flag list."

Do not document all flags or options in SKILL.md. Document the 3 most important ones.
Point to a reference file for the rest.

Put examples in a separate `references/examples.md` file. SKILL.md should contain
at most 2 short inline examples to illustrate the pattern.

## Structure template

```markdown
---
name: skill-name
description: [Does X]. Use when [trigger].
---

# Skill Name

[1-2 sentence summary of what this skill does and why it exists.]

## Process

1. [First step]
2. [Second step]
3. [Third step]

## Rules

[3-7 rules as short declarative sentences.]

## Output format

[What the skill produces. File path, structure, example snippet.]
```

## What to put in reference files

API schemas, configuration options, edge case handling, full example libraries,
platform-specific quirks, troubleshooting guides. Anything that exceeds 10 lines
of detail on a single subtopic belongs in a reference file.

Name reference files descriptively: `api-reference.md`, `edge-cases.md`,
`platform-quirks.md`. Not `notes.md` or `misc.md`.

## Anti-patterns

Walls of text with no headers. Claude skips them during compaction.
Bullet lists longer than 7 items. Split into categories or move to a reference.
Instructions hidden inside examples. State the rule, then show the example.
Conditional logic trees ("if X then Y, unless Z then W"). Simplify or use a table.
Disclaimers and hedging ("you might want to consider"). State the rule directly.
