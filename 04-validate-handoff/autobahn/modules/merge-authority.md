# Merge Authority — Host-Policy Thin Adapter (C1)

Read when deciding whether a goal's PR may merge. `merge-authority.sh` is a
**thin adapter** over the ai-catapult-init host-policy decision. It re-encodes none of
host-policy's rules.

## Ordinary merge and policy bypass

An explicit user instruction to merge when checks pass authorizes an ordinary
host merge after reviewer approval, resolved comments, and current exact-head
local and remote checks. Use the normal merge API without admin/bypass flags;
recheck the PR head and host state immediately before merging. This does not
authorize changes to branch protection or other host policy.

The strict adapter below gates policy-application or supported-bypass verdicts.
An ordinary authorized merge does not need a fabricated bypass verdict or token.
If host policy blocks the normal merge, stop that path; never turn ordinary merge
authorization into bypass approval. Policy changes and bypass retain the explicit
host-policy authorization and readback requirements below.

## What the adapter does NOT own

These are owned by `ai-catapult-init/modules/host-policy-automation.md` and must NOT
be re-encoded in the adapter:

- the confirmation-token regex `^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$`,
- the admin-bypass / non-admin-auto-approval-disallowed matrix,
- the audit format (`.ai/host-policy/<host>/audit.jsonl`) and verdict markers
  (`apply-blocked-no-confirmation`, `apply-rejected-non-admin`,
  `apply-rejected-dry-run-mismatch`).

The adapter **consumes the host-policy decision**, reads its verdict +
`confirmation_token` verbatim, and decides nothing about policy itself.

## What the adapter DOES own

Only the fail-closed exit-code contract that maps a host-policy verdict to a merge
action:

| Host-policy verdict | Token | Adapter decision | Exit |
| --- | --- | --- | --- |
| `mode: apply`, `marker: host-supported-bypass`, `readback_status: match`, no conflicting `status` | opaque, present | **merge** | 0 |
| default / unauthorized / `mode: blocked` / non-admin | any | **ready-for-human**, no merge | non-zero |
| approved-shape but policy rejects (e.g. `apply-rejected-*`) | present | **fail closed**, no merge | non-zero |

The token's validity is whatever host-policy reports; the adapter does not parse
or re-validate the token string. It consumes the verdict's own
approved/rejected/blocked signal.

## Honoring the merge protocol

Merge is gated by the feedback merge protocol (reviewer APPROVE + remote CI +
local CI green, all comments resolved — see review-loop.md) **before** the
authority decision. The adapter is the final gate, not a substitute for the
review/CI gate.

Before **either** normal host merge or policy-bypass adapter, rerun
`run-gates.sh --phase pre-merge --root <repo> --goal-record <exact-selected-goal.json>
--handoff <same-generation-addressed-handoff-path> --context <fresh-merge-context.json>`.
For a direct goal, replace `--handoff` with `--goal <same-direct-envelope.json>`.
The driver invokes the shared validator with `--stage merge`; it requires exact
semantic equality between the selected goal and command record. Missing merge
evidence, stale context, changed subject or mismatched record blocks before
verification. Independently verify live operation authority for this exact
subject/goal/stage; `dispatch_authorized=false` is never a host approval.
`local-validation` and implementation readiness do not satisfy this prerequisite.
All original review, TDD, lint, exact-head remote/local CI and host-policy gates
remain required; readiness alone does not authorize a merge.

## How it is invoked + tested

The adapter takes a **pre-normalized host-policy verdict object** and emits the
merge/ready-for-human/fail-closed outcome. The normalized shape is top-level
`mode` + `confirmation_token` + outcome `marker` + `readback_status`. Normalizing the host-policy
decision into this object — in particular projecting the host-policy audit line's
`apply_results[].status` and the `apply-rejected-*`/`apply-blocked-*` markers
(owned by `ai-catapult-init/modules/host-policy-automation.md`) onto the top-level
`marker` — is the **host-policy consumer's** responsibility (the step that invokes
the host-policy decision), not this adapter's. The adapter never reads
`apply_results[]` or re-derives a marker.

Tests drive it against inline mocks for each marker **and** a committed verdict
fixture (`reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json`)
so the normalized shape is anchored to a real artifact. The opaque-token case (a
non-`ct-` token that still merges on an approved verdict) proves the adapter
consumes the verdict verbatim and never recomputes the regex or admin rule.

## readiness-contract/2 PRs

Once a v2 registry (`.ai/workflows/northstar-readiness-v2.json`) or a live
`readiness-policy/2` is observable, `--pr` is mandatory on every call,
`--verdict` included. Observable means on `origin/<target>`, on the commit
`git ls-remote` reports for it, or at HEAD of the repository it runs in. A
verdict-only call is then refused with exit 4 and never exits 0.

These also refuse with exit 4 and never fall back to the verdict path:
- a missing or rewound target ref;
- an active plan that fails to load (`plan_unloadable`); a registry entry whose
  status is not `active` (retired or superseded) is skipped;
- a branch in a registered plan's reserved namespace that is no goal of it
  (`v2_branch_without_plan`).

`--pr` selects the path by observing the PR's head branch against that registry.
The reserved namespace is built per registered active plan: the policy
`branch_pattern` with `<plan_id>` filled by `re.escape(plan_id)` and `<goal_id>`
left generic, matched case-insensitive. No pattern, the live policy's included,
is ever applied with a generic `<plan_id>`.

| PR head branch | Path |
| --- | --- |
| exactly a registered goal branch (`branch_pattern` with that plan and goal) | v2: `--verdict` refused; merge only on a re-observed `merge-certificate/1` |
| any other branch in a registered active plan's reserved namespace (another goal id, another case) | refused: `v2_branch_without_plan` |
| anything else | the v1 lane below |

**The v1 lane once v2 is live on `origin/<target>`.** A non-goal PR reaches the
unchanged v1 adapter only when its diff touches no reserved path: the policy
file, the v2 registry, `.ai/handoff/readiness-v2/**`, or an active goal's other
scope paths ([readiness-v2.md](readiness-v2.md#merge-routing-once-v2-is-live)).
Any other touch refuses with `v2_scope_outside_goal`. Two exception lanes cover a
touch: a publish-v2 replay (a replaced plan entry is reported as
`v2_plan_entry_replaced`) and sidecar tightening (a loosening refuses with
`v2_sidecar_not_tightening`). The policy file is never covered. The changed paths
come from the hosted changed-files list, renames by both names; a truncated or
unobservable list refuses.

A v1-lane decision prints a `merge-decision/1` with `decision: v1` and the
observed PR head before the v1 adapter runs. The merge that follows must use
`gh pr merge --match-head-commit` at that head. For v2 merges the merge
certificate is the host-policy audit record (O4).

The v2 path does not trust the certificate. It re-runs the local gates and
re-observes every hosted fact and the plan approval, then refuses on any
difference. It also refuses on a moved head (including between observation and
merge), an expired approval, a missing certificate or a non-production adapter.
It merges with `gh pr merge --match-head-commit`.

`--admin` maps only to the host's review bypass, under U3: the policy declares
`identity_model: single`, the certificate carries the admin flag, and an
independent agent review lane signed it. An admin merge backed only by
self-review is refused. Every decision records `assurance`. A call made outside
the target repository takes the v1 path. See [readiness-v2.md](readiness-v2.md).

## Safety rules

- Default is **ready-for-human**; merge only on an approved verdict + valid token.
- A valid token the policy still rejects fails closed (never merges).
- Re-encode no host-policy rule; consume the verdict as-is.
