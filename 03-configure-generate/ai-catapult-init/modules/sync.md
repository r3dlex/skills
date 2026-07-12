# Sync Module

Read when propagating inherited assets from an umbrella repo to its managed sub-repos, when generating drift reports, or when backing up the v3 scaffold. Physical-copy is the canonical sync strategy. Symlinks and git submodules are explicitly rejected as canonical.

## Sync strategy

`sync_strategy: physical-copy` is the only canonical value in `.ai/matrix.json`. The sync lifecycle is:

1. **Resolve** — read `.ai/matrix.json` and compute the set of inherited assets and the set of managed repos.
2. **Backup** — write a snapshot of every destination file that will be overwritten under `.ai/drift/backups/<timestamp>/`. Skip files that are unchanged.
3. **Copy** — overwrite the destination with the source file. Use ordinary file copies, not symlinks and not git submodule references.
4. **Verify** — compute a SHA-256 of source and destination and assert equality. On mismatch, mark the asset as `failed` in the drift report and roll back from the backup.
5. **Audit** — append a sync record to `.ai/drift/last-sync.json` with timestamp, per-asset status, and SHA-256 values.
6. **Drift report** — write `.ai/drift/last-drift.json` listing per-asset `unchanged`, `updated`, `added`, or `failed` status.

## What sync is allowed to write

Sync is allowed to write only paths that appear in `.ai/matrix.json#inherited_assets`. Any other write is rejected. In particular:

- `.memory/human-override/` is never in the inherited-assets list and never written by sync.
- `.memory/self-learned/` is per-repo only and never written by sync.
- The umbrella root's own `AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, and `README.md` are not written by sync unless they are explicitly listed in `inherited_assets`.

## Depth rule

Sync is allowed to run only when `current_depth <= max_allowed_depth`. For `umbrella` topologies, `max_allowed_depth` is fixed at `3`. The validator must:

1. Walk the tree rooted at the umbrella repo and compute the maximum path depth of any managed repo.
2. Treat any path whose depth exceeds 3 as a violation.
3. Refuse to run the sync when the violation persists.

## Drift detection

Drift is detected by comparing the SHA-256 of each source asset against the SHA-256 of the destination asset. Drift is reported per asset:

| Status | Meaning |
| --- | --- |
| `unchanged` | Source and destination SHA-256 match. |
| `updated` | Source and destination SHA-256 differ; destination was overwritten and a backup was written. |
| `added` | Destination did not exist; new file written. |
| `failed` | Sync attempted but SHA-256 mismatch persisted, or write was rejected by safety policy. The destination was rolled back from the backup. |
| `skipped` | Asset was intentionally skipped (e.g., excluded by `.ai/matrix.json#exclusions` or by `.memory/human-override/` membership). |

The drift report is written to `.ai/drift/last-drift.json` and has this shape:

```json
{
  "schema_version": "1.0",
  "generated_at": "2026-06-07T00:00:00Z",
  "umbrella_root": ".",
  "managed_repos": 3,
  "assets": [
    {
      "path": "AGENTS.md",
      "source": ".",
      "mode": "physical-copy",
      "status": "unchanged",
      "source_sha256": "...",
      "destination_sha256": "..."
    }
  ],
  "summary": {
    "unchanged": 12,
    "updated": 1,
    "added": 0,
    "failed": 0,
    "skipped": 2
  }
}
```

## Audit log

Every sync run appends an entry to `.ai/drift/sync-audit.jsonl` with one JSON object per line. Each entry has:

- `ts` — ISO-8601 timestamp.
- `umbrella_root` — repo path.
- `actor` — `ai-sdlc-init` or specific agent role.
- `mode` — `apply` or `dry-run`.
- `assets_changed` — count of `updated` and `added` assets.
- `assets_failed` — count of `failed` assets.
- `confirmation_token` — only present when `mode: apply`; references the explicit user confirmation that authorized the run.

Dry-run is the default. The first `apply` for a given run requires a fresh confirmation token. A confirmation token is valid only for the run that produced it; subsequent retries of the same plan require a fresh confirmation. See `modules/host-policy-automation.md` for the canonical confirmation-token rule.

## Local overrides

A managed sub-repo may declare a local override file at `.ai/local-overrides.json`. The file lists paths that the sub-repo does not want to inherit from the umbrella. Each entry has:

- `path` — the inherited-asset path being overridden.
- `reason` — short human-readable reason.
- `expires_at` — optional ISO-8601 timestamp after which the override should be re-evaluated.

Overrides are honored by sync; the asset status becomes `skipped` with reason `local-override`. Override expiry is enforced during drift review: an expired override is reported in the drift report under `expiring_overrides`.

## Safety rules

- Sync never deletes files outside the inherited-assets list.
- Destructive operations (deleting a destination, removing a backup) require explicit confirmation and emit an audit entry.
- Backups older than the retention window are pruned only with explicit confirmation. Default retention is 30 days; the value lives in `.ai/matrix.json#sync_status.retention_days` when present.
- Sync does not call hosted APIs to apply branch or policy changes. Hosted mutations are scoped to `modules/host-policy-automation.md`.

## Failure modes

| Failure | Behavior |
| --- | --- |
| `current_depth > max_allowed_depth` | Sync refuses to start. Error names the offending repo path and depth. |
| Destination write fails | Sync rolls back from the backup, marks the asset `failed`, and continues with the next asset. |
| Source file missing | Sync marks the asset `failed` and emits a `source-missing` audit entry. |
| Backups directory unwritable | Sync refuses to start. |
| `.ai/matrix.json` invalid | Sync refuses to start. The validator reports the schema violation. |
