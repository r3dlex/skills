---
name: grill-with-docs
description: 'Stress-test a plan against repo docs and update decisions inline. Use when challenging a design against documented language, ADRs, or CONTEXT.md.'
---

# Grill With Docs

Run a [`grilling`](../grilling/SKILL.md) session grounded in the repo's documented
language, using [`domain-modeling`](../../01-discover-decide/domain-modeling/SKILL.md) to
capture what the session settles.

Two things this adds to the open-ended pass:

- **Challenge against the docs.** When a term conflicts with `CONTEXT.md`, or a stated
  behaviour contradicts the code, surface it in the round rather than letting it stand.
- **Write decisions down as they crystallise**, not in a batch at the end. `domain-modeling`
  owns the glossary and ADR formats and when each is worth creating.
