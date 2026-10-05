---
name: northstar
description: "Planning-only intake: turn intent into a tracked, sliced plan and A→B handoff; never implement product changes. Use before autobahn execution."
eval: northstar
---

# Northstar

Northstar converges intent into a tracked, sliced plan inside a repo initialized
with `ai-catapult-init` v3. This lightweight **composer** delegates to existing skills; its output is the A→B handoff that `autobahn` consumes.

## Execution boundary (hard stop)

Northstar is **planning-only**. Never implement a sliced goal, modify product
code or tests, run implementation engines, or start `autobahn` while this skill
is active. Writes are limited to the planning/tracking artifacts required below.
After verifying the A→B handoff, **stop and report it**; implementation requires
a separate, explicit `autobahn` invocation. Never continue into implementation
in the same run, even when the initiating prompt also asks for implementation.

## Quick Start

1. Run the prereq gate (fail-closed) against the repo root:
   `bash northstar/prereq-check.sh --root .`
2. Run the interview loop, then always raise an issue.
3. Run `ralplan` to produce sliced goals.
4. Publish the reviewed versioned bundle: `bash northstar/handoff-write.sh --root <repo> --bundle <reviewed-v1.json>`.

## Prereq (fail-closed)

`northstar` assumes the `ai-catapult-init` v3 structure is already present and never
bootstraps it. `prereq-check.sh` asserts the `.ai/` structure exists and exits
non-zero with guidance if absent. Do not proceed past a failed prereq. See
[modules/prereq.md](modules/prereq.md).

## The loop (delegation)

`deep-interview` is the **primary** driver: interview one question at a time
until ambiguity is at or below threshold. The **adversarial, skippable** pass is
two skills the user declines or accepts as a unit: `grill-with-docs`
(doc-grounded — stress-tests the plan against the repo's language, ADRs and
`CONTEXT.md`) then `grill-me` (open-ended). "Both satisfied" = the
deep-interview gate is met AND (the adversarial pass is clear OR it was
skipped). Delegate to those skills; do not reimplement their loops. See
[modules/loop.md](modules/loop.md).

## Always raise an issue

After the loop, **always** raise an issue regardless of whether grill-me was
skipped. Default is **local-first markdown**; a hosted tracker
(GitHub/ADO/GitLab/Jira) is used only when it is configured **and** authorized,
fail-closed per the ai-catapult-init host-policy. Delegate to `to-issues` and
`triage` for canonical state labels and ownership. See
[modules/issue.md](modules/issue.md).

## Ralplan → sliced goals

Run `ralplan` (consensus planning) on the crystallized spec to produce **sliced
goals** — one tracer-bullet slice per future PR. `ralplan` owns the planning
loop; northstar records its output as the sliced-goal artifacts.

## A→B handoff

`handoff-write.sh` publishes the reviewed `handoff-goals/1` bundle as immutable
`goals.json`, `handoff.md`, and `graph.json` payloads under
`.ai/handoff/readiness-v1/<plan-id>/<generation>/`. It adds generation-addressed
nodes and backlinks to the live `schema_version 1.1` traceability graph, then
atomically publishes `.ai/workflows/northstar-readiness-v1.json` last. This
separate registry's `plans[]` is the sole completion pointer.

The bundle pins the spec digest and exact repository and goal identities; planning completion is **not implementation readiness**: report preparation,
implementation, and merge gaps separately, without claiming execution authority.
Idempotent recovery preserves evidence; legacy migration and matched dependencies are mandatory.
See [modules/handoff.md](modules/handoff.md).

## Command surface

`northstar` registers as a first-class command under `.ai/commands/omx/` and `.ai/commands/omc/` using one shared schema.
See [modules/command-surface.md](modules/command-surface.md).

## Safety rules

- Planning only: never implement product changes or execute a sliced goal.
- Planning completion is not implementation readiness; report preparation, implementation and merge gaps separately.
- Publish completion through the separate v1 registry, never legacy discovery; missing or mismatched peers block publication.
- Hard stop: do not invoke `autobahn`, `ultragoal`, `team`, `ralph`, `ultrawork`,
  or another implementation engine; stop after the verified A→B handoff — never implement in the same run.
- Fail closed: a missing prereq, missing authorization, or partial handoff write stops with guidance — never silently proceed or mutate.
- Compose, never reimplement: delegate every loop to its owning skill.
- Adversarial pass is `grill-with-docs` then `grill-me`, taken or declined as one
  unit; the loop is not done on the deep-interview gate alone unless the user
  explicitly skipped that pass.
- Local-first: never create a hosted issue unless the tracker is configured and
  authorized.

## References

- [modules/prereq.md](modules/prereq.md) — ai-catapult-init presence contract.
- [modules/loop.md](modules/loop.md) — deep-interview + grill-me "both satisfied" rule.
- [modules/issue.md](modules/issue.md) — local-first / hosted-if-authorized issue raising.
- [modules/handoff.md](modules/handoff.md) — A→B handoff schema and recovery.
- [modules/command-surface.md](modules/command-surface.md) — shared omx/omc command schema.

End by declaring knowledge kind `plan`, then reading
`03-configure-generate/ai-catapult-init/modules/knowledge-publish.md` and running its host-neutral producer step — publish when a registry exists, otherwise record `unpublished: <reason>`; never fail the skill because of the registry.
