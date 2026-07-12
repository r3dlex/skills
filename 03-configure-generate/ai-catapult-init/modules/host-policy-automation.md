# Host Policy Automation Module

Read when applying hosted branch, pull-request, or policy mutations to GitHub, Azure DevOps, GitLab, or Jira, or when emitting dry-run diffs and confirmation gates. This module governs the apply path. The default is dry-run; an externally visible or policy-altering apply requires explicit confirmation even when admin credentials are present.

## Default behavior: dry-run first

The default run is `dry-run`. The output is a diff that lists every setting that would change, added, or removed. The apply path is gated by:

1. **Discovery** — read current host settings via the official REST/GraphQL APIs and cache them in `.ai/host-policy/<host>/discovery.json`.
2. **Dry-run diff** — compute the diff between current and intended settings and write it to `.ai/host-policy/<host>/dry-run.json`. The diff includes `path`, `current_value`, `intended_value`, and `change_kind` (`add`, `update`, `remove`).
3. **Confirmation gate** — stop and require an explicit user confirmation. The confirmation is recorded as a `confirmation_token` in the audit log; see `## Audit log` below.
4. **Apply** — call the official APIs to apply the intended settings. Capture every API response and the resulting `etag` or version.
5. **Readback** — re-read the host settings after the apply and assert they match the intended values. Write the readback to `.ai/host-policy/<host>/readback.json`.
6. **Audit** — append an entry to `.ai/host-policy/audit.jsonl` with timestamp, host, plan, diff SHA-256, confirmation token, apply results, and readback status.

Apply is rejected if any of discovery, dry-run, confirmation, or readback fails. A failed apply is rolled back to the values recorded at discovery time when the host supports it; otherwise the audit log records the partial state and emits a `rollback-skipped` entry with the host's response.

## Confirmation boundary

The confirmation gate is mandatory for every apply, including when admin credentials are present. The user's confirmation must:

- name the host (e.g., `github.com/example/repo`),
- name the protected branch or project (e.g., `main`, `services/auth`),
- summarize the dry-run diff (number of adds, updates, removes),
- capture the timestamp and the actor identity, and
- be recorded in the audit log as a `confirmation_token` tied to the run.

A confirmation token is valid only for the run that produced it. Retrying the same plan after a failure requires a fresh confirmation.

### Token format

Confirmation tokens follow the pattern `ct-YYYY-MM-DD-NNN` where `YYYY-MM-DD` is the run date and `NNN` is a zero-padded sequence number scoped to the run date. Tokens are unique per run date; a token is consumed by the first apply that uses it and is invalid for any subsequent apply, even on retry of the same plan.

Implementations validate the format with the regex `^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$` and reject tokens that do not match. The format is intentionally human-readable so audit entries are auditable without a separate format decoder.

## Admin exception and auto-approval

Admins may use host-supported mechanisms to bypass or auto-merge when policy permits. The module never fabricates approvals on top of a host that does not support them. Concretely:

- **GitHub** — admins may use the host's bypass / auto-merge / admin-enforcement features. The module records the bypass as a `host-supported-bypass` audit entry and does not invent a separate approval layer.
- **Azure DevOps** — admins may use the host's policy override or allowed-author bypass. The module records the override and does not invent a separate approval.
- **GitLab** — admins may use the host's allowed-to-merge / allowed-to-push bypass. The module records the bypass and does not invent a separate approval.
- **Jira** — admins may use the host's project-level permissions to bypass workflow transitions. The module records the bypass and does not invent a separate approval.

**Non-admin auto-approval is disallowed.** The module never marks a pull request, merge request, or work item as approved on behalf of a non-admin actor. If the user is not an admin and the host does not support a non-admin bypass, the apply path is rejected and the dry-run plan is returned for explicit human follow-up.

## Provider matrix

### GitHub

- **Discovery** — REST API: `GET /repos/{owner}/{repo}/branches/{branch}/protection` and `GET /repos/{owner}/{repo}/rulesets`. See [GitHub REST branch protection](https://docs.github.com/en/rest/branches/branch-protection) and [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets).
- **Dry-run diff** — compares current protection and rulesets against the intended shape (required status checks, required review count, dismiss stale reviews, required linear history, signed commits, merge queue).
- **Apply** — `PUT /repos/{owner}/{repo}/branches/{branch}/protection` and the rulesets endpoints. Capture the response `etag` per change.
- **Readback** — re-fetch the protection and rulesets; assert equality with the intended shape; record in `.ai/host-policy/github/readback.json`.
- **Admin exception** — host-supported bypass / auto-merge / admin enforcement only; non-admin auto-approval is disallowed.
- **Negative test** — when admin credentials are present but no confirmation is captured, the apply path emits the dry-run diff and refuses to call the mutation endpoints. The audit log records `apply-blocked-no-confirmation`.

Official documentation anchors:

- [GitHub branch protection](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches)
- [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub REST branch protection](https://docs.github.com/en/rest/branches/branch-protection)

### Azure DevOps

- **Discovery** — REST API: `GET https://dev.azure.com/{org}/{project}/_apis/git/policy/configurations?repositoryId={repoId}&refName=refs/heads/{branch}`. See [Azure Repos branch policies](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies-overview?view=azure-devops) and [Azure Repos branch policies settings](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops).
- **Dry-run diff** — compares existing policies (build validation, required reviewers, comment resolution, work-item linking) against the intended shape.
- **Apply** — `POST` and `PUT /_apis/git/policy/configurations` for each policy type. Capture the response status and policy id.
- **Readback** — re-fetch the policy configurations; assert equality; record in `.ai/host-policy/ado/readback.json`.
- **Admin exception** — host-supported policy override / allowed-author bypass only; non-admin auto-approval is disallowed.
- **Negative test** — when admin credentials are present but no confirmation is captured, the apply path emits the dry-run diff and refuses to call the mutation endpoints. The audit log records `apply-blocked-no-confirmation`.

Official documentation anchors:

- [Azure Repos branch policies overview](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies-overview?view=azure-devops)
- [Azure Repos branch policies settings and build validation](https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops)
- [Azure Pipelines triggers (YAML `pr:` triggers vs branch-policy build validation)](https://learn.microsoft.com/en-us/azure/devops/pipelines/build/triggers?view=azure-devops)

### GitLab

- **Discovery** — REST API: `GET /api/v4/projects/{id}/protected_branches` and `GET /api/v4/projects/{id}/merge_request_approval_rules`. See [GitLab protected branches](https://docs.gitlab.com/ee/user/project/protected_branches.html) and [GitLab merge request approvals](https://docs.gitlab.com/ee/user/project/merge_requests/approvals/).
- **Dry-run diff** — compares current protected-branch shape and approval rules against the intended shape. Note GitLab tier differences: some approval-rule features require Premium or higher; blocked or unsupported features are reported in the dry-run and require tier-appropriate configuration. If discovery reports a Free/Core tier for a Premium/Ultimate-only approval-rule mutation, apply refuses mutation endpoints and records `apply-rejected-gitlab-tier-restriction`.
- **Apply** — `POST /api/v4/projects/{id}/protected_branches` and the approval-rule endpoints. Capture the response status and rule id.
- **Readback** — re-fetch the protected branches and approval rules; assert equality; record in `.ai/host-policy/gitlab/readback.json`.
- **Admin exception** — host-supported allowed-to-merge / allowed-to-push bypass only; non-admin auto-approval is disallowed.
- **Negative test** — when admin credentials are present but no confirmation is captured, the apply path emits the dry-run diff and refuses to call the mutation endpoints. The audit log records `apply-blocked-no-confirmation`.

Official documentation anchors:

- [GitLab protected branches](https://docs.gitlab.com/ee/user/project/protected_branches.html)
- [GitLab merge request approvals](https://docs.gitlab.com/ee/user/project/merge_requests/approvals/)

### Jira

- **Discovery** — REST API: `GET /rest/api/3/project/{projectIdOrKey}` and `GET /rest/api/3/issue/{issueIdOrKey}`. See [Jira Cloud REST API v3 introduction](https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/).
- **Dry-run diff** — compares the project metadata, workflow scheme, and issue fields against the intended shape.
- **Apply** — Jira mutations are externally visible. The apply path requires an explicit confirmation that names the project key, the workflow scheme id, and the list of affected issues. See [Jira Cloud REST API v3 projects](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/) and [Jira Cloud REST API v3 workflows](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-workflows/).
- **Readback** — re-fetch the project and workflow configuration; assert equality; record in `.ai/host-policy/jira/readback.json`.
- **Admin exception** — host-supported project-permission bypass only; non-admin auto-approval is disallowed.
- **Negative test** — when admin credentials are present but no confirmation is captured, the apply path emits the dry-run diff and refuses to call the mutation endpoints. The audit log records `apply-blocked-no-confirmation`.

Official documentation anchors:

- [Jira Cloud REST API v3 introduction](https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/)
- [Jira Cloud REST API v3 projects](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/)
- [Jira Cloud REST API v3 workflows](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-workflows/)

## Mocked and live modes

Tests use mocked host adapters. Live host mutations require explicit credentials and an explicit confirmation token recorded in the run directory. The module does not silently fall back from mocked to live mode. The skill's regression suite asserts:

- `apply-blocked-no-confirmation` is recorded when admin credentials are present without confirmation.
- `apply-rejected-non-admin` is recorded when the actor is not an admin and the host does not support a non-admin bypass.
- `apply-rejected-dry-run-mismatch` is recorded when the readback differs from the intended shape.
- `apply-rejected-gitlab-tier-restriction` is recorded when GitLab discovery reports a Free/Core tier for an intended Premium/Ultimate-only approval-rule mutation.

## Audit log

Every run appends one JSON object per line to `.ai/host-policy/<host>/audit.jsonl`, where `<host>` is `github`, `ado`, `gitlab`, or `jira`:

```json
{
  "ts": "2026-06-07T00:00:00Z",
  "host": "github.com/example/repo",
  "audit_path": ".ai/host-policy/github/audit.jsonl",
  "actor": "init-ai-repo",
  "mode": "apply",
  "confirmation_token": "ct-2026-06-07-001",
  "diff_sha256": "...",
  "apply_results": [
    {"path": "branch_protection.required_status_checks", "status": "ok", "etag": "..."}
  ],
  "readback_status": "match",
  "rollback": "not-needed"
}
```

Dry-run entries set `mode: "dry-run"` and omit `apply_results` and `confirmation_token`. Blocked entries set `mode: "blocked"` and include the reason in `apply_results[].status`.

## Safety rules

- The apply path is always confirmation-gated. There is no `auto-apply` mode.
- Backups of pre-apply host settings live under `.ai/host-policy/<host>/discovery.json` and are kept for at least the audit retention window.
- The module never reads or writes credentials to disk. Credentials are passed via environment variables or the host CLI's secret store.
- The module never publishes a `confirmation_token` to the audit log when the run was a dry-run.

## Cross-references

- `modules/ci-policy.md` — CI files and branch-policy/ruleset checklist artifacts. Host-policy-automation is the apply path; ci-policy is the checklist path.
- `modules/tracker-adapters.md` — tracker adapter choice; Jira adapter is added in v3.
- `modules/validation.md` — host-policy negative tests, regression commands, and the audit-format check.
