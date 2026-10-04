# ADR-0016: Git-native plan approval

- Status: Accepted for ACH-S-01 (readiness-contract/2); amended by ACH-S-02 (K3, K3b approval modes)
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
  certificates, never human approvals. Since K3 an agent that also holds
  `ai-catapult-agent-approval` may sign an `agent-self` approval (below).
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

The baseline `approval.accept` was `["ssh-tag", "in-session"]`, by user decision; K3 below
makes the init baseline `agent` mode.
That decision keeps an accepted risk open: an agent could author a policy,
approve it in-session and admin-merge on a `single`-identity repository. The
path stays visible and is never presented as user presence.

**Narrowing `accept` to `["ssh-tag"]` does not close agent self-approval.**
- The anchor and the agent keys sit under the same user's
  `~/.config/ai-catapult`. An agent running as that user can read keys there
  and can write the anchor itself.
- `key-held` therefore proves only that some key listed in some anchor signed.
  It does not prove that a human approved.
- The validator checks the anchor against the policy's `anchor_sha256`. That
  digest is only as trustworthy as the review that accepted it.
- A human must verify each policy candidate's `anchor_sha256` against the
  anchor they created, during the planning-input review, before the candidate
  merges.
- Only `user-presence` (an `sk-` hardware key with touch) evidences a person.

Anchor lines are selected by the public key that signed. Each principal must
appear on exactly one line, the anchor must not be a symlink, and it is read
once into a private copy.

### Approval modes (K3, amended 2026-10-04 by ACH-S-02)

The user decided on 2026-10-04 that agent self-approval is the default approval
mode. This amends U1 ("agent keys never sign approvals"):

- **Forms and modes.** `approval.accept` gains the `agent-self` form, and the
  optional `approval.default_mode` takes `agent`, `prompt` or `ssh-tag`. A
  `default_mode` whose form is not in `accept` is refused. A policy without
  `default_mode` keeps its earlier semantics. The init baseline is `agent` mode.
- **`agent` mode.** Autobahn issues the `plan-approval/1` itself. It signs the
  canonical record with the agent signing key under the distinct namespace
  `ai-catapult-agent-approval`, never the human `ai-catapult-plan-approval`. The
  same single unsigned annotated tag carries it, on an `agent-signature:` line.
  Only an anchor principal that holds `ai-catapult-agent-approval` and not
  `ai-catapult-plan-approval` may sign it (the agent-approval role).
- **`prompt` mode** admits only an explicit in-session human confirmation (the
  digest-echo record): never an agent-self record, and never an ssh-tag signature.
  `prompt` and `ssh-tag` modes may not list `agent-self` at all.
- **`ssh-tag` mode** is an optional opt-in. No default requires a signature.
- **Assurance.** `agent-self` is a fourth level, computed from the form and never
  upgraded. Every approval, admission report, certificate, merge decision,
  driver-log entry and `audit-merges` result carries it and prints
  `ASSURANCE: AGENT-SELF`. No code path renders it as `in-session`, `key-held`
  or `user-presence`, or any of those as `agent-self`.
- **The merge bar is unchanged** in every mode: a `merge-certificate/1` at one
  exact head, every required check SUCCESS, zero unresolved threads, an
  agent-signed independent review lane distinct from the certifier, admin only
  under `single`, and no text, flag, variable or mode that maps to a waiver.

**Rule (d).** A `policy-amendment` or bootstrap generation's approval form must
pass both the live policy's and the candidate's whole form rule (`accept` and
`default_mode`). A v1 or absent live
policy counts as an empty live list. An agent-self approval of a bootstrap
generation is therefore refused with `agent_self_bootstrap_refused`, and every
repository's first policy/2 needs an in-session or ssh-tag approval.

**K3b (user decision 2026-10-04, accepted risk).** Agent-self may also approve
bootstrap and policy-amendment generations, including changes to
`anchor_sha256`, `accept`, `default_mode` or required checks, but only when
agent-self is in both accept lists (rule d). Each such approval carries
`assurance: agent-self`, emits the notice `agent_self_policy_change` in the
admission and merge reports, and `audit-merges` lists it.

The accepted risks, recorded:
- An agent can approve a policy that drops a required check and then merge under
  it. The per-merge certificate bar above still applies to every merge.
- An agent-self anchor change can add approver lines whose keys the agent holds.
  This is the same class of risk as K1: a signature proves key possession, not a
  person.
- After a human-approved bootstrap policy goal merges, rule (d) lets agent-self
  re-approve a later amendment only if both accept lists contain agent-self.
  `agent_self_bootstrap_refused` does not cover that case.

**The 2026-10-04 anchor edits.** The coordinating agent edited
`~/.config/ai-catapult/allowed_signers` on 2026-10-04, on the user's explicit
instruction: it added `reviewer@autobahn` (`ai-catapult-review` only) and added
`ai-catapult-agent-approval` to `agent@autobahn`. That edit is a user-instructed
exception to R2 ("agents never write the anchor"). It is recorded here and on the
plan's approval page.

**Follow-ups, recorded only.**
- Only the user, or an agent on the user's explicit instruction (the 2026-10-04
  edits above), edits `~/.config/ai-catapult/allowed_signers`, and only before a
  generation binds it.
- The `ach-skills-contract-v2` generation binds an anchor that already holds a
  reviewer principal, `reviewer@autobahn` (`ai-catapult-review` only), distinct
  from the certifier `agent@autobahn`, which also holds
  `ai-catapult-agent-approval`.
- Strictly after ACH-S-06 merges and before any XSKP P5 approval, a
  `policy-amendment` generation moves skills to `default_mode: agent`, adding
  `agent-self` to `accept`. That amendment is approved in-session or by ssh-tag,
  because the live accept list does not yet contain agent-self (rule d). Every
  later plan or policy change can then be approved agent-self.
- The P5 generation that ACH-S-05 publishes is then republished against the
  amended policy.
- None of these is part of ACH-S-02.

**Bootstrap generations and amendments.** A bootstrap generation cannot recover by
re-signing once an amendment replaces the policy its candidate introduced: it
refuses with `bootstrap_policy_live`, so republish its unmerged goals as a live-mode
generation, or finish its bootstrap plans before any amendment. An amendment binds
the live digest it amends (`amends_policy_sha256`), so a second, concurrent
amendment refuses once the first lands.

## Consequences

- Two contract modules coexist until v1 retires. A shared core is extracted only
  after no v1 entry remains.
- Merge enforcement stays cooperative where branch protection allows admin
  bypass. The certificate and the re-observing `merge-authority.sh` prevent a
  merge without a valid certificate through autobahn. `audit-merges` detects one
  after the fact: no certificate, a non-agent signer, or a different certified
  head. Its timing checks arrive in a later goal.
- Any policy amendment changes `policy_sha256` and voids every approval in the
  repository. The recovery is to re-sign the same generation. ACH-S-02 adds the
  `policy-amendment` generation kind for this: one goal scoping the policy path,
  a candidate bound by one new approval verified under the candidate's anchor.
- Local gates and verification run PR code as the same user. That code can
  reach the gh keychain token and the agent signing key, so `gate_env`
  stripping is not a sandbox. Gate results are evidence about PR-controlled
  content; the independent review lane is the control.

## Verification

- `tests/readiness_v2_approval_test.py` covers both approval forms and every
  approval refusal of AC-2.
- `tests/readiness_v2_certificate_test.py` covers the certificate and the
  re-observing merge.
- `tests/readiness_v1_freeze_test.sh` proves that v1 bytes and outputs are
  unchanged.
- `tests/readiness_v2_approval_modes_test.py` covers the three modes, the
  agent-self form and its refusals, and assurance rendering (K3).
- `tests/readiness_v2_policy_amend_test.py` covers the amendment kind, rule (d)
  and K3b.
