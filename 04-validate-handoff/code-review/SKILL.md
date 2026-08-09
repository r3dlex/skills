---
name: code-review
description: 'Review changes since a fixed point along two axes, Standards and Spec, reported side by side. Use when reviewing a branch, a PR, or work in progress.'
---

# Code Review

Two-axis review of the diff between `HEAD` and a fixed point the user supplies:

- **Standards** — does the code conform to this repo's documented coding standards?
- **Spec** — does the code faithfully implement the originating issue or spec?

Run the two axes **independently**, in separate workers where the harness allows, so neither
pollutes the other's context. Then aggregate.

## Process

### 1. Pin the fixed point

Whatever the user said is the fixed point — a commit SHA, branch name, tag, `main`, `HEAD~5`.
If they did not specify one, ask.

Capture the diff once: `git diff <fixed-point>...HEAD` (three-dot, so the comparison is
against the merge-base), plus `git log <fixed-point>..HEAD --oneline`.

Confirm the fixed point resolves (`git rev-parse <fixed-point>`) and the diff is non-empty
**before** going further. A bad ref or empty diff must fail here, not inside two workers.

### 2. Identify the spec source

In order: issue references in the commit messages (`#123`, `Closes #45`); a path the user
passed as an argument; a spec file under `docs/`, `specs/`, or the repo's scratch area
matching the branch or feature. Use `to-issues` to resolve a hosted reference, and only when
a tracker is configured and authorized.

If nothing is found, ask. If the user says there is no spec, the Spec axis reports
"no spec available" rather than inventing one.

### 3. Identify the standards sources

Anything documenting how code should be written here — `CODING_STANDARDS.md`,
`CONTRIBUTING.md`, `AGENTS.md`, `CONTEXT.md`.

On top of that, the Standards axis always carries the **smell baseline** in
[SMELL-BASELINE.md](SMELL-BASELINE.md), which applies even when a repo documents nothing.
Two rules bind it: **the repo overrides** (a documented standard always wins, and where it
endorses something the baseline would flag, suppress the smell), and **every smell is a
judgement call** — a labelled heuristic, never a hard violation. Skip anything tooling
already enforces.

### 4. Run both axes

**Standards brief** — give it the diff command, the commit list, the standards sources
found, and the smell baseline **pasted in full** (the worker has no other access to it).
Ask for: every place the diff violates a documented standard, citing the file and rule; and
any baseline smell, named with the hunk quoted. Distinguish hard violations from judgement
calls — documented breaches can be hard, baseline smells never are. Under 400 words.

**Spec brief** — give it the diff command, the commit list, and the spec. Ask for:
requirements the spec asked for that are missing or partial; behaviour in the diff nobody
asked for (scope creep); and requirements that look implemented but implemented wrongly.
Quote the spec line for each finding. Under 400 words.

If there is no spec, skip the Spec axis and say so in the report.

### 5. Aggregate

Present both reports under `## Standards` and `## Spec`, verbatim or lightly cleaned. Do
**not** merge or rerank findings across axes.

End with one line: total findings per axis, and the worst issue *within each axis*. Do not
pick a single winner across axes — that is exactly the reranking the separation prevents.

## Why two axes

A change can pass one and fail the other:

- Follows every standard but implements the wrong thing → **Standards pass, Spec fail.**
- Does exactly what the issue asked but breaks the project's conventions → **Spec pass,
  Standards fail.**

Reporting them separately stops one axis from masking the other.
