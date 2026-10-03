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
| `publish-v2 --root R --bundle B --sidecar S [--policy-candidate C]` | Writes `goals.json`, `graph.json`, `handoff.md`, `sidecar.json` and an optional `policy-candidate.json` under `.ai/handoff/readiness-v2/<plan>/<generation>/`. The registry is written last. Never touches readiness-v1 paths, and refuses holds. |
| `approval-request --root R --handoff H --owner O --reviewer-lane L` | Prints the `plan-approval/1` record, its digest, the anchor sha256, the `ssh-keygen -Y sign` and `git tag` commands, and the in-session fallback labelled `assurance: in-session`. It never signs and never writes. |
| `admit-v2 --root R --handoff H --goal-id G --stage S` | Rebuilds `readiness-context/2` from fresh observation plus the verified approval, and exits 0 only when admitted. A supplied `--context`, `--observation` or `--verdict` is only compared with the rebuilt one; any difference refuses. |
| `certify-v2` (through `run-gates.sh --phase pre-merge --pr N --review-record F`) | Issues an agent-signed `merge-certificate/1` and stores it in observer state. |
| `merge-v2` (through `merge-authority.sh --pr N [--admin]`) | Re-observes every certificate claim, then merges with `gh pr merge --match-head-commit`. |
| `audit-merges --root R --handoff H` | Lists merged PRs through the production adapter (fails closed at 200). It flags each goal-branch PR whose merged head has no certificate (`merged_without_certificate`), has a certificate not signed by an agent principal with the certificate role (`certificate_signature_invalid`), or was certified at another head (`certified_head_mismatch`). For each PR it reports the approval digest, assurance and `lane_independence`. Exits 1 when anything is flagged, 4 when unobservable. |

`context-build`, `inventory-v1` and `export-evidence` are reserved names. They
exit 2 until the goals that deliver them land. Timing checks in `audit-merges`
(check completion and approval expiry against `mergedAt`) also arrive later.

## Inputs on the target

Admission reads every planning input from `origin/<target>`, never from the
checkout: the registry, the generation files, the live policy or candidate, and
the spec. Fetch first. The observer only reads and never fetches.

- **Policy:** `.ai/policies/readiness-policy.json` with `schema: readiness-policy/2`.
  - Its fields are `repository{id}`, `identity_model` (`multi` or `single`), `sources[]` (paths only), `required_checks[]`, `skippable_checks[]`, `branch_pattern` (with `<plan_id>` and `<goal_id>`), `target`, `tools[]`, `reviewer_requirements{independent_lane: true}`, `approval{anchor_sha256, max_age_days: 14, accept}` and `gates[]`.
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

## Plan approval

`plan-approval/1` is canonical JSON. It is carried by exactly one **unsigned** annotated
tag `approval/<plan_id>/<generation[0:12]>` that points at the publication
commit and is pushed to origin. The tag message has two lines:

```
<canonical approval JSON>
signature: <base64 of the ssh-keygen -Y sign -n ai-catapult-plan-approval output>
```

or, for the recorded fallback, `digest-echo: <sha256 of line one>`.

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
- agent principals: `namespaces="ai-catapult-review,ai-catapult-certificate"`.

**Assurance** is computed and never upgraded:

- `user-presence`: only an `sk-` key whose anchor line lacks `no-touch-required`;
- `key-held`: any other signing key;
- `in-session`: the digest-echo record.

An `in-session` record is agent-writable. Every report prints it as
`ASSURANCE: IN-SESSION`.

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
verdict path. A missing or rewound target ref, an unloadable plan, or a branch
that matches a v2 `branch_pattern` but no goal each refuse with exit 4. For a v2 PR it refuses `--verdict`, re-runs the local gates,
re-observes every hosted fact and the approval, and refuses on any difference.
It also refuses on a moved head, an expired approval, a missing certificate or a
non-production adapter. `--admin` is honored only under `single` with an
independent review lane. Run it in the checkout at the PR head.

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
