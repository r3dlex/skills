# Readiness contract v2

Read when a handoff is registered in `.ai/workflows/northstar-readiness-v2.json`.
v2 runs beside v1 ([readiness.md](readiness.md)) and never edits it: v1 bundles,
receipts and outputs stay byte-identical (`tests/readiness_v1_freeze_test.sh`).

v2 replaces hand-written contexts with **one plan approval per generation**.
That approval authorizes implementation and merge of every goal in the
generation. A merge still needs a merge certificate that is re-observed at merge
time. No text, flag or environment variable waives a gate.

## Operations

`contract-run.sh` routes these names to the pinned `contract-run-v2.sh`. Every
other name stays on the v1 path.

| Operation | Does |
| --- | --- |
| `publish-v2 --root R --bundle B --sidecar S [--policy-candidate C]` | Writes `goals.json`, `graph.json`, `handoff.md`, `sidecar.json` and an optional `policy-candidate.json` under `.ai/handoff/readiness-v2/<plan>/<generation>/`. The registry is written last. Never touches readiness-v1 paths, and refuses holds. A sidecar may hold only each goal's `legacy_risk_reason`: readiness and coverage default to `unknown` and `legacy_safe_tdd` to true, and a goal without a non-empty reason is refused (`legacy_risk_reason_missing`). |
| `publish-v2 ... --admit-planning [--target T]` | What `northstar/handoff-write.sh` runs for a `handoff-goals/2` bundle. Planning-stage admission against the simulated post-merge target, then the same write. See [Planning publication](#planning-publication). |
| `approval-request --root R --handoff H --owner O --reviewer-lane L [--assurance agent-self]` | Prints the `plan-approval/1` record, its digest, the anchor sha256, the `ssh-keygen -Y sign` and `git tag` commands, and the in-session fallback labelled `assurance: in-session`. It never signs and never writes. With `--assurance agent-self` (agent mode) it issues the record itself: signed with the agent key under `ai-catapult-agent-approval`, with the tag message and `git tag` commands printed. It still never writes or pushes the tag. |
| `approval-request ... --mode default\|agent\|prompt\|ssh-tag`, `approval-request --root R --handoff H --confirm D` | What `northstar/approve.sh` runs: one request in the governing mode, after an anchor preflight that prints the human setup steps when the anchor is missing. See [approval](../../../02-govern-plan/northstar/modules/approval.md). |
| `admit-v2 --root R --handoff H --goal-id G --stage S` | Rebuilds `readiness-context/2` from fresh observation plus the verified approval, and exits 0 only when admitted. A supplied `--context`, `--observation` or `--verdict` is only compared with the rebuilt one; any difference refuses. |
| `context-build --root R --handoff H --goal-id G --stage S [--context C]` | The same builder as `admit-v2` (one handler): prints `readiness-context/2` and exits 0 only when admitted. Without a verified approval, or when blocked, `authority` states that the context carries none. A supplied `--context` that differs from the rebuilt one refuses. |
| `certify-v2` (through `run-gates.sh --phase pre-merge --pr N --review-record F`) | Issues an agent-signed `merge-certificate/1` and stores it in observer state. |
| `merge-v2` (through `merge-authority.sh --pr N [--admin]`) | Re-observes every certificate claim, then merges with `gh pr merge --match-head-commit`. |
| `inventory-v1 --root R` | Decides the fate of every v1 registry entry on `origin/<target>` (O10), the one implementation every policy goal uses. See [v1 inventory](#v1-inventory). Exits 1 while any entry is in flight. |
| `audit-merges --root R --handoff H` | Lists merged PRs through the production adapter (fails closed at 200). It flags each goal-branch PR whose merged head has no certificate (`merged_without_certificate`), has a certificate not signed by an agent principal with the certificate role (`certificate_signature_invalid`), or was certified at another head (`certified_head_mismatch`). For each PR it reports the approval digest, assurance and `lane_independence`. Exits 1 when anything is flagged, 4 when unobservable. |

`export-evidence` is a reserved name; it exits 2 until ACH-S-06 lands. Timing checks in
`audit-merges` (check completion and approval expiry against `mergedAt`) also arrive later.

**Blocked admissions (proceed semantics).** A context that is not admitted carries no
authority: `authority` is `plan-approval/1` only when admitted, even when the approval
itself verified. Every gap names its `code`, `detail`, `goal`, `gate`, `fact` (the observed
fact, such as `tool:git`, `ancestor:<commit>` or `dependency:<goal>`), `source` and
`recovery`. The gaps are ordered by code, goal, gate, fact, detail and source, without
duplicates, and stderr prints them once as one consolidated report. A dependency is
complete only when its goal-branch PR merge commit reaches `origin/<target>`, for every
ancestor in the dependency chain; no receipt or flag stands in for it.

## Planning publication

`publish-v2 --admit-planning` (from `handoff-write.sh`) refuses unless `origin/<target>`
equals `git ls-remote` (`target_ref_rewound`). Under the publication lock it then:

1. computes the publication exactly as `publish-v2` does, plus publish-time checks that
   registered generations never meet: literal scope paths (`bundle_scope_unsafe`), `bash
   tests/...` verification scripts present at the base (`verification_not_at_base`), no
   goal branch shared with another active plan (`goal_branch_collision`), and a working-tree
   registry equal to the target's (`publication_base_mismatch`);
2. builds the simulated post-merge target: a throwaway repository that borrows the root's
   objects read-only, whose `origin/<target>` and detached HEAD are one deterministic commit
   of the target plus exactly the registry, the generation files and the spec copy;
3. runs planning-stage admission of every goal there, with a hosted adapter that sees no
   goal-branch PR (`planning-simulation`), since none can descend from a commit that does not
   exist yet;
4. writes, registry last, only when no gap blocks.

Gaps are classified by kind, never by gate stage, in `context.planning` and in the
`northstar-publication/2` result:

- **approval**: `approval_*`, `plan_approval_missing` and `ownership_unresolved`;
- **deferred**: `branch_target_mismatch`, `pr_required`, `check_*`,
  `protection_check_unsatisfied`, `review_lane_missing`, `threads_unobserved` and
  `dependency_incomplete`. They are listed, and their gates report `deferred`, never `pass`;
- **blocking**: every other code, unknown codes and `agent_self_*` included.

At planning only, an anchor whose sha256 equals the policy's must satisfy an approval form
the policy admits (through `check_form`: in-session needs no principal, ssh-tag an
approver principal, agent-self an agent-approval principal) and hold a certifier and a
reviewer that are distinct agent principals. Otherwise planning reports
`anchor_role_capability_missing`, which blocks. Publishing therefore needs the real anchor
on the publisher host.

## Inputs on the target

Admission reads every planning input from `origin/<target>`, never from the
checkout: the registry, the generation files, the live policy or candidate, and
the spec. Fetch first. The observer only reads and never fetches.

- **Policy:** `.ai/policies/readiness-policy.json` with `schema: readiness-policy/2`.
  - Its fields are `repository{id}`, `identity_model` (`multi` or `single`), `sources[]` (paths only), `required_checks[]`, `skippable_checks[]`, `branch_pattern` (with `<plan_id>` and `<goal_id>`), `target`, `tools[]`, `reviewer_requirements{independent_lane: true}`, `approval{anchor_sha256, max_age_days: 14, accept, default_mode?}` and `gates[]`.
  - `accept` holds the forms `ssh-tag`, `in-session` and `agent-self`. The optional `default_mode` is `agent`, `prompt` or `ssh-tag` (K3). It needs its form in `accept` (`agent-self`, `in-session` and `ssh-tag` respectively), or it is refused with `policy_default_mode_not_accepted`. `prompt` and `ssh-tag` modes may not list `agent-self` (`policy_default_mode_inconsistent`). A policy without `default_mode` keeps its semantics.
  - `branch_pattern` is `^`, literal `[A-Za-z0-9/_.-]` characters, at most one group of literal alternatives such as `(feat|fix|chore)`, `<plan_id>` and `<goal_id>` once each, and `$`. No other regex syntax is accepted.
  - Gates are repository-scoped and use only the 10 fixed kinds.
  - `not_applicable` is allowed only for `fixture` (`no-fixture-dependency`) and `harness_trust` (`no-pinned-harness`).
  - An unset `anchor_sha256` or empty `required_checks` refuses admission, each with a named gap.
- **Bundle:** `handoff-goals/2` holds content only: `id`, `scope`, `acceptance_criteria`, `dependencies` and `verification`.
  - A goal that carries a gate, readiness, coverage, `legacy_*` or owner is refused.
  - `goal_revision_v2` hashes content only. `generation_v2` binds the bundle, spec, policy and anchor digests.
- **Sidecar:** `readiness-sidecar/1` holds per-goal readiness holds (`unknown` or `blocked`), coverage, `legacy_safe_tdd` and `legacy_risk_reason`.
  - It may only tighten: add a hold, measure coverage once, set `legacy_safe_tdd` to true, or extend the reason by prefix.
  - Loosening needs a new approval that binds the new sidecar.
- **Policy bootstrap:** a generation may carry `policy-candidate.json` only while no live policy/2 exists.
  - Exactly one goal scopes the policy path, and every sibling depends on it.
  - The candidate stays inert until the approval that binds its digest verifies.
  - The policy goal's certificate requires the head policy bytes to equal that digest.
- **Policy amendment:** while policy/2 is live, a `policy-amendment` generation is exactly one goal that scopes the policy path and carries a `policy-candidate.json`.
  - One new approval binds the candidate's digest. It is verified under the candidate's anchor, so a key or anchor rotation verifies against the new anchor.
  - The generation records the live policy digest it amends as `amends_policy_sha256`, and its generation id binds it. Once another policy lands, admission refuses with `amendment_base_moved`; publish the amendment again.
  - It keeps the live `branch_pattern`; a candidate that changes it is refused with `branch_pattern_change_refused`. Routing always reads the live pattern.
  - Its certificate also requires the head policy bytes to equal that digest.
  - Its merge changes the live policy digest and voids every other approval in the repository. The recovery is to re-sign the same generation: a live-mode generation keeps its identity (content under the policy and anchor it was published with), and the new approval binds the new policy and anchor.
  - A bootstrap generation cannot recover by re-signing: once an amendment replaces the policy its candidate introduced, it refuses with `bootstrap_policy_live`, so republish its unmerged goals as a live-mode generation, or finish its bootstrap plans before any amendment.

## Plan approval

`plan-approval/1` is canonical JSON. It is carried by exactly one **unsigned** annotated
tag `approval/<plan_id>/<generation[0:12]>` that points at the publication
commit and is pushed to origin. The tag message has two lines:

```
<canonical approval JSON>
signature: <base64 of the ssh-keygen -Y sign -n ai-catapult-plan-approval output>
```

or, for the recorded fallback, `digest-echo: <sha256 of line one>`, or, in agent mode,
`agent-signature: <base64 of the ssh-keygen -Y sign -n ai-catapult-agent-approval output>`.

The trust anchor is `~/.config/ai-catapult/allowed_signers`, resolved from the
passwd home directory. No environment variable or flag moves it. To be used, it
must:
- be a regular file, not a symlink;
- resolve to a location outside every git worktree;
- have a sha256 equal to the policy's `anchor_sha256`.

It is read once into a private copy. The anchor line is selected by the public
key that signed, and every principal must appear on exactly one line. Roles come
from that line's `namespaces=` option:

- approver principals: `namespaces="ai-catapult-plan-approval"`;
- agent principals: `namespaces="ai-catapult-review,ai-catapult-certificate"`;
- an agent that issues agent-mode approvals also holds `ai-catapult-agent-approval`, and never `ai-catapult-plan-approval`.

**Assurance** is computed and never upgraded:

- `user-presence`: only an `sk-` key whose anchor line lacks `no-touch-required`;
- `key-held`: any other signing key;
- `in-session`: the digest-echo record;
- `agent-self`: an agent-mode approval, whatever key signed it.

An `in-session` record is agent-writable. Every report prints it as
`ASSURANCE: IN-SESSION`, and an `agent-self` approval as `ASSURANCE: AGENT-SELF`.
No level is ever rendered as another.

**Approval modes (K3).** `default_mode` selects the form:
- `agent`: Autobahn issues the `agent-self` approval itself (`approval-request --assurance agent-self`).
- `prompt`: only in-session, an explicit human confirmation; any other form is refused (`approval_form_refused_by_mode`, `agent_self_refused_by_mode`).
- `ssh-tag`: only ssh-tag, an opt-in for human signatures; any other form is refused (`approval_form_refused_by_mode`, `agent_self_refused_by_mode`).

Verification refuses, each with its own code:
- `agent_approval_signer_not_agent`: the agent signature's principal lacks `ai-catapult-agent-approval` or also holds `ai-catapult-plan-approval`;
- `agent_self_claim_without_agent_signature`: a human-namespace signature or a digest-echo record claims `agent-self`;
- `agent_self_not_accepted`: `accept` omits `agent-self`.

**Rule (d).** A `policy-amendment` approval form must pass the live policy's whole
form rule, `accept` and `default_mode` alike, and the candidate's `accept`
(`approval_form_not_in_live_policy`, `approval_form_not_accepted`,
`approval_form_refused_by_mode`, `agent_self_refused_by_mode`). A bootstrap or
amendment candidate's own `default_mode` never governs the approval of that same
candidate, so an ssh-tag-only repository can approve a move to prompt mode by
ssh-tag. A v1 or absent live policy counts as an empty live
list, so an agent-self approval of a bootstrap generation is refused with
`agent_self_bootstrap_refused`. When agent-self is in both lists it may approve an
amendment (K3b); that approval reports the notice `agent_self_policy_change` in the
admission, certificate, merge and `audit-merges` results.

**Narrowing `accept` to `["ssh-tag"]` does not close agent self-approval.**
- The anchor and the agent keys live under the same user's
  `~/.config/ai-catapult`, so an agent running as that user can reach them.
- `key-held` proves only that some anchored key signed.
- A human must verify each policy candidate's `anchor_sha256` against the
  anchor they created, during the planning-input review.
- Only `user-presence` evidences a person.

## Merge certificate and merge

`run-gates.sh --phase pre-merge` issues `merge-certificate/1` only at one exact,
clean head. The certificate binds:

- the approval digest and assurance;
- the PR number, head and base;
- the merge-stage admission digest and the local gate results;
- every required check SUCCESS, completed before issue;
- zero unresolved threads;
- the review lane record, signed by an agent principal other than the certifier (`lane_independence: declared`);
- the admin flag, set only under `identity_model: single`.

The agent signing key is `~/.config/ai-catapult/agent_signing_key`, or a `.pub`
with the key in the agent.

Local gates run PR code, so they run without credentials:
- the environment holds only `PATH`, `LANG`, `LC_ALL` and `TMPDIR`;
- `HOME` is a throwaway temporary directory;
- `PYTHONDONTWRITEBYTECODE=1` is set;
- there is no `GH_TOKEN`, `GH_CONFIG_DIR` or agent socket. Certificates, review records and the driver log live
under `<git common dir>/ai-catapult/observer/`.

`merge-authority.sh` requires `--pr` once a v2 artifact is observable (a
registry or a live policy/2) on `origin/<target>`, on the commit
`git ls-remote` reports, or at HEAD. From then on it never falls back to the
verdict path. A missing or rewound target ref, an unloadable active plan, or a
branch in a registered plan's reserved namespace that is no goal each refuse with
exit 4 (see [Merge routing once v2 is live](#merge-routing-once-v2-is-live)). For a v2 PR it refuses `--verdict`, re-runs the local gates,
re-observes every hosted fact and the approval, and refuses on any difference.
It also refuses on a moved head, an expired approval, a missing certificate or a
non-production adapter. `--admin` is honored only under `single` with an
independent review lane. Run it in the checkout at the PR head.

## Merge routing once v2 is live

`merge-authority.sh --pr N` routes from `origin/<target>`. Registry entries whose
status is not `active` (retired or superseded) are skipped; an active entry that
fails to load refuses with `plan_unloadable`.

- **Reserved branch namespace.** For each registered active plan: its policy
  `branch_pattern` with that `plan_id` and any goal id, case-insensitive. An exact
  goal branch routes to v2. Any other branch in the namespace refuses with
  `v2_branch_without_plan`. No pattern is ever applied with a generic `<plan_id>`.
- **Active goal.** A goal of an active registry entry whose goal-branch PR merge
  commit is not yet an ancestor of `origin/<target>`. The reserved set is the union
  of what is active at the PR's base commit and at the current `origin/<target>`.
- **Reserved paths.** A non-goal PR takes the v1 verdict lane only when its diff
  touches none of these, unless an exception lane below covers the touch:
  - `.ai/policies/readiness-policy.json`, never covered by any exception; it merges
    only through a policy goal's v2 certificate;
  - the v2 registry `.ai/workflows/northstar-readiness-v2.json`;
  - `.ai/handoff/readiness-v2/**`;
  - every active goal's other scope paths (equal to or under a scope entry).
  The free planning-input paths `.ai/traceability/graph.json`, plan-scoped spec
  copies under `docs/specifications/ACTIVE/`, the request documents
  `.ai/handoff/<plan_id>-plan-approval-request.json` and
  `.ai/handoff/<plan_id>-plan-approval.md`, and `.ai/ci/local-ci.json` are never
  reserved through goal scope. Paths match case-insensitively and Unicode-normalized.
  Any other touch refuses with `v2_scope_outside_goal` (exit 4).
- **publish-v2 replay.** A PR that is up to date with `origin/<target>` and adds
  exactly one generation directory takes the v1 lane when its registry and
  `.ai/handoff/readiness-v2/**` changes equal, tree entry for tree entry, a
  publish-v2 replay by the pinned driver. The replay runs in a scratch tree built
  from git objects, with the reserved paths reset to the base and the PR head's new
  `goals.json`, `sidecar.json` and optional `policy-candidate.json` as inputs. It
  may add a plan. It may replace a plan's entry only when that plan has no merged
  and no open goal PR, reported as `v2_plan_entry_replaced`. Symlinks and
  submodules on reserved paths or their parents refuse.
- **sidecar-tighten.** A diff limited to existing generations' `sidecar.json`
  takes the v1 lane when each change passes the pinned `validate_sidecar` and
  `sidecar_leq` against the PR base and the current target's bytes. Any loosening
  refuses with `v2_sidecar_not_tightening`.
- **Diff observation.** The hosted changed-files list, renames by both names,
  unioned with the reserved paths of the head's own three-dot diff read from git
  objects (renames off, submodules included). The objects come from the local
  repository when it has the head, otherwise from a throwaway fetch of
  `refs/pull/<n>/head` and then of the head branch. A fetch that lands on any other
  commit than the observed head refuses with `pr_head_moved` (reported as
  `v2_diff_unobservable`). The hosted list alone is used only when every fetch of
  the PR head fails outright. Residual until ACH-S-06: for non-reserved paths the
  hosted list governs, so a list served for another head (an A-B-A head flip
  between the reads) can hide an edit to an active goal's scope, and there is no
  detective control until ACH-S-06's audit. The decision prints `diff_head`, the
  head the diff was computed from. Reaching GitHub's
  3000-file cap, or a count that differs from the PR's integer `changed_files`,
  refuses with `pr_files_truncated`; a missing count refuses. A PR whose head or
  base moves while it is listed refuses with `v2_diff_unobservable`. A PR whose
  base is not the target refuses with `pr_base_not_target`, and `--pr` outside a
  repository refuses. A v1-lane decision prints a `merge-decision/1` with the
  observed head, and the merge uses `gh pr merge --match-head-commit` at that head.
- **Goal PRs.** A goal PR's own diff (merge-base to head, from git objects) may
  touch a reserved path, or a spec copy bound by an active generation, only inside
  the goal's scope, and then only as the policy goal's policy file, a pinned
  publish-v2 replay, a `retired_v1`-only registry change for the policy goal, or a
  tightening sidecar change. Anything else refuses its certificate with
  `goal_reserved_path`. A goal PR whose scope includes the registry and
  `.ai/handoff/readiness-v2/**` (ACH-S-05's P5 publication) must be an exact
  single-generation publish-v2 replay, up to date with `main` at certify time.
- **Republish.** A replay that replaces a plan's entry (allowed only without merged
  or open goal PRs) may also edit that plan's bound spec copy.
- **Goal-branch facts.** A goal counts as merged only through a PR on its exact
  goal branch into the target, queried per branch, whose merge commit reaches the
  target and descends from the generation's publication. Spec copies bound by an
  active generation are reserved too.

## v1 inventory

`inventory-v1 --root R` reads the v1 registry on `origin/<target>` and decides
each entry's fate from hosted facts and git ancestry only (O10):

- A goal counts as merged only through a merged PR whose head branch carries the
  goal id as a token (case-insensitive, bounded by non-alphanumerics) and whose
  merge commit is an ancestor of `origin/<target>`. Every match is listed as
  `{goal, pr, merge_commit}`. Commit-message and title text are never signals.
  (`audit-merges` separately recomputes each certificate's assurance from the
  approval tag and flags `assurance_mismatch` or `approval_digest_unobserved`; a
  tag whose record claims another level than its carrier evidences counts as no
  evidence. For ACH-S-06: Re-signing an approval tag flags certificates issued under
  the earlier tag with `approval_digest_unobserved`; that flag is noise, not a
  finding, once the re-signed approval verifies.)
- `completed`: every goal merged. The entry is retired by a top-level
  `retired_v1[]` record in the v2 registry that carries the map, never by an entry
  of `plans[]`. The v1 bytes stay unchanged.
- `unstarted`: no goal merged or open; it migrates (O10).
- `partly-merged`: some goals merged and no unmerged goal has an open PR or an
  unmerged origin branch carrying its token; the unmerged goals migrate.
- `in-flight`: an unmerged goal has such a PR or branch. An unreachable hosted
  API, a truncated list or an unattributable match is ambiguous and also in
  flight. Admission of a policy goal then refuses with `v1_inventory_in_flight`.

## Environment and provenance

Every v2 entry point builds its environment from an allowlist:

- `PATH`, `LANG`, `LC_ALL`, `TMPDIR`, `SSH_AUTH_SOCK` and `GH_TOKEN` pass through;
- `HOME` and `GH_CONFIG_DIR` are set from the passwd home directory.

Unknown arguments exit 2. The hosted adapter is the `gh` CLI. A test adapter
exists only in-process, and it is recorded in every observation and certificate.

`readiness-dependency-v2.json`, identical in autobahn and northstar, pins the v2
and v1 helper files and the entry points. A driver running inside the
repository it admits must match the `origin/<target>` copy byte for byte, so a
PR that edits the driver is admitted by the base copy, never by its own head.
Run it from a detached worktree at the base.
