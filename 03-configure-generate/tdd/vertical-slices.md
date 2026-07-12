# TDD Vertical Slices

Read when deciding how to avoid horizontal test-first batches or implementation-coupled tests.

## Philosophy

Tests should verify behavior through public interfaces, not implementation details. A good test reads like a specification and survives refactors because it does not care about internal structure.

Bad tests mock internal collaborators, test private methods, query implementation details, or fail when behavior is unchanged.

## Anti-pattern: horizontal slices

Do not write all tests first and then all implementation. Bulk tests usually describe imagined behavior and data shapes before the implementation teaches you what matters.

```text
WRONG:
  RED:   test1, test2, test3, test4
  GREEN: impl1, impl2, impl3, impl4

RIGHT:
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3
```

## Per-cycle checklist

- [ ] Test describes observable behavior.
- [ ] Test uses the public interface.
- [ ] Test would survive an internal refactor.
- [ ] Code is minimal for the current test.
- [ ] No speculative features were added.
