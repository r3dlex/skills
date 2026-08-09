# Building the Feedback Loop

Build the right feedback loop and the bug is 90% fixed.

## Ways to construct one — try them in roughly this order

1. **Failing test** at whatever seam reaches the bug — unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** — drives the UI, asserts on DOM, console, or network.
5. **Replay a captured trace.** Save a real network request, payload, or event log to disk
   and replay it through the code path in isolation.
6. **Throwaway harness.** Spin up a minimal subset of the system — one service, mocked
   deps — that exercises the bug code path with a single function call.
7. **Property / fuzz loop.** If the bug is "sometimes wrong output", run 1000 random inputs
   and look for the failure mode.
8. **Bisection harness.** If the bug appeared between two known states (commit, dataset,
   version), automate "boot at state X, check, repeat" so it can be bisected.
9. **Differential loop.** Run the same input through old-version vs new-version, or two
   configs, and diff the outputs.
10. **HITL script.** Last resort. If a human must click, drive *them* with
    [scripts/hitl-loop.template.sh](scripts/hitl-loop.template.sh) so the loop is still
    structured. Captured output feeds back to you.

## Tighten the loop

Treat the loop as a product. Once you have *a* loop, tighten it:

- Can I make it faster? Cache setup, skip unrelated init, narrow the test scope.
- Can I make the signal sharper? Assert on the specific symptom, not "didn't crash".
- Can I make it more deterministic? Pin time, seed the RNG, isolate the filesystem, freeze
  the network.

A 30-second flaky loop is barely better than no loop. A 2-second deterministic one is a
debugging superpower.

## Non-deterministic bugs

The goal is not a clean repro but a **higher reproduction rate**. Loop the trigger 100×,
parallelise, add stress, narrow timing windows, inject sleeps. A 50%-flake bug is
debuggable; a 1% one is not — keep raising the rate until it is.

## When you genuinely cannot build a loop

Stop and say so explicitly. List what you tried, then ask the user for one of:

- access to whatever environment reproduces it,
- a redacted captured artifact — HAR file, log dump, core dump, screen recording with
  timestamps,
- permission to add temporary production instrumentation.

Do **not** proceed to hypothesise without a loop.
