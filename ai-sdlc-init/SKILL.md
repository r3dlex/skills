---
name: init-ai-repo
description: 'Bootstrap an end-to-end AI-ready repository: BRD/PRD traceability, tracker setup, CI/governance, release versioning, Archgate rules, Karpathy guidance, ADRs, branch-policy checklist, and validation. Deprecated compatibility alias: ai-sdlc-init. Use when initializing AI-assisted software delivery, modernizing repo governance, or when the user says "init-ai-repo", "ai-sdlc-init", "bootstrap AI SDLC", or "set up AI SDLC".'
---

# Init AI Repo

## Quick Start

Run this skill in the target repo. `init-ai-repo` is the canonical skill name; `ai-sdlc-init` remains a deprecated compatibility alias during the migration. Use dry-run first when scope or host choices are unclear. Keep hosted settings as checklist output unless the user explicitly requests an admin/credentialed action.

## Workflow

### Phase 1 — Discover & Decide
Inspect repository state, host tooling, trackers, CI, and runtime conventions. Choose greenfield bootstrap, brownfield adoption, hosted-tracker-first, or local fallback. Emit `.ai/matrix.json`, `.ai/init/repo-profile.json`, `.ai/init/sdlc-path.md`, and `.ai/phases/01-discover-decide/`. OMX surfaces: `$deep-interview`, `$plan`, `$ralplan`; OMC surfaces must produce the same artifact contract.

### Phase 2 — Govern & Plan
Generate or refresh `AGENTS.md`, `RULES.md`, `PLANS.md`, `CONTRIBUTING.md`, active/archived specs, ADRs, `.ai/work-intake/`, `.ai/plans/`, and `.ai/phases/02-govern-plan/`. Ensure a hosted issue/ticket when configured and authorized. Local fallback is allowed before coding, but it must be reconciled before final PR merge. Require active spec/PRD, plan, and acceptance criteria before implementation.

### Phase 3 — Configure & Generate
Generate command/runtime surfaces and policy automation under `.ai/bin/`, `.ai/policies/`, `.ai/commands/omx/`, `.ai/commands/omc/`, `.ai/language-packs/`, optional `Makefile`/`justfile`, and `.ai/phases/03-configure-generate/`. OMX surfaces: `$ralph`, `$team`, `$ultragoal`, `$ultrawork`; OMC aliases/commands delegate to the same generated structures rather than duplicate semantics.

### Phase 4 — Validate & Handoff
Run local validation, drift checks, generated smoke tests, and hosted/local ticket reconciliation. Emit `.ai/validation/report.md`, `.ai/drift/migration-manifest.json`, `.ai/handoff/init-ai-repo-handoff.md`, and `.ai/phases/04-validate-handoff/`. OMX surfaces: `$doctor`, `$code-review`, `$team`, `$ralph`. The handoff records done, verified, remaining, and reconciliation status.

### Internal checkpoints

The public workflow is four phases, but the generator preserves the original eight internal checkpoints for compatibility and traceability:

1. Detect repo state
2. Choose SDLC path
3. Scaffold foundation
4. Scaffold work intake
5. Configure host adapters
6. Configure CI and policy
7. Select language packs
8. Validate and emit handoff

## PR Merge Gate

Every implementation initialized by this skill must assume protected `main` and PR-only delivery. Emit provider-specific branch-policy checklist/config artifacts unless the user explicitly authorizes hosted mutation with credentials. Admin users may self-approve only when host policy permits it and all required checks still pass.

When this skill creates or updates PR workflow guidance, require merge only after:

1. The **architect** confirms the implementation still matches ADRs, module boundaries, branch policy, and acceptance criteria.
2. The **reviewer** confirms code quality, safety, documentation, and drift checks have no blocking findings.
3. The **executor** confirms the requested change is implemented, cleanup is complete, and all required checks are green.
4. All actionable PR comments are resolved and local CI plus host SCM CI (GitHub Actions, Azure Pipelines, or GitLab CI as applicable) are green.
5. The loop reaches explicit agreement across architect, reviewer, and executor; if any role disagrees, comments remain actionable, checks are not green, or branch policy forbids merge, do not merge or auto-merge.

## Module Map

- `modules/README.md` — read when choosing which Layer 3 module applies.
- `modules/foundation.md` — read when writing the existing core scaffold artifacts.
- `modules/validation.md` — read when validating generated artifacts and golden fixtures.
- `REFERENCE.md` — read only for legacy full template bodies that have not yet moved into focused modules.
- `modules/readme-documentation.md` — read when initializing, augmenting, or rewriting `README.md` (template mode for sparse repos, safe augmentation for existing).
- `modules/release-versioning.md` — read when initializing release tagging, versioning, or CI/CD release workflows (Hybrid default; SemVer/CalVer variants; GHA/Azure/GitLab templates; tag guardrails).

## Safety Rules

- Keep `SKILL.md` under 100 body lines; move variants to modules.
- Treat GitHub/ADO branch settings as checklists by default, never hidden mutations.
- Reference `setup-skills` and `publish-semver` host docs instead of copying their full semantics.
- Preserve existing GitLab/local support unless a later module explicitly migrates it.
