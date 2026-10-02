# Durable handoff publication

Northstar publishes a reviewed `handoff-goals/1` bundle, not a vague goal pointer.
The bundle carries exact repository identity/root, spec path/digest, issue
reference, planning status, and per-goal IDs, scope, acceptance, dependencies,
verification and three readiness stages. Planning complete is not executable.

```sh
bash northstar/handoff-write.sh --root /repo --bundle /input/reviewed-v1.json
```

The source spec must already have one unambiguous node in the traceability graph.
Publication uses the exact pinned Autobahn helper in canonical source layout or
sibling-flat install; missing/mismatched producer/consumer dependencies stop.

## Same-repository worktree publication

To preserve canonical repository identity while publishing only in a verified
linked worktree, pair `--worktree-root /worktrees/plan` and
`--base-commit <40-hex-base>` with `--root /repo` on `handoff-write.sh`.
The helper validates the Git relationship; specification, graph, immutable
payloads, lock and registry are read/written in the linked worktree, not the
primary checkout. Registry-last publication and enrichment preservation still
apply. This opt-in does not transform a bundle into cross-repository mapping,
approve its policy, grant protected-path write authority or admit implementation.
See [worktree execution](../../../04-validate-handoff/autobahn/modules/worktree-execution.md)
for subsequent independent admission and stage-context requirements.

## Publication boundary and recovery

All cooperating writers acquire `.ai/workflows/.northstar-readiness-v1.lock` by
atomic directory creation; contention returns immediately with bounded diagnostics.
The writer baselines the candidate, rereads shared state under the lock and
preserves richer/unknown fields. Immutable payloads live under
`.ai/handoff/readiness-v1/<plan-id>/<generation>/` as `goals.json`, `handoff.md`
and exact generation graph metadata. Then it adds generation-addressed nodes and
reciprocal backlinks to the live `schema_version: 1.1` traceability graph, and
atomically replaces `.ai/workflows/northstar-readiness-v1.json` **last**.
This separate registry's `plans[]` is the sole completion pointer. Legacy
`optional_branches` are never written or used as a fallback.

Inputs are rechecked before shared graph and registry replacement. A crash after
graph publication leaves unreferenced nodes/payloads, never a completed plan.
Readers can use the previous explicitly registered immutable generation if its
policy/evidence remains independently current. Old generations and backlinks are
retained for audit; they do not bypass current-plan checks.

Ordinary errors clean staging and release the lock. A process crash may leave a
lock requiring independently verified targeted recovery. After proving no writer
remains, inspect/reconcile the stale lock and rerun the exact reviewed candidate.
Never steal locks or roll back captured whole graph/registry files. Retry reuses
identical payload bytes and composes narrow additive updates into fresh shared
state. Candidate/enrichment conflicts abort instead of overwriting user edits.
A digest recheck catches ordinary source changes, not arbitrary-editor races.
File/registry writes use same-filesystem atomic replace; no multi-file transaction
or filesystem power-loss atomicity is claimed. No ticket, branch, install or
hosted write occurs. Existing protected-write requirements still cover every
publication path; the lock and command invocation are not approval.

Legacy records require explicit migration using
`autobahn/migrate-handoff.sh`; see [Autobahn readiness](../../../04-validate-handoff/autobahn/modules/readiness.md).
Migration keeps original evidence and resets execution readiness to unknown.
Publishing never supplies policy approval or execution authority.

## Scoped readiness recovery

After publication, run `autobahn/prereq-check.sh --root /repo --handoff <exact-id> --goal-id <id-1> --goal-id <id-2> --stage planning` with independently supplied `--context` when available. Repeat `--goal-id` for **every goal** in the published bundle, not only the first. Include all-stage `per_goal` findings and remaining blockers in the handoff response. A zero planning exit is structural planning success only. Preserve valid scoped approval receipts; unchanged full-file approvals still require their full-file digest.
