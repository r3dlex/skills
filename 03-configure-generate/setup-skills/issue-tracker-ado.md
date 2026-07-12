# Issue tracker: Azure DevOps Boards

Issues, PRDs, and implementation tickets for this repo live as Azure Boards work items. Use the Azure DevOps CLI (`az devops` plus `az boards`) when available; otherwise use the configured Azure DevOps MCP/app connector or REST API with the same operation shape.

## Conventions

- **Create a work item**: `az boards work-item create --type "User Story" --title "..." --description "..." --org <url> --project <project>`.
- **Read a work item**: `az boards work-item show --id <id> --expand Relations` and fetch discussion/comments when the connector supports them.
- **List/query work items**: use WIQL via `az boards query --wiql "..."` for state, tag, area, iteration, or parent filters.
- **Comment on a work item**: use `az boards work-item update --id <id> --discussion "..."` when available, or the Azure DevOps Work Item Tracking Comments REST API/connector.
- **Update state**: `az boards work-item update --id <id> --state "Active|Resolved|Closed|..."` using the project's process states.
- **Apply / remove labels**: use Azure Boards tags, for example `az boards work-item update --id <id> --fields "System.Tags=ready-for-agent;ai-sdlc"`.
- **Link BRD/PRD/tickets**: add parent/related links separately from comments, or include explicit body backlinks: `BRD: <url-or-id>`, `PRD: <url-or-id>`, `Parent: <id>`.

Infer organization/project from `.azuredevops/`, pipeline YAML, remote URLs containing `dev.azure.com` or `visualstudio.com`, or existing `docs/agents/issue-tracker-ado.md` config. Ask only when org/project cannot be inferred safely.

## When a skill says "publish to the issue tracker"

Create an Azure Boards work item with the configured work-item type and add traceability backlinks.

## When a skill says "fetch the relevant ticket"

Fetch the Azure Boards work item, comments/discussion, relations, state, tags, and parent/child links; keep comments and relation links as separate evidence.
