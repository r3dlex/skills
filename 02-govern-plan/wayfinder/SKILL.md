---
name: wayfinder
description: 'Chart work too big for one agent session as a map of decision tickets, resolved one at a time. Use when the way to the destination is not yet visible.'
---

# Wayfinder

A loose idea has arrived — too big for one agent session, and wrapped in fog: the way from
here to the **destination** is not visible yet. Wayfinding is about finding that way, not
charging at the destination. This skill charts the way as a **shared map**, then works its
**decision tickets** — questions whose resolution is a decision, not slices of a build to
execute — one at a time until the route is clear.

The destination varies per effort, and naming it is the first act of charting — it shapes
every ticket. It might be a spec to hand off, a decision to lock before planning starts, or
a change made in place like a data-structure migration. The map is domain-agnostic.

## Plan, don't do

Wayfinder is **planning** by default: each ticket resolves a decision, and the map is done
when nothing is left to decide before someone goes and does the thing. The pull to just do
the work is usually the signal you have reached the edge of the map and it is time to hand
off. An effort can override this in its **Notes** — carrying execution into the map — but
absent that, produce decisions, not deliverables.

## Refer by name

Every map and ticket has a **name** — its title. In everything the human reads, refer to it
by that name, never a bare id, number, or slug. A wall of `#42, #43, #44` is illegible;
names read at a glance. The id and URL do not vanish — a name wraps its link — but they
ride *inside* the name, never stand in for it.

## The map

The map is a single artifact, the canonical one; its tickets are its children. It is an
**index**, not a store: it lists the decisions made and points at the tickets holding their
detail. A decision lives in exactly one place — its ticket — so the map gists and links,
never restates.

**Local-first by default.** The map and its tickets are markdown under the repo, and
blocking edges are a body convention. A hosted tracker is used only when one is configured
**and** authorized, fail-closed; there, use the platform's native blocking or sub-issue
relationship, which renders the frontier visually so the human sees what is takeable
without opening the map. Delegate the raising to `to-issues` and the label vocabulary to
`triage`.

A session **claims** a ticket by assigning it to the dev driving the map, **first**, before
any work, so concurrent sessions skip it. That assignee *is* the claim: an open, unassigned
ticket is unclaimed. A ticket is **unblocked** when every ticket blocking it is closed; the
**frontier** is the open, unblocked, unclaimed children — the edge of the known.

Answers are not part of a ticket body; they are recorded on resolution. Assets created while
resolving a ticket are linked from it, never pasted in.

## Invocation

Two modes. Either way, **never resolve more than one ticket per session** — research
tickets excepted.

### Chart the map

The user invokes with a loose idea.

1. **Name the destination.** Run `grilling` and `domain-modeling` to pin down what this map
   is finding its way to. The destination fixes the scope, so it is settled first.
2. **Map the frontier.** Grill again, **breadth-first** — fan out across the whole space
   rather than deep on one thread, surfacing the open decisions and the first steps takeable
   now. **If this surfaces no fog**, the way is already clear and the journey fits one
   session: you do not need a map. Stop and ask the user how to proceed.
3. **Create the map** with Destination and Notes filled in, Decisions-so-far empty, and the
   fog sketched into **Not yet specified**.
4. **Create the tickets you can specify now**, then wire blocking edges in a **second
   pass** — tickets need identities before they can reference each other. Everything you
   cannot yet specify stays in the fog.
5. **Fire the research subagents.** For each `research` ticket, resolve it in parallel via
   `research`, capturing findings on a throwaway `research/<name>` branch with a context
   pointer from the ticket.
6. Stop — charting is one session's work; it hand-resolves nothing.

### Work through the map

The user invokes with a map. A ticket is **optional** — without one, you pick the next
decision, not the user.

1. Load the **map** — the low-res view, not every ticket body.
2. Choose the ticket: the one the user named, else the first frontier ticket in order.
   **Claim it** before any work.
3. Resolve it, **zooming as needed**: fetch the full body of any related or closed ticket on
   demand, and invoke the skills the Notes block names. If in doubt, use `grilling` and
   `domain-modeling`.
4. Record the resolution: post the answer, close the ticket, and append a context pointer to
   the map's Decisions-so-far.
5. Add newly-surfaced tickets (create-then-wire) and graduate any fog the answer made
   specifiable, clearing each graduated patch from **Not yet specified**. If the answer
   reveals a ticket sits beyond the destination, **rule it out of scope** rather than
   resolving it. If the decision invalidates other parts of the map, update or delete them.

The user may run unblocked tickets in parallel, so expect concurrent edits.

## References

- [MAP-FORMAT.md](MAP-FORMAT.md) — the map body and ticket templates.
- [TICKET-TYPES.md](TICKET-TYPES.md) — research, prototype, grilling, task; HITL vs AFK.
- [SCOPE.md](SCOPE.md) — fog of war, and what belongs out of scope.
