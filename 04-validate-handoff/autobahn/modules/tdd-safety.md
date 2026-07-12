# Autobahn TDD Blast-Radius Gate

Read before implementing each goal. TDD mode and execution-engine selection are
separate decisions: `tdd-mode.sh` chooses the testing safety posture;
`engine-pick.sh` chooses the orchestration engine.

## Selection

- Measure unit-test coverage for the touched module/package when available;
  use repository-wide coverage only when it is the best available signal.
- `coverage_percent < 30` → `legacy-safe` automatically.
- At any coverage level, the running agent may choose `legacy-safe` when the
  specific issue/feature/request shows high coupling, a weak or missing seam,
  broad dependency reach, fragile initialization, or another concrete blast-radius
  risk. Record `legacy_safe_tdd: true` and `legacy_risk_reason` in the goal.
- Otherwise → `standard`.

Coverage is a signal, not proof of safety. The agent's contextual override may
only become more conservative; it must not override coverage under 30% back to
standard mode. Inline selection likewise requires both `--legacy-risk true` and
`--legacy-risk-reason <text>`.

## Legacy-safe contract

Delegate to `tdd` and read `tdd/legacy-systems.md`. Characterize only the change
seam, establish a small blast-radius budget, sprout new behavior into a tested
method/class/module, and make the minimum legacy call-site edit. No coverage
campaign, broad refactor, or unrelated cleanup is allowed in the feature PR.
