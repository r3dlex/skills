# Traceability Graph Module

Read when generating or validating requirement/work-artifact traceability for an `ai-catapult-init` target repository. This module owns stable IDs, node/edge schema, backlink validation, graph fixtures, and cross-skill contracts.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/traceability/graph.json` | Machine-readable node/edge graph for requirements, work items, reviews, tests, and handoffs. |
| `.ai/traceability/index.md` | Human index of graph nodes, backlinks, and uncovered artifacts. |
| `.ai/traceability/validation-report.md` | Validation result proving no dangling edges and required artifact coverage. |

Generated workflow and handoff surfaces should link to the traceability index once this phase is active.

## Stable ID policy

- IDs are deterministic strings: `<type>:<repo-id>:<slug>`, except the bounded repository anchor whose identity is exactly the two-segment `repo:<repo-id>`.
- `type` is one of `brd`, `prd`, `adr`, `plan`, `issue`, `pr`, `test`, `handoff`, `workflow`, or `validation`. Schema `1.1` additively adds `repo`, `eval-result`, and `trajectory-trace` (see below).
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

## Graph schema v1.1 (additive)

Schema `1.1` is a strictly additive bump over `1.0`. No `1.0` field is removed or renamed, so existing `1.0` graphs and fixtures stay valid unchanged.

- `schema_version` is `"1.1"`.
- The `type` enum gains three node types: `repo` (an informational repository anchor), `eval-result` (a recorded LM-judge/eval outcome for a skill or PR), and `trajectory-trace` (a recorded agent trajectory captured during an eval run).
- A `repo` anchor is bounded to the current repository: `repo_id` is a nonempty safe identifier (`A-Z`, `a-z`, `0-9`, `.`, `_`, or `-`), its ID is exactly `repo:<repo_id>`, its `path` is exactly `.`, and its status is exactly `active`. Its only optional fields are a nonempty string `label` and a list of string `backlinks`; `host_url` and other extension fields are rejected. It records informational graph identity only and cannot carry or grant host, execution, deployment, payment, authentication, or merge authority.
- New relations are permitted for the new types, e.g. `evaluated-by` (work item → `eval-result`) and `traced-by` (`eval-result` → `trajectory-trace`).
- All other node/edge field rules from `1.0` apply unchanged to the new types: each node still carries `id`, `type`, `title`, `status`, `repo_id`, and either `path` or `host_url`; backlinks and edges must resolve.

```json
{
  "schema_version": "1.1",
  "root_repo_id": "umbrella-root",
  "nodes": [
    {
      "id": "eval-result:umbrella-root:example-output-eval",
      "type": "eval-result",
      "title": "example-output-eval LM-judge result",
      "status": "active",
      "repo_id": "umbrella-root",
      "path": ".ai/evals/example-output-eval/evalset.json",
      "backlinks": ["pr:umbrella-root:workflow-surfaces"]
    },
    {
      "id": "trajectory-trace:umbrella-root:example-output-eval",
      "type": "trajectory-trace",
      "title": "example-output-eval trajectory trace",
      "status": "active",
      "repo_id": "umbrella-root",
      "path": ".ai/evals/example-output-eval/rubric.md",
      "backlinks": ["eval-result:umbrella-root:example-output-eval"]
    }
  ],
  "edges": [
    {
      "source": "pr:umbrella-root:workflow-surfaces",
      "target": "eval-result:umbrella-root:example-output-eval",
      "relation": "evaluated-by",
      "created_by": "init-ai-repo",
      "evidence_path": ".ai/traceability/index.md"
    }
  ]
}
```

### Wiring eval evidence (eval-result / trajectory-trace)

When eval evidence exists, wire it into the graph so it is reachable from the work item it grades:

- Link the evaluated work item (a `skill`, `pr`, `test`, `issue`, or `plan` node) to its `eval-result` node with an `evaluated-by` edge (`source` = work item, `target` = `eval-result`).
- Link the `eval-result` node to its `trajectory-trace` node with a `traced-by` edge (`source` = `eval-result`, `target` = `trajectory-trace`).
- Each `eval-result` and `trajectory-trace` node's `path` MUST point at a real eval artifact under `.ai/evals/<set-id>/` that exists on disk (e.g. the recorded `judgment-demo.json` for a result, the `evalset.json` trajectory or `rubric.md` for a trace). Do not invent paths; reference the committed eval fixtures/outputs.
- The `evidence_path` on `evaluated-by` / `traced-by` edges should point at the same real eval artifact rather than a generic index, so the edge itself carries provenance.

Both topologies ship a fixture demonstrating this: `reference/fixtures/v3/standalone/.ai/traceability/graph-1.1.json` and `reference/fixtures/v3/umbrella/.ai/traceability/graph-1.1.json`. Each wires a `pr` node → `eval-result` (`evaluated-by`) → `trajectory-trace` (`traced-by`) against the `.ai/evals/example-output-eval/` fixtures.

### Version acceptance and migration

- The current validator accepts schema `1.0` and every version `>= 1.1`. For `>= 1.1`, its known enum includes the bounded informational `repo` anchor, `eval-result`, and `trajectory-trace`; every other node type still fails closed.
- Adding `repo` is an in-place amendment to the `1.1` contract. Existing `1.0` and `1.1` graphs need no rewrite, and the anchor remains optional. A producer that adds `repo` must update its consuming validators in the same change. Older strict `1.1` validators know only the original enum and will reject the anchor; no old-consumer forward compatibility is promised.

See [ADR 0014](../../../docs/architecture/adr/0014-bounded-repository-anchor-schema-amendment.md) for the bounded amendment and compatibility debt.

## Required validation

1. Every edge `source` and `target` exists in `nodes`.
2. Every node has `id`, `type`, `title`, `status`, `repo_id`, and either `path` or `host_url`. Every `type` is in the known enum for the declared schema version (`1.1` adds `repo`, `eval-result`, and `trajectory-trace`); an unknown type fails. Repository anchors additionally require exact ID `repo:<repo_id>` and exact local path `.`.
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
- `ai-catapult-init` owns validation and handoff nodes for generated scaffold evidence.

## Safety rules

- Do not infer hosted links from prose when a host adapter readback is available; use the readback URL/ID.
- Do not drop local fallback nodes during hosted reconciliation; mark them `superseded` and link to the hosted node.
- Do not store credentials or private tokens in graph nodes, edges, evidence paths, or validation reports.
