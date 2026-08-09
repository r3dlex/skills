# Ticket Templates

Two shapes for the same ticket. Which one you use depends only on where it is raised —
the content is identical either way.

In both, avoid specific file paths and code snippets; they go stale fast. The one exception
is a prototype-derived snippet that encodes a decision more precisely than prose can (a
state machine, reducer, schema, or type shape) — inline it, note that it came from a
prototype, and trim it to the decision-rich parts rather than shipping a working demo.

## Local file (default)

One file per ticket, numbered from `01` in dependency order with blockers first. Never
combine tickets into a single file.

```markdown
# <NN> — <Ticket title>

**What to build:** the end-to-end behaviour this ticket makes work, from the user's
perspective — not a layer-by-layer implementation list.

**Blocked by:** the numbers/titles of the tickets that gate this one, or
"None — can start immediately".

**Status:** ready-for-agent

- [ ] Acceptance criterion 1
- [ ] Acceptance criterion 2
```

## Hosted tracker issue

Used only when a tracker is configured **and** authorized.

```markdown
## Parent

A reference to the parent issue on the tracker. Omit this section if the source was not an
existing issue.

## What to build

The end-to-end behaviour this ticket makes work, from the user's perspective — not
layer-by-layer implementation.

## Acceptance criteria

- [ ] Criterion 1
- [ ] Criterion 2

## Blocked by

- A reference to each blocking ticket, or "None — can start immediately".
```
