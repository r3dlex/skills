# Migration Module

Read when migrating a target repo from a legacy AI-SDLC scaffold to the v3 layout, or when classifying legacy artifacts. Migration is a one-time operation that must never silently delete user content.

## Action vocabulary

Each legacy artifact is classified into exactly one of the following actions:

| Action | Meaning | Destructive? |
| --- | --- | --- |
| `migrate` | Move the artifact to its v3 path; the source path is removed only after the move is verified. | Yes (removes the source path). |
| `copy` | Copy the artifact to its v3 path; the source path is left in place and marked deprecated in the migration manifest. | No (keeps the source path). |
| `deprecate` | Mark the artifact as deprecated at its existing path; do not move or copy. Add a "Deprecated by v3" header pointing to the v3 path. | No. |
| `supersede` | Replace the artifact at its existing path with a v3 pointer file that references the new location. The original content lives at the v3 path. | No (the pointer is content-preserving). |

`migrate` is the only destructive action. The other three are content-preserving. Destructive actions require explicit confirmation per the rules below.

## Legacy-to-v3 map

| Legacy path | v3 path | Default action | Confirmation? |
| --- | --- | --- | --- |
| `.agents/skills/<name>/SKILL.md` (role) | `.ai/system-prompts/<role>.md` | `copy` (default) or `migrate` (when `--destructive` is set) | Only for `migrate`. |
| `.agents/skills/<name>/REFERENCE.md` (role) | `docs/learning/concept-maps/<name>.md` or `docs/architecture/<...>.md` (depending on content) | `copy` (default) or `migrate` (when `--destructive` is set) | Only for `migrate`. |
| `.agents/skills/<name>/` (whole directory) | (none — directory contents are split per file) | `supersede` (replace with pointer file at the directory level) | No. |
| `.rules.ts` | `.ai/rules/technical-bounds.md` (Markdown summary) and `docs/architecture/adr/0001-init.md` (decision record) | `copy` (default) or `migrate` (when `--destructive` is set) | Only for `migrate`. |
| `docs/adr/<file>.md` | `docs/architecture/adr/<file>.md` | `copy` (default) or `migrate` (when `--destructive` is set) | Only for `migrate`. |
| AI SDLC marker block in `AGENTS.md` / `CLAUDE.md` / `README.md` | `AGENTS.md` / `CLAUDE.md` / `CONTRIBUTING.md` / `README.md` (entry files) | `supersede` (rewrite the block in v3 form; preserve human prose) | No. |
| `upstream.lock` | `upstream.lock` (top-level, unchanged) | `deprecate` (add a comment-only header if needed) | No. |
| `prek.toml` | `prek.toml` (top-level, unchanged) | `deprecate` (add a comment-only header if needed) | No. |
| `.github/workflows/ci-prek.yml` | `.github/workflows/ci-prek.yml` (unchanged) | `deprecate` (add a comment-only header if needed) | No. |
| `scripts/archgate.sh`, `scripts/validate-rules.sh`, `scripts/sync-upstream.sh` | (unchanged) | `deprecate` (add a comment-only header if needed) | No. |
| `.memory/` (any pre-existing content) | `.memory/human-override/` or `.memory/self-learned/` based on classification | `migrate` per file, with `present-not-overwritten` audit when the v3 path already exists | Only for `migrate`. |
| Legacy marker block `<!-- ai-sdlc-init:start --> ... <!-- ai-sdlc-init:end -->` | (rewrite in v3 form, preserving human prose) | `supersede` | No. |
| `setup-skills`, `publish-semver` (and other reference-only) legacy references | (unchanged; reference-only) | `deprecate` (add a comment-only header if needed) | No. |
| `graphify-out` and other deprecated references | (removed by owner-driven PR) | `supersede` (add a `Deprecated by v3` header) | No. |

## Destructive confirmation rule

A `migrate` action is destructive. The migration path requires an explicit confirmation that:

1. Names the legacy path being migrated.
2. Names the v3 destination path.
3. Asserts that a backup has been written under `.ai/drift/backups/<timestamp>/` for the legacy path.
4. Captures a confirmation token tied to the run.

A confirmation token is valid only for the run that produced it. Retrying the same migration plan after a failure requires a fresh confirmation.

## Migration manifest

The migration path writes a manifest to `.ai/drift/migration-manifest.json` with this shape:

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-06-07T00:00:00Z",
  "actor": "ai-sdlc-init",
  "umbrella_root": ".",
  "actions": [
    {
      "source_path": ".agents/skills/karpathy-guidelines/SKILL.md",
      "destination_path": ".ai/system-prompts/architect.md",
      "action": "copy",
      "destructive": false,
      "confirmation_token": null,
      "status": "completed"
    },
    {
      "source_path": ".rules.ts",
      "destination_path": ".ai/rules/technical-bounds.md",
      "action": "migrate",
      "destructive": true,
      "confirmation_token": "ct-2026-06-07-001",
      "status": "completed",
      "backup_path": ".ai/drift/backups/2026-06-07T00-00-00Z/.rules.ts"
    }
  ],
  "summary": {
    "copy": 5,
    "migrate": 1,
    "deprecate": 3,
    "supersede": 2,
    "skipped": 0,
    "failed": 0
  }
}
```

`status` is one of `pending`, `in_progress`, `completed`, `failed`, or `skipped`. A `failed` action is rolled back from the backup when one exists; the manifest records the rollback outcome under `rollback`.

## Audit trail

Every migration run appends one JSON object per line to `.ai/drift/migration-audit.jsonl`. The shape mirrors the host-policy audit format in `modules/host-policy-automation.md`, with fields `ts`, `actor`, `mode` (`apply` or `dry-run`), `confirmation_token`, `manifest_sha256`, and a per-action results list.

## Idempotency

Re-running the migration against a target that already has v3 paths is a no-op. The validator emits a `present-not-overwritten` audit entry for any v3 path that already exists and skips the write. The migration manifest is regenerated with `status: skipped` for the affected actions.

## Rollback

A full migration run can be rolled back from `.ai/drift/migration-manifest.json` plus `.ai/drift/backups/<timestamp>/` when the destructive actions are limited to `migrate`. `deprecate` and `supersede` are content-preserving and do not need rollback. `copy` does not remove the source path, so rollback is also unnecessary.

## Safety rules

- The migration path never deletes a file that is not classified `migrate`.
- The migration path never deletes a file outside the action vocabulary above. There is no `--unsafe-destinations` flag; the migration manifest is the only allowed bypass, and a `migrate` action on a path outside the legacy map requires both the action to be added to the manifest under `exceptions` and a fresh confirmation token.
- The migration path never writes into `.memory/human-override/` if the file already exists. The path is `present-not-overwritten` and the migration skips the write.
- The migration path is always confirmation-gated for `migrate` actions. There is no `auto-apply` mode.
