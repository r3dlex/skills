# CI and Branch Policy Module

Read when adding CI files or branch-policy/ruleset checklist artifacts. This module is scaffold guidance, not hosted-policy automation.

## Official docs anchors

- GitHub rulesets: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- GitHub branch protection: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches
- Azure Repos branch policies: https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies-overview?view=azure-devops
- Azure Repos policy settings and build validation: https://learn.microsoft.com/en-us/azure/devops/repos/git/branch-policies?view=azure-devops
- Azure Pipelines triggers: https://learn.microsoft.com/en-us/azure/devops/pipelines/build/triggers?view=azure-devops

## Safety boundary

By default, write checklist artifacts into the repo. Do not call GitHub or Azure DevOps APIs/CLIs that mutate branch rules, rulesets, or policies unless the user explicitly requests it and confirms admin credentials/permissions.

Every initialized implementation assumes protected `main` and PR-only delivery. The scaffold may emit provider-specific checklists/config templates for branch rules, but hosted policy mutation remains opt-in and explicit.

## GitHub path

### CI scaffold

- Write `.github/workflows/ci-prek.yml` as a separate workflow.
- Keep existing `.github/workflows/ci.yml` intact.
- Include the `validate-rules` prek hook and any detected language-pack checks.

### Branch ruleset/protection checklist

Create `docs/agents/branch-policy-github.md` with:

- Default branch target, usually `main` or `dev`.
- Required PR before merge.
- Protected `main` ruleset/protection intent; direct pushes are disallowed.
- Required status checks, including the AI SDLC prek workflow.
- Required review count and stale-review dismissal policy.
- Whether administrators may self-approve PRs through admin approve/admin bypass, and the local policy rationale when allowed; this is valid only when the host/runtime explicitly supports admin approval for the same actor. GitHub hosted PR review rejects same-actor approval, so GitHub requires a distinct admin reviewer or explicit admin bypass/admin merge with actor, authority, reason, checks, and approval mode recorded.
- Optional linear history, signed commits, merge queue, or deployment requirements.
- Ruleset/protection owner and whether enforcement is active, evaluate-only, or checklist-only.
- Links to the official GitHub rulesets and branch protection docs above.

### PR merge gate

For any PR workflow or branch-policy checklist created by this skill, state that merge is allowed only when all of these are true:

- **Architect** agrees the PR still matches ADRs, module boundaries, branch policy, and acceptance criteria.
- **Reviewer** agrees code quality, safety, documentation, and drift checks have no blocking findings.
- **Executor** agrees the requested change is complete, cleanup is done, and required checks are green.
- All actionable PR comments are resolved.
- Local CI and host SCM CI (GitHub Actions, Azure Pipelines, or GitLab CI as applicable) are green.
- The architect, reviewer, and executor loop reaches explicit agreement. If any role disagrees, comments remain actionable, or checks are not green, do not merge.
- Auto-merge may be enabled only after actionable comments are resolved, local CI and host SCM CI are green, the architect/reviewer/executor loop agrees, and branch policy permits merge.

## Azure DevOps path

### CI scaffold

Write `azure-pipelines.yml` only when ADO Pipelines is selected:

```yaml
trigger:
  branches:
    include:
      - main

pr:
  branches:
    include:
      - main

pool:
  vmImage: ubuntu-latest

steps:
  - checkout: self
  - script: bash scripts/validate-rules.sh .rules.ts
    displayName: Validate Archgate rules
```

### Branch policy/build-validation checklist

Create `docs/agents/branch-policy-ado.md` with:

- Project, repository, and protected branch target.
- Minimum reviewer count.
- Linked work-item requirement when desired.
- Comment resolution requirement.
- Build validation policy referencing the selected pipeline.
- Required status/check naming convention.
- Whether administrators may self-approve PRs through admin approve/admin bypass, and the local policy rationale when allowed; this is valid only when the host/runtime explicitly supports admin approval for the same actor and the merge record captures actor, authority, reason, checks, and approval mode.
- Distinction between YAML `pr` triggers and Azure Repos branch-policy build validation.
- Links to the official Microsoft branch policy and pipeline trigger docs above.

## GitLab/local path

Keep existing GitLab/local tracker support. If GitLab CI or local-only checks are selected, write a checklist that mirrors the same intent: protected main/default branch, PR/MR-only delivery, required review, required checks, comment resolution, traceability, and explicit owner.

## Validation CI vs release CI

The `ai-sdlc-init` scaffold produces two distinct CI flows. They must be kept separate:

- **Validation CI** (`.github/workflows/ci-prek.yml` and equivalents for Azure Pipelines and GitLab CI) — runs on every push and PR. Owns prek hooks, Archgate structural checks, language-pack checks, golden verification, and lint/typecheck/test. Status checks from validation CI gate PR merges.
- **Release CI** (`modules/release-versioning.md` provider templates) — runs on push to `main`, on tag push, and via `workflow_dispatch`. Owns the release/versioning strategy, the `release.json` manifest, the tag guardrails, and the optional publish step. Status checks from release CI gate tag creation, not PR merges.

A common mistake is to fold release logic into validation CI (e.g. running semantic-release on every push). This module explicitly rejects that pattern. Release CI must not run on PRs, and validation CI must not produce tags or push to registries.
