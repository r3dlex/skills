# Foundation Module

Read when writing the current base scaffold artifacts. This module names the artifact set; use `../REFERENCE.md` for full legacy template bodies until the templates are split further.

## Artifacts

- `.agents/skills/karpathy-guidelines/SKILL.md` and `REFERENCE.md`
- `upstream.lock` with source, via, pinned SHA, update date, and sync script
- `.gitignore` marker block plus `upstream-pocock/.gitkeep`
- `raw/docs/incident-template.md`
- `scripts/sync-upstream.sh` as a documented sync scaffold
- `.github/workflows/ci-prek.yml`, `prek.toml`, `scripts/validate-rules.sh`, and `scripts/archgate.sh`
- `.rules.ts` with backend, frontend, data, architecture, and general rule domains
- `AGENTS.md`, `CLAUDE.md`, and `README.md` AI SDLC marker blocks
- `docs/adr/ADR-TEMPLATE.md` and `ADR-0001-record-architecture-decisions.md`

## Idempotency

Before writing marker blocks, check both the marker and the `AI SDLC Methodology` header. If the header exists without the marker, warn and skip rather than duplicating content.
