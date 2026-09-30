# Readiness: shared v1 contract

Northstar and direct intake call the same pinned, read-only validator. Planning
completion is distinct from preparation, implementation and merge readiness.

## Exact inputs

```sh
bash autobahn/prereq-check.sh --root /repo --handoff northstar-plan-example \
  --goal-id G1 --context /independent/context.json
bash autobahn/readiness-check.sh --root /repo --goal /input/direct.json \
  --context /independent/context.json
```

Repeat `--goal-id` for an explicit set. A selector is the exact registered ID or
registered generation handoff path. Never pick the first matching plan. Empty,
duplicate, blocked, superseded, unknown or mixed-generation selections fail.
Direct intake requires `{"schema":"direct-goal/1","bundle":{...}}` containing
one goal, not a legacy flat `implementation_ready` assertion.
`--stage planning` checks durable structure without execution admission.

The bundled `lib/readiness_contract.py` is the versioned producer/consumer
implementation. `schemas/readiness-contract.json` describes the vocabulary;
semantic checks live in that single helper, with no JSON Schema dependency.

## Supported minimum policy

Policy is loaded **only** from `.ai/policies/readiness-policy.json`. A
`readiness-policy/1` record binds repository ID/absolute canonical root, exact
source path/SHA-256 pairs, typed gates, and explicit not-applicable reasons.
An independent `readiness-context/1` must match its digest and approved revision,
source set, selected goals, stage and exact subject digest. Caller context is an
input from the execution authority, **not an authenticated authority token**.
A goal may add requirements; it cannot select policy or supply exemptions.

Every policy accounts for owners, reviewer, branch target, fixtures, tooling,
registration approval and harness trust using a gate `dimension` or an explicit
`not_applicable` reason. Unsupported policy schemas/scope/predicates fail closed.
Only these minimum gate kinds are supported:

- `file_digest`: observe an exact root-contained, non-symlink file and digest.
- `executable_presence`: observe a root-contained executable file without running it.
- `measured_coverage`: actual numeric measured coverage, never waived by a goal.
- `independent_result`: exact gate/stage/scope/subject result supplied by the
  independently checked authority adapter. Strings such as `pass` are not proof
  of runtime authenticity by themselves.

A gate applies to its explicit stage and repository or explicit goal scope.
Missing dependency completion blocks the dependent goal. The shared existing
verification allowlist validates the **whole list**, cwd, scripts and tools but
executes nothing. No fixture command is run by readiness validation.

Unknown coverage remains explicit: `coverage_status: unknown`, null/absent
`coverage_percent`, `legacy_safe_tdd: true`, and `legacy_risk_reason` are required.
This selects a safe TDD technique, not a measured-coverage policy waiver.

## Authority boundary

`execution_ready: true` means the supplied contract is internally consistent,
**not dispatch permission**. Every report emits `dispatch_authorized: false` and
`authority_verification: external-required`. Before dispatch, the orchestrating
agent MUST independently verify the live policy approval and operation authority
for the exact repository, subject, goal set and stage using the host's supported
boundary. Missing live authority blocks dispatch; do not promote fixture contexts,
JSON issuer labels or stale context into authority. No new trust/signing platform
is introduced. Tests use explicitly simulated policy/runtime issuers only.

Advanced trusted-harness provenance, approval reuse/invalidation, external SQL
fixture attestation and targeted recovery adapters belong to RT-02; unsupported
ones return unknown/blocked, never assumed ready. RT-03 delivers this matched
release; old installed copies are not fixed by editing source.

## Migration

Legacy direct records and registrations return `migration_required`. Supply a
reviewed v1 bundle with explicit repo/spec/goal identities, then run:

```sh
bash autobahn/migrate-handoff.sh --root /repo --legacy /input/legacy.json \
  --bundle /input/reviewed-v1.json
```

The stdout candidate retains the entire legacy object and digest in extensions,
sets all goal readiness stages to unknown, and writes nothing. Review retained
rich evidence, then explicitly publish the candidate; revalidate policy and
live authority separately. No silent conversion or fallback discovery exists.

Legacy `root_causes`, evidence, solutions and richer annotations are retained in the migration original; they never substitute for current policy evidence. Content-bound freshness is rechecked by current file digests and exact subject bindings. Time-based freshness predicates and unrecognized gate fields are unsupported and blocked, not ignored. Governing root `AGENTS.md`, `.rules.ts` and `.ai/rules/` files must be covered in addition to the independently identified source set.
