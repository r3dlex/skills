# ai-catapult-init Phase Modules

The canonical `ai-catapult-init` workflow exposes four optimized phases so agents and humans can move quickly while still preserving traceability. Each phase writes durable state under `.ai/phases/<phase>/` and links command output back to specs, plans, and validation evidence.

## Four optimized phases

| Phase | Name | Primary outputs |
|-------|------|-----------------|
| 1 | Discover & Decide | `.ai/matrix.json`, `.ai/init/repo-profile.json`, `.ai/init/sdlc-path.md`, `.ai/phases/01-discover-decide/` |
| 2 | Govern & Plan | `AGENTS.md`, `RULES.md`, `PLANS.md`, `CONTRIBUTING.md`, specs, ADRs, `.ai/work-intake/`, `.ai/plans/`, `.ai/phases/02-govern-plan/` |
| 3 | Configure & Generate | `.ai/bin/`, `.ai/policies/`, `.ai/commands/omx/`, `.ai/commands/omc/`, `.ai/language-packs/`, `.ai/phases/03-configure-generate/` |
| 4 | Validate & Handoff | `.ai/validation/report.md`, `.ai/drift/migration-manifest.json`, `.ai/handoff/init-ai-repo-handoff.md`, `.ai/phases/04-validate-handoff/` |

## Eight internal checkpoints

The old eight-step model remains as internal checkpoint metadata, not as the public workflow surface:

1. Detect repo state → Phase 1
2. Choose SDLC path → Phase 1
3. Scaffold foundation → Phase 2
4. Scaffold work intake → Phase 2
5. Configure host adapters → Phase 3
6. Configure CI and policy → Phase 3
7. Select language packs → Phase 3
8. Validate and emit handoff → Phase 4

## Command-surface schema

Phase 3 generates `.ai/commands/omx/` and `.ai/commands/omc/` entries. The
shared command-surface schema (fields, `.json` extension, and the omx `$name`
vs omc `/oh-my-claudecode:name` invocation forms) is defined once in
[`northstar/modules/command-surface.md`](../../../northstar/modules/command-surface.md);
this generator and the catalog skills emit identical shapes.
