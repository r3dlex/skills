# Work Item: P5c — Skills producer pointers (`skills`, plan `xskp-p5c-skill-producers`)

- **Traceability node:** `issue:skills:xskp-p5c-skill-producers`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** `issue:aitool-root:cross-surface-knowledge-publication` (umbrella
  `.ai/work-intake/cross-surface-knowledge-publication.md` in `r3dlex/ai-tool-workspace`)
- **Delivery posture:** one readiness-contract/2 generation (`xskp-p5c-skill-producers`)
  with one goal, `XSKP-P5C-01`, in one PR. It completes the undispatched `XSKP-P5-03`
  slice of the predecessor plan `xskp-p5-skill-producers` (`XSKP-P5-01` #116,
  `XSKP-P5-02` #118 and `XSKP-P5-04` #121 merged) at a corrected scope and under a
  fresh plan id. Planning complete is not implementation readiness; implementation
  needs one verified plan approval for this generation.
- **Hard boundaries:**
  - Never touch `04-validate-handoff/autobahn/**`, the frozen v1 registry and corpus,
    or the retained policy JSON files.
  - `.ai/ci/local-ci.json` changes only the existing hash value for
    `tests/readiness_v2_migrate_test.py`.
  - The `*/SKILL.md` digest re-pin covers exactly the four pointer-block edits; every
    other assertion in `tests/readiness_v2_migrate_test.py` is unchanged.
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created.

## Traceability

- Spec: [P5c — Skills producer pointers — plan-scoped planning specification](../../docs/specifications/ACTIVE/cross-surface-knowledge-publication-xskp-p5c-skill-producers.md)
  (graph node `prd:skills:xskp-p5c-skill-producers`).
- Handoff: `.ai/handoff/readiness-v2/xskp-p5c-skill-producers/<generation>/` and
  `.ai/workflows/northstar-readiness-v2.json`.

## Acceptance criteria

Per-goal acceptance is authoritative in the published `goals.json`.