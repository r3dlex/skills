# Plan approval (readiness-contract/2)

Read after a v2 planning PR merges, when a published generation needs its approval.

## Plan approval is not Spec approval

- **Plan approval** is one `plan-approval/1` record for one published generation,
  carried by exactly one annotated tag `approval/<plan_id>/<generation[0:12]>`. It
  authorizes implementation and merge of every goal in that generation, and nothing else.
- **Spec approval** is a review of the specification text. It remains not a state:
  no file, tag or field records it, and no gate reads it. A spec copy is bound by its
  digest inside the generation, so the plan approval covers exactly the reviewed bytes.

## approve.sh

```sh
bash northstar/approve.sh --root /repo --handoff northstar-plan-<id> --owner <owner> --reviewer-lane <lane> [--mode <mode>]
bash northstar/approve.sh --root /repo --handoff northstar-plan-<id> --confirm <digest>
```

Owner and reviewer lane are recorded once, in the approval record. `--root` is the
physical path (`pwd -P`). Without `--mode`, the mode is the governing policy's
`default_mode`, else agent. A policy-amendment is governed by the live policy; a
bootstrap is governed by none.

| Mode | Use | Prints |
| --- | --- | --- |
| `agent` mode | the default | An `agent-self` approval signed with the agent key under `ai-catapult-agent-approval`, its tag message and the `git tag` and `git push` commands. |
| `prompt` mode | only when the user explicitly asks for it | The `plan-approval/1` digest, the anchor sha256 and one human action: ask the user to confirm that digest in chat. |
| `ssh-tag` mode | optional | The `ssh-keygen -Y sign -n ai-catapult-plan-approval` command for a human approver key, and the unsigned annotated tag (`git tag -a`) and push commands. |

Prompt mode takes two steps:

1. `approve.sh --root R --handoff H --owner O --reviewer-lane L --mode prompt` prints the
   digest and stores the request in observer state under the git common directory.
2. After the user confirms that exact digest in chat, `approve.sh --root R --handoff H
   --confirm <digest>` prints the in-session digest-echo tag message, labelled
   `ASSURANCE: IN-SESSION`, and the tag commands. A changed generation, sidecar or
   policy, or an expired request, refuses with `approval_confirmation_stale`.

Bootstrap generations (every repository's first readiness-policy/2) need an in-session or
ssh-tag approval (rule d): a v1 or absent live policy accepts no agent-self. A
policy-amendment approval must also pass the live policy's form rule.

## What approve.sh never does

- It never signs with an approver key: only the agent mode signs, with the agent key,
  and an anchor line holding `ai-catapult-plan-approval` is refused
  (`agent_approval_signer_not_agent`) before anything is signed.
- It never writes the anchor, never writes or pushes a tag, and never reads a terminal.
  The agent runs the printed tag commands; the tag is the only approval.

## Assurance

The assurance is computed from the tag and never upgraded:

- `user-presence`: an `sk-` approver key whose anchor line lacks `no-touch-required`;
- `key-held`: any other approver key;
- `in-session`: the digest-echo record, printed as `ASSURANCE: IN-SESSION`;
- `agent-self`: the agent-mode approval, printed as `ASSURANCE: AGENT-SELF`.

## Anchor setup (human only)

With no anchor, approve.sh exits 1 with `anchor_missing` and prints these steps.
Agents never write the anchor.

1. Create a human-only approver key: `ssh-keygen -t ed25519-sk` (or `ssh-keygen -t ed25519`, key-held).
2. Write `~/.config/ai-catapult/allowed_signers`, outside every git worktree, one
   line per principal with its `namespaces=` roles:
   - approver: `namespaces="ai-catapult-plan-approval"`;
   - certifier: `namespaces="ai-catapult-review,ai-catapult-certificate"`, plus
     `ai-catapult-agent-approval` only for agent mode;
   - reviewer: `namespaces="ai-catapult-review"`, a principal distinct from the certifier.
3. Record `shasum -a 256 ~/.config/ai-catapult/allowed_signers` as
   `approval.anchor_sha256` through a reviewed policy goal.

Planning admission names an anchor that cannot satisfy an accepted approval form, or
that holds no distinct certifier and reviewer, as `anchor_role_capability_missing`.
See [readiness-v2.md](../../../04-validate-handoff/autobahn/modules/readiness-v2.md#plan-approval)
for verification.
