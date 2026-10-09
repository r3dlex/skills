---
name: wiki-maintainer
description: 'Consolidate rollout traces into an append-only wiki of logs and skill impact. Use when the evolution loop has new runs to fold in.'
---

# Wiki maintainer

The wiki is the loop's long-term memory: the patterns it has learned, distilled
from raw runs into words someone can act on. Consolidating is a write-only
append — the wiki is never rolled back, not even when the proposal it describes
is rejected.

## Quick Start

1. List `evolve/raw/<run-id>/` and find runs with no entry yet in
   `evolve/wiki/logs.md`.
2. Read each trace; never move, rewrite or delete it.
3. Append one audit entry per run to `evolve/wiki/logs.md`.
4. When a run's verdict lands, append a skill-impact entry to
   `evolve/wiki/skill-impact.md`.
5. Stop when every trace is folded in. Consolidation is not a proposal: leave
   `evolve/proposals/` to `skill-proposer`.

## The two append-only files

`evolve/wiki/logs.md` is the run log, one entry per rollout, in run order. Each
entry is the audit entry: metadata, the target skill, the unified diff, the
score, and the verdict — Accepted or Rejected. An entry is appended once and
never edited; a correction is a new entry that cites the one it corrects.

`evolve/wiki/skill-impact.md` is the per-skill view: for each skill under test,
what the runs say has changed about how it behaves, and which accepted overlays
in `evolve/proposals/` account for it. It restates nothing from `logs.md` — it
links to run ids and adds only the pattern.

Append-only is also the reject path. A rejected proposal drops its overlay; its
wiki entries stay, because the learning is the point of the cycle, not the
verdict.

## What an entry needs

An entry carries numbers only from a judgment record, and only one that is
bound: `judgment_id`, `run_id`, `candidate_overlay_sha256`, `skill_under_test`,
`task_set_id`, `task_set_version`, `judge_model`, `rubric_sha256`,
`per_criterion_scores[]`, `weighted_aggregate`, `verdict`, `cost_usd`,
`recorded_at`, `recorder`. A record missing any binding is not a number to fold
in — it is an attribution gap to name in the entry.

## Rules

- **Append, never rewrite.** No line of `logs.md` or `skill-impact.md` is
  edited or deleted, and the wiki is never reverted with the code.
- **Never mutate a skill.** `skills/` is the source of truth; a change lives in
  an `evolve/proposals/` overlay until it is accepted, upstreamed as an atomic
  single-skill change and lock-bumped.
- **Trace the trace.** Every entry names the `run-id` it came from, so a reader
  can always walk back from a pattern to the runs that produced it.
- **Read the tree through the sandbox reader** when the maintainer runs inside a
  rollout export; the wiki itself is written only in the home repo.

## Economics

- **$100 per cycle** is the ceiling (user, 2026-10-04). The maintainer spends
  nothing itself, but it is where spend becomes visible: the per-cycle sum over
  recorded `cost_usd` is read from these entries, and a cycle at the ceiling
  accepts nothing further (`cycle_budget_exhausted`).
- **Judges are human and out-of-band**, the `eval-a-skill` model. The maintainer
  records their verdicts; it never re-judges a run to fill a gap.
- **No threshold comes from the WikiSkill paper.** It is cited for the wiki's
  shape; it states no complexity, lint, type or coverage value.

## Related

`evolution-rollout` produces the traces read here; `skill-proposer` consumes the
patterns written here; `eval-a-skill` owns the judgment contract the entries
quote.
