---
name: ask-ai-catapult
description: 'Ask which skill or flow fits your situation. Use when you know what you want to achieve but not which skills to combine, or which order to run them in.'
---

# Ask ai-catapult

Recommend a **combination** of skills for the situation described — not a single answer, and
not a fixed script. Enumerate what is actually installed, map it to the use case, then
propose a sequence with reasons.

## How to route

1. **Detect the harness.** Claude Code and Codex expose different ecosystems. Establish
   which one you are running under before recommending anything from tier 2.
2. **Enumerate what is actually available.** Query the catalog for tier 1
   ([CATALOG.md](CATALOG.md) is the generated inventory); for tiers 2 and 3, look at what is
   genuinely installed in this environment. **Never name a skill you have not confirmed
   exists** — a confident pointer to a missing skill is worse than no pointer.
3. **Map the use case to a phase**, then to skills within it.
4. **Propose a sequence**, with one line of reasoning per step and the decision points
   called out. Say what you would skip, and why.

## The three tiers

**Tier 1 — the ai-catapult catalog.** The SDLC spine: discover → govern/plan →
configure/generate → validate/handoff. Always present. Prefer these for the phase work
itself.

**Tier 2 — the host ecosystem, resolved at runtime.** Under Claude Code that is
oh-my-claudecode; under Codex, oh-my-codex. These are **orchestration and execution
accelerators layered on top of** the spine, never replacements for it. Both are optional —
ai-catapult ships to users who have neither, so their absence must degrade gracefully rather
than produce dead references.

Route by capability, not by name, since these ecosystems version independently of this
catalog and any roster written down here would rot:

- Need parallel execution across independent tasks → look for an orchestration skill.
- Need persistence across a long multi-session effort → look for a durable-loop skill.
- Need an independent review or verification lane → look for a review or verify skill.
- Need deep multi-file search → look for a codebase-search skill.

**Tier 3 — anything else installed.** Use opportunistically when it fits better than tier 1
or 2.

## Two flows, deliberately

This catalog has **two** intake→ship paths. Say which one applies rather than presenting
both as equally canonical:

- **`northstar` → `autobahn`** is the **governed spine**. Use it when the work needs a
  tracked A→B handoff, consensus planning, sliced goals, and a merge gate — multi-PR efforts,
  anything with review and CI requirements. It is the default for substantial work.
- **`to-spec` → `to-tickets` → `implement`** is the **lighter path**. Use it when the
  decisions are already made and the work just needs specifying and building, without the
  handoff and merge-authority machinery.

Both end in `code-review`. Choosing between them is the single most useful thing this skill
does — ask how much governance the effort actually needs.

## On-ramps

Route by where the user actually is, not where a tidy process would start them:

- Something is broken, slow, or throwing → `diagnosing-bugs`.
- A pile of untriaged issues → `triage`.
- Work too big to hold in one session, and the route is not yet visible → `wayfinder`.
- A merge or rebase has stopped with conflicts → `resolving-merge-conflicts`.
- Repo not yet initialized for this workflow → `ai-catapult-init`.

## Vocabulary layer

`domain-modeling` and `codebase-design` are **references consulted during** other work, not
sessions to run on their own. Recommend them alongside a flow — "use `codebase-design`'s
vocabulary while shaping that interface" — rather than as a step.

## Answering

Give a **sequence**, not a menu. Name the first concrete action, and be explicit about what
you are leaving out. If the situation genuinely does not need a flow — a one-line fix, a
question — say so instead of manufacturing process.

If nothing fits, say that plainly rather than stretching a skill to cover it.

## References

- [CATALOG.md](CATALOG.md) — generated tier-1 inventory, grouped by phase.
- [PHASE-BOUNDARIES.md](PHASE-BOUNDARIES.md) — what belongs in each phase, and the handoffs.
