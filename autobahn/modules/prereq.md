# Autobahn Prereq Contract

Read when gating autobahn's entry. `prereq-check.sh` performs this read-only,
fail-closed check against `--root`. The catalog repo root has no `.ai/`, so the
script always operates on an explicit `--root`.

## What must be present

Autobahn ships an existing plan; it never bootstraps `ai-catapult-init` and never
authors the plan. Two conditions must hold, both **fail-closed**:

1. **ai-catapult-init v3 structure** — the same presence set northstar requires:
   `.ai/matrix.json`, `.ai/workflows/repo-workflow.json`, `.ai/traceability/graph.json`,
   and `.ai/handoff/`.
2. **A valid northstar handoff** — discoverable as BOTH:
   - a manifest `optional_branches` entry whose `id` starts `northstar-handoff-`,
     and
   - the matching handoff file `.ai/handoff/northstar-<slug>.md`.

If either condition is absent, the gate exits non-zero with actionable guidance
naming the missing artifact and pointing back to `northstar`. Do not proceed past
a failed prereq.

## Why both checks

The ai-catapult-init check proves the repo is governed; the handoff check proves
northstar (Skill A) actually ran and produced the A→B contract autobahn (Skill B)
consumes. A governed repo with no handoff means there is nothing to ship — that is
a fail-closed stop, not a silent no-op.

## Safety rules

- Read-only: the gate never mutates the target tree.
- Name the missing artifact on stderr so the operator knows exactly what to run.
- A manifest entry without its handoff file (or vice versa) is a partial/invalid
  handoff — fail closed.
