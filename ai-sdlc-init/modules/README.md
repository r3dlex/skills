# Init AI Repo Modules

Layer 3 modules keep the canonical `init-ai-repo` skill lean. The files currently remain under `ai-sdlc-init/` as a deprecated compatibility path/alias. Read only the module that matches the current scaffold decision.

| Module | When to read |
| --- | --- |
| `foundation.md` | Read when creating the base AI SDLC scaffold: Karpathy guidance, ADRs, `.rules.ts`, prek, sync scripts, and doc markers. |
| `validation.md` | Read when running scaffold verification, golden fixture checks, or regression tests. |
| `brd-prd-traceability.md` | Read when adding BRD, PRD, issue/ticket, agent brief, and drift-report backlinks. |
| `tracker-adapters.md` | Read when choosing GitHub, ADO, GitLab, or local markdown tracker integration. |
| `ci-policy.md` | Read when adding GitHub/ADO/GitLab CI and branch-policy/ruleset checklist artifacts. |
| `archgate.md` | Read when configuring structural `.rules.ts` validation or optional semantic/drift checks. |
| `language-packs.md` | Read when selecting local/CI checks for TypeScript, Python, Rust, Go, JVM/.NET, or polyglot repos. |
| `readme-documentation.md` | Read when initializing, augmenting, or rewriting `README.md` (template mode for sparse repos, safe augmentation/rewrite for existing). |
| `release-versioning.md` | Read when initializing release tagging, versioning, or CI/CD release workflows (Hybrid default, SemVer/CalVer variants, GHA/Azure/GitLab templates, tag guardrails). |

Planned modules may start as index entries before their dedicated story fills the file. Until then, fall back to `REFERENCE.md` only for existing template bodies.
