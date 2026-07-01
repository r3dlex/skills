# Cascade Module

Read when initializing multiple repositories together or when an umbrella repository must keep parent/child work items, traceability graphs, workflow handoffs, and tracker links in sync. This module owns multi-repo orchestration, idempotency, parent/child linking, reconciliation, and composition of tracker adapters with host-policy safety.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/cascade/cascade-plan.json` | Machine-readable plan for topology discovery, parent/child work items, host adapters, and intended mutations. |
| `.ai/cascade/audit.jsonl` | Append-only audit of dry-run, blocked, confirmed, apply, readback, and idempotent update events. |
| `.ai/cascade/reconciliation-report.md` | Human report proving linked items are present, duplicates are absent, and host/local readback matched. |
| `.ai/cascade/host-adapters/<host>.json` | Mocked adapter contract fixture for GitHub, Azure DevOps, GitLab, Jira, and Local Markdown. |

Workflow and handoff surfaces must link to the cascade plan, audit, and reconciliation report when this branch is available.

## Common cascade workflow

1. **Discover topology** — read `.ai/matrix.json`; standalone repos produce a no-op plan unless the user explicitly selects multiple repos. Umbrella repos read `managed_repositories` and reject paths that violate the topology depth rule.
2. **Plan links** — create a parent work item for the mother repo and child work items for each managed repo; every child records `parent_id`, `parent_url` or `parent_path`, BRD/PRD links, and traceability node IDs.
3. **Dry-run mutations** — route hosted changes through `modules/host-policy-automation.md`; local markdown writes remain normal file writes but still appear in the dry-run plan.
4. **First-run confirmation** — the first externally visible apply requires a confirmation token matching `^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$`. Without it, hosted adapters must return `apply-blocked-no-confirmation` and must not call mutation endpoints.
5. **Apply and readback** — apply only the confirmed plan, capture host response IDs/ETags/version numbers, then read back each parent/child link before reporting success.
6. **Idempotent subsequent update** — after a confirmed cascade scope exists, later runs update the known linked items by stable ID instead of creating duplicates. Unsupported, destructive, or policy-changing mutations still require fresh confirmation.
7. **Audit and reconcile** — append every dry-run/apply/readback/idempotency event to `.ai/cascade/audit.jsonl`, then write `.ai/cascade/reconciliation-report.md` with duplicate count, missing link count, and readback status.

## Host adapter cascade contract

Each configured host adapter must expose the same logical operations:

- `discover_scope`
- `plan_parent_item`
- `plan_child_item`
- `dry_run`
- `confirm_first_run`
- `apply_confirmed_plan`
- `readback_links`
- `apply_idempotent_update`
- `audit_event`
- `reconcile`

Configured hosts are `github`, `ado`, `gitlab`, `jira`, and `local-markdown`. Hosted adapters delegate externally visible mutation safety to `modules/host-policy-automation.md`; local markdown writes still record audit/readback evidence but do not need confirmation.

## Host adapter JSON schema

Each `.ai/cascade/host-adapters/<host>.json` is a mocked, offline contract fixture — never a live connector and never a credential store. The schema is intentionally small so the idempotency and no-duplicate guarantees are mechanically checkable without a network:

| Field | Type | Meaning |
| --- | --- | --- |
| `schema_version` | string | Adapter contract version (`"1.0"`). |
| `host` | string | One of `github`, `ado`, `gitlab`, `jira`, `local-markdown`. |
| `host_label` | string | Human label for the tracker surface. |
| `hosted` | bool | `true` for externally visible hosts; `false` for `local-markdown`. |
| `adapter_doc` | string | Pointer to the `setup-skills/*` adapter detail doc. |
| `operations` | string[] | Exactly the 10 logical operations (see below). |
| `safety` | object | `credentials_stored: false`, `host_policy_mutation: false`, and (for hosted) `first_run_without_confirmation: "blocked"`, `confirmation_token_required: true`, `confirmation_token` matching `^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$`. |
| `dry_run` | object | Planned mutation summary (`status`, `would_create_parent`, `would_create_children`). No external call. |
| `apply` | object | First confirmed apply result (`status`, `parent_key`, `child_keys`). |
| `second_run` | object | Idempotent re-run result: `status: "updated-existing"`, `duplicates_created: 0`, and a stable `idempotency_key`. |
| `readback` | object | Required link evidence: `status`, `parent_link_present`, `child_links_present`. |
| `audit_path` | string | Pointer to `.ai/cascade/audit.jsonl`. |

The `operations` array is exactly these 10 logical ops: `discover_scope`, `plan_parent_item`, `plan_child_item`, `dry_run`, `confirm_first_run`, `apply_confirmed_plan`, `readback_links`, `apply_idempotent_update`, `audit_event`, `reconcile`.

### Stable idempotency key

`second_run.idempotency_key` is the stable key (derived from the cascade `cascade_id`, e.g. `init-ai-repo:<repo-id>:cascade`) that maps the cascade scope to already-created host work items. On any re-run, the adapter resolves the existing child by this key and **updates it in place** (`status: "updated-existing"`) instead of creating a duplicate; `duplicates_created` stays `0`. This is the contract that makes the no-duplicate-child guarantee testable offline (see `tests/cascade-host-adapter-schema_test.sh`, which runs a mocked adapter twice and asserts a single child).

### No credentials

Adapter fixtures must never contain API tokens, access/refresh tokens, OAuth secrets, bearer headers, passwords, or any `authorization:` material. Credential handling is owned by `setup-skills` configuration and `modules/host-policy-automation.md`, never serialized into cascade artifacts.

```json
{
  "schema_version": "1.0",
  "host": "github",
  "hosted": true,
  "operations": [
    "discover_scope", "plan_parent_item", "plan_child_item", "dry_run",
    "confirm_first_run", "apply_confirmed_plan", "readback_links",
    "apply_idempotent_update", "audit_event", "reconcile"
  ],
  "safety": {
    "first_run_without_confirmation": "blocked",
    "confirmation_token_required": true,
    "confirmation_token": "ct-2026-06-27-001",
    "credentials_stored": false,
    "host_policy_mutation": false
  },
  "apply": { "status": "created-or-linked", "parent_key": "GH-101", "child_keys": ["GH-102"] },
  "second_run": { "status": "updated-existing", "duplicates_created": 0, "idempotency_key": "init-ai-repo:umbrella-root:cascade" },
  "readback": { "status": "match", "parent_link_present": true, "child_links_present": true }
}
```

## Safety rules

- Never auto-create hosted parent/child items on the first run without an explicit confirmation token.
- Never create duplicate child work items when a stable `cascade_id` or traceability node already maps to a host item.
- Never store credentials, API tokens, OAuth refresh tokens, or secret headers in cascade plans, host adapter fixtures, audit logs, or reconciliation reports.
- Never downgrade missing readback to success; if readback cannot prove parent/child links, reconciliation status is `fail` or `blocked`.
- Never mutate host branch, project, workflow, permission, or approval policy from cascade; those changes remain owned by `host-policy-automation.md` and require their own confirmation.

## Cross-skill contracts

- `init-ai-repo` creates the cascade plan, links it from workflow/handoff, and validates no duplicates.
- `setup-skills` supplies host adapter operation details for GitHub, Azure DevOps, GitLab, Jira, and Local Markdown.
- `to-issues` creates or updates child work items using the cascade stable IDs instead of free-form duplicates.
- `triage` preserves parent/child backlinks when issue state changes.
- `to-prd` and `brd-prd-traceability.md` provide BRD/PRD links for parent and child items.
- `traceability.md` records parent/child host URLs or local paths as graph nodes and edges.
