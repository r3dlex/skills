# Autobahn Orchestration Contract

Read when driving goals from a northstar handoff or direct-ready record to PRs.
Autobahn delegates durable orchestration to `ultragoal` and never reimplements
the ledger or goal loop.

## One PR per goal

The northstar handoff references **sliced goals** — one tracer-bullet slice per
future PR. Autobahn feeds those goals to `ultragoal`, which owns the durable
multi-goal workflow (its plan + ledger artifacts under `.ai`/its own state). The
contract is strict: **one PR per goal**, never a mega-PR spanning slices.

## What autobahn owns vs delegates

| Concern | Owner |
| --- | --- |
| Goal ledger, durability, resume | `ultragoal` |
| Per-goal engine selection | `autobahn/engine-pick.sh` (see engine-pick.md) |
| Implementation contract | `implement` driving `tdd` (see implementation.md) |
| Implementation loop | the picked engine (`team`/`ralph`/`ultrawork`/`ultraqa`) |
| Commit + PR seam | `commit-protocol.md` |
| Peer review + CI gate | `architect`/`code-reviewer`/`executor` (see review-loop.md) |
| Merge authority | `merge-authority.sh` thin adapter (see merge-authority.md) |
| Issue closure | cascade engine (see cascade-closure.md) |

Autobahn sequences each goal through `ultragoal`. A direct-ready record becomes
one ledger goal; a northstar handoff supplies one or more. Autobahn does not
duplicate `ultragoal`'s ledger.

## Per-goal sequence

For each sliced goal, in order:

1. Resolve exact v1 handoff and goal IDs (or explicit direct envelope). Run
   `prereq-check.sh --stage implementation` for feature work, or `--stage preparation`
   only for an explicitly bounded preparation goal. Require zero exit plus exact
   repository/subject/goal identity, the exact requested stage and
   `execution_ready=true`. Planning-stage success is never admission.
2. Independently verify live policy approval and operation authority for that
   subject, goal set and stage through the supported host boundary. Context
   issuer/status labels cannot satisfy this: the helper always reports
   `dispatch_authorized=false`. Missing authority stops before TDD or engine
   calls. Only then extract the admitted goal, select standard or legacy-safe
   TDD, and pick the engine.
3. Run `implement` under the selected posture, driving `tdd` red-green; the
   picked engine executes. See implementation.md.
4. `run-gates.sh --phase pre-commit` — TDD evidence and lint, or stop.
5. Commit the goal's staged diff and open its PR. See commit-protocol.md.
6. Peer-review until all comments resolved.
7. Refresh the independently established context for **merge**, preserving the
   exact generation-addressed handoff (or direct envelope) and selected goal from
   implementation admission. Run `run-gates.sh --phase pre-merge` with that
   selection and context, plus exact-SHA remote host CI, all green, or stop.
   The driver derives the goal ID from the command record and requires semantic
   JSON equality with the selected goal before any verification command runs.
   Implementation-stage readiness does not satisfy merge-stage gates.
8. Use the authorized normal host merge, or the strict policy-bypass adapter
   when that path is explicitly authorized (see merge-authority.md).
9. On merge, cascade-close the issue with a triage status.

## Why not port `implement-spec`

Upstream (engineering skills at v1.3) also ships an `implement-spec` skill: it
implements a written spec end-to-end with its own spec-intake, plan, and
execution loop. It was a candidate port and was rejected (SSCM-06, 2026-09-30);
this is the decision record, so a future port attempt does not silently
duplicate a seam that is already owned.

Enumerated delta — what `implement-spec` offers vs the owning module:

| `implement-spec` capability | Autobahn owner already providing it |
| --- | --- |
| spec intake / refuse unsettled spec | [implementation.md](implementation.md) (`implement` refuses an unsettled spec) |
| implement the spec's decisions | [implementation.md](implementation.md) + [engine-pick.md](engine-pick.md) (engine executes under `implement`'s contract) |
| verify each spec point | [review-loop.md](review-loop.md) + the CI gate (`run-gates.sh`, [ci-gate.md](ci-gate.md)) |
| per-spec-point progress | the goal record itself (`scope`, `acceptance_criteria`, `verification`) |

Trigger conditions to revisit: only if autobahn starts accepting goals that are
**not** implementation-ready (no acceptance criteria, no verification commands)
— at that point `implement-spec`'s spec-intake loop would be the missing piece.
While every goal record passes the readiness gate first, the port would add a
second, weaker intake path.

## Wired gate scripts

`run-gates.sh` invokes the gates, so a skipped gate is impossible rather than
merely against the rules:

```
autobahn/run-gates.sh --root . --goal-record <goal.json> --phase pre-commit
autobahn/run-gates.sh --root . --goal-record <goal.json> --phase pre-merge --handoff <generation-addressed-handoff-path> --context <fresh-merge-context.json>
# Direct-goal equivalent: replace --handoff with --goal <same-direct-envelope.json>.
# Supporting local checks only, without claiming merge admission:
autobahn/run-gates.sh --root . --goal-record <goal.json> --phase local-validation
```

It runs gates, **not** the goal loop — one goal record per invocation, and
sequencing stays with `ultragoal`. A driver that grew a goal loop would be the
reimplementation autobahn exists to avoid, and
`tests/autobahn_run_gates_test.sh` asserts it has not.

For `pre-merge` and default `all`, exact selection and merge-stage admission
are mandatory; a missing or failed admission stops before other gates. Once
admitted, every remaining gate runs and reports its blocks unless `--fail-fast`
is set. `local-validation` runs TDD, lint, local CI and goal verification only:
it is **not merge admission or authority**. Never use its success for either
normal merge or the admin-bypass route. Context labels still cannot replace
independent live policy and operation-authority verification.

The table below is still the authority on what exists. A gate that ships without
appearing here is inert — nothing in this repo detects an unwired script, which
is why the list is explicit rather than implied.

| Script | Step | Blocks on |
| --- | --- | --- |
| `prereq-check.sh` | 1 | missing `.ai/` structure or handoff |
| `readiness-check.sh` | 1 | an evidence-incomplete direct goal |
| `tdd-mode.sh` | 2 | — (selects posture) |
| `engine-pick.sh` | 2 | — (selects engine) |
| `tdd-evidence.sh --verify` | 4 | absent, malformed, or inconsistent evidence |
| `lint-gate.sh` | 4 | lint failures, a missing linter, an unreadable manifest |
| `local-ci.sh` | 7 | no safe executable subset, unsupported context/command, or a failing local command |
| `ci-gate.sh --verify` | 7 | a failing or non-allowlisted `verification[]` command |
| `merge-authority.sh` | 8 | any verdict short of host-policy-approved |
| `run-gates.sh` | 4, 7 | merge-stage admission and exact record binding before pre-merge/all; then the four local gates |

## Safety rules

- Never collapse multiple sliced goals into one PR.
- Never advance a goal to merge with unresolved comments or red CI.
- Resume is `ultragoal`'s responsibility; autobahn re-reads its status rather than
  re-running completed goals.

## Scoped readiness recovery

Inspect the exact stage verdict and remaining findings, not planning exit status. Dependency completion requires current revision-bound receipts; currently failing dependency gates still block dependents. Only independently admitted goals may reach engine selection. A ready independent goal may proceed without reopening unrelated blocked work. Preparation has separate stage authority and cannot bypass repository-wide trust. Reuse still-valid exact approval receipts; obtain only missing or invalidated evidence.

Preparation is separately selected and authorized for its bounded setup scope; it cannot include feature implementation. Existing TDD, review, CI and merge obligations still apply to any preparation code. A completed preparation ancestor does not need readiness flags for another stage, but current applicable implementation policy/fixture/trust gates still govern its dependents.
