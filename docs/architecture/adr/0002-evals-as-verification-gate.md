# ADR 0002: Evals as a first-class verification gate

## Status
Proposed.

## Context
The Day-1 whitepaper (*The New SDLC With Vibe Coding*, May 2026) names verification as the single biggest differentiator between vibe coding and agentic engineering: tests verify deterministic parts, **evals** (rubrics, labelled datasets, LM judges) verify non-deterministic parts, and **trajectory evaluation** checks the tool-call sequence — not just the final artifact. "Set the bar at the eval, not the demo." The repo currently has no first-class eval concept (`eval` appears only incidentally in `ci-policy.md`/`sync.md`).

## Decision
Treat evals as a first-class, generated, gating artifact alongside tests:
- `init-ai-repo` gains `modules/evals.md` and generates a `.ai/evals/` scaffold (evalset structure, scoring rubric template, LM-judge harness stub).
- Both **output evaluation** and **trajectory evaluation** are representable.
- A capability is not shippable without an eval carrying an explicit rubric — enforced by a CI eval-coverage gate wired into the `init-ai-repo` PR merge gate.
- The traceability graph gains `eval-result` and `trajectory-trace` node types.

## Consequences
- Higher up-front (CapEx) cost per capability; lower OpEx via fewer regressions, matching the paper's economics argument.
- Eval rubrics must be authored and reviewed like code; an eval without a rubric is rejected.
- Enables `eval-a-skill` (ADR-independent capability) to measure catalog skills.
