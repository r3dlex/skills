# Work Item: P5d — Corrected-scope skills producer pointers

- **Traceability node:** `issue:skills:xskp-p5d-skill-producers`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned until the generation's verified approval records one
- **Repository:** `skills`
- **Parent:** `issue:aitool-root:cross-surface-knowledge-publication` in `r3dlex/ai-tool-workspace`
- **Delivery posture:** one readiness-contract/2 generation, one goal `XSKP-P5D-01`,
  one future implementation PR after a separate explicit Autobahn invocation.

## Current position

Predecessor `xskp-p5c-skill-producers` generation
`14f98166c8a42bbebf74d4af2aa961cdf68fc1c5d7efe5931e8d608f68f8fed4` is scope-blocked:
PR #129 at `2ce69ca67000aae0ff446fe220b03271f665591d` is red because its four
pointer additions require an unscoped catalog-audit update. This successor adds
exactly that required path to the intended change set, uses its own evidence file,
and preserves the predecessor registration, generation and PR.

## Traceability and acceptance

- Spec: [P5d — corrected-scope planning specification](../../docs/specifications/ACTIVE/cross-surface-knowledge-publication-xskp-p5d-skill-producers.md),
  node `prd:skills:xskp-p5d-skill-producers`.
- Handoff: `.ai/handoff/readiness-v2/xskp-p5d-skill-producers/<generation>/`,
  registered at the tail of `.ai/workflows/northstar-readiness-v2.json`.
- The published `goals.json` is authoritative for scope, ACs and verification;
  the spec's recipe names the catalog red-first leg and preservation constraints.
- **Hosted reconciliation:** local-first record only; no hosted issue created.

Next after the planning publication: coordinator-dispatched Autobahn must select
the exact registered generation and goal, and independently re-observe admission.
