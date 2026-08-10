# Autobahn Implementation Routine

Read before implementing a goal. Autobahn's per-goal sequence used to say
"implement via the picked engine", which named no contract: the engine chose how
to work, and the TDD posture selected in [tdd-safety.md](tdd-safety.md) had no
effect on what the engine actually did.

`implement` is now the named implementation step. The picked engine still does
the work — `implement` owns the contract it works under.

## Division of labour

| Concern | Owner |
| --- | --- |
| What "done" means for this goal | `implement` |
| Red-green loop, seams, anti-patterns | `tdd` |
| Which safety posture applies | `tdd-mode.sh` (see [tdd-safety.md](tdd-safety.md)) |
| Executing the work | the picked engine |
| Proof that red preceded green | `tdd-evidence.sh` |

`implement` refuses an unsettled spec. That refusal is load-bearing here: a goal
whose acceptance criteria are still being decided cannot produce a meaningful
failing test, so TDD on it is theatre.

## Both postures drive `tdd`

The posture changes what gets tested, never whether tests come first.

- **standard** — `tdd` red-green over the goal's acceptance criteria. Write the
  failing test at an agreed seam, watch it fail, implement to green.
- **legacy-safe** — `tdd` with `tdd/legacy-systems.md`. Characterize the change
  seam first, sprout new behaviour into a tested unit, keep the legacy call-site
  edit minimal. Still red first: the characterization test is the red leg.

A goal that reaches review with no failing-test-first step has not been
implemented under either posture, whatever the goal record says.

## What "tests first" means in a docs repo

A repo whose product is prose has no unit test for a paragraph, and "TDD does
not apply here" is the wrong conclusion — it is how skill content ships
unverified.

In **this** repo, tests-first means authoring the structural checks before the
content they cover: the `eval-a-skill` triplet, and any validator that asserts
the property the change is supposed to establish. Write the check, watch it fail
against the current content, then write the content.

That check is the red leg, and it is a real one. It fails for the same reason a
unit test does — the property it asserts is not yet true.

Recovered from an installed copy at `~/.claude/skills/autobahn` that existed in
no repository; see the provenance open item in the hardening spec.

## Evidence

`tdd-evidence.sh` records the red and green legs of one test command into
`.ai/evidence/<goal-id>.json` by running it and storing the observed exit code:

```
autobahn/tdd-evidence.sh --record-red   --goal <id> --root . --command '<test cmd>'
autobahn/tdd-evidence.sh --record-green --goal <id> --root . --command '<test cmd>'
autobahn/tdd-evidence.sh --verify       --goal <id> --root .
```

Both legs must record the **same** command. A red from some other failing
command is no evidence for this goal's green.

`--verify` fails closed on absent evidence, malformed evidence, a red leg that
exited 0, a green leg that did not, or a green with no preceding red.

It cannot stop an agent that simply never runs it — that is why the gate is
`--verify` at the review seam rather than the recording itself. Wiring it there
is [Slice 7's](../SKILL.md) job; this module ships the routine and the script.

## Safety rules

- Never generate implementation before its failing test exists.
- Never record a green leg for a different command than the red leg.
- Never treat a posture selection as a substitute for running `tdd`.
