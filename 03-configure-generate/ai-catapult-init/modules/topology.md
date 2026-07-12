# Topology Module

Read when the target repo is a standalone repository or an umbrella repository that needs canonical topology, max-depth, and sync metadata. The matrix is generated under `.ai/matrix.json` and is the single source of truth for repo layout, sync strategy, and inherited assets.

## Topology types

| Type | When to use | Required fields in `.ai/matrix.json` |
| --- | --- | --- |
| `standalone` | A single repository with one top-level tree, no nested managed repos. | `topology_type`, `max_allowed_depth: 0`, `current_depth: 0`, `sync_strategy: physical-copy`, `upstream_authority`, `inherited_assets`, `sync_status`. |
| `umbrella` | A repository that owns managed sub-repositories and propagates inherited assets to them. | All standalone fields plus `managed_repositories`, `max_allowed_depth: 3`, and a per-repo `depth` value. |

`max_allowed_depth` is fixed at `3` for `umbrella` topologies. `current_depth` is the maximum path depth observed across managed repositories. When `current_depth > max_allowed_depth`, validation must fail or block the apply path; the error must identify the offending repo path and the offending depth.

## `.ai/matrix.json` schema (v1.0)

```json
{
  "schema_version": "1.0",
  "topology_type": "umbrella",
  "max_allowed_depth": 3,
  "current_depth": 2,
  "sync_strategy": "physical-copy",
  "upstream_authority": {
    "type": "git",
    "url": "https://github.com/example/upstream.git",
    "ref": "main"
  },
  "managed_repositories": [
    {
      "path": "services/auth",
      "depth": 2,
      "inherits_assets_from": "."
    }
  ],
  "inherited_assets": [
    {
      "path": "AGENTS.md",
      "source": ".",
      "mode": "physical-copy"
    },
    {
      "path": ".ai/matrix.json",
      "source": ".",
      "mode": "physical-copy"
    }
  ],
  "sync_status": {
    "last_synced_at": "2026-06-07T00:00:00Z",
    "drift_detected": false,
    "last_drift_report": ".ai/drift/last-drift.json"
  }
}
```

### Required fields and types

- `schema_version` (string) — fixed at `"1.0"` until v2 is introduced.
- `topology_type` (string enum) — `standalone` or `umbrella`.
- `max_allowed_depth` (integer) — `0` for standalone, `3` for umbrella. Other values are rejected.
- `current_depth` (integer) — `0` for standalone, computed for umbrella.
- `sync_strategy` (string enum) — `physical-copy` only. `symlink` and `git-submodule` are explicitly rejected as canonical.
- `upstream_authority` (object) — non-null when sync reads from an upstream source. `type` is `git` or `local`. `url` and `ref` describe the source.
- `managed_repositories` (array) — required when `topology_type` is `umbrella`. Each entry has `path`, `depth`, and `inherits_assets_from`.
- `inherited_assets` (array) — list of file or directory paths propagated to managed repos. Each entry has `path`, `source`, and `mode: physical-copy`.
- `sync_status` (object) — `last_synced_at`, `drift_detected`, and an optional `last_drift_report` path.

### Optional fields

- `migration` (object) — references the legacy-to-v3 migration manifest; see `modules/migration.md` for the migration manifest format.
- `exclusions` (array of strings) — managed repos or paths that opt out of inheritance. Exclusions must be explicit and listed in the matrix, not inferred from `.gitignore`.

## Umbrella depth rule

`max_allowed_depth: 3` is a hard limit. The validator must:

1. Walk the tree rooted at the umbrella repo and compute the maximum path depth of any managed repo relative to the umbrella root.
2. Treat any path whose depth exceeds 3 as a violation.
3. Emit a blocking error that names the offending repo path and its depth.
4. Refuse to start the sync or apply path while the violation persists.

Depth is the number of path segments from the umbrella root to the managed repo, not the Git history depth.

## Sync-strategy rule

`sync_strategy: physical-copy` is the canonical strategy. Concretely:

- Inherited assets are propagated as ordinary file copies at sync time.
- The sync path writes a backup under `.ai/drift/backups/<timestamp>/` before overwriting any inherited asset.
- The sync path emits a drift report that lists per-asset `unchanged`, `updated`, or `added` status.
- Symlinks and git submodules are not the canonical strategy and must not appear as `mode` values.

See `modules/sync.md` for the full sync lifecycle, drift detection, and audit log format.

## Standalone-only files

A standalone repo does not need `managed_repositories`. A standalone repo must still set `max_allowed_depth: 0`, `current_depth: 0`, and `sync_strategy: physical-copy` so the schema is uniform.

## Safety rules

- Matrix generation never deletes files outside the inherited-assets list.
- Destructive migration of legacy matrix fields requires explicit confirmation; see `modules/migration.md` for the migration audit manifest format.
- `.memory/human-override/` is terminal priority and is never listed in `inherited_assets` because it is per-repo, not propagated.
