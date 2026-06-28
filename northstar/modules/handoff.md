# Northstar A→B Handoff Contract

Read when writing the handoff that `autobahn` consumes. `handoff-write.sh`
performs this write idempotently against `--root`.

## What gets written

| Artifact | Location | Contents |
| --- | --- | --- |
| Handoff entry | `<root>/.ai/handoff/northstar-<slug>.md` | spec ref, sliced-goals ref, issue ref |
| Manifest record | `<root>/.ai/workflows/repo-workflow.json` | an `optional_branches` entry |
| Traceability nodes | `<root>/.ai/traceability/graph.json` | a `plan` node + a `handoff` node |

The spec itself lives in `docs/specifications/ACTIVE/`; the handoff references it
by path rather than copying it.

## Manifest registration (optional_branches)

`repo-workflow.json` has no skill-registration slot, and its validator fails when
a manifest *phase* lacks a status file. To avoid demanding a new status file, the
handoff registers in the existing **`optional_branches`** array — no new phase:

```json
{ "id": "northstar-handoff-<slug>", "enabled_when": "northstar_handoff_present", "status": "available" }
```

This adds no phase, so the phase/status-file rule is not tripped, and the
existing required branches (`multi-repo-cascade`, `skill-modernization`) and the
four phases stay intact.

## Traceability nodes (schema_version 1.1)

The graph is bumped to `schema_version: 1.1` (additive; the validator accepts
≥1.1). Two nodes are added with `<type>:<repo-id>:<slug>` ids:

- `plan:<repo-id>:northstar-<slug>` — the sliced plan, backlinking the spec PRD.
- `handoff:<repo-id>:northstar-<slug>` — the handoff, backlinking the plan.

Valid types include `prd`, `plan`, `issue`, `handoff`, `workflow`. Nodes carry
`id`, `type`, `title`, `status`, `repo_id`, and `path`; backlinks and edges
resolve.

## Idempotency and partial-write recovery

The write order is **manifest/graph first, handoff file last** so a re-run can
reconcile. Re-running never duplicates a node or branch record (matched by id)
and recreates the handoff file if it was lost. A partial write reports non-zero
and names the unwritten artifact; the idempotent re-run converges the graph.

## Safety rules

- Never duplicate a node or branch record on re-run; match by id.
- Fail closed on a partial write and name the missing artifact.
