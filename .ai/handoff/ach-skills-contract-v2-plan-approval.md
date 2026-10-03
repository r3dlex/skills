# `ach-skills-contract-v2` plan approval: request only

This page is an **unsigned request**. It is not a `plan-approval/1`, an
approval tag, an admission or a merge authorization, and nothing in this
repository performs the approval. The raw output of the merged
`contract-run.sh approval-request` is in `.ai/handoff/ach-skills-contract-v2-plan-approval-request.json`, byte for byte.

## Subject

| Field | Value |
| --- | --- |
| Plan | `ach-skills-contract-v2`, goals `ACH-S-02`, `ACH-S-03`, `ACH-S-04`, `ACH-S-05`, `ACH-S-06` |
| Stages | `implementation`, `merge` |
| Generation (`generation_v2`) | `125d3861b973e96bda84d901b92a39f43a5c1e7b25243cd68c325f5297e10480` |
| Bundle (`goals.json`, canonical) | `d5421d893ff32ec146f8526c1fc2c74ff83a1aed3d127319a5fe2971e3b0bd23` |
| Spec (plan-scoped copy, generation 2) | `de32d160c698664ab7134dca13e2b36c4a7c4381275b767d97eac8f9a0803a61` |
| Policy candidate (skills `readiness-policy/2`, O3) | `9c2b748d620c5014f2fc3de8b6cbef6cff90205cc6af60cb8ed4c339bbb3d816` |
| Sidecar v0 (holds-only, no holds) | `f155f3976e193e0dcf625b27ec67ba5fc0a238586d8d1d67a55e0670df6748e6` |
| Trust anchor | `52c61dc5e6d406ea2654885281ec7464c8b6efece173ddf8ee5f2d7997294fb4` |
| Owner / reviewer lane | Andres Silva Burgstahler / independent agent review lane |
| Issued / expires | `2026-10-03T23:17:04Z` / `2026-10-17T23:17:04Z` |
| Tag | `approval/ach-skills-contract-v2/125d3861b973` |

Approving also approves the policy candidate (O3). It authorizes only the
implementation and merge stages of these five goals in this generation. Every
merge still needs its own `merge-certificate/1`, full green and an independent
review lane.

## When to approve

Approve only after both of these hold:
- this planning-input PR has merged on full green;
- every observed preparation check passes.

The tag must point at this PR's merge commit on `main`. The request ran
against a simulated `origin/main` at `b9ece3e723cedf148d6364d24ea20a588d703456`, the pre-merge head. A squash
merge does not keep that commit, so derive the merge commit first:

```sh
MERGE="$(git fetch -q origin && git log -1 --format=%H origin/main -- .ai/handoff/readiness-v2/ach-skills-contract-v2/125d3861b973e96bda84d901b92a39f43a5c1e7b25243cd68c325f5297e10480)"
```

## Form 1: in-session (`ASSURANCE: IN-SESSION`)

This is the form chosen for this plan.
- Record digest: `03f3d313517225213c044b3ad5c332050a8f3666053b84ed1c14b1333b4cf050`.
- The approval act is the user's explicit in-session confirmation of that
  digest.
- The record is agent-writable. It is always reported as `in-session` and
  never as `user-presence` (K2).

```sh
printf '%s\ndigest-echo: %s\n' '{"anchor_sha256":"52c61dc5e6d406ea2654885281ec7464c8b6efece173ddf8ee5f2d7997294fb4","assurance":"in-session","bundle_sha256":"d5421d893ff32ec146f8526c1fc2c74ff83a1aed3d127319a5fe2971e3b0bd23","expires_at":"2026-10-17T23:17:04Z","generation":"125d3861b973e96bda84d901b92a39f43a5c1e7b25243cd68c325f5297e10480","goals":["ACH-S-02","ACH-S-03","ACH-S-04","ACH-S-05","ACH-S-06"],"issued_at":"2026-10-03T23:17:04Z","owner":"Andres Silva Burgstahler","plan_id":"ach-skills-contract-v2","policy_sha256":"9c2b748d620c5014f2fc3de8b6cbef6cff90205cc6af60cb8ed4c339bbb3d816","reviewer_lane":"independent agent review lane","schema":"plan-approval/1","sidecar_sha256":"f155f3976e193e0dcf625b27ec67ba5fc0a238586d8d1d67a55e0670df6748e6","spec_sha256":"de32d160c698664ab7134dca13e2b36c4a7c4381275b767d97eac8f9a0803a61","stages":["implementation","merge"]}' 03f3d313517225213c044b3ad5c332050a8f3666053b84ed1c14b1333b4cf050 > approval.msg
git tag -a --cleanup=verbatim -F approval.msg approval/ach-skills-contract-v2/125d3861b973 "$MERGE"
git push origin refs/tags/approval/ach-skills-contract-v2/125d3861b973
```

## Form 2: SSH-signed tag (optional, `assurance: key-held`)

- Record digest: `5117f661f968855e4229bda97a0cb827316441be81c6a5aa4532c4db84e4df83`.
- Either approver principal can sign: `approver@human`
  (`~/.ssh/ai-catapult-approver`, ed25519) or `approver-rsa@human` (ssh-rsa).
  Neither is an `sk-` key, so the observed assurance is `key-held`, which
  matches the record.

```sh
printf '%s' '{"anchor_sha256":"52c61dc5e6d406ea2654885281ec7464c8b6efece173ddf8ee5f2d7997294fb4","assurance":"key-held","bundle_sha256":"d5421d893ff32ec146f8526c1fc2c74ff83a1aed3d127319a5fe2971e3b0bd23","expires_at":"2026-10-17T23:17:04Z","generation":"125d3861b973e96bda84d901b92a39f43a5c1e7b25243cd68c325f5297e10480","goals":["ACH-S-02","ACH-S-03","ACH-S-04","ACH-S-05","ACH-S-06"],"issued_at":"2026-10-03T23:17:04Z","owner":"Andres Silva Burgstahler","plan_id":"ach-skills-contract-v2","policy_sha256":"9c2b748d620c5014f2fc3de8b6cbef6cff90205cc6af60cb8ed4c339bbb3d816","reviewer_lane":"independent agent review lane","schema":"plan-approval/1","sidecar_sha256":"f155f3976e193e0dcf625b27ec67ba5fc0a238586d8d1d67a55e0670df6748e6","spec_sha256":"de32d160c698664ab7134dca13e2b36c4a7c4381275b767d97eac8f9a0803a61","stages":["implementation","merge"]}' > approval.json
ssh-keygen -Y sign -f ~/.ssh/ai-catapult-approver -n ai-catapult-plan-approval approval.json
printf '%s\nsignature: %s\n' "$(cat approval.json)" "$(base64 < approval.json.sig | tr -d '\n')" > approval.msg
git tag -a --cleanup=verbatim -F approval.msg approval/ach-skills-contract-v2/125d3861b973 "$MERGE"
git push origin refs/tags/approval/ach-skills-contract-v2/125d3861b973
```

## Expiry and recovery

- An approval tagged after `2026-10-17T23:17:04Z` is refused.
- Recovery is a new `approval-request` for the same generation. Its new
  `issued_at` gives a new digest, while the generation and sidecar v0 stay the
  same.
