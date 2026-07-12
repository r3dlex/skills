---
name: diagnose
description: 'Run a reproduce-minimize-hypothesize-instrument-fix loop. Use when debugging bugs, failures, thrown errors, or performance regressions.'
---

# Diagnose

A discipline for hard bugs. Skip phases only when explicitly justified. Use the project's domain glossary and relevant ADRs before touching code.

## Phase 1 — Build a feedback loop

This is the skill. First create a fast, deterministic, agent-runnable pass/fail signal for the bug. Read `feedback-loops.md` when you need loop candidates, flaky-bug tactics, or HITL fallback structure.

Do not proceed to Phase 2 until you have a loop you believe in. If no credible loop is possible, stop and list what access/artifact/instrumentation is needed.

## Phase 2 — Reproduce

Run the loop and watch the bug appear.

Confirm:

- [ ] The loop produces the user's failure mode, not a nearby different failure.
- [ ] The failure reproduces across runs, or at a high enough rate for flaky bugs.
- [ ] The exact symptom is captured for later fix verification.

Do not proceed until you reproduce the bug.

## Phase 3 — Hypothesise

Generate 3–5 ranked, falsifiable hypotheses before testing any single idea.

Use this format: "If `<cause>` is true, then `<change/probe>` will make the bug disappear, worsen, or expose `<signal>`."

Show the ranked list to the user when they are present; proceed with your ranking if AFK.

## Phase 4 — Instrument

Each probe must map to one Phase 3 prediction. Change one variable at a time.

Tool preference:

1. Debugger/REPL inspection when available.
2. Targeted boundary logs that distinguish hypotheses.
3. Never "log everything and grep".

Tag debug logs with a unique prefix such as `[DEBUG-a4f2]` so cleanup is a single grep. For performance regressions, establish a timing/profiler/query-plan baseline before fixing.

## Phase 5 — Fix + regression test

Write the regression test before the fix, but only at a seam that exercises the real bug pattern as it occurs at the call site.

If no correct seam exists, document that finding; the architecture is preventing reliable regression coverage.

If a correct seam exists:

1. Turn the minimized repro into a failing test.
2. Watch it fail.
3. Apply the fix.
4. Watch it pass.
5. Re-run the original Phase 1 loop.

## Phase 6 — Cleanup + post-mortem

Required before declaring done:

- [ ] Original repro no longer reproduces.
- [ ] Regression test passes, or absence of seam is documented.
- [ ] All `[DEBUG-...]` instrumentation removed.
- [ ] Throwaway prototypes deleted or moved to a marked debug location.
- [ ] Correct root-cause hypothesis is stated in the commit/PR.

Then ask what would have prevented the bug. If the answer is architectural, hand off to `improve-codebase-architecture` with specifics after the fix is verified.
