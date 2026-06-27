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
├── CLAUDE.md
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
| Entry files | `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md` | Both | Inherited assets only when explicitly listed. |

## `.ai/`

- `system-prompts/` holds role-specific instructions for `architect`, `developer`, and `qa-engineer`. New roles are added with a clearly named `.md` file and a one-line description in the file's first paragraph.
- `skills/` holds target-repo tool injection definitions in JSON form. These are tool/MCP descriptors that the target repo exposes to agents; they are not the same as Codex skill packages under `skills/`.
- `rules/` holds repo-specific safety and technical-bounds rules in Markdown. Cross-reference these from `.rules.ts` when present.
- `matrix.json` holds the topology matrix; see `modules/topology.md`.
- `workflows/` holds the human repo workflow and machine-readable workflow manifest.
- `phases/` holds per-phase status JSON for mandatory workflow steps.
- `handoff/` holds the generated initialization handoff index.
- `traceability/` holds graph.json, index.md, and validation-report.md for BRD/PRD/work artifact links.

## `.memory/`

- `human-override/` is terminal priority. The scaffold never overwrites existing files in this directory; new files are only created with explicit opt-in.
- `self-learned/` holds machine-readable knowledge such as `error-patterns.json` and `module-complexity.json`. Schemas are versioned with a `schema_version` field and a changelog under `.memory/self-learned/CHANGELOG.md`. See `modules/memory.md` for the full schema rules.

## `docs/`

- `architecture/adr/` holds ADR files numbered as `NNNN-title.md`, starting at `0001-init.md`.
- `architecture/data-contracts/` holds shared data contract definitions referenced by ADRs and code.
- `specifications/ACTIVE/` holds current specs; `ARCHIVED/` holds retired specs with a `superseded_by` pointer in their first paragraph.
- `learning/concept-maps/` holds concept-map diagrams or Markdown summaries; `troubleshooting-matrix.md` is the canonical index for known-issue → fix pairs.

## Entry files

- `AGENTS.md` — agent-facing operating contract.
- `CLAUDE.md` — Claude Code specific overrides (only if used; otherwise skip).
- `CONTRIBUTING.md` — human contributor guide.
- `README.md` — top-level human entry point.

All four files are required for standalone repos. Umbrella repos include them as inherited assets; managed sub-repos may have a thin local override that references the umbrella. Generated `AGENTS.md`, `CLAUDE.md`, and `README.md` link to `.ai/workflows/repo-workflow.md` and `.ai/workflows/repo-workflow.json`.

## Generation rules

1. Existing files are never overwritten silently. If a target path exists, the generator emits a `present-not-overwritten` audit entry and skips the write.
2. The first generation writes a `migration` block to `.ai/matrix.json` referencing the legacy-to-v3 migration manifest; see `modules/validation.md`.
3. Destructive operations (deleting a legacy artifact) require explicit confirmation; see `modules/host-policy-automation.md` and `modules/validation.md`.
4. Generation emits an audit log under `.ai/drift/last-generation.json` listing per-path action (`created`, `present-not-overwritten`, `skipped-conflict`).

## Migration from legacy scaffold

Migration rules, the action vocabulary, and the migration-manifest schema are owned by `modules/migration.md`. The blueprint does not duplicate them; consumers must read `modules/migration.md` for the authoritative classification of `.agents/`, `.rules.ts`, `docs/adr/`, marker blocks, and any pre-existing `.memory/` content.
