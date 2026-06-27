# Tracker Adapters Module

Read when choosing where BRDs, PRDs, tickets, and comments live. The adapter is selected at scaffold time and referenced by `init-ai-repo`; full operation semantics live in `setup-skills`. v3 adds an optional Jira adapter and explicit confirmation boundaries for any host adapter that mutates externally visible state.

## Adapter rule

`init-ai-repo` selects and references setup-skills tracker adapters; it does not duplicate their full operation semantics.

| Host | Adapter | Confirmation-gated operations |
| --- | --- | --- |
| GitHub Issues | `setup-skills/issue-tracker-github.md` | create / update / close / re-open / label / assign / project move |
| Azure DevOps Boards | `setup-skills/issue-tracker-ado.md` | create / update / close / re-open / tag / assign / state transition |
| GitLab Issues | `setup-skills/issue-tracker-gitlab.md` | create / update / close / re-open / label / assign |
| Jira (Cloud) | `setup-skills/issue-tracker-jira.md` (v3) | create / update / transition / close / re-open / assign / project / workflow mutation |
| Local Markdown | `setup-skills/issue-tracker-local.md` | none (local file writes) |

## Required operation shape

Every adapter must document equivalents for:

- create ticket/work item
- read ticket/work item with comments
- list/query by state and label/tag
- comment
- update state
- apply/remove label or tag
- preserve BRD/PRD/parent backlinks

## Jira adapter (v3)

The Jira adapter is optional and confirmation-gated. Use it only when the target repo already uses Jira for issue tracking or the user explicitly opts in. The adapter must document:

- **Project bootstrap** — read existing project metadata and emit a discovery report before any mutation.
- **Issue creation** — create issues with `summary`, `description`, `issuetype`, `labels`, `assignee`, and BRD/PRD/parent backlinks. Capture the issue key on success.
- **Workflow transitions** — list the available transitions for a given issue and apply one with explicit confirmation. Non-admin auto-approval of workflow transitions is disallowed.
- **Comments** — append a comment and capture the comment id. Comments must preserve BRD/PRD/parent backlinks.
- **Search** — use JQL (`project = FOO AND type = Bug AND status != Done`) for state and label/tag queries.
- **Webhook ingestion** — optional; if enabled, the adapter reads webhook events and routes them to the local memory layer (`.memory/self-learned/event-patterns.json`). Webhook ingestion does not require confirmation because it is read-only.

### Confirmation boundaries for Jira

- Project creation, project metadata changes, and workflow scheme mutations are externally visible. The adapter must capture an explicit confirmation token before calling the mutation API.
- Issue creation, update, transition, close, and re-open are externally visible. Each apply call must capture a confirmation token.
- Comments and read operations do not require a confirmation token.
- The adapter never fabricates an approval on behalf of a non-admin actor. When the actor is not an admin and the host does not support a non-admin bypass, the apply path is rejected and the dry-run plan is returned for explicit human follow-up.
- The adapter never stores or generates credentials. Credentials are passed via environment variables or the host CLI's secret store.
- The adapter writes an audit entry to `.ai/host-policy/jira/audit.jsonl` (per-host, consistent with `modules/host-policy-automation.md`), mirroring the format in `modules/host-policy-automation.md`.

## Hosted apply path

Tracker adapter mutations are routed through the host-policy-automation apply path when they are externally visible. See `modules/host-policy-automation.md` for the discovery / dry-run / confirmation / apply / readback / audit lifecycle.
