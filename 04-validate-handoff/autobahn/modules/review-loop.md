# Peer-Review Loop + CI Gate

Read when reviewing and gating a goal's PR. Autobahn keeps authoring and review in
separate lanes and never self-approves; it delegates to the review agents and the
host CI rather than reimplementing review logic.

## The loop

Each goal's PR runs an `architect` + `code-reviewer` + `executor` loop:

1. `executor` implements the goal (via the picked engine).
2. `architect` reviews for design/architecture soundness.
3. `code-reviewer` reviews for correctness, style, and defects.
4. The executor resolves every comment.
5. Repeat until **all comments are resolved** — no open threads remain.

Authoring (executor) and review (architect, code-reviewer) are separate lanes.
The agent that wrote the change never approves its own work in the same lane.

## CI gate (feedback merge protocol)

A PR is mergeable only when ALL hold:

- every review comment is resolved,
- current host policy has been read successfully and every required hosted check is green for the exact PR head SHA,
- the strictly supported local command subset has passed before commit and again before merge after review changes, and
- the goal record's allowlisted `verification[]` has passed before merge.

`local-ci.sh` does not reproduce the hosted workflow. It accepts only the narrow GitHub workflow and command shapes documented in [ci-gate.md](ci-gate.md). Unsupported workflow context, no runnable admitted commands, malformed structure, an unallowlisted command, or a nonzero command leaves local evidence undetermined or failed and blocks the goal. A separately recorded `verification[]` remains required, but it does not convert an unsupported workflow into a green derived-CI signal.

A red, pending, missing, skipped, stale-SHA, or undetermined signal holds the merge. Supporting local evidence never substitutes for exact-head hosted checks or current host-policy authorization.

## What autobahn owns vs delegates

Autobahn sequences the loop and reads the CI/review status; the review judgment
belongs to `architect`/`code-reviewer`, the CI verdict belongs to the host and the
local suite. Autobahn never fabricates an approval or a green check.

## Safety rules

- Never self-approve: review happens in a lane separate from authoring.
- Never merge with an open comment or a non-green CI signal.
- Treat missing/pending CI as not-green (fail-closed).
