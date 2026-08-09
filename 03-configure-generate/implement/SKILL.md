---
name: implement
description: 'Implement a piece of work from a spec or set of tickets. Use when the decisions are already made and the work just needs building.'
---

# Implement

Implement the work described in the spec or tickets. This skill is a thin orchestrator — its
value is the skills it calls, not logic of its own.

1. **Lead with `tdd`**, at pre-agreed seams. The failing test comes first, and no test is
   written at a seam the user has not confirmed.
2. **Run typechecking and single test files regularly**, and the full test suite once at the
   end. A green full suite at the end is not a substitute for fast feedback during.
3. **Review with `code-review`** once the work is done — the two-axis Standards and Spec
   pass, in a separate lane from the authoring.
4. **Commit to the current branch.**

If the decisions have not actually been made yet, stop: that is a `deep-interview`,
`to-spec`, or `wayfinder` job, and implementing against an unsettled spec wastes the work.
