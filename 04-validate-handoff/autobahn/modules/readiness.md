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

The finite typed adapters below support scoped approval/trust/recovery evidence;
unsupported kinds remain unknown/blocked. RT-03 delivers the matched release;
old installed copies are not fixed by editing source.

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

Legacy `root_causes`, evidence, solutions and richer annotations are retained in the migration original; they never substitute for current policy evidence. Content-bound freshness is rechecked by current file digests and exact subject bindings. Typed receipts require current observation/expiry timestamps; arbitrary time predicates and unrecognized gate fields are unsupported and blocked. Governing root `AGENTS.md`, `.rules.ts` and `.ai/rules/` files must be covered in addition to the independently identified source set.

## Scoped typed evidence (RT-02)

Planning admission (`--stage planning`) validates structural identity once and
reports `per_goal[goal_id][stage]` and consolidated `gaps` for all three stages.
Missing context/policy produces repository-wide unknown findings, not a planning
failure or execution admission. Invalid identity, graph or bundle remains fatal.
A valid completed plan exits zero even with readiness gaps; always inspect the
explicit stage verdict before execution. Every gap includes source, freshness,
evidence references, responsible party (default `unassigned`) and recovery.

The finite typed gates add a `binding` object to the existing gate. No expression
language or fixture execution is supported. Exact binding fields:

| Kind | Binding |
| --- | --- |
| `ownership` | `roles`: nonempty unique subset of `owner`, `reviewer` |
| `branch_target` | nonempty exact `target`, `branch` keys |
| `fixture` | digest-bound `file`, allowlisted `command`, `tool`, `isolation` |
| `tooling` | executable name `tool`, resolved without running it |
| `protected_approval` | `subject`: `{mode: full-file, file: {path, sha256}}` or `{mode: goal-scope, goal, goal_sha256}` |
| `harness_trust` | separate `lock`, `anchor` file references, each `{path, sha256}` |

Fixture files must be executable; isolation is one of `disposable-database`,
`transaction-rollback`, `temporary-directory`, `container`. A fixture receipt is
an externally verified observation of executability/isolation, never a claim
that preflight itself ran it. The command uses the existing allowlist.

Typed context `results` have exactly `gate`, `status`, `stage`, `scope`,
`subject_sha256`, `issuer`, `evidence` (nonempty reference list), `observed_at`,
`expires_at` (timezone-aware ISO timestamps), and `value`. Status must be `pass`.
Ownership values map each required role to a real name, not a placeholder;
other values exactly echo the observed binding. Evidence labels and JSON names
are data; the host must independently establish provenance before using context.

`goal_revision(bundle, id)` hashes repository, plan ID, specification and the
exact goal plus transitive dependency revisions (iteratively, including deep DAGs). `gate_subject(bundle, gate, policy_sources, policy_ref)` hashes repository, plan,
exact gate, exact policy reference/digest, approved policy source digests and only governed goal revisions.
Use these shared functions when constructing independent adapter receipts;
neither function signs or authorizes anything. An unrelated goal edit preserves
a narrow receipt. Changed governed content, approval subject, source digest or
gate invalidates it. Full-file approval always binds the whole referenced file.
Expired/future evidence fails closed. Do not request still-valid approvals again.

`completed_goals` contains exact revision-bound receipts, never bare IDs: fields
`goal`, `goal_sha256`, `status: complete`, `issuer`, `evidence`, `observed_at`,
`expires_at`. Current prerequisite gate failures override cached completion.
Shared gates affect governed goals and their dependents; unrelated ready goals
remain independently eligible. Preparation needs its own stage authority and
cannot waive shared trust or admit dependent implementation prematurely.

Trust files are JSON with a full lowercase 40-character `commit`; the anchor
object has exactly this field. Extra-key/enriched plan objects, specification
copies and same-file/hardlink aliases cannot serve as independent anchors. The independent
anchor must occur in the externally approved policy source set, cannot be the
lock itself, and must retain its digest. Diagnostics distinguish unavailable
sources from expected/actual mismatch and identify the anchor. Credential-bearing
URLs are redacted from failure details. Recovery obtains independent provenance;
it never rewrites the trusted commit to match the lock.

Do not infer missing root causes or solutions during Autobahn execution.
Incomplete or contradictory diagnostic evidence requires northstar or
`diagnosing-bugs`; never mark such a record implementation-ready.
Direct intake remains one bounded goal and one PR, not an implicit multi-goal plan.
