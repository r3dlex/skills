---
name: pr
description: 'Use when writing a PR body: summary with the smallest clarifying visual, before/after evidence, and merge-danger (door + blast radius).'
---

> Adapted from `show-me` by Dex Horthy (Humanlayer): https://github.com/humanlayer/skills

Use this template for writing the PR body:

```markdown
## Summary

<diagram, diff-sketch, or tree>

## Evidence

- **Before:** <screenshot/output/failing test run>
  **After:** <screenshot/output/passing test run>

## Merge Danger

**Door:** <one-way or two-way>

<optional: description>

**Blast Radius:** <one-word description>

<optional: potential ramifications of merge>
```

Skip all preambles and keep prose brief. Use the repo's domain vocabulary from `GLOSSARY.md` (vendored repos: `CONTEXT.md`).

## Summary

Pick the smallest view that makes the key point clear:

- **Pseudocode** for logic or an algorithm:

```text
on(save)
  if content is unchanged
    return cached result
  write new content
```

- **Call tree** for runtime control flow:

```text
submitForm
  createSession
    persistPrompt
  navigateToSession
```

- **Component/module tree** for UI structure or file responsibility:

```text
src/
├── commands/       # parses user actions
├── sessions/       # owns session state
└── transport/      # sends API requests
```

- **Mermaid** for component interaction or data flow; **diff** when the point is what changes inside a shape that already exists (match the diff shape: component, file layout, call tree, or state flow). Show the whole block as code only when most of it is new or omitted context would hide ownership.

Place each visual next to the short text it supports. Keep only the calls, files, states, and boundaries needed for the current question. One visual, several, or none — use judgement and don't overwhelm the reviewer.

## Evidence

Concrete evidence that the change works — before and after. Screenshots are S-tier when the change is visual and the environment supports them. Execution-based evidence (test results, console output) is A-tier: show the exact test that now fails and passes, describing its steps as pseudocode.

## Merge Danger

**Door** — one-way or two-way. Two-way doors can be walked back through; one-way doors cannot. A PR that is cheap to roll back is lower risk; destructive actions or hard-to-reverse decisions are one-way doors.

**Blast radius** — the potential impact of the change: layout shift, breakage for consumers, behavior drift, mobile responsiveness, and so on. Consider all possibilities, not just the intended one.