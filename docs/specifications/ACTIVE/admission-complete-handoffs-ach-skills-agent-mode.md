# Skills plan `ach-skills-agent-mode` — plan-scoped specification (planning copy)

Plan-scoped specification copy for the skills post-S-06 policy amendment (one
`policy-amendment` generation). Bound by the plan approval once issued; until then it is a free
planning path. It never amends the umbrella spec (root #95 L5; umbrella sha256
`e6feb698bde18356f0d49c497b7f368f242f39bc254b12942f7f1902408cee39`).

## Purpose

One `policy-amendment` generation moves skills to `default_mode: agent` and adds `agent-self`
to `approval.accept` (D-ACCEPT variant a). After it merges, every later skills plan (D1
`ach-skills-gate-workspace`, the hardening plan) and the P5 republish
(`xskp-p5-skill-producers`) is approved **agent-self**; until it merges, nothing else gets
approved in skills (HANDOFF §6 Phase B, the freeze).

## The candidate (D-ACCEPT variant a)

The generation's `policy-candidate.json` is the live policy
`.ai/policies/readiness-policy.json` (`readiness-policy/2`, sha256
`2ee17f06817e424dffdb30047f83b8e69805fe92d4771c21d1c4662092cb2176`) with exactly two edits,
everything else byte-identical:

- `approval.accept` becomes `["agent-self", "ssh-tag", "in-session"]`;
- `approval.default_mode` becomes `"agent"`.

Unchanged: `identity_model: single`, the same `anchor_sha256 8b33406c…`,
`max_age_days: 14`, `required_checks`, `skippable_checks`, `sources`, `tools`, `gates`,
`branch_pattern`, `target`. The candidate never changes `branch_pattern`
(`branch_pattern_change_refused`, M4: routing reads the live pattern).

## Goal

- **ACH-AM-01** — scope: only `.ai/policies/readiness-policy.json`; verification
  `["bash tests/run-tests.sh", "git diff --check"]`.

Acceptance criteria (bound text):

1. [D-ACCEPT variant a] The merged `.ai/policies/readiness-policy.json` bytes equal the
   generation's `policy-candidate.json` — the live policy `2ee17f06…` with exactly the two
   edits above and every other byte unchanged.
2. [M4] The candidate keeps the live `branch_pattern` byte-identical; any change is refused
   with `branch_pattern_change_refused`.
3. [M1] The registry entry records `amends_policy_sha256 = 2ee17f06…`; the generation id binds
   it; admission refuses `amendment_base_moved` if any other policy change lands first.
4. [rule (d)] This amendment's own approval is in-session or ssh-tag; agent-self is refused
   (`approval_form_not_in_live_policy`) while the live accept list lacks agent-self; the
   candidate's own `default_mode` never governs its own approval.
5. [K3b] After the merge, agent-self is admissible for later skills generations and later
   amendments; every agent-self approval is reported agent-self, never upgraded; agent-self
   approvals of policy changes emit `agent_self_policy_change`.

## Approval and merge

- The approval request runs `approve.sh --mode prompt` (explicit — without it the default
  resolves to agent and refuses under rule (d)). The user confirms the exact printed digest in
  chat (in-session); a general "continue" is not a confirmation.
- The goal merges through the certified v2 lane: worktree from `origin/main`, admission, TDD
  red→green, local checks, gate-driver pre-commit from a base copy, PR, two independent review
  lanes, signed review record, certify from a pristine PR-head checkout,
  `merge-authority.sh --pr <n> --admin` (admin honoured under `identity_model: single`),
  post-merge backup and §9 log.
- The certificate additionally proves the head policy bytes equal the bound candidate digest
  (`bootstrap_certificate_gaps`).

## What the merge changes (informational)

1. Every other approval in the repository is voided: approval records bind `policy_sha256`
   against the current live policy digest (`approval_policy_mismatch`).
2. S-02..S-06 certificates remain valid audit records (the audit verifies the certificate
   signature against the anchor, not the approval against the live policy).
3. The P5 generation (`xskp-p5-skill-producers`, `6a211a9c…`) is republished against the
   amended policy and only then approved agent-self (bound mandate: gen2 spec 146-147,
   ADR-0016).
4. 14-day windows: the amendment approval's `expires_at` bounds its goal's certify+merge.
5. `amendment_base_moved`: any other policy change between publication and merge refuses
   admission; the amendment must be republished (the freeze prevents this in practice).
