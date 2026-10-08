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
- `local_ci`: optional local-CI declaration — see below. An absent or empty `local_ci` means the consumer parks.

Validation fails when any manifest phase lacks a matching status file or when any generated entry surface omits either workflow link.

## `local_ci` declaration

`local_ci` declares what "local CI is green" means for this repository so that a consumer never has to probe for a command. Its shape is exactly a list of surfaces with per-surface hermeticity plus a truth claim. Illustrative example only — a hypothetical repository that carries no `.ai/ci/local-ci.json`, not any real repository's declaration:

```json
"local_ci": {
  "surfaces": [
    {
      "cmd": "bash tests/run-tests.sh",
      "hermetic": true,
      "covers": "unit tests, lint and fixture gates"
    },
    {
      "cmd": "bash tests/integration_test.sh",
      "hermetic": false,
      "covers": "integration tests that need hosted tooling"
    }
  ],
  "sole_source_of_truth": true
}
```

- `surfaces`: list of surface records, one per real CI surface. Each record has exactly `cmd`, `hermetic`, and `covers`:
  - `cmd`: non-empty string, the command run from the repository root.
  - `hermetic`: boolean — `true` when the surface runs offline in a fresh worktree, `false` when it is a declared non-hermetic surface (network, hosted tooling).
  - `covers`: non-empty string naming what the surface covers, so a completeness check can see what the declaration omits.
- `sole_source_of_truth`: boolean — `true` only when the listed surfaces are the repository's complete definition of local CI and a drift guard holds them honest; `false` while the list is provisional or partial. `true` over zero surfaces is malformed.

A flat command string or list (`"local_ci": "bash …"`, `"local_ci": ["bash …"]`) is **not** a valid declaration: one command cannot express a multi-surface definition of green with per-surface hermeticity and declared non-hermetic surfaces. Validation rejects a malformed declaration and names the offending JSON path (for example `local_ci.surfaces[0].hermetic`); the declaration is never repaired, defaulted, or replaced by a guess.

**An absent or empty `local_ci` declaration means the consumer parks**: it never verifies, never merges, and never probes the repository for a command. The same park rule applies to a declaration whose `sole_source_of_truth` is `false` and to any malformed declaration (fail closed). The scaffold emits an empty declaration (`"surfaces": []`, `"sole_source_of_truth": false`) so a freshly initialized repository starts parked until its owner derives the declaration from that repository's real CI surfaces — a template default is never treated as a derived declaration.

A `local_ci` is **declared** only when `surfaces` is non-empty and `sole_source_of_truth` is `true`; every other state parks. The parked starter (`"surfaces": []`, `"sole_source_of_truth": false`) is neither a declaration nor an exemption: it waives no gate and certifies nothing.

### Execution semantics

A consumer runs every declared surface regardless of `hermetic`: `hermetic: false` only declares that the surface needs network or hosted tooling, and never exempts it from the clean pass. Surfaces run sequentially in list order, and the first non-zero exit ends the run as not green. Each `cmd` is split into shell words and executed as argv without a shell, matching ADR-0015 (`.ai/ci/local-ci.json`); a compound command (`&&`, a pipe, a redirection) belongs in a script that the surface names.

### Relationship to `.ai/ci/local-ci.json`

`local_ci` is the declaration read by the af-06 `local_ci` consumer (ai-factory's verification gate and the root guard), and its `sole_source_of_truth` claim is scoped to that consumer's gate. `.ai/ci/local-ci.json` (`local-ci/1`, later `local-ci/2`) stays the autobahn contract defined by ADR-0015. The two are distinct contracts; neither is derived from or substitutes for the other. Until a reconciliation rule exists (owned by af-06b or tci-meta-af06), a repository that carries `.ai/ci/local-ci.json` **MUST NOT** declare `sole_source_of_truth: true`: it keeps the parked starter or declares `false`.

### Adoption

The field is not retroactive. An existing repository never receives it from the scaffold, because a present `repo-workflow.json` is `present-not-overwritten`; its owner adds `local_ci` deliberately. `ai-catapult init --force` replaces `repo-workflow.json` with the template and therefore resets a derived declaration to the parked starter.
