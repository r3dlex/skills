---
name: evolution-rollout
description: 'Run one blind rollout of a skill under test in a wiki-stripped export, then record its trace. Use when the evolution loop executes a proposal.'
---

# Evolution rollout

One rollout is one execution of a skill under test against a task set, with the
wiki made unreachable — by the environment, never by asking the agent to look
away.

## Quick Start

1. Confirm the cycle has a frozen `D_val` and budget left (see *Economics*).
2. Build the wiki-stripped export with *The blindness sandbox* below.
3. Run the skill under test inside that export, one task at a time.
4. Write the trace to `evolve/raw/<run-id>/` in the home repo, write-once.
5. Hand the trace to `wiki-maintainer`; never write `evolve/wiki/` yourself.

## The blindness sandbox

A grep over the prompt proves nothing: the rollout can still read
`evolve/wiki/` at runtime. Blindness is an environment property, so the rollout
runs in an export that has no `evolve/` and no git history, making the wiki
unreachable even through `git log` or `git show`. The block below is the whole
procedure, and the blindness test executes exactly these commands, so the proof
and the procedure cannot drift.

```bash blindness-sandbox
# Build a wiki-stripped rollout export. SOURCE is the repo under rollout; EXPORT
# is a disposable directory the rollout owns for the run.
SOURCE="${SOURCE:?set SOURCE to the repository under rollout}"
EXPORT="${EXPORT:?set EXPORT to a disposable directory}"
test -d "$SOURCE" && test ! -e "$EXPORT" && mkdir -p "$EXPORT"
# Snapshot the committed workload only: no .git, so history is unreachable.
git -C "$SOURCE" archive HEAD | tar -x -C "$EXPORT"   # blindness-sandbox:snapshot
# Path denial: no wiki path survives, tracked or not.
rm -rf "$EXPORT/evolve"                               # blindness-sandbox:denial
printf 'deny evolve/\ndeny .git/\n' > "$EXPORT/.blindness-policy"
# The export's only reader refuses a denied prefix before it opens anything.
mkdir -p "$EXPORT/bin"
cat > "$EXPORT/bin/rollout-read" <<'ROLLOUT_READ'
#!/bin/bash
set -euo pipefail
root="${1:?usage: rollout-read <root> <relative-path>}"; target="${2:?}"
case "${target#./}" in
  evolve/*|.git/*|*/.git/*|../*) echo "denied: $target" >&2; exit 3 ;;
esac
cat "$root/${target#./}"
ROLLOUT_READ
chmod +x "$EXPORT/bin/rollout-read"
```

The rollout reads the tree only through `bin/rollout-read`. `.blindness-policy`
and that wrapper are the path denial; the `rm -rf` is what removes a wiki file a
commit already tracked.

## What a rollout records

Write to `evolve/raw/<run-id>/`, once. A run id is a slug plus a UTC timestamp,
and a later run never rewrites an earlier run's directory.

- `judgment.json` — one judgment record per judge, bound to the candidate:
  `judgment_id`, `run_id`, `candidate_overlay_sha256`, `skill_under_test`,
  `task_set_id`, `task_set_version`, `judge_model`, `rubric_sha256`,
  `per_criterion_scores[]`, `weighted_aggregate`, `verdict`, `cost_usd`,
  `recorded_at`, `recorder`. The gate refuses a number unbound to the candidate
  hash, the task-set version or the judge model (`judgment_unbound`).
- `audit-entry.json` — metadata, target skill, unified diff, score,
  Accepted/Rejected.
- `transcript/` — the task runs as they happened.

The prompt-grep gate is a cheap pre-check before the export, and every record
says so. It never stands in for the sandbox.

## Economics

- **$100 per cycle** is the ceiling (user, 2026-10-04). Judges run out-of-band,
  so the loop sees spend only through records: a structural pre-reject drops a
  bad proposal before any judge call, and `evolve --validate` sums `cost_usd`
  and refuses to dispatch or accept past the ceiling
  (`cycle_budget_exhausted`). Unrecorded invocations are named as attribution
  gaps in the audit entry.
- **Judges are human and out-of-band** — the `eval-a-skill` model. CI proves the
  record exists; the judge proves quality.
- **Three samples plus majority** within the ceiling: a single judge on a small
  `D_val` drifts. Stop early only when the rubric's weighted aggregate reaches
  its maximum.
- **`D_val` is frozen per cycle.** A task-set change is a new version, and its
  scores are never compared with another version's.

The WikiSkill paper is cited for the loop's shape alone. It states no
complexity, lint, type or coverage threshold; never cite it for one.

## Related

`wiki-maintainer` folds these traces into the wiki; `skill-proposer` turns an
accepted pattern into one overlay; `eval-a-skill` owns the rubric-and-judge
contract this procedure binds its records to.
