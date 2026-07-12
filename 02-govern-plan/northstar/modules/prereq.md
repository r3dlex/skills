# Northstar Prereq Contract

Read when verifying that the `ai-catapult-init` v3 structure is present before
running `northstar`. This is a **fail-closed** gate: if the structure is absent,
stop and tell the user to run `ai-catapult-init` first.

## Presence set

`prereq-check.sh --root <repo>` asserts these exist under `<repo>`:

| Path | Why |
| --- | --- |
| `.ai/matrix.json` | topology + repo identity |
| `.ai/workflows/repo-workflow.json` | workflow manifest (handoff registration target) |
| `.ai/handoff/` | handoff index directory |
| `.ai/traceability/graph.json` | traceability graph (handoff nodes are added here) |

The check is **read-only** — it never creates or modifies anything under the
target root. The repo root in this catalog has no `.ai/`; tests therefore point
`--root` at `reference/fixtures/v3/standalone/`, which carries a real `.ai/`.

## Behavior

- All paths present → exit `0`, print a one-line confirmation.
- Any path missing → exit non-zero, print to stderr which artifact is missing and
  the guidance: run the `ai-catapult-init` skill to initialize the repo, then retry.

## Safety rules

- Never bootstrap the `.ai/` structure from `northstar`; that is `ai-catapult-init`'s
  responsibility.
- Never mutate the target root during the check.
