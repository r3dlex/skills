---
name: to-tickets
description: 'Break a plan, spec, or conversation into tracer-bullet tickets, each declaring its blocking edges. Use when turning a plan into agent-grabbable slices.'
---

# To Tickets

Break a plan, spec, or conversation into **tickets** — tracer-bullet vertical slices, each
declaring the tickets that **block** it.

Delegate the raising to `to-issues` (local-first markdown by default; a hosted tracker only
when one is configured **and** authorized, fail-closed) and use `triage` for the label
vocabulary.

## Process

### 1. Gather context

Work from whatever is already in the conversation. If the user passes a reference — a spec
path, an issue number or URL — fetch it and read its full body and comments.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so. Ticket titles and descriptions should
use the project's domain glossary and respect ADRs in the area you are touching.

Look for opportunities to prefactor so the implementation is easier: *make the change easy,
then make the easy change.*

### 3. Draft vertical slices

Break the work into **tracer bullet** tickets:

- Each slice cuts a narrow but COMPLETE path through every layer (schema, API, UI, tests) —
  vertical, never a horizontal slice of one layer.
- A completed slice is demoable or verifiable on its own.
- Each slice is sized to fit in a single fresh context window.
- Any prefactoring is done first.

Give each ticket its **blocking edges** — the other tickets that must complete before it can
start. A ticket with no blockers can start immediately.

**Wide refactors are the exception to vertical slicing.** A wide refactor is one mechanical
change — rename a column, retype a shared symbol — whose blast radius fans across the whole
codebase, so a single edit breaks thousands of call sites at once and no vertical slice can
land green. Sequence it as **expand–contract** instead:

1. **Expand** — add the new form beside the old so nothing breaks.
2. **Migrate** — move call sites in batches sized by blast radius (per package, per
   directory), each batch its own ticket blocked by the expand. CI stays green batch to
   batch because the old form still exists.
3. **Contract** — delete the old form once no caller remains, in a ticket blocked by every
   migrate batch.

When even the batches cannot stay green alone, keep the sequence but let them share an
integration branch that all block a final integrate-and-verify ticket — green is promised
only there.

### 4. Quiz the user

Present the breakdown as a numbered list. For each ticket show the **title**, what it is
**blocked by**, and **what it delivers** (the end-to-end behaviour it makes work). Then ask:

- Does the granularity feel right — too coarse, too fine?
- Are the blocking edges correct: does each ticket depend only on tickets that genuinely
  gate it?
- Should any tickets be merged or split further?

Iterate until the user approves the breakdown.

### 5. Raise the tickets

Raise the approved tickets in dependency order, blockers first. The tickets are the same
either way; only the shape of the blocking edges changes:

- **Local-first (default)** — one file per ticket, numbered from `01` in dependency order.
  Never a single combined file. Each file's "Blocked by" lists the numbers or titles it
  depends on.
- **A configured, authorized tracker** — one issue per ticket in dependency order, so each
  ticket's blocking edges can reference real identifiers. Use the platform's native blocking
  or sub-issue relationship where it has one; otherwise set "Blocked by" to the blocking
  issues. Apply the `ready-for-agent` role unless instructed otherwise — these tickets are
  agent-grabbable by construction.

Work the **frontier**: any ticket whose blockers are all done. For a purely linear chain
that means top to bottom. Do **not** close or modify any parent issue.

Avoid file paths and code snippets — they go stale fast. *Exception:* if a prototype
produced a snippet that encodes a decision more precisely than prose can, inline it and note
that it came from a prototype, trimmed to the decision-rich parts.

## References

- [TEMPLATES.md](TEMPLATES.md) — the per-ticket file and issue templates.
