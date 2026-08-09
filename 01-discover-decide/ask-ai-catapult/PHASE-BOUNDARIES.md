# Phase Boundaries

What belongs in each phase, and what the handoff between them looks like. Use this when a
request straddles two phases and you need to say which one it is actually in.

The boundaries matter because the commonest routing mistake is starting a phase too early —
specifying before the decisions are made, or building before the spec exists.

## 01 — discover / decide

**In:** understanding the problem, pinning down terminology, gathering facts, deciding what
to build.

**Out:** anything that assumes the decision is already made.

**Done when** the question is answered and the decision is recorded somewhere durable. If
you cannot state what was decided, this phase is not finished — and everything downstream
will be built on sand.

## 02 — govern / plan

**In:** turning a settled decision into a tracked, sliced plan — specs, tickets, blocking
edges, issue state, the route through work too big for one session.

**Out:** implementation, and re-litigating decisions from phase 01. If a plan keeps
reopening a decision, the work belongs back in discovery.

**Done when** each slice is a tracer bullet someone could pick up cold, and the ordering
between them is explicit.

## 03 — configure / generate

**In:** building it. Scaffolding, prototypes, and the test-first implementation loop.

**Out:** deciding *what* to build. `implement` explicitly refuses an unsettled spec, and
that refusal is the boundary being enforced.

**Done when** the behaviour exists, the tests covering it pass, and the work is committed.

## 04 — validate / handoff

**In:** review, diagnosis, verification, merge readiness, closing the loop.

**Out:** new feature work discovered during review — that is a fresh pass through 01 or 02,
not something to fold into the current change.

**Done when** the change is reviewed on both axes, CI is green, and the issue is closed with
its state recorded.

## Handoffs

The transitions are where work is usually lost:

- **01 → 02** — the decision, written down. Not a conversation someone remembers.
- **02 → 03** — a slice small enough for one session, with acceptance criteria.
- **03 → 04** — a diff plus the spec it claims to implement, so review has both axes.
- **04 → anywhere** — what was learned, and the next question, if there is one.

A phase that hands off nothing durable has not really completed — the next phase just starts
by rediscovering what the last one knew.
