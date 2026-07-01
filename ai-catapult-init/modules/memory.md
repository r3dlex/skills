# Memory Layer Module

Read when defining the `.memory/human-override/` and `.memory/self-learned/` schemas for a target repo. The memory layer is local machine-readable knowledge scoped to the repo. Human override is terminal priority and must never be silently rewritten.

## Two layers

| Layer | Path | Authority | Sync | Edit policy |
| --- | --- | --- | --- | --- |
| Human override | `.memory/human-override/` | Humans, terminal priority | Never propagated | Append-only by default; never silently rewritten |
| Self-learned | `.memory/self-learned/` | Agents, local | Per-repo only, never propagated | Append-only with `schema_version`; changelog required |

Both layers are local to the repo. Neither is pushed upstream and neither is inherited by managed sub-repos.

## `.memory/human-override/`

Holds human-authored content that the AI SDLC must respect. The directory is terminal priority: the scaffold never overwrites an existing file in this directory and never deletes a file without explicit confirmation.

Default files:

- `custom-conventions.md` — repo-specific naming, formatting, or commit conventions that override generic defaults.
- `tribal-knowledge.md` — undocumented but load-bearing facts about the repo, the team, or the build environment.

### Schema rules

- Plain Markdown; frontmatter is optional and only used for `id`, `last_reviewed`, and `owner` fields when present.
- Files are immutable from the agent's perspective unless the user explicitly asks to edit them.
- The validator must verify that any generated scaffold that would touch this directory emits a `present-not-overwritten` audit entry and skips the write.

## `.memory/self-learned/`

Holds machine-readable knowledge produced by the scaffold, the validator, or runtime agents. The directory is per-repo only and never propagated.

Default files:

- `error-patterns.json` — recurring error patterns and their fix hints.
- `module-complexity.json` — module-level complexity and coverage data.
- `CHANGELOG.md` — chronological list of schema or file changes.

### `error-patterns.json` schema (v1.0)

```json
{
  "schema_version": "1.0",
  "entries": [
    {
      "id": "ep-2026-001",
      "pattern": "ModuleNotFoundError: No module named 'foo'",
      "context": "Python module resolution failure after a refactor",
      "detection": "ImportError raised in CI step 'unit-tests'",
      "fix_hint": "Add 'foo' to pyproject.toml dependencies or pin via uv.lock",
      "first_seen_at": "2026-05-12T00:00:00Z",
      "last_seen_at": "2026-06-01T00:00:00Z",
      "occurrences": 3,
      "owner": "platform"
    }
  ]
}
```

### `module-complexity.json` schema (v1.0)

```json
{
  "schema_version": "1.0",
  "entries": [
    {
      "path": "src/foo.py",
      "language": "python",
      "lines_of_code": 412,
      "cyclomatic_complexity": 18,
      "test_coverage": 0.62,
      "owner": "team-foo",
      "last_measured_at": "2026-06-01T00:00:00Z"
    }
  ]
}
```

### Schema rules

- Every self-learned file must declare `schema_version`. Bumping the version requires an entry in `CHANGELOG.md` and a migration note.
- `CHANGELOG.md` is the canonical change log; do not scatter date markers across individual files.
- Self-learned files are append-only. New entries are added; existing entries are not edited in place. If a fact becomes wrong, add a new entry with `superseded_by` pointing to the corrective entry.
- The validator must check that any new self-learned file declares `schema_version` and that the version is supported by the scaffold.

## Privacy and external integration

- The memory layer is local-only. The scaffold never uploads `.memory/` to a remote system.
- Any external integration (telemetry, dashboards) requires explicit confirmation and an opt-in flag in `.ai/matrix.json` under `memory.external_integration`.
- `.memory/human-override/` content is never included in external uploads even when integration is enabled.
- Credentials, secrets, and tokens are never stored in `.memory/`. The validator must reject writes that match credential patterns.

## Migration

When a target repo already has a `.memory/` directory under a different layout, the migration path is:

1. Classify each existing file as `human-override` or `self-learned` based on the migration rules in `modules/migration.md`.
2. Move or copy the file to the v3 path with a backup under `.ai/drift/backups/<timestamp>/`.
3. Emit a `present-not-overwritten` audit entry for any file that already exists in the v3 path.
4. Append a `CHANGELOG.md` entry describing the migration.

Destructive moves (delete-then-copy) require explicit confirmation. Copy-with-keep is the default.
