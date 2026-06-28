# Deterministic Engine-Pick (M3)

Read when selecting the sub-engine for a sliced goal. The mapping is a **pure
function** of the goal record — no model call, no network. `engine-pick.sh`
implements it; this module is the contract.

## Signals → engine

Each sliced goal record carries shape signals. The mapping reads those signals
and emits exactly one engine name:

| Signal (from the goal record) | Engine |
| --- | --- |
| `qa_heavy: true`, or `kind` is `test`/`qa` | `ultraqa` |
| `parallelizable: true` | `ultrawork` |
| `needs_persistence: true` (alias `long_running: true`) | `ralph` |
| none of the above | `team` (default) |

## Precedence

Signals are not mutually exclusive, so the mapping applies a **fixed precedence**
and the highest-priority matching signal wins:

```
qa > parallel > persistence > default
```

So a goal that is both `qa_heavy` and `parallelizable` picks `ultraqa`; a goal
that is both `parallelizable` and `needs_persistence` picks `ultrawork`. The order
is total and deterministic — the same record always yields the same engine.

## Override

A user-supplied `--engine <name>` override **wins over auto-pick** entirely, for
any of the four valid engines (`ultraqa`, `ultrawork`, `ralph`, `team`). An
override naming an unknown engine is rejected (fail-closed, non-zero) rather than
silently falling back, so a typo never ships under the wrong engine.

## Reading the goal record

`engine-pick.sh` reads the signals from a goal-record JSON file (`--goal <path>`)
or accepts them as inline flags for testability; either way the result is the same
pure mapping. The goal record is part of what the northstar handoff references.

## Safety rules

- Pure and deterministic: no model, no network, no clock-dependence.
- A valid `--engine` override always wins; an invalid one fails closed.
- Exactly one engine is emitted per goal.
