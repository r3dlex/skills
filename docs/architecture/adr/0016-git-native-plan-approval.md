# ADR-0016: Git-native plan approval

- Status: Accepted for ACH-S-01 (readiness-contract/2)
- Date: 2026-10-03
- Amends: [ADR-0014](0014-versioned-readiness-transfer.md), clause "No signing platform or generic policy expression engine is introduced"
- Specification: `ACH-20261002` (umbrella sha256 `fded0858d0c3aa2ba06cdc9b6d716053cb92dd82a3afa22e6a13774e30f6ddd5`), decisions U1–U3, R2, R2b, K1, K2, G1–G3, O1–O4, O7, O9

## Context

ADR-0014 made readiness transfer explicit. It also kept authority outside the
contract: contexts are supplied by an "independent authority adapter", and JSON
labels authenticate nothing. In practice agents hand-wrote those contexts,
every readiness flip invalidated approval pins, and `merge-authority.sh` merged
on any verdict file. "Proceed" could therefore skip steps (spec problems P2,
P3 and P7).

## Decision

**The RT-02 approval adapter is git-native SSH signature verification.**

- A plan approval is a canonical `plan-approval/1` record over the content-only
  `generation_v2` (bundle, spec, policy and anchor digests) and the `sidecar_v0`
  digest. It is carried by one unsigned annotated tag,
  `approval/<plan_id>/<generation[0:12]>`, that is pushed to origin.
- The signature is detached: `ssh-keygen -Y sign -n ai-catapult-plan-approval`.
  `ssh-keygen -Y verify` checks it against the machine-local trust anchor
  `~/.config/ai-catapult/allowed_signers`.
- Agents never write the anchor. The validator refuses an anchor inside any git
  worktree, or one whose sha256 differs from the policy's `anchor_sha256`.
- Principal roles come from the anchor's `namespaces=` option. Approvers hold
  `ai-catapult-plan-approval`. Agents hold `ai-catapult-review` and
  `ai-catapult-certificate`, so they can sign review records and merge
  certificates, never approvals.
- No service, key-management system or second identity is added. The human
  creates the keys and the anchor.

This replaces ADR-0014's "no signing platform" clause for readiness-contract/2
only. v1 is unchanged, and its bytes and outputs are frozen. A pure validator
(`readiness_contract_v2.py`) decides from facts. A pinned read-only observer
(`observer.py`) gathers those facts and re-observes them at merge time.

### Assurance (K1, K2)

Key presence is not enforced: agents can reach `SSH_AUTH_SOCK`. A signature
therefore proves possession of an approver key, not human presence. Every
approval, admission report, merge certificate, merge decision and driver-log
entry carries `assurance`:

| Assurance | When |
| --- | --- |
| `user-presence` | an `sk-` key whose anchor line lacks `no-touch-required` |
| `key-held` | any other approver key, including an `sk-` key with `no-touch-required` |
| `in-session` | the recorded digest-echo fallback; agent-writable, no signature |

Assurance is computed from the anchor and never upgraded. No code path renders
`in-session` or `key-held` as `user-presence`, and reports print
`ASSURANCE: IN-SESSION` prominently.

The baseline `approval.accept` is `["ssh-tag", "in-session"]`, by user decision.
That decision keeps an accepted risk open: an agent could author a policy,
approve it in-session and admin-merge on a `single`-identity repository. The
path stays visible and is never presented as user presence. A repository closes
it by narrowing `accept` to `["ssh-tag"]`.

## Consequences

- Two contract modules coexist until v1 retires. A shared core is extracted only
  after no v1 entry remains.
- Merge enforcement stays cooperative where branch protection allows admin
  bypass. The certificate, the re-observing `merge-authority.sh` and, in a later
  goal, `audit-merges` detect a merge without a valid certificate.
- Any policy amendment changes `policy_sha256` and voids every approval in the
  repository. The recovery is to re-sign the same generation.

## Verification

- `tests/readiness_v2_approval_test.py` covers both approval forms and every
  approval refusal of AC-2.
- `tests/readiness_v2_certificate_test.py` covers the certificate and the
  re-observing merge.
- `tests/readiness_v1_freeze_test.sh` proves that v1 bytes and outputs are
  unchanged.
