# `ach-skills-contract-v2` plan approval: request only

This page is an **unsigned request**. It is not a `plan-approval/1`, an
approval tag, an admission or a merge authorization, and nothing in this
repository performs the approval.

`.ai/handoff/ach-skills-contract-v2-plan-approval-request.json` holds the output of the merged `contract-run.sh approval-request`
with one change: the tag target and `publication_commit` read `$MERGE` instead
of the pre-merge commit. The records and digests are unchanged.

## Subject

| Field | Value |
| --- | --- |
| Plan | `ach-skills-contract-v2`, goals `ACH-S-02`, `ACH-S-03`, `ACH-S-04`, `ACH-S-05`, `ACH-S-06` |
| Stages | `implementation`, `merge` |
| Generation (`generation_v2`) | `9b96709c9b0682524af8eba9094f7911f657d4b364b5f38788014f6927d71527` |
| Bundle (`goals.json`, canonical) | `5b6baa59ff13e603dbef4e04c820758854ef99090bcae601135c618323a17a1c` |
| Spec (plan-scoped copy, generation 2) | `ba7431dd22b71206ecb111fc05592941d33b24b54b080e973f28d16b341e020a` |
| Policy candidate (skills `readiness-policy/2`, O3) | `2ee17f06817e424dffdb30047f83b8e69805fe92d4771c21d1c4662092cb2176` |
| Sidecar v0 (holds-only, no holds) | `13da19aac9d1a99beb250e2157f27bc2046bbe6fd583d7cdedcf2833b629c3f4` |
| Trust anchor | `8b33406c8f2cfe54c0a4204f63ffa03e5c1a35aa0b648d0d3a7a35399ecb14f1` (see provenance below) |
| Owner / reviewer lane | Andres Silva Burgstahler / independent agent review lane |
| Issued / expires | `2026-10-04T07:57:44Z` / `2026-10-18T07:57:44Z` |
| Tag | `approval/ach-skills-contract-v2/9b96709c9b06` |

Approving also approves the policy candidate (O3). It authorizes only the
implementation and merge stages of these five goals in this generation. Every
merge still needs its own `merge-certificate/1`, full green and an independent
review lane.

**Anchor provenance.** The coordinating agent edited the anchor on 2026-10-04,
on the user's explicit instruction. That edit is a user-instructed exception
to R2, which ACH-S-02 records in ADR-0016.

It holds four principals, one line each:
- `approver@human` and `approver-rsa@human`: plan approval;
- `agent@autobahn`: review, certificate and agent approval (the certifier);
- `reviewer@autobahn`: review only (the independent review lane).

Check the digest against the anchor on this machine before approving.

**Bootstrap.** This generation bootstraps skills `readiness-policy/2`, so it
needs an in-session or ssh-tag approval. A v1 live policy accepts no
agent-self (rule d).

## Interim audit branches

From this PR's merge until ACH-S-02's route guard lands, the merged
`merge-authority.sh` refuses every non-goal `feat|fix|chore/<x>-<y>` head.
During that interval, name a host-policy audit PR
`audit/host-policy-skills-<PR>`. That name applies only when all of these hold:
- the diff is an append-only change to `.ai/host-policy/github/audit.jsonl`;
- every required check is green at the exact head;
- an independent review is recorded;
- the merge goes through `merge-authority.sh --pr <N> --verdict <file>`.

## When to approve

Approve only after both of these hold:
- this planning-input PR has merged on full green;
- every observed preparation check passes.

The tag must point at this PR's merge commit on `main`. The request ran
against a simulated `origin/main` at `fd47a792dee70c863b7fb47ce455cebcfd6519f6`, the pre-merge head. A squash
merge does not keep that commit, so derive the merge commit first:

```sh
MERGE="$(git fetch -q origin && git log -1 --format=%H origin/main -- .ai/handoff/readiness-v2/ach-skills-contract-v2/9b96709c9b0682524af8eba9094f7911f657d4b364b5f38788014f6927d71527)"
```

## Form 1: in-session (`ASSURANCE: IN-SESSION`)

This is the form chosen for this plan.
- Record digest: `08f355259b58f0838dc0429270de96d9c55fb8b3b7067b3ab76d08931dab7d7d`.
- The approval act is the user's explicit in-session confirmation of that
  digest.
- The record is agent-writable. It is always reported as `in-session` and
  never as `user-presence` (K2).

```sh
printf '%s\ndigest-echo: %s\n' '{"anchor_sha256":"8b33406c8f2cfe54c0a4204f63ffa03e5c1a35aa0b648d0d3a7a35399ecb14f1","assurance":"in-session","bundle_sha256":"5b6baa59ff13e603dbef4e04c820758854ef99090bcae601135c618323a17a1c","expires_at":"2026-10-18T07:57:44Z","generation":"9b96709c9b0682524af8eba9094f7911f657d4b364b5f38788014f6927d71527","goals":["ACH-S-02","ACH-S-03","ACH-S-04","ACH-S-05","ACH-S-06"],"issued_at":"2026-10-04T07:57:44Z","owner":"Andres Silva Burgstahler","plan_id":"ach-skills-contract-v2","policy_sha256":"2ee17f06817e424dffdb30047f83b8e69805fe92d4771c21d1c4662092cb2176","reviewer_lane":"independent agent review lane","schema":"plan-approval/1","sidecar_sha256":"13da19aac9d1a99beb250e2157f27bc2046bbe6fd583d7cdedcf2833b629c3f4","spec_sha256":"ba7431dd22b71206ecb111fc05592941d33b24b54b080e973f28d16b341e020a","stages":["implementation","merge"]}' 08f355259b58f0838dc0429270de96d9c55fb8b3b7067b3ab76d08931dab7d7d > approval.msg
git tag -a --cleanup=verbatim -F approval.msg approval/ach-skills-contract-v2/9b96709c9b06 "$MERGE"
git push origin refs/tags/approval/ach-skills-contract-v2/9b96709c9b06
```

## Form 2: SSH-signed tag (optional, `assurance: key-held`)

- Record digest: `a7b15e0839ddbb9ef4158ca31ad595d5b34da7fc4380e80a50cb90d1c2cd4075`.
- Either approver principal can sign: `approver@human`
  (`~/.ssh/ai-catapult-approver`, ed25519) or `approver-rsa@human` (ssh-rsa).
  Neither is an `sk-` key, so the observed assurance is `key-held`, which
  matches the record.

```sh
printf '%s' '{"anchor_sha256":"8b33406c8f2cfe54c0a4204f63ffa03e5c1a35aa0b648d0d3a7a35399ecb14f1","assurance":"key-held","bundle_sha256":"5b6baa59ff13e603dbef4e04c820758854ef99090bcae601135c618323a17a1c","expires_at":"2026-10-18T07:57:44Z","generation":"9b96709c9b0682524af8eba9094f7911f657d4b364b5f38788014f6927d71527","goals":["ACH-S-02","ACH-S-03","ACH-S-04","ACH-S-05","ACH-S-06"],"issued_at":"2026-10-04T07:57:44Z","owner":"Andres Silva Burgstahler","plan_id":"ach-skills-contract-v2","policy_sha256":"2ee17f06817e424dffdb30047f83b8e69805fe92d4771c21d1c4662092cb2176","reviewer_lane":"independent agent review lane","schema":"plan-approval/1","sidecar_sha256":"13da19aac9d1a99beb250e2157f27bc2046bbe6fd583d7cdedcf2833b629c3f4","spec_sha256":"ba7431dd22b71206ecb111fc05592941d33b24b54b080e973f28d16b341e020a","stages":["implementation","merge"]}' > approval.json
ssh-keygen -Y sign -f ~/.ssh/ai-catapult-approver -n ai-catapult-plan-approval approval.json
printf '%s\nsignature: %s\n' "$(cat approval.json)" "$(base64 < approval.json.sig | tr -d '\n')" > approval.msg
git tag -a --cleanup=verbatim -F approval.msg approval/ach-skills-contract-v2/9b96709c9b06 "$MERGE"
git push origin refs/tags/approval/ach-skills-contract-v2/9b96709c9b06
```

## Expiry and recovery

- An approval tagged after `2026-10-18T07:57:44Z` is refused.
- Recovery is a new `approval-request` for the same generation. Its new
  `issued_at` gives a new digest, while the generation and sidecar v0 stay the
  same.
