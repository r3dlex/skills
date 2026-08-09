# Map Format

## The map body

The whole map at low resolution, loaded once per session. Open tickets are **not** listed —
they are open children, found by query.

```markdown
## Destination

<what reaching the end of this map looks like — the spec, decision, or change this effort
is finding its way to. One or two lines; every session orients to it before choosing a
ticket.>

## Notes

<domain; skills every session should consult; standing preferences for this effort>

## Decisions so far

<!-- the index — one line per closed ticket: enough to judge relevance, then zoom the link
     for the detail the ticket holds -->

- [<closed ticket title>](link) — <one-line gist of the answer>

## Not yet specified

<!-- in-scope fog you cannot ticket yet; graduates as the frontier advances. See SCOPE.md -->

## Out of scope

<!-- work ruled beyond the destination; closed, never graduates. See SCOPE.md -->
```

## Tickets

Each ticket is a child of the map, and its identity is whatever the tracker gives it — an
issue id when hosted, the filename when local. The body is the question, sized to one
100K-token agent session:

```markdown
## Question

<the decision or investigation this ticket resolves>
```

Each ticket carries a type — one of `research`, `prototype`, `grilling`, `task`. See
[TICKET-TYPES.md](TICKET-TYPES.md).

## Blocking

Local-first, blocking is a body convention: each ticket lists the tickets that gate it, or
"None — can start immediately".

On a configured and authorized hosted tracker, use the platform's **native** blocking or
sub-issue relationship instead. This matters beyond bookkeeping: it renders the frontier
visually in the tracker's own UI, so the human can see what is takeable without opening the
map. Fall back to the body convention only where no native relationship exists.
