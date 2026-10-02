# ADR-0014: Versioned readiness transfer and registry-last publication

- Status: Accepted for RT-01 reusable minimum
- Date: 2026-09-30

## Context

Legacy discovery accepted some handoff rather than the requested executable work.
A flat direct `implementation_ready` assertion could avoid repository policy.
Planning completion and execution readiness were conflated. Producer helper
imports were not guaranteed in flat installed layouts.

## Decision

Use one pinned `readiness-contract/1` implementation for Northstar publication and
Autobahn/direct admission. Exact handoff and goal selectors are mandatory. Legacy
intake requires explicit evidence-preserving migration. Repository policy comes
only from the fixed `.ai/policies/readiness-policy.json`, bound to independently
provided source/revision context; goals may strengthen it but never exempt it.

The validator is non-writing and never executes verification or fixture commands.
It reuses the existing complete-list CI allowlist validator. Planning, preparation,
implementation and merge statuses remain separate. Unknown coverage selects
legacy-safe TDD and cannot waive measured-coverage policy.

Immutable generation bundle/handoff/graph payloads are published under a
cooperating-writer lock and registered atomically last. Additive generation-addressed live graph nodes publish before the separate
`.ai/workflows/northstar-readiness-v1.json` completion registry. Legacy
`optional_branches` stay untouched; prior immutable generations remain for audit. Regeneration rejects enrichment loss. Crash
recovery inspects stale locks and retries; no lock stealing or whole-file rollback.

Source/flat readers verify matching local dependency fingerprints. Missing or
mixed versions fail closed. An older installed reader is not upgraded by source
changes; delivery/version floor is RT-03, umbrella coordinated adoption RT-04.

## Authority and limits

### Explicit planning/execution bridge

The opt-in `mapped-handoff-goals/1` bundle keeps the planning repository as the
admission root. That root owns governance, specification, registry and immutable
generations. A mandatory `execution` binding identifies one distinct, disjoint
execution repository, exact canonical worktree, target, source revision,
instruction sources and validation mode. Execution does not inherit planning
governance and needs no copied `.ai/` scaffold. Nested execution repositories
are not supported by this bridge.

The fixed planning policy must authorize that exact binding. Independent context
must repeat it and provide the current full `execution_revision`. Neither a goal
nor context can select policy or weaken its requirements. Execution binding is
part of goal revisions; gate subjects also bind the current execution revision.
Mapped authority, independent-result and dependency-completion receipts must
match that revision. This is context-supplied observation, not a Git HEAD check
or proof of authenticated authority. Old readers reject the mapped schema.

The gate driver requires explicit `--execution-root`, exact intake selection and
stage context before checking mapped work. Local checks use the execution root,
never planning-root green evidence. `external-only` validation fails closed with
`external_validation_adapter_required` before local gates. It does not run local
application builds or translate unrelated hosted results into readiness. A
supported independently verified external-validation adapter remains required
for ADO-only delivery. Structural bridge tests establish no real application
readiness, fixture authority, ticket eligibility or dispatch permission.

JSON consistency is not authenticated approval. Reports always state
`dispatch_authorized: false`; the orchestrator must independently verify live
policy and operation authority before dispatch. No signing platform or generic
policy expression engine is introduced. RT-02 owns richer approval/trust/recovery
adapters; unsupported predicates remain unknown, not ready. Filesystem power-loss
atomicity and noncooperating-writer serialization are not claimed.

## Verification

`tests/readiness_contract_test.sh` covers selector, policy, schema/version,
non-writing, migration, canonical/flat dependency parity and publication failure
boundaries. Existing CI allowlist tests preserve executable semantics.
