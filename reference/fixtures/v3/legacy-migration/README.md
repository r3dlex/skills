# Legacy Migration Fixture D

Reference v3 layout for a target repo migrating from a legacy AI-SDLC scaffold. The manifest documents four actions:

1. `copy` of `.agents/skills/karpathy-guidelines/SKILL.md` to `.ai/system-prompts/architect.md`.
2. `migrate` of `.rules.ts` to `.ai/rules/technical-bounds.md` (destructive, confirmation token required).
3. `copy` of `docs/adr/0001-record-architecture-decisions.md` to `docs/architecture/adr/0001-record-architecture-decisions.md`.
4. `supersede` of `AGENTS.md` (rewrite in v3 form, preserving human prose).

The destructive action is gated by `confirmation_token: ct-2026-06-07-001` and the legacy `.rules.ts` is backed up under `.ai/drift/backups/2026-06-07T00-00-00Z/.rules.ts`. The `migration-audit.jsonl` snippet shows the audit format.
