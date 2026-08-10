---
name: autobahn
description: "Ship implementation-ready goals from a northstar handoff or evidence-complete direct record, with review, CI, fail-closed merge, and cascade closure."
eval: autobahn
---

# Autobahn

Autobahn ships implementation-ready goals one PR at a time. It delegates engines,
review, merge policy, and cascade logic rather than reimplementing their loops.

## Quick Start

1. Gate either a northstar handoff or one direct implementation-ready goal:
   `bash autobahn/prereq-check.sh --root . [--goal <goal.json>]`.
2. Select standard or legacy-safe TDD, then pick the execution engine.
3. Implement one goal per PR, peer-review, gate CI, and decide merge.
4. On merge, cascade-close the goal's issue with a triage status.

## Prereq (fail-closed)

Requires `ai-catapult-init` v3 plus a northstar handoff or an evidence-complete
direct goal passing `readiness-check.sh` — direct intake is for already-understood
work, not a shortcut past discovery.

## Orchestration (ultragoal, one PR per goal)

Delegate durable orchestration to `ultragoal` and ship **one PR per goal**.
See [modules/orchestration.md](modules/orchestration.md).

## Engine auto-pick + override

Per goal, pick a sub-engine **deterministically** from the goal record's shape
(precedence qa > parallel > persistence > default): `ultraqa` for QA-heavy goals,
`ultrawork` for parallelizable goals, `ralph` for persistence-needing goals,
`team` by default. A user `--engine <name>` override wins over auto-pick.

Use `autobahn/engine-pick.sh`; see
[modules/engine-pick.md](modules/engine-pick.md).

## TDD blast-radius gate

Before implementation, `tdd-mode.sh` selects **legacy-safe** TDD automatically
when coverage is under 30%. The running agent may also select it at any coverage
level when the specific change has high coupling, weak seams, or elevated blast
radius; record `legacy_safe_tdd: true` and `legacy_risk_reason` in the goal. This
changes the TDD technique, never the review or CI bar. See
[modules/tdd-safety.md](modules/tdd-safety.md).

## Peer-review loop

Each goal's PR runs an `architect` + `code-reviewer` + `executor` loop until
**all comments are resolved**. Authoring and review stay in separate lanes —
never self-approve.

## CI gate

Mergeable only when **remote host CI AND local CI are green** and every review
comment is resolved. `ci-gate.sh` derives local CI from the repo's own config
and runs the goal's `verification[]`.

## Merge authority (configurable, fail-closed)

Merge authority is a **thin adapter** over the ai-catapult-init host-policy decision:
`merge-authority.sh` invokes host-policy, consumes its verdict + `confirmation_token`,
and wraps only the fail-closed exit-code contract. Admin-bypass merges only on a
host-policy-approved verdict with a valid token; otherwise stop at
**ready-for-human**; a valid token the policy still rejects fails closed.
<!-- codex:optional -->
Authorizing a merge is the second interactive point, after the `--engine`
override above. To authorize, supply the
host-policy verdict + token to `autobahn/merge-authority.sh`; with no authorized
verdict the goal stops at ready-for-human. See
[modules/merge-authority.md](modules/merge-authority.md).

## Cascade issue closure

On merge, delegate to the cascade engine to close the goal's issue idempotently
across repos and apply the canonical `triage` status. Closure is audited and
re-runnable without creating duplicates.

## Safety rules

- Fail closed: missing prereq, missing handoff, red CI, or unauthorized merge
  stops with guidance — never silently merge or mutate.
- Direct intake must pass the evidence-complete readiness gate.
- Low coverage or agent-observed legacy risk must use legacy-safe TDD.
- Accept no goal without recorded red-then-green evidence: one test command that
  failed before the change and passed after. Absent or inconsistent, it blocks.
- Never commit past a failing lint policy. A declared policy whose tool is
  missing, or an unreadable manifest, blocks too — nothing linted the diff.
- A repo with no derivable CI is blocked, never assumed green; a CI file using
  constructs the reader does not support is refused rather than guessed at.
- Run the goal's `verification[]` before merge, and only commands that are
  allowlisted and free of shell metacharacters.
- Run the gates through the bundled gate driver, not by hand: one goal record
  each time, the pre-commit set before committing and pre-merge before merging.
- Compose, never reimplement: delegate every loop, merge policy, and cascade.
- Default merge authority is **ready-for-human**; admin-bypass only on an
  explicit, host-policy-approved, valid-token verdict.

## References

- [modules/prereq.md](modules/prereq.md), [modules/readiness.md](modules/readiness.md), [modules/orchestration.md](modules/orchestration.md), [modules/engine-pick.md](modules/engine-pick.md), [modules/tdd-safety.md](modules/tdd-safety.md), [modules/implementation.md](modules/implementation.md).
- [modules/commit-protocol.md](modules/commit-protocol.md), [modules/lint-gate.md](modules/lint-gate.md), [modules/ci-gate.md](modules/ci-gate.md), [modules/review-loop.md](modules/review-loop.md), [modules/merge-authority.md](modules/merge-authority.md), [modules/cascade-closure.md](modules/cascade-closure.md), [modules/command-surface.md](modules/command-surface.md).
