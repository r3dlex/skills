---
name: northstar
description: Intake intent into a tracked, sliced plan in an init-ai-repo repo — deep-interview + skippable grill-me, always raise an issue, ralplan, write the A→B handoff.
---

# Northstar

Northstar fixes direction: it converges intent into a crystal-clear, tracked,
sliced plan inside a repo already initialized with `init-ai-repo` v3. It is a
lightweight **composer** — it delegates to existing skills and never reimplements
their loops. The output is the A→B handoff that `autobahn` consumes.

## Quick Start

1. Run the prereq gate (fail-closed) against the repo root:
   `bash northstar/prereq-check.sh --root .`
2. Run the interview loop, then always raise an issue.
3. Run `ralplan` to produce sliced goals.
4. Write the handoff: `bash northstar/handoff-write.sh --root . --spec <spec-path> --slug <plan-slug>`.

## Prereq (fail-closed)

`northstar` assumes the `init-ai-repo` v3 structure is already present and never
bootstraps it. `prereq-check.sh` asserts the `.ai/` structure exists and exits
non-zero with guidance if absent. Do not proceed past a failed prereq. See
[modules/prereq.md](modules/prereq.md).

## The loop (delegation)

`deep-interview` is the **primary** driver: interview one question at a time
until ambiguity is at or below threshold. `grill-me` runs as an **adversarial,
skippable** pass the user may decline. "Both satisfied" = the deep-interview
gate is met AND (the grill-me decision tree is clear OR grill-me was skipped).
Delegate to those skills; do not reimplement their loops. See
[modules/loop.md](modules/loop.md).

## Always raise an issue

After the loop, **always** raise an issue regardless of whether grill-me was
skipped. Default is **local-first markdown**; a hosted tracker
(GitHub/ADO/GitLab/Jira) is used only when it is configured **and** authorized,
fail-closed per the init-ai-repo host-policy. Delegate to `to-issues` and
`triage` for canonical state labels and ownership. See
[modules/issue.md](modules/issue.md).

## Ralplan → sliced goals

Run `ralplan` (consensus planning) on the crystallized spec to produce **sliced
goals** — one tracer-bullet slice per future PR. `ralplan` owns the planning
loop; northstar only records its output as the sliced-goal artifacts the handoff
points at.

## A→B handoff

`handoff-write.sh` records the A→B contract under `.ai/`: a handoff entry in
`.ai/handoff/`, a registration record in the workflow manifest's
`optional_branches` slot, and traceability nodes pinned to `schema_version 1.1`.
The spec lives in `docs/specifications/ACTIVE/`; sliced goals are referenced from
the handoff. The write is idempotent and recovers from a partial write on re-run.
See [modules/handoff.md](modules/handoff.md).

## Command surface

`northstar` registers as a first-class command in both harnesses under
`.ai/commands/omx/` and `.ai/commands/omc/` using one shared schema. See
[modules/command-surface.md](modules/command-surface.md).

## Safety rules

- Fail closed: a missing prereq, missing authorization, or partial handoff write
  stops with guidance — never silently proceed or mutate.
- Compose, never reimplement: delegate every loop to its owning skill.
- Local-first: never create a hosted issue unless the tracker is configured and
  authorized.

## References

- [modules/prereq.md](modules/prereq.md) — init-ai-repo presence contract.
- [modules/loop.md](modules/loop.md) — deep-interview + grill-me "both satisfied" rule.
- [modules/issue.md](modules/issue.md) — local-first / hosted-if-authorized issue raising.
- [modules/handoff.md](modules/handoff.md) — A→B handoff schema and recovery.
- [modules/command-surface.md](modules/command-surface.md) — shared omx/omc command schema.
