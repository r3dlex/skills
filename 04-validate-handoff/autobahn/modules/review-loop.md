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

A PR is mergeable only when ALL hold (the feedback merge protocol):

- every review comment is resolved,
- **remote host CI is green** (the hosted check run on the PR), and
- **local CI is green** (the repo's offline test suite).

A red or pending CI run — remote or local — holds the merge. The gate is
fail-closed: absence of a green signal is treated as not-green, never assumed
passing.

## What autobahn owns vs delegates

Autobahn sequences the loop and reads the CI/review status; the review judgment
belongs to `architect`/`code-reviewer`, the CI verdict belongs to the host and the
local suite. Autobahn never fabricates an approval or a green check.

## Safety rules

- Never self-approve: review happens in a lane separate from authoring.
- Never merge with an open comment or a non-green CI signal.
- Treat missing/pending CI as not-green (fail-closed).
