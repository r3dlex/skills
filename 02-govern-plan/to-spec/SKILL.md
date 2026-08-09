---
name: to-spec
description: 'Turn the current conversation into a spec and raise it as an issue. Use after a design discussion — no interview, just synthesis of what was already decided.'
---

# To Spec

Take the current conversation context and codebase understanding and produce a spec. Do
**not** interview the user — synthesize what you already know. If the decisions have not
been made yet, that is a `deep-interview` job, not this one.

Delegate the raising itself to `to-issues` (local-first markdown by default; a hosted
tracker only when one is configured **and** authorized, fail-closed) and use `triage` for
the label vocabulary.

## Process

1. **Explore the repo** to understand the current state of the codebase, if you have not
   already. Use the project's domain glossary throughout the spec, and respect any ADRs in
   the area you are touching.

2. **Sketch the seams** at which you will test the feature. Prefer existing seams to new
   ones, and use the highest seam possible. The fewer seams across the codebase the
   better — the ideal number is one. If new seams are needed, propose them at the highest
   point you can. Check with the user that these seams match their expectations.

3. **Write the spec** using the template below, then raise it. Apply the `ready-for-agent`
   role — no further triage needed.

## Spec template

### Problem Statement

The problem the user is facing, from the user's perspective.

### Solution

The solution to that problem, from the user's perspective.

### User Stories

A LONG, numbered list, each in the form:

1. As an `<actor>`, I want a `<feature>`, so that `<benefit>`

For example: *As a mobile bank customer, I want to see the balance on my accounts, so that
I can make better informed decisions about my spending.*

This list should be extremely extensive and cover every aspect of the feature.

### Implementation Decisions

The decisions that were made — modules built or modified, the interfaces of those modules,
technical clarifications from the developer, architectural decisions, schema changes, API
contracts, specific interactions.

Do **not** include file paths or code snippets; they go stale fast.

*Exception:* if a prototype produced a snippet that encodes a decision more precisely than
prose can (a state machine, reducer, schema, or type shape), inline it in the relevant
decision and note that it came from a prototype. Trim to the decision-rich parts — not a
working demo, just the important bits.

### Testing Decisions

What makes a good test here (external behavior only, never implementation details), which
modules will be tested, and prior art — similar tests already in the codebase.

### Out of Scope

What this spec deliberately does not cover.

### Further Notes

Anything else worth recording.
