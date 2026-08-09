# Autobahn Commit + PR Protocol

Read before committing a goal. The per-goal sequence ran Implement → Peer-review
→ CI → Merge with **nothing in it that creates the PR being reviewed**. The step
was assumed rather than specified, which is also why the lint and CI gates had
no seam to attach to. This is that seam.

## Branch naming

One branch per goal, cut from the current `main`:

```
<type>/<slug>-<goal-id>
```

`type` matches the change (`feat`, `fix`, `chore`, `docs`, `refactor`); `slug` is
a few words from the goal's title in glossary terms. Never reuse a branch across
goals — a branch that outlives its goal accumulates diff that belongs to neither.

## One goal per diff

Stage explicitly. `git add -A` sweeps up whatever else the working tree
accumulated — evidence files, scratch output, another goal's half-finished edit —
and the reviewer then reviews a diff nobody assembled deliberately.

- Stage the paths this goal changed, then read back `git status --short` and
  `git diff --cached --stat` before committing.
- Regenerated artifacts belong in the same commit as the change that moved them,
  never in a follow-up.
- If the staged diff contains a file the goal does not explain, that file is
  either missing from the goal's scope or does not belong in the PR. Resolve it
  before committing; do not commit and explain afterwards.

## Commit messages

`CONTEXT.md` is the authoritative glossary, and it binds agent output: issue
titles, PR descriptions, commit messages and ADRs use glossary terms, never
synonyms. A message that renames a concept the glossary already fixed makes the
history unsearchable by the vocabulary the rest of the repo uses.

- Subject: `<type>(<scope>): <what changed>`, imperative, glossary terms.
- Body: why the change was needed and what was rejected — the reasoning a
  reviewer cannot reconstruct from the diff. Not a restatement of the diff.
- Record what the change does **not** do when a reviewer would otherwise assume
  it does.

## PR creation

The goal's PR is created here, before review — a review step that runs first is
reviewing something that does not exist.

1. Push the branch.
2. Create the PR with the goal id and the acceptance criteria it claims to meet.
3. Include the local verification actually run, with its result. Claimed
   verification is worse than none: it reads as evidence.

Only then does the peer-review loop start.

## Local CI

"Local CI green" was an undefined noun in [review-loop.md](review-loop.md): it
named no commands, so it could be satisfied by whatever the agent happened to
run. It means the repo's own CI commands, executed locally, before the PR is
opened.

Resolve them in this order and record which applied:

1. The commands the repo's CI workflows run (derivation lands with the CI gate).
2. Failing that, the repo's documented test entry point — its `AGENTS.md`,
   `CONTRIBUTING.md`, or the test script in its manifest.

If neither resolves, the local CI signal **cannot be determined**, and an
undetermined signal blocks the goal. It is never treated as green: a repo whose
tests could not be found is exactly the repo where assuming success is worst.

## Safety rules

- Never open a PR for more than one sliced goal.
- Never stage with a blanket add; stage paths and read back the staged diff.
- Never report verification that was not run.
- Never treat an undetermined local CI signal as green.
