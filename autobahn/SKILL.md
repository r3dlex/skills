---
name: autobahn
description: Ship a northstar handoff's sliced goals in an init-ai-repo repo — ultragoal one-PR-per-goal, deterministic engine-pick, peer review, CI gate, fail-closed merge, cascade closure.
eval: autobahn
---

# Autobahn

Autobahn drives a northstar A→B handoff to shipped code: one PR per sliced goal,
each peer-reviewed, CI-green, and merged only under explicit authority. It is a
lightweight **composer** — it delegates to existing engines and skills and never
reimplements their loops, merge policy, or cascade logic.

## Quick Start

1. Run the prereq gate (fail-closed) against the repo root:
   `bash autobahn/prereq-check.sh --root .`
2. Consume the sliced goals from the northstar handoff.
3. For each goal: pick an engine, implement, peer-review, gate CI, decide merge.
4. On merge, cascade-close the goal's issue with a triage status.

## Prereq (fail-closed)

Autobahn assumes `init-ai-repo` v3 **and** a valid northstar handoff are present;
it never bootstraps either. `prereq-check.sh` asserts the `.ai/` structure exists
and a discoverable handoff (manifest `optional_branches` entry + handoff file) is
present, exiting non-zero with guidance otherwise. Do not proceed past a failed
prereq. See [modules/prereq.md](modules/prereq.md).

## Orchestration (ultragoal, one PR per goal)

Delegate to `ultragoal` for durable, ledger-backed orchestration: consume the
sliced goals from the handoff and ship **one PR per goal**. `ultragoal` owns the
ledger and goal loop; autobahn only feeds it the sliced goals and reads back
status. See [modules/orchestration.md](modules/orchestration.md).

## Engine auto-pick + override

Per goal, pick a sub-engine **deterministically** from the goal record's shape
(precedence qa > parallel > persistence > default): `ultraqa` for QA-heavy goals,
`ultrawork` for parallelizable goals, `ralph` for persistence-needing goals,
`team` by default. A user `--engine <name>` override wins over auto-pick.

<!-- codex:optional -->
The override is the first interactive point. If no override is supplied, fall back
to the deterministic auto-pick below; to override, pass `--engine <name>` to
`autobahn/engine-pick.sh` (`ultraqa|ultrawork|ralph|team`).

See [modules/engine-pick.md](modules/engine-pick.md) and
`autobahn/engine-pick.sh`.

## Peer-review loop

Each goal's PR runs an `architect` + `code-reviewer` + `executor` loop: the
executor implements, architect and reviewer review, and the loop continues until
**all comments are resolved**. Authoring and review stay in separate lanes — never
self-approve. See [modules/review-loop.md](modules/review-loop.md).

## CI gate

A PR is mergeable only when **remote host CI AND local CI are green** and every
review comment is resolved (the feedback merge protocol). A red or pending CI run
holds the merge. See [modules/review-loop.md](modules/review-loop.md).

## Merge authority (configurable, fail-closed)

Merge authority is a **thin adapter** over the init-ai-repo host-policy decision:
`merge-authority.sh` invokes host-policy, consumes its verdict + `confirmation_token`,
and wraps only the fail-closed exit-code contract. Admin-bypass merges only on a
host-policy-approved verdict with a valid token; otherwise stop at
**ready-for-human**; a valid token the policy still rejects fails closed. The
adapter re-encodes none of host-policy's token regex / admin rule / audit format.

<!-- codex:optional -->
Authorizing a merge is the second interactive point. To authorize, supply the
host-policy verdict + token to `autobahn/merge-authority.sh`; with no authorized
verdict the goal stops at ready-for-human. See
[modules/merge-authority.md](modules/merge-authority.md).

## Cascade issue closure

On merge, delegate to the cascade engine to close the goal's issue idempotently
across repos and apply the canonical `triage` status. Closure is audited and
re-runnable without creating duplicates. See
[modules/cascade-closure.md](modules/cascade-closure.md).

## Command surface

`autobahn` registers as a first-class command in both harnesses under
`.ai/commands/omx/` and `.ai/commands/omc/` using the shared schema northstar
designed. See [modules/command-surface.md](modules/command-surface.md).

## Safety rules

- Fail closed: missing prereq, missing handoff, red CI, or unauthorized merge
  stops with guidance — never silently merge or mutate.
- Compose, never reimplement: delegate every loop, merge policy, and cascade.
- Default merge authority is **ready-for-human**; admin-bypass only on an
  explicit, host-policy-approved, valid-token verdict.

## References

- [modules/prereq.md](modules/prereq.md), [modules/orchestration.md](modules/orchestration.md), [modules/engine-pick.md](modules/engine-pick.md).
- [modules/review-loop.md](modules/review-loop.md), [modules/merge-authority.md](modules/merge-authority.md), [modules/cascade-closure.md](modules/cascade-closure.md), [modules/command-surface.md](modules/command-surface.md).
