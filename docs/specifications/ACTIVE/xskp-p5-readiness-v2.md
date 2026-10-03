# P5 readiness-contract/2 successor

Status: planning publication; exact generation approval pending.
Repository: `r3dlex/skills`. Plan: `xskp-p5-skill-producers-v2`.

## Feature contract and non-goals

This successor carries the four feature goals from the registered
`northstar-plan-xskp-p5-skill-producers` v1 generation
`4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c`.
Their scopes, acceptance criteria and verification commands are unchanged.
The feature specification remains
[cross-surface-knowledge-publication-xskp-p5-skill-producers.md](cross-surface-knowledge-publication-xskp-p5-skill-producers.md),
sha256 `f2c315e2843033cde9d4e609b2ab2b3c841ac1321f1a461f21c09c1b29120fa4`.
The frozen contract lock remains sha256
`9f5d7edfc17554c383b06aa4726dfffe564ecc8d657b16baa89ce72098d5e102`.
No producer, runtime, installed skill, template or catalog implementation is
included in this preparation change. No active policy, v1 publication, old
approval request, trust anchor or signing key is changed.

## Bootstrap and dependency order

Readiness v2 is delivered by ACH-S-01, but the target's active policy is still
v1. Add one new planning goal, `XSKP-P5-00`, scoped exclusively to
`.ai/policies/readiness-policy.json`. When separately approved and admitted,
it installs the exact bytes of the generation's inert policy/2 candidate.
Every feature goal transitively depends on that bootstrap:
`00 -> 01 -> 02 -> 03` and `01 -> 04`.
Bootstrap does not authorize feature dispatch before its admitted merge.

The candidate is repository-wide and plan-agnostic. It requires ownership,
SSH-tag plan approval, target ancestry, matching branch/target, tooling, lock
and validator fingerprints, all three current hosted checks, independent
review and merge certificates. There are no skippable checks or admin merges.
Fixture and pinned-harness gates retain their P5 no-dependency rationale through
the fixed v2 not-applicable tokens. Each feature still requires observed
red/green evidence, local CI, lint and security checks through the bundled driver.

## Evidence-backed sidecar transition

The only historical preparation hold was B5: the planning spec and contract
copy had to reach `main` before implementation worktrees were cut. They landed
at commit `277cc698e8403131f87549b0d8ac64a7906a7c3e` (skills PR #86), an
ancestor of fetched target `48f90f11f5ce443451c2bfaeda3e2e4657791828`.
The spec, contract lock and all twelve locked members match at that target.
This successor proposes unknown readiness, never passing readiness; it leaves
the original blocked v1 generation intact. Coverage remains unknown and all
four original legacy-safe TDD postures and reasons are preserved verbatim.
Any future hold is preserved; the publisher refuses blocked sidecars.

## Authority boundary

The candidate anchor digest is only an observed pin. A human must verify it
against their own external allowed-signers file while reviewing the candidate.
Publication is not approval, ownership assignment, implementation admission or
merge authority. After planning publication reaches the target, request approval
for this exact generation with the actual owner and independent reviewer lane.
No old P1 approval or unsigned P5 v1 request can approve this new subject.
The candidate stays inert until the bound plan approval verifies. Use fresh
`admit-v2`, bundled local gates and independently signed review/certificate
records for each goal; no hand-written context or digest echo is accepted.

Preparation regression: `bash tests/xskp_p5_v2_successor_test.sh`.
Transition rationale: [xskp-p5-v2-transition.md](../../../.ai/handoff/xskp-p5-v2-transition.md).
