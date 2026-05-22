# ADR-0001 — Record Architecture Decisions

**Status:** Accepted
**Date:** 2026-05-23
**Deciders:** project maintainers

---

## Context

Architectural decisions accumulate silently in codebases. When a contributor asks
"why is this structured this way?", the answer lives in someone's memory or an
old Slack thread — not in the repository. New contributors repeat the same
trade-off analysis and sometimes reverse decisions whose rationale was sound but
undocumented.

We need a lightweight, version-controlled way to capture significant architectural
decisions alongside the code they describe.

## Decision

We will record architecturally significant decisions in `docs/adr/` using MADR
(Markdown Architectural Decision Records) format. Each ADR is a numbered file:
`ADR-NNNN-slug.md`. ADRs are immutable once accepted; superseded ADRs are marked
"Superseded by ADR-MMMM" rather than deleted.

An ADR is warranted when a decision:
- Is hard to reverse without significant rework
- Involves non-obvious trade-offs
- Affects multiple modules or teams
- Contradicts a common default or industry practice

## Consequences

### Positive
- Decisions are traceable to the commit that introduced them.
- New contributors can understand constraints without asking senior engineers.
- Drift detection at PR review time has an authoritative source to compare against.

### Negative
- Writing ADRs takes time. Teams may skip them under deadline pressure.
- Stale ADRs that are never marked "Deprecated" can mislead readers.

### Neutral / Trade-offs
- ADRs capture intent, not enforcement. Compliance verification is an agent
  behavior (see AGENTS.md — Drift Verification Protocol), not a CI gate in this
  iteration.

## Compliance

Agent behavior: at PR review time, the drift-verification agent loads the PR diff
and relevant ADRs, then flags conflicts. See AGENTS.md for the documented protocol.
