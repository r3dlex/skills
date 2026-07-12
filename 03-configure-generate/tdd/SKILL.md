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
- [ ] Identify opportunities for [deep modules](deep-modules.md).
- [ ] Design interfaces for [testability](interface-design.md).

Ask: "What should the public interface look like? Which behaviors are most important to test?"

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

Rules:

- One test at a time.
- Test public behavior, not private implementation.
- Do not anticipate future tests.
- Keep edge cases tied to user-visible behavior.

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
- [deep-modules.md](deep-modules.md) — identifying deep modules.
- [interface-design.md](interface-design.md) — designing testable interfaces.
