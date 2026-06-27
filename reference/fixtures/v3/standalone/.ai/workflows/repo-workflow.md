# init-ai-repo Workflow

This generated workflow is the shared source of truth for mandatory and optional AI-SDLC initialization steps.

- Machine manifest: [`repo-workflow.json`](repo-workflow.json)
- Handoff index: [`../handoff/init-ai-repo-handoff.md`](../handoff/init-ai-repo-handoff.md)

## Mandatory steps

1. **Discover & Decide** (`.ai/phases/01-discover-decide/status.json`) - required outputs include .ai/matrix.json, .ai/init/repo-profile.json, .ai/init/sdlc-path.md.
2. **Govern & Plan** (`.ai/phases/02-govern-plan/status.json`) - required outputs include AGENTS.md, RULES.md, PLANS.md, docs/specifications/ACTIVE/.
3. **Configure & Generate** (`.ai/phases/03-configure-generate/status.json`) - required outputs include .ai/bin/, .ai/policies/, .ai/commands/omx/, .ai/commands/omc/, .github/workflows/.
4. **Validate & Handoff** (`.ai/phases/04-validate-handoff/status.json`) - required outputs include .ai/validation/report.md, .ai/drift/migration-manifest.json, .ai/handoff/init-ai-repo-handoff.md.

## Optional steps

- **multi-repo-cascade** - enabled when topology_type == umbrella; status: `planned-pr-6d`.
- **hosted-tracker-first** - enabled when configured tracker is authorized; status: `available`.
- **legacy-migration** - enabled when legacy scaffold artifacts are detected; status: `available`.
- **skill-modernization** - enabled when target repo owns a skill catalog; status: `planned-pr-6e`.

## Entry surface links

Generated `AGENTS.md`, `CLAUDE.md`, and `README.md` must link to this workflow doc and `.ai/workflows/repo-workflow.json`.
