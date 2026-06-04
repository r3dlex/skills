# Tracker Adapters Module

Read when choosing where BRDs, PRDs, tickets, and comments live.

## Adapter rule

`ai-sdlc-init` selects and references setup-skills tracker adapters; it does not duplicate their full operation semantics.

| Host | Adapter |
| --- | --- |
| GitHub Issues | `setup-skills/issue-tracker-github.md` |
| Azure DevOps Boards | `setup-skills/issue-tracker-ado.md` |
| GitLab Issues | `setup-skills/issue-tracker-gitlab.md` |
| Local Markdown | `setup-skills/issue-tracker-local.md` |

## Required operation shape

Every adapter must document equivalents for:

- create ticket/work item
- read ticket/work item with comments
- list/query by state and label/tag
- comment
- update state
- apply/remove label or tag
- preserve BRD/PRD/parent backlinks
