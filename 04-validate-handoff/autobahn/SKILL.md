---
name: autobahn
description: "Ship implementation-ready goals from a northstar handoff or evidence-complete direct record, with review, CI, fail-closed merge, and cascade closure."
eval: autobahn
---

# Autobahn

Autobahn ships implementation-ready goals one PR at a time. It delegates engines, review, merge policy, and cascade logic rather than reimplementing their loops.

## Quick Start

1. Gate either a northstar handoff or one direct implementation-ready goal:
   `bash autobahn/prereq-check.sh --root . --handoff <registered-id> --goal-id <id> --context <independent-context.json>`; direct intake uses `--goal <direct-v1.json>`. Mapped intake adds `--execution-root`; see [execution-mapping.md](modules/execution-mapping.md).
   Same-repository linked worktrees instead pair `--worktree-root` with `--base-commit`; see [worktree-execution.md](modules/worktree-execution.md).
2. Select standard or legacy-safe TDD, then pick the execution engine.
3. Implement one goal per PR, peer-review, then require fresh merge-stage context for the original exact selection through `run-gates.sh --phase pre-merge` before either merge-authority route. `local-validation` is supporting evidence, not merge admission or authority.
4. On merge, cascade-close the goal's issue with a triage status.

## Prereq (fail-closed)
Requires `ai-catapult-init` v3 at the planning root plus an exact versioned northstar handoff or an evidence-complete
direct goal passing `readiness-check.sh` — direct intake is for already-understood
work, not a shortcut past discovery. Planning completion is separate from execution readiness. Both routes use one pinned, non-writing validator and fixed approved policy. Reports never grant dispatch authority: independently verify live policy/operation authority before dispatch. Missing authority blocks; a self-authored context cannot authorize execution.

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
comment is resolved. `local-ci.sh` executes the supported safe CI subset;
`ci-gate.sh --verify` runs goal checks. Hosted checks must pass at the exact SHA. Mapped `external-only` validation blocks before local gates until a supported external adapter exists; never substitute planning checks.

## Merge authority (configurable, fail-closed)

An ordinary merge explicitly authorized by the user may use the host's normal
merge API after exact-head CI and review gates pass, without admin or bypass
flags. That authorization does not permit changing branch policy.
For policy changes or admin-bypass, `merge-authority.sh` is the **thin adapter**
over the host-policy verdict + `confirmation_token`. Only an explicit approved
marker and matching readback permit that path; otherwise **ready-for-human**.
<!-- codex:optional -->
Never fabricate a bypass verdict or token for an ordinary merge. See
[modules/merge-authority.md](modules/merge-authority.md).

## Cascade issue closure

On merge, delegate to the cascade engine to close the goal's issue idempotently
across repos and apply the canonical `triage` status. Closure is audited and
re-runnable without creating duplicates.

## Safety rules

- Fail closed: missing prereq, missing handoff, red CI, or unauthorized merge
  stops with guidance — never silently merge or mutate.
- Select an exact handoff and explicit goal IDs, or one nested direct envelope; never fall back to unrelated work.
- Independently verify live policy and operation authority before TDD or engine dispatch; validator reports never authorize dispatch.
- Direct intake must pass the evidence-complete readiness gate.
- Low or explicitly unknown coverage, or agent-observed legacy risk, must use legacy-safe TDD; never invent a percentage.
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
  Pre-merge/all require the same exact selection and fresh merge context; local-validation is not merge admission.
- Compose, never reimplement: delegate every loop, merge policy, and cascade.
- Default merge authority is **ready-for-human**; admin-bypass only on an
  explicit, host-policy-approved, valid-token verdict.

## References

- [modules/prereq.md](modules/prereq.md), [modules/readiness.md](modules/readiness.md), [modules/orchestration.md](modules/orchestration.md), [modules/engine-pick.md](modules/engine-pick.md), [modules/tdd-safety.md](modules/tdd-safety.md), [modules/implementation.md](modules/implementation.md).
- [modules/commit-protocol.md](modules/commit-protocol.md), [modules/lint-gate.md](modules/lint-gate.md), [modules/ci-gate.md](modules/ci-gate.md), [modules/review-loop.md](modules/review-loop.md), [modules/merge-authority.md](modules/merge-authority.md), [modules/cascade-closure.md](modules/cascade-closure.md), [modules/command-surface.md](modules/command-surface.md).
