# Documentation Blueprint Module

Read when generating the v3 canonical layout in a target repo. The blueprint defines the deterministic `.ai/`, `.memory/`, and `docs/` trees, and the human/agent entry files. Standalone and umbrella repos both use the same blueprint; umbrella repos only differ in the inherited-assets list and the managed repos.

## Tree shape

```
.
├── .ai/
│   ├── matrix.json
│   ├── system-prompts/
│   │   ├── architect.md
│   │   ├── developer.md
│   │   └── qa-engineer.md
│   ├── skills/                  # target-repo tool injection definitions, not Codex skill packages
│   │   ├── git-ops.json
│   │   └── workspace-sync.json
│   ├── workflows/
│   │   ├── repo-workflow.md
│   │   └── repo-workflow.json
│   ├── phases/
│   │   ├── 01-discover-decide/status.json
│   │   ├── 02-govern-plan/status.json
│   │   ├── 03-configure-generate/status.json
│   │   └── 04-validate-handoff/status.json
│   ├── handoff/
│   │   └── init-ai-repo-handoff.md
│   ├── traceability/
│   │   ├── graph.json
│   │   ├── index.md
│   │   └── validation-report.md
│   ├── evals/
│   │   ├── coverage-exceptions.json
│   │   └── <set>/
│   │       ├── evalset.json
│   │       ├── rubric.md
│   │       └── judge-config.json
│   ├── policies/
│   │   └── model-routing.json
│   ├── observability/
│   │   ├── conventions.md
│   │   └── audit-checklist.md
│   ├── mcp/
│   │   ├── registry.json
│   │   └── a2a-handoff.md
│   ├── rules/
│   │   ├── security.md
│   │   └── technical-bounds.md
│   └── drift/
│       ├── last-drift.json
│       └── backups/
├── .memory/
│   ├── human-override/          # terminal-priority; never silently rewritten
│   │   ├── custom-conventions.md
│   │   └── tribal-knowledge.md
│   └── self-learned/            # local machine-readable knowledge
│       ├── error-patterns.json
│       └── module-complexity.json
├── docs/
│   ├── architecture/
│   │   ├── adr/
│   │   │   └── 0001-init.md
│   │   └── data-contracts/
│   ├── specifications/
│   │   ├── ACTIVE/
│   │   └── ARCHIVED/
│   └── learning/
│       ├── concept-maps/
│       └── troubleshooting-matrix.md
├── AGENTS.md
├── CLAUDE.md                     # thin pointer to AGENTS.md
├── GEMINI.md                     # thin pointer to AGENTS.md
├── CONTRIBUTING.md
└── README.md
```

## Layer rules

| Layer | Path | Audience | Mutable by sync? |
| --- | --- | --- | --- |
| Execution / policy | `.ai/` | Agents and CI | Inherited assets only. |
| Human override | `.memory/human-override/` | Humans | No; terminal priority. |
| Self-learned | `.memory/self-learned/` | Agents, local | No; written only by local agents, never by physical-copy sync. |
| Architecture | `docs/architecture/` | Humans | No; per-repo authorship. |
| Specifications | `docs/specifications/` | Humans | No; per-repo authorship. |
| Learning | `docs/learning/` | Humans | No; per-repo authorship. |
| Entry files | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, `README.md` | Both | Inherited assets only when explicitly listed. |

## `.ai/`

- `system-prompts/` holds role-specific instructions for `architect`, `developer`, and `qa-engineer`. New roles are added with a clearly named `.md` file and a one-line description in the file's first paragraph.
- `skills/` holds target-repo tool injection definitions in JSON form. These are tool/MCP descriptors that the target repo exposes to agents; they are not the same as Codex skill packages under `skills/`.
- `rules/` holds repo-specific safety and technical-bounds rules in Markdown. Cross-reference these from `.rules.ts` when present.
- `matrix.json` holds the topology matrix; see `modules/topology.md`.
- `workflows/` holds the human repo workflow and machine-readable workflow manifest.
- `phases/` holds per-phase status JSON for mandatory workflow steps.
- `handoff/` holds the generated initialization handoff index.
- `traceability/` holds graph.json, index.md, and validation-report.md for BRD/PRD/work artifact links.
- `evals/` holds one directory per evalset (`evalset.json`, `rubric.md`, `judge-config.json`) plus `coverage-exceptions.json`. Both output and trajectory evaluation are representable; see `modules/evals.md`. The eval-coverage gate is offline-structural only.
- `policies/` holds machine-readable routing/config policy. `model-routing.json` (ADR-0003) declares a `schema_version`, provider-neutral tiers `{frontier, mid, cheap}`, a `task_classes` map (task-class → tier), and a `host_aliases` table binding each host (e.g. `claude`, `codex`) to per-tier model names. Frontier covers requirements/architecture/initial-implementation/hard-verification; mid covers standard implementation/planning; cheap covers test generation/first-pass code review/CI monitoring/lookups. Tier aliases — not provider IDs — keep the policy portable; routing is validated offline-structurally (`modules/validation.md` check #15) with no network model resolution.
- `observability/` holds the generated observability surface (ADR-0005): `conventions.md` (logging and trace conventions) and `audit-checklist.md` (the token-cost and trajectory-audit checklist). Observability is non-optional harness surface — without it agent drift, cost, and trajectory are not auditable. These are generated conventions and a checklist, not live metering: token-cost and trajectory metering execute out-of-band and are recorded as evidence; CI validates only that the conventions and checklist exist (`modules/validation.md` check #16). The PR merge gate in `modules/ci-policy.md` references the audit checklist for behavior-changing PRs.
- `mcp/` holds the generated MCP/A2A surface (ADR-0005) under `.ai/mcp/`: `registry.json` (the MCP-server registry stub) and `a2a-handoff.md` (the A2A cross-agent handoff convention). Promoting MCP/A2A from a mention to a real surface adopts the open standards now and preserves multi-vendor optionality. The registry is a stub — declared servers carry `status: "stub"` and no resolved endpoint — and the handoff doc is a convention, not a live router; generation makes no network or model call. CI validates only that the registry parses with the expected shape and the handoff convention exists (`modules/validation.md` check #17). See `modules/mcp-a2a.md`.

## `.memory/`

- `human-override/` is terminal priority. The scaffold never overwrites existing files in this directory; new files are only created with explicit opt-in.
- `self-learned/` holds machine-readable knowledge such as `error-patterns.json` and `module-complexity.json`. Schemas are versioned with a `schema_version` field and a changelog under `.memory/self-learned/CHANGELOG.md`. See `modules/memory.md` for the full schema rules.

## `docs/`

- `architecture/adr/` holds ADR files numbered as `NNNN-title.md`, starting at `0001-init.md`.
- `architecture/data-contracts/` holds shared data contract definitions referenced by ADRs and code.
- `specifications/ACTIVE/` holds current specs; `ARCHIVED/` holds retired specs with a `superseded_by` pointer in their first paragraph.
- `learning/concept-maps/` holds concept-map diagrams or Markdown summaries; `troubleshooting-matrix.md` is the canonical index for known-issue → fix pairs.

## Entry files

- `AGENTS.md` — agent-facing operating contract and single source of truth for rule-file/static context.
- `CLAUDE.md` — thin pointer to `AGENTS.md` with no content-bearing sections (ADR-0004).
- `GEMINI.md` — thin pointer to `AGENTS.md` with no content-bearing sections (ADR-0004).
- `CONTRIBUTING.md` — human contributor guide.
- `README.md` — top-level human entry point.

`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, and `README.md` are required for standalone repos. Umbrella repos include them as inherited assets; managed sub-repos may have a thin local override that references the umbrella. Generated `AGENTS.md` and `README.md` link to `.ai/workflows/repo-workflow.md` and `.ai/workflows/repo-workflow.json`. `CLAUDE.md` and `GEMINI.md` carry only a single pointer to `AGENTS.md` and are emitted as thin pointers, not workflow-linking surfaces.

## Harness Map

Generated `AGENTS.md` carries a `## Harness Map` section enumerating the six context types and documenting the static-vs-dynamic context boundary (ADR-0005). The Harness Map is non-optional AGENTS.md surface: it makes the agent's context inputs explicit and reviewable rather than implicit.

The six context types, each emitted as a code-fenced cell pointing at its canonical source in the v3 tree:

| Context type | Canonical source | Static or dynamic |
| --- | --- | --- |
| `Instructions` | `AGENTS.md`, `.ai/system-prompts/`, `.ai/rules/` | Static |
| `Knowledge` | `docs/architecture/`, `docs/specifications/`, `docs/learning/` | Static |
| `Memory` | `.memory/human-override/`, `.memory/self-learned/` | Dynamic |
| `Examples` | `.ai/evals/<set>/`, `docs/learning/concept-maps/` | Static |
| `Tools` | `.ai/skills/`, `.ai/mcp/registry.json` | Dynamic |
| `Guardrails` | `.ai/rules/security.md`, `.ai/rules/technical-bounds.md`, `.ai/policies/` | Static |

**Static-vs-dynamic boundary.** Static context is fixed at the start of a task (instructions, knowledge, examples, guardrails) and is reviewed and versioned in-repo; dynamic context is assembled per-run (memory written by local agents, tool/MCP results resolved at call time). The boundary is a reviewed, versioned architectural decision (ADR-0005), not an implicit one: moving a context type across the boundary requires an ADR update.

## Generation rules

1. Existing files are never overwritten silently. If a target path exists, the generator emits a `present-not-overwritten` audit entry and skips the write.
2. The first generation writes a `migration` block to `.ai/matrix.json` referencing the legacy-to-v3 migration manifest; see `modules/validation.md`.
3. Destructive operations (deleting a legacy artifact) require explicit confirmation; see `modules/host-policy-automation.md` and `modules/validation.md`.
4. Generation emits an audit log under `.ai/drift/last-generation.json` listing per-path action (`created`, `present-not-overwritten`, `skipped-conflict`).

## Migration from legacy scaffold

Migration rules, the action vocabulary, and the migration-manifest schema are owned by `modules/migration.md`. The blueprint does not duplicate them; consumers must read `modules/migration.md` for the authoritative classification of `.agents/`, `.rules.ts`, `docs/adr/`, marker blocks, and any pre-existing `.memory/` content.

## Cascade outputs

When the cascade branch is enabled, generate `.ai/cascade/cascade-plan.json`, `.ai/cascade/audit.jsonl`, `.ai/cascade/reconciliation-report.md`, and `.ai/cascade/host-adapters/<host>.json` for each configured host. These outputs are validation artifacts; hosted mutation remains confirmation-gated.

## Skill catalog outputs

When the target repo owns a skill catalog, generate `.ai/skills/catalog-audit.json`, `.ai/skills/description-exceptions.json`, and `.ai/skills/modernization-report.md`. These artifacts enforce compact descriptions, progressive disclosure, trigger boundaries, cross-skill links, and AI-SDLC compatibility.
