# Topology Module

Read when the target repo is a standalone repository or an umbrella repository that needs canonical topology, max-depth, and sync metadata. The matrix is generated under `.ai/matrix.json` and is the single source of truth for repo layout, sync strategy, and inherited assets.

## Topology types

| Type | When to use | Required fields in `.ai/matrix.json` |
| --- | --- | --- |
| `standalone` | A single repository with one top-level tree, no nested managed repos. | `topology_type`, `max_allowed_depth: 0`, `current_depth: 0`, `sync_strategy: physical-copy`, `upstream_authority`, `inherited_assets`, `sync_status`. |
| `umbrella` | A repository that owns managed sub-repositories and propagates inherited assets to them. | All standalone fields plus `managed_repositories`, `max_allowed_depth: 3`, and a per-repo `depth` value. |

`max_allowed_depth` is fixed at `3` for `umbrella` topologies. `current_depth` is the maximum path depth observed across managed repositories. When `current_depth > max_allowed_depth`, validation must fail or block the apply path; the error must identify the offending repo path and the offending depth.

## `.ai/matrix.json` dual-reader contract

Readers must accept both v1.0 and v1.1 during the rollout. Writers preserve
v1.0 until the distribution layer advertises v1.1 support; they never silently
upgrade an existing matrix. A v1.0 entry remains `path`, `depth`, and
`inherits_assets_from`. A v1.1 entry adds stable binding fields while keeping
the same membership semantics:

```json
{
  "repo_id": "auth-service",
  "path": "services/auth",
  "depth": 2,
  "inherits_assets_from": ".",
  "canonical_origin": "https://github.com/example/auth-service.git",
  "canonical_upstream": null,
  "default_ref": "main",
  "disposable": true,
  "moon_project_id": "auth-service",
  "dependencies": [],
  "profile_refs": {
    "checkout": {"type": "checkout", "id": "full-history", "version": "1.0"},
    "execution": {"type": "execution", "id": "production-default", "version": "1.0"},
    "toolchain": {"type": "toolchain", "id": "managed", "version": "1.0"},
    "cas": {"type": "cas", "id": "pull-only", "version": "1.0"}
  }
}
```

- `repo_id` is a stable lowercase identifier, unique independently of `path`.
- Canonical remotes, the default ref, and disposable-checkout policy make checkout intent explicit.
- `moon_project_id` is stable and unique; dependencies reference other `repo_id` values and must form an acyclic graph.
- Each typed, versioned profile reference resolves below
  `.ai/execution/profiles/<type>/<id>.json`; policy bodies do not live in the matrix.
- Paths, IDs, and references are unique, relative, traversal-free, and fail closed on unknown fields or versions.

The executable reference reader is `scripts/matrix-contract.py validate`. It
rejects unknown versions rather than guessing. This repository remains v1.0
until the downstream ai-catapult distribution supports the dual reader.

### v1.0 compatibility example

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

- `schema_version` (string) — `"1.0"` or additive `"1.1"`; readers support
  both, while writers preserve the input version unless migration is explicit.
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

## Execution profile contract

Checkout, execution, toolchain, and CAS profiles share a versioned envelope:
`schema_version`, `profile_type`, `profile_id`, `version`, and `settings`.
Execution settings select `self-hosted` or `hosted`, supported hosts (GitHub,
ADO, and GitLab), and hosted fallback. Lore is reserved for future support and
is not selectable. Profile type, ID, and version must match the binding and
filename. Credentials and repository membership are forbidden in profiles.

Override precedence is terminal human policy (where allowed), child-local
schema-declared override, root-bound profile, then ai-catapult default. The
only child-local keys are `runner_preference`, `host_selection`, and
`toolchain_tier`. Membership, canonical remote, repository identity, and protected
fallback eligibility cannot be overridden.

## Child-safe parent projection

`scripts/matrix-contract.py project` emits one binding document per child. A
projection contains only that child's `repo_id`, parent-relative path, profile
references, profile versions, the inheritance digest, and permitted local overrides. It never contains
another child identity, upstream authority, credentials, or profile policy
bodies. Generation rejects a forbidden override before writing anything.

## Transactional generation

Projection generation is set-transactional:

1. Acquire an exclusive sibling lock.
2. Validate the matrix, every profile reference, and existing local overrides.
3. Render and validate the complete set in a sibling temporary directory.
4. Promote by directory rename, retaining the previous set as a rollback copy.
5. Restore the previous set if promotion fails; remove temporary state and the
   lock on every terminal path.

`--check` performs a byte-for-byte readback without mutation. Failure injection
and recovery tests prove a mid-render failure leaves the prior set unchanged.

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
