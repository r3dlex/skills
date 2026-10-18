# Migrated own-script verification publication repair

**DRAFT — pending intake closure, independent consensus and publication allocation.**
This specification proposes one skills-repository repair; it grants no execution authority.

## Next steps and completion gates

1. Complete the Northstar intake/adversarial receipts against this exact proposal. No completed interview or measured ambiguity is claimed by this draft.
2. Freeze the proposal, candidate bundle and local intake together. Obtain original-parent capacity allocation for separate, sequential Architect and blind Critic contexts. Consensus is complete only after their actual reports and any required full-loop revision.
3. Obtain the skills registry/graph publication window from the owning coordinator. Publish only the reviewed bytes using the current pinned base-copy driver and a verified same-repository planning worktree; a successful planning report must still disclose every remaining readiness gap.
4. Stop at the verified Northstar handoff. The retained product author may later receive a separate exact-goal Autobahn dispatch only after independently current approval, admission and source-window authority.

## Subject and custody

| Binding | Proposed value |
| --- | --- |
| Repository | `skills` / `r3dlex/skills` |
| Plan | `skills-migrated-own-verification-repair` |
| Registration | `northstar-plan-skills-migrated-own-verification-repair` |
| Goal | `migrated-own-verification-01` |
| Local intake | `.ai/work-intake/skills-migrated-own-verification-repair.md` |
| Candidate | `.omc/plans/skills-migrated-own-verification-repair-20261010/goals.candidate.json` |
| Initial inspection base | `656d64e1759a27f97248d50bf613e8d31839fde5` |

The existing publisher-repair product author keeps its worktree, branch and drafts. This run owns only isolated planning artifacts. The planning base is an inspection binding, not a claim that it will remain the current publication or execution base. A later admitted execution must use the live policy's exact goal branch, such as `fix/skills-migrated-own-verification-repair-migrated-own-verification-01`; the held historical branch is preserved, not silently treated as a matching branch.

## Goal

Allow an explicitly proved v1-to-v2 migration to publish a goal whose preserved verification command references a test script that the same goal will introduce. Defer only that script's planning-time existence check. Preserve ordinary missing-script refusals and require the actual script and actual command success whenever runtime verification executes.

The known HPG refusal was one deterministic attempt. This plan uses that completed evidence and existing tests; it does not rerun the blocked HPG publication or drop its commands.

## Scope and boundaries

The candidate bundle is the exact product-path fence. It includes v2 validation/observation, public vocabulary, two contract-reference modules, three existing test files, both v2 dependency manifests, the derived local-CI declaration and one canonical TDD evidence file. The planning specification and intake are publication inputs, not additions to the product goal's scope.

Keep these boundaries because this is a load-bearing publication contract:

| Observable boundary | Reason |
| --- | --- |
| `verification.py`, `readiness_contract.py`, both v1 dependency manifests and v1 golden outputs remain byte-identical. | The v1-freeze contract pins those bytes, not merely equivalent behavior. |
| Existing immutable v1/v2 generations, policy, signers anchor, approval forms and required hosted checks remain unchanged. | A publication repair must not manufacture its own approval or relax another gate. |
| The repair plan itself uses only base-present verification scripts and carries no own-script deferral marker. | The old driver must be able to govern the repair without circular self-admission. |
| Ordinary fresh v2 plans keep both present-in-checkout and present-at-base checks. | Goal scope alone is not a general missing-fixture exemption. |
| No HPG/TCI/A2 goal executes or migrates as part of this repair. | Each dependent subject retains its original owner and separate admission. |
| Catalog files, SKILL.md bodies, workflows and other owners' source paths are unchanged. | Generated-file labels do not expand this exact fence. |

## Proposed interface

Use an optional, versioned object at `attachments.migrated_own_script_verification`. A marker is an untrusted request to verify provenance, never proof or permission. The proposed object has exactly these fields:

```json
{
  "schema": "migrated-own-script-verification/1",
  "registration": "northstar-plan-legacy-plan",
  "generation": "<full legacy generation sha256>",
  "legacy_bundle": {
    "path": ".ai/handoff/readiness-v1/legacy-plan/<generation>/goals.json",
    "sha256": "<legacy bundle byte sha256>"
  },
  "scripts": [
    {
      "goal_id": "legacy-goal",
      "verification_index": 0,
      "path": "tests/legacy-goal_test.sh"
    }
  ]
}
```

Use the existing content-only bundle and attachment surface rather than adding a gate, mutable readiness field or waiver flag. Original legacy attachment values remain verbatim; this is a separately reviewed publication-time addition. Reject a collision with an existing legacy attachment of the reserved name rather than overwriting it. The unmarked migration transform and its existing deterministic content/attachment outputs remain unchanged.

Every bundle-ingress route that parses or compares bundle, goal, sidecar, policy, approval/certificate or supplied-context records — publication preparation (`prepare_publication`), registered generation load, sidecar tightening, approval sidecar lookup, bare publication replay, supplied-context comparison, and the legacy-to-v2 migration projection — validates every present reserved marker on presence, independently of any missing-script detection, and refuses only on validation failure, including a forged marker whose selected scripts are all present. Presence triggers validation; it is not itself a refusal. Refusal is the only permitted outcome of a validation failure: wrong canonical value type, Boolean-as-integer `verification_index`, nested or misplaced reserved objects, a reserved name in an unsupported legacy goal field (never silently dropped by the migration projection), a reserved name in legacy attachments (refused before the verbatim attachment copy), and duplicate-key last-key-wins bytes (parsing for any object that can carry the reserved name uses unique-key parsing only, per `readiness_contract.py:58-65` and `observer.py:157-166`) — each refuses, none silently degrades. A marker that passes this validation on every route keeps its ordinary frozen-candidate treatment: valid provenance is preserved, the ordinary publication path proceeds exactly as before, genuine runtime script presence and success remain honored under AC-5, and presence-independent validation never rewrites an ordinary refusal and never silently treats marked input as unmarked content. Every such refusal keeps ordinary zero-publication-write behavior.

The pure v2 validator owns marker shape and goal linkage. The observer owns facts about the registered legacy source, target Git tree and filesystem. Reuse existing migration projection, inventory and B5 rules; no caller-authored prose or Boolean establishes migration eligibility.

## Acceptance criteria

### AC-1 — independently proved legacy binding

Before honoring a marker, independently read the v1 registry and source payload from the actual publication/replay base. Exactly one active registration must match the marker's registration, plan, generation, canonical payload path and byte digest. Repository identity and bound spec must match the candidate. Verify the selected unmerged goals against the supported migration projection: IDs, scopes, acceptance criteria, verification entries and issue references are preserved, with only already-supported merged-dependency/B5 reduction. Fresh inventory eligibility remains required for the actual migration; unknown, in-flight, retired, unregistered or drifted source evidence does not become eligible through this marker.

An ordinary fresh v2 plan, a different legacy plan, a copied scope with changed commands, or a forged/stale binding refuses before publication writes. Additional attachment prose is not interpreted as authority.

This validation is presence-independent: every present reserved marker is validated before any script-existence check, and again when every selected script exists — the goals bundle's AC-1 string carries the identical rule: validate every present reserved marker at every bundle-ingress route on presence and independently of missing-script detection — refuse on validation failure, including an all-present forged marker, with ordinary zero-publication-write behavior, while preserving valid provenance and genuine runtime success. No missing-script handler is part of this contract, and marker validation must not wait for one. The mirror of the refusal rule holds equally: a marker that passes this validation preserves its valid provenance and follows the ordinary publication path of the frozen candidate exactly; this contract never bans words in acceptance criteria, documentation or `legacy_risk_reason`, never requires that a selected script remain missing at runtime, and never weakens an ordinary refusal — an existing, genuinely passing selected script still satisfies the runtime gates of AC-5 unchanged.

### AC-2 — exact own-script selection

Every marker entry names one existing candidate goal and one exact preserved verification index. The command is either the original string form or the original `{cwd, command}` form; preserve its value and array position. The deferred form is narrowly `bash tests/<name>.sh` with exactly the executable and script argument, no added arguments; `<name>` may include safe nested path components. Its normalized repository-relative script path must equal the marker path and be an exact literal scope entry in that same original and migrated goal.

The cwd must already exist at the base and resolve safely inside the repository. The missing leaf must be absent from the target tree, with no symlink, submodule, traversal, control-character, wildcard or case/path alias used to establish its ownership. Missing interpreters/tools, missing cwd, unreadable existing scripts and scripts belonging to another goal remain blocking. Reject duplicate, extra, malformed, unknown-goal and out-of-range marker entries.

### AC-3 — v2-only planning validation, never execution

Apply the exception only to proved selected missing script leaves during v2 planning publication and its deterministic publication replay. Both current barriers must be addressed: `prepare_publication` calls strict shared command validation before `publish_checks` checks the base tree. Bypassing only the latter is insufficient.

Retain the frozen shared validator's parsing, command allowlist, executable resolution and containment checks. The recommended implementation uses a disposable v2-only validation view with inert placeholders for only the proved missing leaves; validate all existing/unmarked commands normally first. The view is not a fixture, script implementation, TDD receipt or gate workspace. It never runs commands, changes the observed repository/index/refs/object store, or survives into a runtime verification workspace. Independent review must either confirm this safe reuse or select an equally strict v2-only alternative inside the same fence; do not edit the frozen validator to simplify it.

Publication and its deterministic publication replay reconstruct a marker's proof from a trusted, observer-owned source: the real bound Git repository, the resolved immutable base commit, the v1 registry and the legacy payload read from that base or from the recorded generation's immutable bytes. The bare publication replay must receive this proof source and base context through trusted observer-owned plumbing — never through a caller-defined proof flag or Boolean, a scratch-root fallback, or a caller-supplied inventory file — and a marked bare publication that cannot independently rebuild its source facts refuses; the existing unmarked bare replay remains unchanged. The actual Git proof/source root, the publication replay/simulation scratch and the disposable validation view stay three separated filesystem contexts, and a proof-source allocation or cleanup failure refuses fail-closed with defined refusal bytes and zero publication writes.

The existing unmarked `verification_invalid` and `verification_not_at_base` refusals retain their behavior and zero-publication-write guarantee. Merely creating an untracked test file in the planning checkout is still insufficient for an ordinary plan.

### AC-4 — explicit deferral and deterministic publication

Publish the marker as hashed immutable bundle content. Report each selected leaf as deferred, with goal, verification index, path, legacy source and recovery; never report it as a passed verification check or execution readiness. Keep readiness unknown and publication authority none. Extend the public v2 vocabulary for the optional marker and diagnostic shape without changing approval, policy or sidecar semantics.

The admission-complete writer, bare publication replay, idempotent retry and same-repository worktree path produce matching immutable payloads. A refusal leaves the original registry/generations/traceability inputs unchanged; successful publication keeps registry-last ordering and existing sidecar enrichment behavior. Proof is rebuilt against the relevant base, not against arbitrary working-tree or supplied-context claims.

Publication decisions, deferral reports and refusal records are canonically serialized, ordered by the original preserved legacy goal position, the original verification array index and the normalized path, and reproducible byte-for-byte: successful and refused replays of the same inputs compare their full decision and refusal bytes — not only payload hashes — across fresh ephemeral locations, and carry no operating-system exception text, no ephemeral view or scratch paths beyond the existing planning-simulation normalization, no environment- or PATH-dependent executable paths, and no wall-clock value outside the context's defined clock. The plan defines the complete closed input set for these bytes and assigns every proof input to exactly one of two semantics: fresh eligibility, observed fresh by the observer at the marked publication, or historical provenance, reconstructed from recorded immutable bytes during replay — replay must not re-derive fresh eligibility, and publication must not treat caller-supplied records as observation.

The replay-determinism condition of AC-4 is discharged as an explicit cross-product, not a sample: for every fixture in the three scoped test seams (`tests/northstar_v2_publish_test.py`, `tests/readiness_v2_migrate_test.py`, `tests/readiness_v2_certificate_test.py`) — every eligible marked fixture and every negative fixture — each of the four route contexts (the admission-complete writer, the bare publication replay, the idempotent retry, the same-repository worktree path) produces byte-identical full decision and refusal bytes for the same fixture, alongside the existing payload parity. Every compared byte string is recorded as a plan evidence entry carrying the pinned test's case identifier, so an independent re-review can enumerate fixture × route pairs and their compared bytes; equal payload hashes alone never substitute for compared bytes.

Leak-set closure is defined per route context. Clocks: publication, bare publication replay, idempotent retry and the same-repository worktree each fix that context's clock to the resolved immutable base commit's committer timestamp — the exact rule the planning simulation already applies when it pins `GIT_COMMITTER_DATE` from `show -s --format=%ct` of the base (`observer.py:1301-1304`) — so no wall-clock value enters decision or refusal bytes outside the context's clock, and a proof-source allocation or cleanup failure refuses with refusal bytes timed by its own context's clock. Exception map: the pairs are the table inserted immediately after this paragraph; every code in that table is a literal the frozen bytes already emit, and this plan adds none. Refusal bytes of the new route carry that table's code only: no exception message text, no OS-derived text, and no runtime `'%s: %s'`-style type/message serialization (`observer.py:3268-3271`, `verification.py:168`). Named pinned cases, listed with their compared bytes in the evidence matrix: a PATH-variation case (identical decision and refusal bytes with reordered PATH entries) and a different-wall-clock case (identical decision and refusal bytes when the same invocation is computed at different wall-clock times, because the context clock is pinned to the base commit).

The table is the assignment. Precedence is first match, so one failure has one code. A `VerificationError` from the shared validator is converted at `observer.py:1108-1110` before any outer wrap sees the underlying `OSError`. An `Invalid` already carries its code as the text before the first colon (`readiness_contract_v2.py:117-119`). No row adds a code.

| Surface | Exception class at the anchor | Anchor | Canonical refusal code | Where that code already exists | Context clock |
| --- | --- | --- | --- | --- | --- |
| Strict-path cwd unreadable | `OSError` caught at `verification.py:147`, raised as `VerificationError` by `stop(3, …)` at `:148` | `verification.py:146-148`; class at `:92` | `verification_invalid` | `observer.py:1110` | base committer timestamp (`observer.py:1301-1304`) |
| Strict-path script unreadable | `OSError` caught at `verification.py:167`, raised as `VerificationError` by `stop(3, …)` at `:168` (the `{error}` leak) | `verification.py:165-168` | `verification_invalid` | `observer.py:1110` | base committer timestamp (`observer.py:1301-1304`) |
| Executable unavailable | `find_executable` returns `None` and raises nothing; `stop(3, …)` at `:173-174` raises `VerificationError`. Not a `ValueError` from `:83-89` | `verification.py:83-89`, `:172-174` | `verification_invalid` | `observer.py:1110` | base committer timestamp (`observer.py:1301-1304`) |
| Bare-replay wrap | `Invalid`, `OSError`, `KeyError`, `TypeError`, `ValueError` at `:2458`. The sibling un-publishable wrap at `:2447-2448` already emits the same code | `observer.py:2456-2459`; sibling `:2447-2448` | `v2_scope_outside_goal` | `observer.py:2459` and `:2448` | base committer timestamp (`observer.py:1301-1304`) |
| Sidecar-tighten failure | `Invalid` at `:2408`. An `OSError` is not caught here; if one escapes, the allocation/cleanup row applies | `observer.py:2404-2409` | `v2_sidecar_not_tightening` | `observer.py:2409` | base committer timestamp (`observer.py:1301-1304`) |
| Marked approval-lookup `sidecar_invalid` | `Invalid` whose `code()` is `sidecar_invalid` (`parse_json` at `observer.py:166`, or `validate_sidecar`). The catch must refuse and must not `continue`. Unmarked historical lookup still continues | `observer.py:688-690`; `readiness_contract_v2.py:351`, `:352`, `:356`, `:366`, `:367` | `sidecar_invalid` | the `Invalid` itself; `readiness_contract_v2.py:117-119` | base committer timestamp (`observer.py:1301-1304`) |
| Marked approval-lookup `sidecar_goals_mismatch` | `Invalid` whose `code()` is `sidecar_goals_mismatch`. Refuse; do not `continue` | `observer.py:688`; `readiness_contract_v2.py:354` | `sidecar_goals_mismatch` | `readiness_contract_v2.py:354` | base committer timestamp (`observer.py:1301-1304`) |
| Marked approval-lookup `sidecar_unknown_field` | `Invalid` whose `code()` is `sidecar_unknown_field`. Refuse; do not `continue` | `observer.py:688`; `readiness_contract_v2.py:358` | `sidecar_unknown_field` | `readiness_contract_v2.py:358` | base committer timestamp (`observer.py:1301-1304`) |
| Marked approval-lookup `sidecar_hold_invalid` | `Invalid` whose `code()` is `sidecar_hold_invalid`. Refuse; do not `continue` | `observer.py:688`; `readiness_contract_v2.py:361` | `sidecar_hold_invalid` | `readiness_contract_v2.py:361` | base committer timestamp (`observer.py:1301-1304`) |
| Marked approval-lookup `sidecar_coverage_invalid` | `Invalid` whose `code()` is `sidecar_coverage_invalid`. Refuse; do not `continue` | `observer.py:688`; `readiness_contract_v2.py:365` | `sidecar_coverage_invalid` | `readiness_contract_v2.py:365` | base committer timestamp (`observer.py:1301-1304`) |
| Proof-source allocation or cleanup failure | `OSError` or other non-`Invalid` from proof-source allocation or cleanup that is not caught by a row above | reaches `observer.py:3268-3269` | `operation_failed` | `observer.py:3269` | base committer timestamp (`observer.py:1301-1304`) |
| `Invalid` that reaches `run()` | an `Invalid` not already refused by a row above keeps the code already on it. This row adds no literal | `observer.py:3268-3269` | that `Invalid`'s existing `code()` | `readiness_contract_v2.py:117-119` | base committer timestamp (`observer.py:1301-1304`) |
| Other non-`Invalid` that reaches `run()` | any remaining non-`Invalid` `Exception` | `observer.py:3268-3269` | `operation_failed` | `observer.py:3269` | base committer timestamp (`observer.py:1301-1304`) |

Refusal bytes of the new route carry the matched row's code and nothing else: no exception message, no OS-derived text, no resolved executable path, and no `'%s: %s'` or `'%s' % error` serialization (`observer.py:1110`, `observer.py:2409`, `observer.py:2459`, `observer.py:3271`, `verification.py:148`, `verification.py:168`). The integer passed to `stop()` is not the refusal identity; the publication wrap's string is. The clock sentence in the paragraph above this table is binding for every row, including a proof-source allocation or cleanup failure, whose refusal bytes are timed by that same context clock.

The closed decision-input set is complete and finite: bundle bytes, sidecar bytes, optional policy-candidate bytes, the resolved base commit and its tree facts, v1 registry bytes at that base, legacy payload bytes, carried attachment bytes, the preserved original verification values, the context's clock value as defined above, and the three sealed capture records `real_root_safety`, `fresh_eligibility` and `spec_policy_bytes` defined by the capture contract below. Defined inputs and internal computation that must be accounted inside this boundary — and are not environment inputs: the mandatory real-root safety resolution of the frozen shared validator (`verification.py:83-89`, `verification.py:146-176`), the fresh eligibility observation at the marked publication (adapter queries at `observer.py:971`, ancestry at `observer.py:976-977`, with the in-flight/ambiguous fate rules of `readiness_contract_v2.py:465-510`), and the publication's own spec and policy reads (`observer.py:1112`, `observer.py:1130`, `observer.py:1136-1141`) — these are sealed, before decision construction begins, as those three capture records, which are members of this set and not notes about it; environment state, host PATH order, cwd, adapter freshness beyond the queried facts, and ephemeral view or scratch names stay outside the set and never enter decision or refusal bytes. Capture contract: observation is mandatory and is not suppressed to keep bytes stable. It ends when `real_root_safety`, `fresh_eligibility` and `spec_policy_bytes` are sealed. Decision construction begins at that seal — the first instruction that reads the sealed records and does not itself perform a subprocess, an environment read, or a filesystem read. `prepare_publication` (`observer.py:1098`) is the computation that today interleaves those reads (`:1108`, `:1112`, `:1127`, `:1130`, `:1136-1138`) with the decision; the marked route seals the records before the first decision or refusal byte is derived from them. `publication_bytes` (`observer.py:1094-1095`) remains the single exit of decision and refusal bytes and sits inside the spy, downstream of construction. A spy bound only at that serializer does not discharge this condition, because its argument can already contain values read before the call. The seal itself may call `publication_bytes` during observation; that call is an input, not the decision exit.

Each record has exactly these fields. A field not listed is not part of the record. Changing real-interpreter availability changes `executable_available`. Changing hosted in-flight status changes `fate`. Either change changes the sealed record, so the closed set is not equal.

| Record | Field | Captured from | Excluded from the record |
| --- | --- | --- | --- |
| `real_root_safety[]` | `goal_id`, `verification_index` | preserved goal position, then original verification index | order key only |
| `real_root_safety[]` | `executable_available` | `find_executable` returned non-`None` (`verification.py:83-89`); refusal path `:173-174` | the resolved path is not stored |
| `real_root_safety[]` | `cwd_readable` | the resolve at `verification.py:146` succeeded; `OSError` at `:147` records false | the `{error}` text at `:148` is not stored |
| `real_root_safety[]` | `script_readable` | true, false, or null when there is no script argument (`verification.py:165-168`) | the `{error}` text at `:168` is not stored |
| `real_root_safety[]` | `refusal_code` | null, or `verification_invalid` when any of the three outcomes failed | no OS message, no `argv`, no integer `stop()` code |
| `fresh_eligibility` | `merged` | `adapter.merged_prs` at `observer.py:971`, each item `{number, head_ref, merge_commit, reached}` after ancestry at `:976` | adapter freshness beyond these items is not stored |
| `fresh_eligibility` | `open_prs` | `adapter.open_prs` at `observer.py:971`, each item `{number, head_ref}` | not re-queried on replay |
| `fresh_eligibility` | `branches` | `adapter.branches` at `observer.py:971`, each item `{ref, merged}` after `:977` | not re-queried on replay |
| `fresh_eligibility` | `unobservable` | null, the existing literal `hosted_list_truncated` (`observer.py:973`), or `code()` of the `Invalid` at `:974-975` | `hosted_list_truncated` is an observation reason, not a new refusal code |
| `fresh_eligibility` | `fate` | `inventory_fate` result (`readiness_contract_v2.py:465-510`): `fate`, `action`, `merged`, `unmerged`, `in_flight`, `ambiguous`, `refused` | replay reads this object and does not re-derive it |
| `fresh_eligibility` | `served` | derived from the captured `fate` and `merged` fields, not captured: a goal id `g` is served exactly when `fate.merged` holds an item whose `goal` equals `g` — equivalently, when `g` is absent from `fate.unmerged` (`readiness_contract_v2.py:488`, `:493`). Each `fate.merged` item carries `goal`, `pr` and `merge_commit` only (`:485`); `reached` is not a field of that item. The join to the observation is explicit: the `merged` item whose `number` equals the item's `pr` and whose `merge_commit` equals the item's `merge_commit` has `reached` true, because `inventory_fate` appends to `fate.merged` only under `pull.get('reached') is True` (`:486-487`); a false `reached` lands in `fate.refused` (`:489-490`) and a null one in `fate.ambiguous` (`:491-492`), never in `fate.merged`. When `unobservable` is set, `fate.merged` is empty (`:475-478`) and no goal is served | not a separate query, not a new observation and not a new `inventory_fate` field; replay derives it from the sealed `fate` and `merged` and does not re-run `inventory_fate` |
| `spec_policy_bytes` | `policy_source` | `candidate` when `args.policy_candidate` is set, otherwise `live` | the path string is not a decision input |
| `spec_policy_bytes` | `policy_bytes` | the bytes at `observer.py:1127`, or `live_bytes` assigned at `:1130` from the read at `:1112` | not re-read after the seal |
| `spec_policy_bytes` | `live_bytes` | the bytes read at `observer.py:1112` from `root / v2.POLICY` (`:1111`; `POLICY` is `.ai/policies/readiness-policy.json`, `readiness_contract_v2.py:27`), or null when that path is not a file. Captured in every mode, because `:1112` runs before the mode branch at `:1117`; in `live` mode `policy_bytes` is this same value (`:1130`). Changing whether a policy/2 file is live at that path changes this field and, through it, `live_policy2`, `mode` and `amends`, so the sealed record changes | the path string is not stored; not re-read after the seal |
| `spec_policy_bytes` | `live_policy2` | the boolean `live2` of `observer.py:1114-1116`: true only when `live_bytes` is non-null and its parsed `schema` equals `v2.POLICY_SCHEMA` (`readiness-policy/2`, `readiness_contract_v2.py:19`); a `ValueError` or `AttributeError` while parsing records false | computed from the captured `live_bytes` only; no exception text is stored |
| `spec_policy_bytes` | `mode` | `policy-amendment` when `policy_source` is `candidate` and `live_policy2` is true (`observer.py:1118-1123`); `bootstrap` when `policy_source` is `candidate` and `live_policy2` is false (`:1124-1126`); `live` when `policy_source` is `live` (`:1128-1132`). The amendment validation at `:1121-1122` takes the sealed `policy_bytes` and `live_bytes` as its two parsed inputs — the marked route feeds the sealed `policy_bytes` to both `:1121` and `:1127`, so the candidate path is read once, at capture. Every value is an existing literal (`readiness_contract_v2.py:42`, `observer.py:1132`) | a function of `policy_source` and `live_policy2`, not a fourth observation; the `bootstrap_policy_live` check at `:1120` and the `policy2_not_live` check at `:1129` read sealed values and refuse with those existing codes |
| `spec_policy_bytes` | `amends` | `sha256(live_bytes)` when `mode` is `policy-amendment` (`observer.py:1141`), otherwise null; it is the `amends_policy_sha256` input of `generation_v2` at `:1142` | computed from the captured `live_bytes` at capture time; not recomputed from a later read |
| `spec_policy_bytes` | `spec_bytes` | the bytes at `observer.py:1138`, or null when the `spec_missing` check at `:1137` fails | not re-read after the seal |
| `spec_policy_bytes` | `spec_missing` | the boolean from `observer.py:1137`; a true value refuses with the existing code `spec_missing` | the check is not repeated inside the spy |
| `spec_policy_bytes` | `policy_sha256`, `spec_sha256` | computed from the captured bytes at capture time (`observer.py:1139-1140`) | not recomputed from a later read |

A scoped test in the three existing seams (`tests/northstar_v2_publish_test.py`, `tests/readiness_v2_migrate_test.py`, `tests/readiness_v2_certificate_test.py`) binds a no-subprocess, no-environment, no-filesystem-read spy at decision-construction start and holds it through the single decision exit at `publication_bytes`. The test fails if the spy is bound only at `observer.py:1094-1095`. Publication performs the observations and seals the records. Bare publication replay, idempotent retry and the same-repository worktree read the sealed records and do not re-query the adapter, re-run `find_executable`, or re-read the spec or policy paths. That is reconstruction, not suppression: a missing mandatory observation refuses with the code the C1.4 table already assigns and writes nothing.

Every proof input of the marker proof is assigned exactly one of two semantics — fresh eligibility, observed fresh by the observer at the marked publication, or historical provenance, reconstructed from recorded immutable bytes during replay — as this table fixes once; replay never re-derives fresh eligibility, publication never treats a caller-supplied record as observation, and reusing the caller-supplied `--inventory` file (`contract-run-v2.sh:88`) is explicitly not independent observation. Landing the selected scripts, tightening over marked generations, and certificate rebuilds never convert a historical input into a fresh one:

| Proof input | Semantics | Pinned test |
| --- | --- | --- |
| Fresh inventory eligibility — migration window, in-flight/ambiguous status (`observer.py:971`, `observer.py:976-977`; `readiness_contract_v2.py:465-510`) | Fresh — observed by the observer at the marked publication only | migrate seam: unknown/in-flight/retired/ambiguous negatives; publish seam: the same fixture's bare replay recomputes nothing fresh |
| Supported projection / B5 merged-dependency reduction (`readiness_contract_v2.py:556-569`) | Fresh — computed at publication from preserved legacy entries; recorded immutable bytes thereafter | migrate seam: projection-preserved fixtures (replay re-reads recorded bytes, never re-projects) |
| v1 registry bytes at the resolved immutable base (`V1_REGISTRY` = `.ai/workflows/northstar-readiness-v1.json`, `readiness_contract_v2.py:27-30`) | Historical — reconstructed from the resolved base's recorded immutable bytes | publish seam: registry-binding fixture, replay byte-equality case |
| Legacy payload bytes (`.ai/handoff/readiness-v1/legacy-plan/<generation>/goals.json`) | Historical — reconstructed from recorded immutable bytes | migrate + publish seams: payload-binding fixtures |
| Spec/repository binding records | Historical — reconstructed from recorded immutable bundle/registry/spec bytes | publish + certificate seams: binding-mismatch negatives |
| Base/tree facts — absent leaf, cwd containment, attachment collision | Historical — read from the resolved immutable base commit's exact objects; the same immutable facts serve publication and replay | publish seam: base/tree fixtures; worktree-route cross-product case |
| Carried attachment bytes (verbatim) | Historical — recorded immutable bytes | certificate seam: attachment-fidelity fixture |
| Tighten over marked generations (`observer.py:2391-2410` lane) | Historical — reconstructs each prior proof from recorded generation bytes; never derives fresh eligibility | certificate seam: tighten-over-generations case |
| Certificate rebuild | Historical — rebuilt from recorded immutable bytes only | certificate seam: rebuild fixture |
| Marker validity after the selected scripts land | Historical — the marker's proof stays reconstruction from recorded immutable bytes; landed scripts change runtime verification only (AC-5), never the proof semantics | publish seam: post-landing replay case |

### AC-5 — strict runtime enforcement

Keep `verification.py`, `ci-gate.sh`, runtime gate execution and certificate checks unchanged. Initial exact-goal implementation admission may independently authorize creation of the goal's own script; the planning deferral supplies no such authority. At every actual verification invocation, including pre-commit and the pre-merge gate workspace, the real selected script must exist, be contained, and return success under the unchanged command.

Tests must prove: absent real script blocks verification/certification; a failing real script blocks; the script's genuine passing implementation passes the original command. Planning placeholders cannot leak into, satisfy or skip these checks. All unrelated approval, ancestry, fixture, tool, hosted-check and independent-review gates remain required.

### AC-6 — regression matrix and honest TDD

Extend the existing publication, migration and certificate test seams. Cover string/object command forms, eligible unstarted/partly-merged migration, multiple selected goals, strict ordinary-plan controls, forged source/digest/goal/index/scope controls, unsafe paths and missing tools/cwd, no-authority reporting, zero-write refusals, matching replay/idempotence/worktree output, real missing/failing/passing-script runtime behavior, the all-ingress reserved-marker matrix (per-route presence-independent negatives including the all-present forged marker, wrong-type/nested/misplaced/Boolean-index/duplicate-key forms, pre-projection legacy collisions and unsupported-field refusals), and the replay-determinism matrix (byte-equal successful and refused replays across fresh ephemeral locations, with leak-set diagnostics — OS exception text, ephemeral paths, PATH-dependent executables, undefined clock — asserted absent from decision and refusal bytes). Preserve the existing ordinary missing-base-script test and v1 freeze corpus; do not edit old expected outcomes into green.

The all-ingress negative matrix is explicit per ingress route and per scoped seam; the seven bundle-ingress routes are publication preparation (`prepare_publication`, `observer.py:1098-1110`), registered generation load (`observer.py:615`, `:618`), sidecar tightening (`observer.py:2402-2409`), approval sidecar lookup (`observer.py:685-692`), bare publication replay (`observer.py:2436-2457`), supplied-context comparison (`observer.py:1069-1086`), and the legacy-to-v2 migration projection (`readiness_contract_v2.py:556-574`):

| Negative | Bundle-ingress route(s) | Scoped seam(s) |
| --- | --- | --- |
| Reserved-marker object of wrong canonical value type (Boolean/null/list/string/number where the schema requires an object; `readiness-contract-v2.json:75` keeps `"attachments": {"type": "object"}`) | all seven routes | publish + migrate + certificate |
| Boolean-as-integer `verification_index` | publication preparation; registered generation load; bare publication replay; migration projection | publish + migrate |
| Duplicate raw keys / last-key-wins marker bytes | every route that parses any object that can carry the reserved name (unique-key parsing only: `observer.py:157-166`, `readiness_contract.py:58-65`) | publish + migrate + certificate |
| Nested/misplaced reserved objects (inside goals, `acceptance_criteria`, verification entries, sidecars, policy/approval/certificate objects, supplied-context records) | six bundle routes; the migration projection refuses before projection for legacy placements | publish + certificate |
| All-present forged marker (every selected script present) | all seven routes, including the migration projection's eligibility path | all three seams |
| Reserved name in legacy attachments (collision with an existing legacy attachment of the reserved name) | migration projection — refuses before the verbatim copy (`readiness_contract_v2.py:572-573`) | migrate |
| Reserved name in an unsupported legacy goal field (the reduced projection would silently drop it, `readiness_contract_v2.py:565`) | migration projection — refuses instead | migrate |
| Source-name reservation / forged source name | publication preparation; registered generation load; bare publication replay | publish |
| Registration/generation/digest/repository/spec mismatch | publication preparation; registered generation load; bare publication replay | publish |
| Stale/retired/ambiguous registration | publication preparation; registered generation load | publish |
| Unknown/in-flight eligibility (`observer.py:971`; `readiness_contract_v2.py:465-510`) | publication preparation; bare publication replay (fresh eligibility never re-derived) | migrate + publish |
| Forged/malformed marked sidecar reaching the approval sidecar lookup, whose catch (`observer.py:688-690`) must not swallow it as absent | approval sidecar lookup | certificate |
| Marked bare-replay error wrap leaking exception text (`observer.py:2458-2459`) | bare publication replay — refusal bytes carry canonical codes only per the D12 map | publish |

The later product author records one focused failing-before/passing-after command in `.ai/evidence/migrated-own-verification-01.json` through the canonical TDD tool. Retain any failed attempts as evidence; do not invent a red leg or overwrite a terminal breaker. Planning writes are not TDD evidence.

### AC-7 — dependency and exact-head CI pins

Recompute both `readiness-dependency-v2.json` files identically for changed pinned v2 helper/schema bytes; leave all frozen v1 pins unchanged. In `.ai/ci/local-ci.json`, change only hashes for this goal's changed declared sources: the two v2 helpers, the schema, the three tests and the two v2 manifests. Preserve every other source/workflow value, inventory key and verification command. If a settled later base requires another repair, stop for explicit scope recovery rather than expanding this goal silently.

Serialize this declaration with the retained P5C owner and any other live manifest custodian. Verify all source/workflow pins against the final exact head, not the initial planning base, then require the goal's commands, full declared local CI, all policy-required hosted checks, resolved independent review and fresh pre-merge admission/certificate at that same head.

### AC-8 — complete bounded handoff

The actual repair touches only its candidate scope, uses the current base-copy driver to admit driver-changing work, preserves the original product author, and stops on any needed new source or generated file. After a genuine qualified merge, return the repaired driver identity and test/evidence receipts to the held HPG/TCI owners. Their later republication/implementation remains separate work; neither this planning run nor the repair's completion grants it automatically.

## Version impact

Proposed `minor`: a backward-compatible, opt-in v2 publication contract extension. No release/tag/npm publication is assigned. A review finding that existing behavior changes incompatibly requires explicit reconsideration rather than an inferred downgrade from a small diff.

## Planning readiness

| Stage | Current gap | When to resolve |
| --- | --- | --- |
| Intake | No completed deep-interview/adversarial receipt is asserted. | Before claiming Northstar intake complete. |
| Consensus | Separate Architect and blind Critic capacity has not been released. | After the exact draft is frozen and original-parent allocation arrives. |
| Publication | No registry/graph or commit/merge window is held. | After consensus, at the owning coordinator's exact serialized publication turn. |
| Implementation | No registered repair subject, approval or independent current admission exists. | In a separate original-author Autobahn run after qualified planning publication. |
| Merge | No product head, TDD/local/hosted evidence or pre-merge certificate exists. | Only after implementation and exact-head independent verification. |

**Next action:** allocate the pending independent planning reviews against the frozen packet, without resuming or replacing the retained product author.
