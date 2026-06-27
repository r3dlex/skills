# Traceability Graph Module

Read when generating or validating requirement/work-artifact traceability for an `init-ai-repo` target repository. This module owns stable IDs, node/edge schema, backlink validation, graph fixtures, and cross-skill contracts.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/traceability/graph.json` | Machine-readable node/edge graph for requirements, work items, reviews, tests, and handoffs. |
| `.ai/traceability/index.md` | Human index of graph nodes, backlinks, and uncovered artifacts. |
| `.ai/traceability/validation-report.md` | Validation result proving no dangling edges and required artifact coverage. |

Generated workflow and handoff surfaces should link to the traceability index once this phase is active.

## Stable ID policy

- IDs are deterministic strings: `<type>:<repo-id>:<slug>`.
- `type` is one of `brd`, `prd`, `adr`, `plan`, `issue`, `pr`, `test`, `handoff`, `workflow`, or `validation`.
- `repo-id` comes from `.ai/matrix.json` when present; otherwise use `root` for the local repo fixture.
- `slug` is lower-kebab-case from the artifact title or host key.
- IDs never include credentials, access tokens, or mutable host session IDs.

## Graph schema v1.0

```json
{
  "schema_version": "1.0",
  "root_repo_id": "root",
  "generated_at": "2026-06-27T00:00:00Z",
  "nodes": [
    {
      "id": "prd:root:init-ai-repo-workflow-surfaces",
      "type": "prd",
      "title": "init-ai-repo workflow surfaces",
      "status": "active",
      "repo_id": "root",
      "path": "docs/specifications/ACTIVE/init-ai-repo-workflow-surfaces.md",
      "backlinks": ["plan:root:init-ai-repo-pr-stack"]
    }
  ],
  "edges": [
    {
      "source": "plan:root:init-ai-repo-pr-stack",
      "target": "prd:root:init-ai-repo-workflow-surfaces",
      "relation": "decomposes-to",
      "created_by": "init-ai-repo",
      "evidence_path": ".ai/traceability/index.md"
    }
  ]
}
```

## Required validation

1. Every edge `source` and `target` exists in `nodes`.
2. Every node has `id`, `type`, `title`, `status`, `repo_id`, and either `path` or `host_url`.
3. Every node backlink references another existing node ID.
4. The graph covers BRD/PRD/ADR/plan/issue/PR/test/handoff/workflow/validation artifacts when those artifacts exist.
5. The human index links every node ID back to its file path or host URL.
6. The validation report records `status: pass` only when the graph has no dangling edges or backlinks.

## Cross-skill contracts

- `to-prd` must emit or update `prd:*` nodes for generated PRDs/specs.
- `to-issues` must emit or update `issue:*` nodes and `implements` / `tracked-by` edges.
- `triage` must preserve issue node status and host URLs when state changes.
- `setup-skills` must record tracker adapter source metadata for hosted issue nodes.
- `publish-semver` must link release/versioning evidence to PRD/spec and PR/test nodes.
- `init-ai-repo` owns validation and handoff nodes for generated scaffold evidence.

## Safety rules

- Do not infer hosted links from prose when a host adapter readback is available; use the readback URL/ID.
- Do not drop local fallback nodes during hosted reconciliation; mark them `superseded` and link to the hosted node.
- Do not store credentials or private tokens in graph nodes, edges, evidence paths, or validation reports.
