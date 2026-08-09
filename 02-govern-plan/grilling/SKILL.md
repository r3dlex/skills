---
name: grilling
description: 'Interview relentlessly to stress-test a plan, decision, or idea. Use when thinking needs challenging before it hardens into work.'
---

# Grilling

Interview until you and the user reach a shared understanding. Map the problem as a
**design tree**: every decision branches into the decisions that hang off it.

This skill owns the interview loop. `grill-me` and `grill-with-docs` are thin wrappers
that run it with different context — do not restate the loop in either.

## Work the tree in rounds

The **frontier** is every decision whose prerequisites are already settled — the questions
you can ask *now* without guessing at answers you have not heard yet.

Ask the whole frontier in one round. Number each question and give your recommended
answer:

```
Q1 - <question title>: <question body — may be several paragraphs, and may offer choices>

Recommended: <your answer, and why>
```

Then wait. Each round of answers reshapes the tree: settled decisions push the frontier
outward and unblock questions that depended on them. Recompute the frontier and ask the
next round.

A question whose answer depends on another question still open **in this round** belongs
to a later round, not this one. Asking it early forces the user to guess, and a guessed
answer is worse than no answer — it looks settled.

## Find facts yourself

Finding *facts* is your job, never the user's. When a frontier question needs a fact from
the environment — the filesystem, the code, a tool's output — go and find it rather than
asking for something you could look up.

Do not block on it. A running exploration is an unsettled prerequisite, so only the
questions downstream of it wait; ask the rest of the frontier now.

The *decisions* are the user's. Put each one to them and wait.

## When you are done

The session is done when the frontier is empty: every branch of the tree visited, nothing
left silently assumed.

Do not act on the plan until the user confirms the understanding is shared. A grilling
session that answers its own questions has not grilled anything.

## References

- [`grill-me`](../grill-me/SKILL.md) — this loop, run open-ended.
- [`grill-with-docs`](../grill-with-docs/SKILL.md) — this loop, grounded in the repo's docs.
