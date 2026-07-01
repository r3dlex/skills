# Issue tracker: Jira Cloud

Issues, PRDs, and implementation tickets for this repo live as Jira Cloud issues. Use the configured Jira MCP/app connector or Jira REST API v3. Use CLI wrappers only when the target repo already documents one.

## Conventions

- **Discover project metadata**: read `/rest/api/3/project/{projectIdOrKey}` and issue type metadata before any mutation.
- **Create an issue**: create with `summary`, `description`, `issuetype`, `project`, optional `labels`, optional `assignee`, and explicit BRD/PRD/parent backlinks in the description. Capture the returned issue key and URL.
- **Read an issue**: fetch `/rest/api/3/issue/{issueIdOrKey}` with comments and relevant fields; keep comments, links, status, labels, and parent/child links as separate evidence.
- **List/query issues**: use JQL, for example `project = FOO AND labels in (ai-sdlc) AND statusCategory != Done`.
- **Comment on an issue**: append a comment through Jira comments API/connector and capture the comment id.
- **Update state**: list available transitions for the issue first, then apply the selected transition only with explicit confirmation when externally visible.
- **Apply / remove labels**: update the `labels` field while preserving existing labels unless the user explicitly requests removal.
- **Link BRD/PRD/tickets**: preserve body backlinks (`BRD:`, `PRD:`, `Parent:`) and Jira issue links/parent fields when project configuration supports them.

Infer site/project from existing repo docs, `.jira/`, tracker config, or issue URLs. Ask only when the Jira site or project key cannot be inferred safely.

## Cascade contract

When `init-ai-repo` runs a multi-repo cascade, Jira participates through the common cascade operations: `discover_scope`, `plan_parent_item`, `plan_child_item`, `dry_run`, `confirm_first_run`, `apply_confirmed_plan`, `readback_links`, `apply_idempotent_update`, `audit_event`, and `reconcile`.

First externally visible parent/child issue creation or transition requires a confirmation token recorded in the cascade audit. Subsequent updates are idempotent only within the already-confirmed cascade scope and must target known issue keys. Project creation, workflow scheme changes, permission changes, and destructive transitions are not cascade operations; route them through `ai-catapult-init/modules/host-policy-automation.md` and require fresh explicit authority.

## When a skill says "publish to the issue tracker"

Create a Jira issue in the configured project with traceability backlinks and return the issue key plus URL.

## When a skill says "fetch the relevant ticket"

Fetch the Jira issue, comments, state, labels, issue links, parent/child links, and BRD/PRD backlinks.
