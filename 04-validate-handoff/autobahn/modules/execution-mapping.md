# Explicit execution repository mapping

Read when the planning repository and execution worktree differ. This opt-in
bridge does not govern excluded repositories or authorize execution.

## Two roots, one fixed policy

- `--root` is the planning/admission root. It owns v3 governance, specification,
  immutable generations, graph, registration and fixed readiness policy.
- `mapped-handoff-goals/1` adds mandatory `execution`. Its `repository` contains
  a distinct ID and exact absolute canonical root. The roots must be disjoint,
  not aliases or nested. Each goal uses that execution repository and scope.
- The binding also contains exact `target`, full lowercase 40-character
  `source_revision`, execution instruction `sources` and `validation`, either
  `local` or `external-only`. The source revision is a stable baseline, not
  implementation-branch authority or a claim about current HEAD.
- `.ai/policies/readiness-policy.json` must contain exactly the same `execution`
  binding. Independently verified context repeats it and adds full current
  `execution_revision`. Goals and context cannot choose a different policy.

Planning policy `sources` remain planning-root-relative. `execution.sources`
are execution-root-relative. Both sets are digest-bound. Governing root and
applicable nested instructions must be covered; no traversal or symlink escape
is allowed. A gate's `root` is `planning` by default, or explicitly `execution`.
Its files and fixture commands resolve inside that root. Tool availability is
checked on the invoking session's PATH, not on the target host; it is not
target-host capability evidence. Goal verification commands resolve inside
execution, not planning. Single-root v1 rejects execution mapping fields and
remains unchanged.

## Receipt freshness

The mapping participates in `goal_revision`. Mapped `gate_subject` also requires
the current `execution_revision`. Mapped authority, independent-result and
dependency-completion receipts repeat that revision. Typed results keep their
existing shape but bind the mapped gate subject. Changing a worktree, repository,
target, source, instruction digest or current revision invalidates affected
receipts. Old readers reject the mapped schema rather than ignore enrichment.

The validator reads these inputs; it does not observe Git HEAD or authenticate
an issuer. Reports identify the execution revision as independent-context data
and retain `dispatch_authorized: false`. A structurally consistent fixture is
not approved policy or live operation authority.

## Driver and external-only boundary

```sh
bash autobahn/prereq-check.sh --root /planning --execution-root /execution \
  --handoff <exact-registration> --goal-id G1 --context /independent/context.json
bash autobahn/run-gates.sh --root /planning --execution-root /execution \
  --goal-record /input/goal.json --handoff <exact-registration> \
  --context /independent/context.json --phase pre-commit
```

Mapped driver phases require explicit matching `--execution-root`, exact intake
and semantic equality between selected goal and command record. Pre-commit and
supporting local-validation require implementation-stage admission; pre-merge
and all require fresh merge-stage admission. Local mappings route TDD, lint, CI
and verification to execution. Planning checks cannot satisfy execution gates.

`external-only` stops with `external_validation_adapter_required` before any
local executable gate. This preserves ADO-only application validation. No
external adapter or local substitution is supplied by this bridge. Missing
independent policy, runtime, owner, fixture, branch, review or hosted evidence
still blocks the corresponding action.

## Legacy and delivery

Explicit migration accepts a reviewed mapped bundle, preserves the entire
legacy object and digest, resets readiness to unknown and writes only stdout.
Publication remains registry-last. Migration cannot infer or grant mapping
authority. Do not manufacture real policy/context to make a migration pass.

Keep producer/consumer fingerprints matched. Source and isolated candidate
builds are not an installed release. Deliver through the reviewed immutable
Skills pin and ai-catapult build/install path; never patch installed cache.
