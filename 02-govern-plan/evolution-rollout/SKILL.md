---
name: evolution-rollout
description: 'Run one blind rollout of a skill under test in a wiki-stripped export, then record its trace. Use when the evolution loop executes a proposal.'
---

# Evolution rollout

One rollout is one execution of a skill under test against a task set; the
wiki is made unreachable by the environment, never by asking the agent to look away.

## Quick Start

1. Confirm the cycle has a frozen `D_val` and budget left (see *Economics*).
2. Build the wiki-stripped export with *The blindness sandbox* below.
3. Run the skill under test inside that export, one task at a time.
4. Write the trace to `evolve/raw/<run-id>/` in the home repo, write-once.
5. Hand the trace to `wiki-maintainer`; never write `evolve/wiki/` yourself.

## The blindness sandbox

A grep over the prompt proves nothing: the rollout can still read `evolve/wiki/` at runtime.
Blindness is an environment property, not a prompt discipline: the export below has no `evolve/` and no git history, so the wiki is unreachable even through `git log` or `git show`; the block is the whole procedure, and the blindness test runs it exactly.

```bash blindness-sandbox
# Fail closed before any write: an EXPORT that exists, overlaps SOURCE, or sits inside a git work tree — on physical paths — is refused, so the wiki is never touched and its history never reachable.
SOURCE="${SOURCE:?set SOURCE to the repository under rollout}"
EXPORT="${EXPORT:?set EXPORT to a disposable directory}"
if ! [ -d "$SOURCE" ]; then echo "refused: SOURCE is not a directory" >&2; exit 1; fi
if [ -e "$EXPORT" ]; then echo "refused: EXPORT already exists: $EXPORT" >&2; exit 1; fi
SRC_R="$(cd "$SOURCE" && pwd -P)"; EXP_D="$(dirname -- "$EXPORT")"
if ! [ -d "$EXP_D" ]; then echo "refused: EXPORT parent is not a directory: $EXP_D" >&2; exit 1; fi
EXP_R="$(cd "$EXP_D" && pwd -P)/$(basename -- "$EXPORT")"
if [ "$EXP_R" = "$SRC_R" ] || [ "${EXP_R#"$SRC_R"/}" != "$EXP_R" ] || [ "${SRC_R#"$EXP_R"/}" != "$SRC_R" ]; then echo "refused: EXPORT overlaps SOURCE: $EXPORT" >&2; exit 1; fi
p="$(dirname "$EXP_R")"; while [ "$p" != / ]; do if [ -e "$p/.git" ]; then echo "refused: EXPORT sits inside git history: $p/.git" >&2; exit 1; fi; p="$(dirname "$p")"; done
mkdir -p "$EXPORT"
# Snapshot the committed workload only: no .git, so history is unreachable.
git -C "$SOURCE" archive HEAD | tar -x -C "$EXPORT"   # blindness-sandbox:snapshot
# Path denial: no wiki path survives, tracked or not.
rm -rf "$EXPORT/evolve"                               # blindness-sandbox:denial
printf 'deny evolve/\ndeny .git/\n' > "$EXPORT/.blindness-policy"
# The export's only reader expands every component before entering it; a symlink hop is followed link step by link step, and any traversal or link that leaves the export is refused.
mkdir -p "$EXPORT/bin"
cat > "$EXPORT/bin/rollout-read" <<'ROLLOUT_READ'
#!/bin/bash
set -euo pipefail
root="${1:?usage: rollout-read <root> <relative-path>}"; target="${2-}"
d3() { echo "denied: $1" >&2; exit 3; }
case "$target" in /*|'') d3 "$target" ;; esac
base="$(cd -- "$root" 2>/dev/null && pwd -P)" || d3 "missing root: $root"
case "$target" in */*) dir="${target%/*}"; file="${target##*/}" ;; *) dir=""; file="$target" ;; esac
pend="$dir" hop="$base" hops=0
while [ -n "$pend" ]; do
  hops=$((hops + 1)); if [ "$hops" -gt 64 ]; then d3 "hop limit: $target"; fi
  case "$pend" in */*) c="${pend%%/*}"; pend="${pend#*/}" ;; *) c="$pend"; pend="" ;; esac
  case "$c" in ''|.) continue ;; ..) d3 "$target" ;; esac
  if [ -L "$hop/$c" ]; then t="$(readlink -- "$hop/$c")" || d3 "$target"; case "$t" in /*|'') d3 "$target" ;; esac; if [ -n "$pend" ]; then pend="$t/$pend"; else pend="$t"; fi
  else
    if ! hop="$(cd -- "$hop/$c" 2>/dev/null && pwd -P)"; then d3 "$target"; fi
    case "$hop" in "$base"|"$base"/*) ;; *) d3 "$target escapes the export" ;; esac
  fi
done
if [ -L "$hop/$file" ] || ! [ -f "$hop/$file" ]; then d3 "$target"; fi
cat "$hop/$file"
ROLLOUT_READ
chmod +x "$EXPORT/bin/rollout-read"
```

The rollout reads the tree only through `bin/rollout-read`: the policy and wrapper are the path denial, and the `rm -rf` removes a wiki file a commit already tracked.

## What a rollout records

Write to `evolve/raw/<run-id>/`, once. A run id is a slug plus a UTC timestamp, and a later run never rewrites an earlier run's directory.

- `judgment.json` — one judgment record per judge, bound to the candidate:
  `judgment_id`, `run_id`, `candidate_overlay_sha256`, `skill_under_test`,
  `task_set_id`, `task_set_version`, `judge_model`, `rubric_sha256`,
  `per_criterion_scores[]`, `weighted_aggregate`, `verdict`, `cost_usd`,
  `recorded_at`, `recorder`. The gate refuses a number unbound to the candidate
  hash, the task-set version or the judge model (`judgment_unbound`).
- `audit-entry.json` — metadata, target skill, unified diff, score,
  Accepted/Rejected.
- `transcript/` — the task runs as they happened.

The prompt-grep gate is a cheap pre-check before the export — every record says so; it never stands in for the sandbox.

## Economics

- **$100 per cycle** is the ceiling (user, 2026-10-04). Judges run out-of-band,
  so the loop sees spend only through records: a structural pre-reject drops a
  bad proposal before any judge call, and `evolve --validate` sums `cost_usd`
  and refuses past the ceiling (`cycle_budget_exhausted`). Unrecorded
  invocations are named as attribution gaps in the audit entry.
- **Judges are human and out-of-band** — the `eval-a-skill` model. CI proves the
  record exists; the judge proves quality.
- **Three samples plus majority** within the ceiling: a single judge on a small
  `D_val` drifts, so stop early only when the rubric's weighted aggregate hits its maximum.
- **`D_val` is frozen per cycle.** A task-set change is a new version, and its
  scores are never compared with another version's.

The WikiSkill paper is cited for the loop's shape alone and states no threshold; never cite it for one.

## Related

`wiki-maintainer` folds these traces into the wiki; `skill-proposer` turns an accepted pattern into one overlay; `eval-a-skill` owns the judge contract this procedure binds its records to.
