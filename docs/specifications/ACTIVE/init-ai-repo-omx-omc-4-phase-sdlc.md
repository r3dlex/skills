# init-ai-repo OMX/OMC 4-Phase AI-SDLC Integration Spec

Status: Active
Owner: `skills/init-ai-repo`
Date: 2026-06-21
Source context: `.omx/context/ai-sdlc-phases-omx-omc-integration-20260620T114916Z.md`

## 1. Purpose

Update the canonical `init-ai-repo` skill so its generated AI-SDLC scaffold is efficient, phase-driven, and directly usable through OMX and OMC command surfaces. The workflow should preserve governance quality while minimizing ceremony.

The skill must generate the files, folders, command docs, and helper surfaces needed for agents to move from requirements to implementation with traceability.

## 2. Scope

### In scope

- Canonical skill name: `init-ai-repo`.
- Legacy compatibility: keep `ai-sdlc-init` as an alias or compatibility path where needed.
- OMX command-surface integration.
- OMC / oh-my-codex alias, command, and runtime integration.
- Phase-specific folders under `.ai/`.
- Generated governance and workflow files:
  - `RULES.md`
  - `PLANS.md`
  - `CONTRIBUTING.md`
- Generated `.ai`, `docs`, and command/runtime structures.
- Recommended workflow lanes with allowed alternatives.
- Hosted issue/ticket reconciliation before final PR merge.

### Out of scope

- Mandatory integration with non-OMX orchestration frameworks.
- Requiring one single workflow command for every repo regardless of repo maturity.
- Bypassing human-hosted source-of-truth systems when they are configured and authorized.

## 3. Source Decisions From Deep Interview

1. Use only OMX and OMC command surfaces for workflow integration.
2. OMC means oh-my-codex alias, command, and runtime surfaces.
3. Preserve phase-specific folders.
4. Prefer a recommended lane, but allow alternatives.
5. Commands should generate the required `.ai`, `docs`, and other generated structures.
6. Keep the original eight AI-SDLC phases as internal checkpoints or metadata, but expose a minimized four-phase workflow.
7. Hosted ticket/issue tracking is preferred and fail-closed when configured and authorized.
8. Local fallback is allowed before coding only when hosted tracking is unavailable or unauthorized, but it must be reconciled before final PR merge.

## 4. Required 4-Phase Workflow

### Phase 1 — Discover & Decide

Combines legacy phases:

- Detect repo state.
- Choose SDLC path.

Purpose:

- Identify repo type, language stacks, existing governance files, existing CI, hosted tracker availability, and whether the repo is greenfield or brownfield.
- Select the minimal applicable SDLC profile.

Required outputs:

- `.ai/matrix.json`
- `.ai/init/repo-profile.json`
- `.ai/init/sdlc-path.md`
- Phase folder: `.ai/phases/01-discover-decide/`

Expected command surfaces:

- OMX: `$deep-interview`, `$plan`, `$ralplan`
- OMC: equivalent oh-my-codex alias/command/runtime invocations for the same actions

Exit criteria:

- Repo profile exists.
- SDLC path is selected.
- Missing hosted tracker or CI capabilities are explicitly recorded.

### Phase 2 — Govern & Plan

Combines legacy phases:

- Scaffold foundation.
- Scaffold work intake.

Purpose:

- Generate the durable governance layer before implementation.
- Ensure every coding effort has traceability, specification, plan, and acceptance criteria.

Required outputs:

- `AGENTS.md` updates or managed block.
- `RULES.md`
- `PLANS.md`
- `CONTRIBUTING.md`
- `docs/specifications/ACTIVE/`
- `docs/specifications/ARCHIVED/`
- `docs/architecture/adr/`
- `.ai/work-intake/`
- `.ai/plans/`
- Phase folder: `.ai/phases/02-govern-plan/`

Required governance gates before coding:

1. A hosted issue/ticket exists when the hosted system is configured and authorized.
2. If hosted issue creation is unavailable, a local fallback ticket may be created under `.ai/work-intake/`.
3. A local fallback ticket must be reconciled with the hosted tracker before final PR merge.
4. A PRD/spec or equivalent active specification exists.
5. A plan exists.
6. Acceptance criteria are explicit enough to verify.

Expected command surfaces:

- Recommended lane: `$ralplan` for reviewed planning.
- Alternatives:
  - `$deep-interview` for unclear requirements.
  - `$plan` for lightweight planning.
  - `$prometheus-strict` where clean-room adversarial planning is preferred.

Exit criteria:

- Governance files exist.
- Work item source of truth is recorded.
- Spec and plan are present.
- Acceptance criteria are testable.

### Phase 3 — Configure & Generate

Combines legacy phases:

- Configure host adapters.
- Configure CI and policy.
- Select language packs.

Purpose:

- Generate the executable repo-local helpers and command documentation that make the workflow usable through OMX and OMC.
- Keep generation lightweight and repo-appropriate.

Required outputs:

- `.ai/bin/`
- `.ai/policies/`
- `.ai/commands/omx/`
- `.ai/commands/omc/`
- `.ai/language-packs/` where applicable
- Optional `Makefile` targets only when compatible with the repo or explicitly configured.
- Optional `justfile` recipes only when compatible with the repo or explicitly configured.
- Phase folder: `.ai/phases/03-configure-generate/`

Generation policy:

- Always generate canonical scripts under `.ai/bin/`.
- Document OMX and OMC command equivalents regardless of whether optional wrappers are generated.
- Do not add heavyweight dependencies by default.
- Do not overwrite existing human-maintained workflow files without a managed block or explicit migration step.

Expected command surfaces:

- `$ralph` for single-owner execution loops.
- `$team` for coordinated multi-agent execution.
- `$ultragoal` for durable goal-driven execution.
- `$ultrawork` for bounded high-throughput execution when appropriate.
- OMC equivalents must write to the same `.ai` and `docs` artifact locations.

Exit criteria:

- Command surfaces are documented.
- Scripts or wrappers exist where expected.
- Generated structures are idempotent or clearly managed.

### Phase 4 — Validate & Handoff

Combines legacy phases:

- Validate.
- Emit handoff.

Purpose:

- Verify the scaffold and workflow before claiming completion.
- Produce durable handoff material for humans and future agents.

Required outputs:

- `.ai/validation/report.md`
- `.ai/drift/migration-manifest.json`
- `.ai/handoff/init-ai-repo-handoff.md`
- Phase folder: `.ai/phases/04-validate-handoff/`

Expected command surfaces:

- `$doctor` for OMX/runtime health where relevant.
- `$code-review` for drift and policy review.
- `$team` or `$ralph` for execution verification when the setup was part of an implementation lane.

Exit criteria:

- Validation report exists.
- Missing capabilities are listed as warnings or blockers.
- Hosted/local work item reconciliation status is explicit.
- Handoff describes next commands and expected artifacts.

## 5. Legacy 8-Phase Mapping

| Legacy phase | New phase | Notes |
| --- | --- | --- |
| 1. Detect repo state | 1. Discover & Decide | Preserved as repo-profile checkpoint. |
| 2. Choose SDLC path | 1. Discover & Decide | Preserved as path selection. |
| 3. Scaffold foundation | 2. Govern & Plan | Generates governance docs. |
| 4. Scaffold work intake | 2. Govern & Plan | Enforces ticket/spec/plan/AC gates. |
| 5. Configure host adapters | 3. Configure & Generate | Generates hosted/local adapter docs and helpers. |
| 6. Configure CI and policy | 3. Configure & Generate | Generates validation and policy hooks where applicable. |
| 7. Select language packs | 3. Configure & Generate | Optional, repo-aware generation. |
| 8. Validate and emit handoff | 4. Validate & Handoff | Validation and handoff remain explicit. |

## 6. OMX / OMC Command-Surface Contract

| Intent | Recommended lane | Allowed alternatives | Required artifact impact |
| --- | --- | --- | --- |
| Requirements unclear | `$deep-interview` | `$prometheus-strict` | Create or update spec seed under `docs/specifications/ACTIVE/` and `.ai/work-intake/`. |
| Reviewed plan needed | `$ralplan` | `$plan` | Create or update `.ai/plans/`, `PLANS.md`, and active spec references. |
| Single-owner execution | `$ralph` | Direct solo execution for small changes | Update `PLANS.md`, `.ai/plans/`, and validation report. |
| Coordinated execution | `$team` | `$ultrawork` for bounded parallelism | Create phase/team execution records under `.ai/plans/` and `.ai/phases/`. |
| Durable goal loop | `$ultragoal` | `$ralph` for simpler loops | Create durable goal plan and progress state under `.ai/plans/` or `.ai/goals/`. |
| Health and validation | `$doctor`, `$code-review` | repo-native lint/test/typecheck | Write `.ai/validation/report.md`. |

OMC / oh-my-codex aliases and runtime commands must resolve to the same artifact contract. They may differ in invocation syntax, but not in generated structure or governance semantics.

## 7. Expected Generated Structure

```text
.
├── AGENTS.md
├── RULES.md
├── PLANS.md
├── CONTRIBUTING.md
├── .ai/
│   ├── matrix.json
│   ├── init/
│   │   ├── repo-profile.json
│   │   └── sdlc-path.md
│   ├── work-intake/
│   ├── plans/
│   ├── policies/
│   ├── bin/
│   ├── commands/
│   │   ├── omx/
│   │   └── omc/
│   ├── phases/
│   │   ├── 01-discover-decide/
│   │   ├── 02-govern-plan/
│   │   ├── 03-configure-generate/
│   │   └── 04-validate-handoff/
│   ├── validation/
│   │   └── report.md
│   ├── drift/
│   │   └── migration-manifest.json
│   └── handoff/
│       └── init-ai-repo-handoff.md
└── docs/
    ├── specifications/
    │   ├── ACTIVE/
    │   └── ARCHIVED/
    └── architecture/
        └── adr/
```

## 8. Governance and Merge Gates

Before coding:

- There must be an issue/ticket, hosted when configured and authorized.
- There must be an active spec or PRD.
- There must be a plan.
- Acceptance criteria must be explicit.

During coding:

- Plans and state should update in `PLANS.md` and `.ai/plans/`.
- Phase-specific evidence should land under `.ai/phases/` where applicable.
- Changes should stay traceable to the ticket/spec/plan.

Before final PR merge:

- Local fallback tickets must be reconciled with the hosted issue tracker.
- admin approval mode is explicit: an approving reviewer may be the same admin actor only when the host/runtime explicitly supports admin approval or admin bypass for that actor; GitHub hosted PR review rejects same-actor approval, so GitHub uses distinct admin review or admin bypass/admin merge with actor, authority, reason, checks, and approval mode recorded.
- Validation evidence must be recorded.
- Drift against spec, ADRs, and `RULES.md` must be checked.
- Handoff must state what was done, what was verified, and what remains.

Fail-closed rule:

- If a hosted tracker is configured and authorized but cannot be reached or validated, final merge should be blocked until reconciliation succeeds or a human explicitly overrides the gate.

## 9. Acceptance Criteria

1. The canonical skill is named `init-ai-repo` and any `ai-sdlc-init` usage is compatibility-only.
2. The exposed workflow has four phases.
3. The original eight phases remain represented as internal checkpoints or metadata.
4. The generated scaffold includes `RULES.md`, `PLANS.md`, and `CONTRIBUTING.md`.
5. `.ai/phases/` contains phase-specific folders for all four phases.
6. OMX command documentation is generated.
7. OMC / oh-my-codex command and runtime documentation is generated.
8. Hosted issue/ticket-first workflow is documented and enforced where possible.
9. Local fallback work intake is allowed before coding but must be reconciled before final PR merge.
10. Validation and handoff artifacts are generated.

## 10. Validation Strategy

The implementation should add or update tests that verify:

- The four-phase scaffold is generated.
- Legacy eight-phase metadata is preserved.
- Required files are generated.
- OMX and OMC command directories are generated.
- Local fallback reconciliation status is represented.
- Existing scaffold generation remains idempotent.

Manual validation should include:

- Running the skill generator on a temporary fixture repo.
- Inspecting generated `.ai`, `docs`, `RULES.md`, `PLANS.md`, and `CONTRIBUTING.md`.
- Confirming no unmanaged human content is overwritten.

## 11. Risks and Open Implementation Notes

- Existing repos may already have `CONTRIBUTING.md`, `RULES.md`, or planning docs. The generator should prefer managed blocks or non-destructive merge behavior.
- Repos without hosted tracker credentials need a clear local fallback path, but final PR merge must still record reconciliation status.
- Optional Makefile and justfile support should remain opt-in or compatibility-detected to avoid forcing a build style.
- OMC alias/runtime docs should avoid duplicating OMX semantics; they should point to the same artifact contract.
