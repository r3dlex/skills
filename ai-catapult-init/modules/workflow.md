# Workflow Surfaces Module

Read when generating the repo workflow documentation, machine-readable workflow manifest, per-phase status files, or handoff links for an `init-ai-repo` target repository.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/workflows/repo-workflow.md` | Human-readable workflow with mandatory and optional steps. |
| `.ai/workflows/repo-workflow.json` | Machine-readable phase, status, surface-link, and handoff manifest. |
| `.ai/phases/<phase>/status.json` | Per-phase status record for agent/human progress tracking. |
| `.ai/handoff/init-ai-repo-handoff.md` | Final handoff index linking workflow, validation, and remaining work. |

Generated `AGENTS.md` and `README.md` surfaces must link to both the workflow doc and the manifest so humans and agents can find the same source of truth. `CLAUDE.md` and `GEMINI.md` are thin pointers to `AGENTS.md` (ADR-0004) and carry no workflow links of their own.

## Mandatory repo initialization workflow

1. **Discover & Decide** — classify topology, host/tracker posture, current governance, and first-run safety constraints.
2. **Govern & Plan** — generate governance docs, active specification placeholders, ADR baseline, work intake, and branch-policy checklist.
3. **Configure & Generate** — generate `.ai/`, `.memory/`, commands, language-pack checks, host-policy dry-run artifacts, and CI/policy templates.
4. **Validate & Handoff** — run local checks, fixture/static validation, hosted/local reconciliation, drift report, and handoff.

Every mandatory phase writes a status JSON with `phase_id`, `required`, `status`, `inputs`, `outputs`, and `next_actions`.

## Optional workflow branches

- **Multi-repo cascade** — enabled only for umbrella topology or explicit multi-repo selection; see `cascade.md` for orchestration, confirmation, idempotency, audit, and reconciliation semantics.
- **Hosted tracker first** — enabled when a configured tracker is authorized; otherwise local markdown fallback is recorded and reconciled before final merge.
- **Legacy migration** — enabled when legacy `.agents`/`.rules.ts`/marker-block artifacts are present; destructive actions remain confirmation-gated.
- **Skill modernization** — enabled when the target repo owns a skill catalog; see `skill-modernization.md` for description budgets, audit gates, and cross-skill workflow links.

## Manifest contract

`repo-workflow.json` uses schema version `1.0` and must include:

- `workflow_id`: stable workflow name, normally `init-ai-repo`.
- `topology_type`: `standalone` or `umbrella` from `.ai/matrix.json`.
- `human_doc`: path to `.ai/workflows/repo-workflow.md`.
- `manifest`: path to `.ai/workflows/repo-workflow.json`.
- `entry_surfaces`: generated surfaces that link to both workflow files — `AGENTS.md` and `README.md` only. `CLAUDE.md`/`GEMINI.md` are thin pointers to `AGENTS.md` and are never entry surfaces.
- `phases`: ordered phase records with `id`, `title`, `required`, `status_path`, and `outputs`.
- `optional_branches`: optional branch records with `id`, `enabled_when`, and `status`.
- `handoff`: path to `.ai/handoff/init-ai-repo-handoff.md`.

Validation fails when any manifest phase lacks a matching status file or when any generated entry surface omits either workflow link.
