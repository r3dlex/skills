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

1. Resolve the goal record from the handoff or readiness gate.
2. Select standard or legacy-safe TDD, then pick the engine.
3. Run `implement` under the selected posture, driving `tdd` red-green; the
   picked engine executes. See implementation.md.
4. `run-gates.sh --phase pre-commit` — TDD evidence and lint, or stop.
5. Commit the goal's staged diff and open its PR. See commit-protocol.md.
6. Peer-review until all comments resolved.
7. `run-gates.sh --phase pre-merge` plus remote host CI, all green, or stop.
8. Decide merge via the host-policy thin adapter (else ready-for-human).
9. On merge, cascade-close the issue with a triage status.

## Wired gate scripts

`run-gates.sh` invokes the gates, so a skipped gate is impossible rather than
merely against the rules:

```
autobahn/run-gates.sh --root . --goal-record <goal.json> --phase pre-commit
autobahn/run-gates.sh --root . --goal-record <goal.json> --phase pre-merge
```

It runs gates, **not** the goal loop — one goal record per invocation, and
sequencing stays with `ultragoal`. A driver that grew a goal loop would be the
reimplementation autobahn exists to avoid, and
`tests/autobahn_run_gates_test.sh` asserts it has not.

By default every gate runs and every block is reported, so one pass shows
everything to fix. `--fail-fast` stops at the first block.

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
| `ci-gate.sh --derive` | 7 | no derivable CI, or an unsupported CI construct |
| `ci-gate.sh --verify` | 7 | a failing or non-allowlisted `verification[]` command |
| `merge-authority.sh` | 8 | any verdict short of host-policy-approved |
| `run-gates.sh` | 4, 7 | invokes the four gates above; any of them blocking |

## Safety rules

- Never collapse multiple sliced goals into one PR.
- Never advance a goal to merge with unresolved comments or red CI.
- Resume is `ultragoal`'s responsibility; autobahn re-reads its status rather than
  re-running completed goals.
