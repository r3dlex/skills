# P5 v2 successor preparation

Status: preparation only; unsigned, unapproved and not execution-admitted.

## Plan

1. Freeze the registered P5 v1 generation, retained policy and approval request.
2. Verify B5 planning inputs and every contract-lock member at fetched `origin/main`.
3. Lock content preservation, dependency order and fail-closed publication with regression tests.
4. Publish a separate content-only v2 successor with an inert policy/2 candidate and
   a policy bootstrap goal. Do not change the active policy or issue approval.
5. Run regression, full tests, lint and security scans; obtain independent review.

## Readiness transition

The historical v1 preparation hold says the spec and contract planning copy must
be on the default branch before worktrees are cut. They landed in skills PR #86,
commit `277cc698e8403131f87549b0d8ac64a7906a7c3e`, and remain byte-identical on
fetched `origin/main` at `48f90f11f5ce443451c2bfaeda3e2e4657791828`.
The preparation worktree was cut from that fetched commit. The v2 successor
therefore proposes `preparation: unknown`, not `pass`, for the four feature goals.
This is an evidence-backed new proposal, not an edit or loosening of an approved
sidecar. The original blocked v1 generation stays unchanged. Regression tests
verify the spec digest, contract lock and every member at the observed base.
Implementation and merge remain unknown; coverage and legacy-safe posture remain
unchanged. Missing ownership is not silently assigned: v2 binds the actual owner
and reviewer in the future exact plan approval.

## New approval boundary

`XSKP-P5-00` is a new policy-bootstrap planning goal, not feature implementation.
It scopes only `.ai/policies/readiness-policy.json`. All original P5 feature goals
transitively depend on it; their scope, ACs and verification are otherwise copied
exactly. The candidate is plan-agnostic, uses all three current required hosted
checks, accepts SSH-tag approval only and forbids admin merge (`identity_model:
multi`). Its observed anchor pin is a candidate only: the human must verify it
against their own external allowed-signers file. No anchor or key is written.

Do not merge this publication until a human independently verifies the candidate
anchor digest against their external trust anchor (ADR-0016). Review the exact
successor publication before merging it. Then request one exact v2
approval for the new generation with the actual owner and independent reviewer
lane. The older unsigned v1 request and P1 approval do not approve this successor.
Publication, review and green tests are not approval or dispatch authority.
