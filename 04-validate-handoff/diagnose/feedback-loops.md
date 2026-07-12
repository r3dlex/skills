# Diagnosis Feedback Loops

Read when Phase 1 of `diagnose/SKILL.md` does not yet have a fast, deterministic repro loop.

## Build candidates

Try these roughly in order:

1. Failing test at the seam that reaches the bug.
2. Curl/HTTP script against a running dev server.
3. CLI invocation with fixture input and stdout snapshot diff.
4. Headless browser script that asserts DOM, console, or network state.
5. Replayed captured trace: HAR, payload, event log, or request fixture.
6. Throwaway harness for one service or function path with mocked dependencies.
7. Property/fuzz loop for intermittent wrong output.
8. `git bisect run` harness for regressions between known states.
9. Differential loop comparing old/new version or config.
10. HITL script using `scripts/hitl-loop.template.sh` when a human must click.

## Improve the loop

- Make it faster: cache setup, skip unrelated init, narrow test scope.
- Make it sharper: assert the symptom, not just "did not crash".
- Make it deterministic: pin time, seed RNG, isolate filesystem, freeze network.

## Non-deterministic bugs

Aim for a higher reproduction rate, not a perfect repro. Loop 100x, parallelize, add stress, narrow timing windows, or inject sleeps. Keep raising the failure rate until hypotheses can be tested.

## If no loop is possible

Stop and report what was tried. Ask for access to the reproducing environment, a captured artifact, or permission for temporary instrumentation. Do not proceed to hypothesis-testing without a credible signal.
