# Autobahn Prereq Contract

Read when gating autobahn's entry. `prereq-check.sh` performs this read-only,
fail-closed check against `--root`. The catalog repo root has no `.ai/`, so the
script always operates on an explicit `--root`.

## What must be present

Autobahn never bootstraps `ai-catapult-init`. The governed structure must exist,
plus one of two implementation inputs:

1. **ai-catapult-init v3 structure** — the same presence set northstar requires:
   `.ai/matrix.json`, `.ai/workflows/repo-workflow.json`, `.ai/traceability/graph.json`,
   and `.ai/handoff/`.
2. **A valid northstar handoff** — discoverable as BOTH:
   - a manifest `optional_branches` entry whose `id` starts `northstar-handoff-`,
     and
   - the matching handoff file `.ai/handoff/northstar-<slug>.md`.

3. **Or one direct-ready goal** supplied with `--goal` and accepted by
   `readiness-check.sh`; see [readiness.md](readiness.md).

If the governed structure or both input routes are absent, the gate exits
non-zero. Do not proceed past a failed prereq.

## Why both checks

The ai-catapult-init check proves the repo is governed. A handoff proves northstar
produced the multi-goal A→B contract. The direct route is narrower: one bounded,
evidence-complete goal whose discovery work is already finished.

## Safety rules

- Read-only: the gate never mutates the target tree.
- Name the missing artifact on stderr so the operator knows exactly what to run.
- A manifest entry without its handoff file (or vice versa) is a partial/invalid
  handoff — fail closed.
- A vague direct goal is not a substitute handoff — fail closed.
