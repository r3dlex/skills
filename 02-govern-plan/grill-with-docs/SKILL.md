---
name: grill-with-docs
description: 'Stress-test a plan against repo docs and update decisions inline. Use when challenging a design against documented language, ADRs, or CONTEXT.md.'
---

# Grill With Docs

Call the Skill tool twice, for [`grilling`](../grilling/SKILL.md) and
[`domain-modeling`](../../01-discover-decide/domain-modeling/SKILL.md): run the session
grounded in the repo's documented language, and capture what it settles.

Two things this adds to the open-ended pass:

- **Challenge against the docs.** When a term conflicts with `CONTEXT.md`, or a stated
  behaviour contradicts the code, surface it in the round rather than letting it stand.
- **Write decisions down as they crystallise**, not in a batch at the end. `domain-modeling`
  owns the glossary and ADR formats and when each is worth creating.
