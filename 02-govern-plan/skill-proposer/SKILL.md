---
name: skill-proposer
description: 'Turn a wiki-supported pattern into one atomic single-skill proposal overlay. Use when the loop has evidence for a change and must not edit the catalog in place.'
---

# Skill proposer

The proposer is the loop's only writer, and it writes exactly one thing: an
overlay for **one** skill, parked in `evolve/proposals/` until a gate accepts
it. It never edits a skill where the skill lives.

## Quick Start

1. Read `evolve/wiki/skill-impact.md` and pick the single skill with the
   strongest recorded evidence.
2. Create `evolve/proposals/<slug>/` — `PURPOSE.md` first: what changes, why,
   and which run ids support it.
3. Copy the skill's current files into the overlay and edit them there.
4. Attach the rubric and the judgment records that would decide the change.
5. Submit to `evolve --validate`. Accepted, the overlay is upstreamed as one
   atomic single-skill change and lock-bumped; rejected, the overlay is dropped
   and the wiki keeps its entries.

## One skill, one overlay

`evolve/proposals/<slug>/PURPOSE.md` states the intent in prose: the skill under
test, the behaviour that should change, and the runs that say so. The overlay
then holds the changed files at their skill-relative paths, so applying it is a
copy, not a merge — and so a reviewer reads the whole of the change in one
place.

Atomic single-skill is a hard rule, not a style. Two skills in one overlay
cannot be accepted, reverted or lock-bumped independently, and a rollback would
have to reason about a partial application. If two skills need the same change,
that is two overlays and two cycles.

In-place mutation is forbidden. The proposer writes only under `evolve/`. The
change reaches the catalog the way any other change does: an atomic
single-skill change upstream in the skills source of truth, a lock bump of the
pinned vendor copy, then a revendor and payload rebuild. An overlay that edits
a `SKILL.md` at its catalog path has already broken the loop.

## What a proposal is judged on

A proposal carries its rubric and the judgment records that decide it, each
bound to the candidate: `judgment_id`, `run_id`, `candidate_overlay_sha256`,
`skill_under_test`, `task_set_id`, `task_set_version`, `judge_model`,
`rubric_sha256`, `per_criterion_scores[]`, `weighted_aggregate`, `verdict`,
`cost_usd`, `recorded_at`, `recorder`. The gate refuses a number that is not
bound to the candidate hash, the task-set version and the judge model
(`judgment_unbound`).

Every proposal is also read structurally **before** any judge is called:
complexity, lint and frontmatter findings on the proposed skill files are
collected first, and a proposal that fails them is rejected with zero judge
spend. A proposal that cites the WikiSkill paper for a complexity, lint, type or
coverage threshold is citing a source that states none. Keep the advisory
frontmatter findings advisory: they are findings, never a blocker.

## Economics

- **$100 per cycle** is the ceiling (user, 2026-10-04), enforced twice: the
  structural pre-reject above happens before spend, and `evolve --validate`
  refuses to dispatch or accept once recorded `cost_usd` reaches it
  (`cycle_budget_exhausted`). An invocation with no recorded cost is an
  attribution gap, and the audit entry says so.
- **Judges are human and out-of-band**, the `eval-a-skill` model. The proposer
  never scores its own overlay.
- **Early stop** only when the rubric's weighted aggregate is at its maximum;
  otherwise accept iff the candidate's aggregate beats the seeded best.

## Related

`wiki-maintainer` supplies the patterns; `evolution-rollout` produced the runs
behind them; `write-a-skill` owns the structure of the skill a proposal changes.
