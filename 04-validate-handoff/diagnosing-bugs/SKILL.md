---
name: diagnosing-bugs
description: 'Diagnosis loop for hard bugs and performance regressions. Use when asked to diagnose or debug, or when something is broken, throwing, failing, or slow.'
---

# Diagnosing Bugs

A discipline for hard bugs. Skip phases only when explicitly justified. When exploring the
codebase, read `CONTEXT.md` if it exists for a mental model of the relevant modules, and
check ADRs in the area you are touching.

## Redact

This skill has you show commands, outputs, and captured artifacts. **Redact every secret
first** — write `<REDACTED>` in its place. Build loops against env vars so the credential
stays in the environment rather than in what you show. Captured artifacts carry auth
headers: quote only the lines that carry the signal. If the redacted output is not enough to
diagnose the bug, say so and ask the user.

## Phase 1 — Build a feedback loop

**This is the skill.** Everything else is mechanical. With a **tight** pass/fail signal that
goes red on *this* bug, you will find the cause — bisection, hypothesis-testing, and
instrumentation all just consume it. Without one, no amount of staring at code will save you.
Spend disproportionate effort here. **Be aggressive. Be creative. Refuse to give up.**

### Completion criterion — a tight loop that goes red

Phase 1 is done when you can name **one command** — a script path, a test invocation, a
curl — that you have **already run at least once** (show the invocation and its output,
redacted), and that is:

- [ ] **Red-capable** — drives the actual bug code path and asserts the **user's exact
      symptom**, so it goes red on this bug and green once fixed. Not "runs without
      erroring"; it must be able to catch *this specific bug*.
- [ ] **Deterministic** — same verdict every run (for flaky bugs, a pinned high
      reproduction rate).
- [ ] **Fast** — seconds, not minutes.
- [ ] **Agent-runnable** — runnable unattended; a human enters the loop only via the HITL
      template.

If you catch yourself reading code to build a theory before this command exists, **stop.**
Jumping straight to a hypothesis is the exact failure this skill prevents. No red-capable
command, no Phase 2.

## Phase 2 — Reproduce and minimise

Run the loop. Watch it go red. Confirm it produces the failure mode the **user** described
— not a nearby one, since the wrong bug gets the wrong fix — that it reproduces across runs,
and that you captured the exact symptom.

**Minimise.** Shrink to the smallest scenario that still goes red: cut inputs, callers,
config, data, and steps **one at a time**, re-running after each cut. Done when every
remaining element is load-bearing. This shrinks the Phase 3 hypothesis space and becomes the
Phase 5 regression test. Do not proceed until you have reproduced *and* minimised.

## Phase 3 — Hypothesise

Generate **3–5 ranked hypotheses** before testing any; single-hypothesis generation anchors
on the first plausible idea. Each must be **falsifiable** — state its prediction: *"If X is
the cause, then changing Y will make the bug disappear."* If you cannot state the
prediction, it is a vibe. Discard or sharpen it.

**Show the ranked list to the user before testing** — they often re-rank it instantly ("we
just deployed a change to #3"). Do not block on it; proceed with your ranking if they are away.

## Phase 4 — Instrument

Each probe maps to a specific Phase 3 prediction. **Change one variable at a time.** Prefer
a debugger or REPL — one breakpoint beats ten logs — then targeted logs at the boundaries
that distinguish hypotheses. Never "log everything and grep". **Tag every debug log** with a
unique prefix such as `[DEBUG-a4f2]`, so cleanup is one grep: untagged logs survive, tagged
logs die. **Performance regressions take the other branch** — logs are usually wrong.
Establish a baseline (timing harness, profiler, query plan), then bisect. Measure first.

## Phase 5 — Fix and regression test

Write the regression test **before the fix**, but only if a **correct seam** exists: one
where the test exercises the real bug pattern as it occurs at the call site. A seam that is
too shallow — a single-caller test when the bug needs several — gives false confidence.
**If no correct seam exists, that itself is the finding**: the architecture is preventing
the bug from being locked down, so carry it into Phase 6.

Otherwise: turn the minimised repro into a failing test at that seam, watch it fail, apply
the fix, watch it pass, then re-run the Phase 1 loop against the original scenario.

## Phase 6 — Cleanup and post-mortem

Required before declaring done:

- [ ] Original repro is gone and the regression test passes (or no-seam is documented).
- [ ] All `[DEBUG-...]` instrumentation removed (grep the prefix).
- [ ] Throwaway prototypes deleted, or moved somewhere clearly marked.
- [ ] The hypothesis that turned out correct is stated in the commit or PR message, so the
      next debugger learns.

**Then ask: what would have prevented this bug?** If the answer involves architectural
change — no good test seam, tangled callers, hidden coupling — hand off to
`improve-codebase-architecture` with the specifics, **after** the fix is in: you know more
now than when you started.

## References

- [FEEDBACK-LOOP.md](FEEDBACK-LOOP.md) — constructing, tightening, and salvaging the loop.
