# Legacy-Safe TDD

Read when relevant coverage is under 30%, or when the running agent records
`legacy_safe_tdd: true` with a concrete `legacy_risk_reason` for this change at
any coverage level.

## Objective

Add one behavior without turning the feature into a broad legacy-code cleanup.
Coverage is a risk signal, not a target for this PR.

## Sequence

1. **Locate one change seam.** Trace the public behavior to the narrowest point
   where behavior can vary without restructuring the surrounding system.
2. **Set a blast-radius budget.** Name the intended production files, test files,
   and one legacy call site. Expanding it requires a new explicit justification.
3. **Characterize only what you touch.** Add the smallest characterization test
   needed to preserve existing behavior at the seam. It may start green because
   it records current behavior; do not characterize the whole subsystem.
4. **Make the new behavior red.** Add one failing behavior test before production
   code, through the seam or the proposed sprout interface.
5. **Sprout new code.** Prefer a **Sprout Method** when logic can live behind one
   narrow call, or a **Sprout Class**/module when it needs its own state or
   dependencies. Test the sprout directly through its public interface.
6. **Connect minimally.** Make the smallest call-site edit that delegates to the
   sprout. Run the focused tests, then the available regression suite.
7. **Refactor only the sprout while green.** Do not modernize adjacent legacy code,
   raise repository coverage broadly, or combine unrelated cleanup with the goal.

## Stop conditions

- No usable seam can be established without broad restructuring.
- The characterization test exposes contradictory or unknown required behavior.
- The blast-radius budget must expand across multiple coupled subsystems.

When one occurs, stop implementation and route to `diagnose`, architecture work,
or a separately planned characterization/refactoring goal. Never manufacture a
large test harness merely to preserve strict TDD appearances.
