# Northstar handoff writer repair plan (2026-09-09)

## Scope

Repair only the authoritative Northstar handoff writer, its direct contract
documentation, and its direct pipeline/prerequisite tests. Installed, vendored,
generated, target-project, runtime, deployment, and merge state stay untouched.

## Behavior lock and regression plan

1. Add regression coverage before implementation for required `--goals`, prompt
   missing-value failures, safe slug/path containment, real spec/goals files,
   unique exact-spec PRD selection, and graph-root/PRD identity agreement.
2. Cover fail-closed ambiguity, conflicting identity, invalid goals, traversal,
   and escaping symlinks, proving every preflight failure is mutation-free.
3. Cover atomic/idempotent success and lost-handoff recovery while preserving
   unrelated manifest/graph data and existing status values.
4. Cover the bounded legacy migration from generated
   `plan:root:northstar-*` / `handoff:root:northstar-*` IDs to the verified repo
   identity, rewriting only references to those IDs, retaining custom fields and
   blocked statuses, and refusing a legacy/current duplicate conflict.
5. Run the new test red against the old implementation. Then make the smallest
   writer/docs/caller changes needed, run targeted tests green, and run the
   repository's applicable validation checks.
6. Treat spec and goals as immutable input evidence: reject direct paths and
   symlink, case-insensitive, or hardlink filesystem aliases of the manifest,
   graph, or handoff before parsing JSON or performing any mutation.

## Chosen migration versus alternatives

The repair renames the two exact legacy IDs in place and rewrites graph
backlinks/edge endpoints that reference them. This avoids duplicate generated
nodes and preserves status, custom fields, and graph relationships. It does not
merge a legacy node with an already-present corrected node: that case is
ambiguous and fails before mutation. Deleting legacy nodes would lose audit
state; retaining both would create competing generated records, so both
alternatives are rejected.

## Stop conditions

- No successful write unless spec, goals, manifest, graph, matching PRD, and
  repository identity are unambiguous and contained in the selected root.
- No status is promoted and no host/execution/merge authority is created.
- No input file can alias an atomic output target.
- A failed preflight leaves manifest, graph, handoff, and directories unchanged.
