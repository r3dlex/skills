---
name: init-ai-repo
description: 'Bootstrap an end-to-end AI-ready repository: BRD/PRD traceability, tracker setup, CI/governance, release versioning, Archgate rules, Karpathy guidance, ADRs, branch-policy checklist, and validation. Deprecated compatibility alias: ai-sdlc-init. Use when initializing AI-assisted software delivery, modernizing repo governance, or when the user says "init-ai-repo", "ai-sdlc-init", "bootstrap AI SDLC", or "set up AI SDLC".'
---

# Init AI Repo

## Quick Start

Run this skill in the target repo. `init-ai-repo` is the canonical skill name; `ai-sdlc-init` remains a deprecated compatibility alias during the migration. Use dry-run first when scope or host choices are unclear. Keep hosted settings as checklist output unless the user explicitly requests an admin/credentialed action.

## Workflow

1. **Detect repo state** — read `AGENTS.md`/`CLAUDE.md`, setup-skills markers, existing CI, language manifests, ADRs, and `.rules.ts`. Read `modules/README.md` when selecting optional modules.
2. **Choose SDLC path** — map the repo to lifecycle modules: foundation, work intake, tracker, CI/policy, Archgate, language packs, and validation.
3. **Scaffold foundation** — create/update Karpathy guidance, ADR templates, `.rules.ts`, `prek.toml`, Archgate scripts, `upstream.lock`, and AI SDLC doc blocks. Read `modules/foundation.md` for artifacts and `modules/archgate.md` for the JSON/semantic contract.
4. **Scaffold work intake** — add BRD/PRD/ticket traceability only through the dedicated module. Read the BRD/PRD module when the repo lacks business-to-ticket flow.
5. **Configure host adapters** — use setup-skills tracker adapters for GitHub, ADO, GitLab, or local markdown. Do not duplicate tracker semantics in this skill.
6. **Configure CI and policy** — write CI files and branch-protection/branch-policy checklists. Read `modules/ci-policy.md` when choosing GitHub/ADO CI or hosted policy checklist details. Do not silently mutate GitHub or ADO settings.
7. **Select language packs** — detect manifests or use explicit user selection. Read `modules/language-packs.md` when choosing TypeScript, Python, Rust, Go, JVM/.NET, or polyglot checks. Do not add dependencies unless detection or opt-in supports them.
8. **Validate and emit handoff** — run structural checks and golden verification. Read `modules/validation.md` when verifying scaffold output.

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
