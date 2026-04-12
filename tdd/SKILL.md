---
name: tdd
description: Test-driven development with red-green-refactor loop. Use when user wants to build features or fix bugs using TDD, mentions "red-green-refactor", wants integration tests, or asks for test-first development.
---

# Test-Driven Development

## Quick Start

1. Confirm with user which behaviors to test (prioritize critical paths)
2. Write ONE test → fails (RED)
3. Write minimal code to pass → passes (GREEN)
4. Repeat for next behavior
5. After GREEN, look for refactor candidates

**Never refactor while RED.** Get to GREEN first.

## Core Principle

Tests should verify behavior through public interfaces, not implementation details. Good tests survive refactors because they describe _what_ the system does, not _how_.

## Anti-Pattern: Horizontal Slices

**DO NOT write all tests first, then all implementation.** This produces crap tests that test imagined behavior rather than actual behavior.

**Correct approach**: Vertical slices via tracer bullets. One test → one implementation → repeat.

```
WRONG: RED: test1→test5, GREEN: impl1→impl5
RIGHT: RED→GREEN: test1→impl1, RED→GREEN: test2→impl2, ...
```

## Workflow

### 1. Planning

- Confirm with user which interface changes are needed
- List the behaviors to test (not implementation steps)
- Ask: "What should the public interface look like?"

### 2. Tracer Bullet

Write ONE test for the first behavior. Fails → write minimal code to pass.

### 3. Incremental Loop

For each remaining behavior:
- Write next test → fails
- Minimal code to pass → passes
- One test at a time. Don't anticipate future tests.

### 4. Refactor

After all tests pass:
- Extract duplication
- Deepen modules (move complexity behind simple interfaces)
- Run tests after each refactor step

## Checklist Per Cycle

```
[ ] Test describes behavior, not implementation
[ ] Test uses public interface only
[ ] Test would survive internal refactor
[ ] Code is minimal for this test
[ ] No speculative features added
```

## Mocking Guidelines

Prefer testing through public interfaces with real collaborators. Use mocks only when:
- The collaborator is slow or has side effects
- You're testing error handling paths that are hard to trigger
- The collaborator isn't yet implemented (tracer bullet)
