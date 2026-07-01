# Init AI Repo Modules

Layer 3 modules keep the canonical `init-ai-repo` skill lean. These files live under the canonical `init-ai-repo/` path; `ai-sdlc-init/` is only a deprecated compatibility path/alias shim. Read only the module that matches the current scaffold decision.

| Module | When to read |
| --- | --- |
| `foundation.md` | Read when creating the base AI SDLC scaffold: Karpathy guidance, ADRs, `.rules.ts`, prek, sync scripts, and doc markers. |
| `validation.md` | Read when running scaffold verification, golden fixture checks, or regression tests. |
| `brd-prd-traceability.md` | Read when adding BRD, PRD, issue/ticket, agent brief, and drift-report backlinks. |
| `tracker-adapters.md` | Read when choosing GitHub, ADO, GitLab, Jira, or local markdown tracker integration. |
| `ci-policy.md` | Read when adding GitHub/ADO/GitLab CI and branch-policy/ruleset checklist artifacts. |
| `host-policy-automation.md` | Read when applying hosted branch/PR/policy mutations to GitHub, ADO, GitLab, or Jira, or when emitting dry-run diffs and confirmation gates. |
| `archgate.md` | Read when configuring structural `.rules.ts` validation or optional semantic/drift checks. |
| `language-packs.md` | Read when selecting local/CI checks for TypeScript, Python, Rust, Go, JVM, .NET Core/EF Core, legacy .NET/EF, or polyglot repos. |
| `readme-documentation.md` | Read when initializing, augmenting, or rewriting `README.md` (template mode for sparse repos, safe augmentation/rewrite for existing). |
| `release-versioning.md` | Read when initializing release tagging, versioning, or CI/CD release workflows (Hybrid default, SemVer/CalVer variants, GHA/Azure/GitLab templates, tag guardrails). |
| `topology.md` | Read when the target repo needs a standalone or umbrella topology matrix, depth validation, or `.ai/matrix.json` schema generation. |
| `documentation-blueprint.md` | Read when generating the v3 canonical `.ai/`, `.memory/`, `docs/architecture`, `docs/specifications`, `docs/learning` trees, and the entry files. |
| `memory.md` | Read when defining the `.memory/human-override/` and `.memory/self-learned` schemas. |
| `sync.md` | Read when implementing physical-copy sync, drift detection, backups, or audit logs. |
| `migration.md` | Read when migrating a target repo from a legacy AI-SDLC scaffold to the v3 layout, or when classifying legacy artifacts. |
| `phases/README.md` | Read when mapping the four public phases to internal checkpoints. |
| `phases/01-discover-decide.md` | Read when executing Phase 1 discovery, lane selection, hosted-ticket posture, and OMX/OMC planning surfaces. |
| `workflow.md` | Read when generating repo workflow docs, workflow/status manifests, entry-surface links, and handoff indexes. |
| `traceability.md` | Read when generating stable IDs, graph schema, backlink validation, graph fixtures, and cross-skill artifact links. |
| `cascade.md` | Read when generating multi-repo cascade plans, first-run confirmation gates, idempotent linked updates, host adapter contracts, audits, and reconciliation reports. |
| `skill-modernization.md` | Read when auditing compact descriptions, progressive disclosure, trigger boundaries, cross-skill links, and AI-SDLC compatibility. |

`workflow.md`, `traceability.md`, `cascade.md`, and `skill-modernization.md` are active phase modules. Fall back to `REFERENCE.md` only for legacy template bodies that have not yet moved into focused modules.

## Module ordering for a fresh v3 scaffold

1. `topology.md` — decide standalone or umbrella, set `max_allowed_depth`.
2. `documentation-blueprint.md` — generate the v3 tree.
3. `memory.md` — wire `.memory/` schemas.
4. `sync.md` — wire physical-copy propagation and drift.
5. `tracker-adapters.md` + `host-policy-automation.md` — choose tracker and apply path.
6. `ci-policy.md` — CI workflow and branch-policy checklist.
7. `language-packs.md` — choose checks.
8. `validation.md` — verify the scaffold matches the blueprint and golden fixtures.
9. `foundation.md` + `brd-prd-traceability.md` + `archgate.md` + `migration.md` — supporting modules as needed (migration only when a legacy scaffold is present).

## Phase modules

| Module | Purpose |
|--------|---------|
| [`phases/README.md`](phases/README.md) | Four-phase AI-SDLC phase index and original eight-checkpoint mapping. |
| [`phases/01-discover-decide.md`](phases/01-discover-decide.md) | Phase 1 discovery, lane selection, hosted-ticket posture, and OMX/OMC planning surfaces. |
