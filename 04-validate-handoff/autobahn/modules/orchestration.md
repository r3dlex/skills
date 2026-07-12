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
| Implementation loop | the picked engine (`team`/`ralph`/`ultrawork`/`ultraqa`) |
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
3. Implement via the picked engine and selected TDD posture.
4. Peer-review until all comments resolved.
5. Gate on remote + local CI green.
6. Decide merge via the host-policy thin adapter (else ready-for-human).
7. On merge, cascade-close the issue with a triage status.

## Safety rules

- Never collapse multiple sliced goals into one PR.
- Never advance a goal to merge with unresolved comments or red CI.
- Resume is `ultragoal`'s responsibility; autobahn re-reads its status rather than
  re-running completed goals.
