# Direct Implementation-Readiness Gate

Read when Autobahn is invoked without a northstar handoff. This route accepts
one already-understood goal; it does not perform discovery or planning.

## Required goal record

`readiness-check.sh --goal <json>` fails closed unless the record contains:

- `implementation_ready: true`, stable `id`, and tracked `issue_ref`;
- concrete `context`, `root_causes`, and reproduction/diagnostic `evidence`;
- bounded `solutions`, `acceptance_criteria`, and impacted `scope`;
- executable `verification` entries and numeric `coverage_percent`;
- when agent-selected legacy-safe TDD is used at coverage ≥30%,
  `legacy_safe_tdd: true` plus a concrete `legacy_risk_reason`.

The evidence/scope arrays remain non-empty string arrays. Each verification
entry is either a legacy non-empty string or an exact
`{"cwd":"…","command":"…"}` object. Object cwd is `.` or a normalized,
relative POSIX descendant with no absolute path, empty/`.`/`..` component,
backslash, or ASCII control; command is a non-empty string without ASCII
controls. Readiness validates portable shape, while `ci-gate.sh` validates cwd
existence, physical containment, scripts, executables, and command grammar
before execution. Coverage must be from 0 through 100.

Passing the schema does not weaken peer review, CI, merge authority, or
one-PR-per-goal.

## Safety rules

- Do not infer missing root causes or solutions during Autobahn execution.
- If evidence is incomplete or contradictory, stop and route through northstar
  or `diagnose`; do not mark the record implementation-ready.
- Direct intake is one bounded goal and one PR, never an implicit multi-goal plan.
