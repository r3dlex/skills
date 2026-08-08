---
name: tdd
description: 'Run red-green-refactor with one failing test, one implementation, then cleanup. Use when building features or fixes test-first.'
---

# Test-Driven Development

## Quick Start

Use one vertical slice at a time: one behavior test, minimal implementation, refactor only after green. Read `vertical-slices.md` when you need philosophy, anti-pattern examples, or the per-cycle checklist.

## Planning

Before writing code:

- [ ] Use the project's domain glossary for test names and interface vocabulary.
- [ ] Respect ADRs in the area you are touching.
- [ ] Confirm the public interface shape with the user when it is not already specified.
- [ ] Prioritize the behaviors worth testing.
- [ ] Use the `codebase-design` skill for module, interface, depth, seam, adapter,
      leverage and locality vocabulary — including deep modules and designing for
      testability. It is a reference to consult, not a session to run.

Ask: "What should the public interface look like? Which behaviors are most important to test?"

## Seams — where tests go

A **seam** is the public boundary you test at: the interface where you observe behavior
without reaching inside. Tests live at seams, never against internals.

**Test only at pre-agreed seams.** Write down the seams under test and confirm them with
the user before writing any test; no test is written at an unconfirmed seam. You cannot
test everything — agreeing seams up front is how effort lands on critical paths and
complex logic instead of every edge case.

## Legacy-safe mode

Use legacy-safe TDD automatically when relevant unit-test coverage is under 30%. Use it at
any coverage level when the specific change has high coupling, weak seams, or a
high observed blast radius; record the reason rather than relying on a silent
confidence judgment. Characterize only the change seam, then use a Sprout Method,
Sprout Class, or equivalent module to keep new behavior isolated. Read
[legacy-systems.md](legacy-systems.md) before editing legacy production code.

## Red-Green Loop

### 1. Tracer bullet

Write one test that confirms one externally visible behavior:

```text
RED:   Write test for first behavior → test fails
GREEN: Write minimal code to pass → test passes
```

This proves the path works end-to-end.

### 2. Incremental cycles

For each remaining behavior:

1. Write the next behavior-focused test.
2. Watch it fail for the expected reason.
3. Write only enough code to pass.
4. Run the relevant test set.
5. Commit or checkpoint when the slice is coherent.

Rules: one test at a time; do not anticipate future tests; keep edge cases tied to
user-visible behavior. Testing public behavior rather than internals is covered by Seams.

## Anti-patterns

- **Implementation-coupled** — mocks internal collaborators, tests private methods,
  or verifies through a side channel (querying the database instead of using the
  interface). The tell: the test breaks when you refactor but behavior has not changed.
- **Tautological** — the assertion recomputes the expected value the way the code does
  (`expect(add(a, b)).toBe(a + b)`, a hand-derived snapshot, a constant asserted equal to
  itself), so it passes by construction and can never disagree with the code. Expected
  values must come from an independent source of truth — a known-good literal, a worked
  example, the spec.
- **Horizontal slicing** — all tests first, then all implementation. Bulk tests verify
  *imagined* behavior, go insensitive to real changes, and commit you to a test structure
  before you understand the implementation. Work in vertical slices instead.

## Refactor

Refactor only after green. Read [refactoring.md](refactoring.md) when choosing refactor candidates.

Check:

- [ ] Extract duplication.
- [ ] Deepen modules behind simple interfaces.
- [ ] Apply SOLID principles where natural.
- [ ] Consider what new code reveals about existing code.
- [ ] Run tests after each refactor step.

Never refactor while red.

## References

- [tests.md](tests.md) — examples of behavior-focused tests.
- [mocking.md](mocking.md) — when mocks help or harm.
- [legacy-systems.md](legacy-systems.md) — low-coverage and high-risk change strategy.
- The `codebase-design` skill — deep modules, seams, and designing for testability.
