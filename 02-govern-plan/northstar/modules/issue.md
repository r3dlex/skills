# Northstar Issue Raising

Read when raising the tracking issue after the interview loop. An issue is
**always** raised — skipping grill-me does not skip the issue.

## Local-first, hosted-if-authorized

- **Default: local-first markdown.** Write the issue as a markdown work item
  under `.ai/work-intake/` (the local fallback the ai-catapult-init workflow
  reconciles before final merge).
- **Hosted only when configured AND authorized.** A hosted tracker
  (GitHub/ADO/GitLab/Jira) is used only when a tracker is configured and the
  actor is authorized, fail-closed per `ai-catapult-init`
  `modules/host-policy-automation.md`. If either is missing, stay local and
  record the fallback for reconciliation.

## Delegation

Delegate the issue creation and state to existing skills:

- `to-issues` — break the crystallized plan/spec into independently-grabbable
  issues (tracer-bullet slices) and emit the `issue:*` traceability nodes.
- `triage` — apply the canonical state labels and ownership.

Do not reimplement issue-tracker logic; northstar only ensures the issue is
raised and links it from the handoff.

## Safety rules

- Never create a hosted issue without configured + authorized tracker access.
- Always leave a local-markdown record even when a hosted issue is created, so
  the fallback is reconcilable.
