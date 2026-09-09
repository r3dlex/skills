# Northstar A→B Handoff Contract

Read when writing the handoff that `autobahn` consumes. `handoff-write.sh`
requires contained, existing `--spec` and `--goals` files and performs this
write idempotently against `--root`.

## What gets written

| Artifact | Location | Contents |
| --- | --- | --- |
| Handoff entry | `<root>/.ai/handoff/northstar-<slug>.md` | spec ref, sliced-goals ref, issue ref |
| Manifest record | `<root>/.ai/workflows/repo-workflow.json` | an `optional_branches` entry |
| Traceability nodes | `<root>/.ai/traceability/graph.json` | plan + handoff nodes; plan resolves the concrete goals file |

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

- `plan:<repo-id>:northstar-<slug>` — the sliced plan at `--goals`, backlinking the unique PRD whose path exactly matches `--spec`.
- `handoff:<repo-id>:northstar-<slug>` — the handoff, backlinking the plan.

Valid types include `prd`, `plan`, `issue`, `handoff`, `workflow`. Nodes carry
`id`, `type`, `title`, `status`, `repo_id`, and `path`; backlinks and edges
resolve.

## Idempotency and partial-write recovery

All prerequisites are validated before mutation. Each file is replaced
atomically, but the three replacements are not a cross-file transaction. The
write order is **manifest/graph first, handoff file last**, and the handoff file
is the **completion marker**. Recovery is by **idempotent re-run**: records are
reconciled by ID, and a missing handoff is recreated without duplication.

## Safety rules

- Never duplicate a node or branch record on re-run; match by id.
- Derive repository identity from the exact-spec PRD and reconcile any declared
  graph/manifest identity; ambiguity or conflict fails before mutation.
- A generated legacy `*:root:northstar-<slug>` pair may be renamed in place only
  when its complete shape matches. Preserve statuses, custom fields, and graph
  references; fail closed on partial or legacy/current collisions.
- Never promote blocked records or infer execution, host, payment, or merge authority.
- Treat spec and goals as immutable evidence. Reject lexical, symlink,
  case-insensitive, and hardlink aliases of every output target before parsing
  or mutation.
- Fail closed on a partial write and identify the failing artifact.
