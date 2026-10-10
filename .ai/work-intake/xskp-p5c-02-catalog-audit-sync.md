# Work Item: P5c-02 — Skills catalog audit sync (`skills`, plan `xskp-p5c-02-catalog-audit-sync`)

- **Traceability node:** `issue:skills:xskp-p5c-02-catalog-audit-sync`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** `issue:aitool-root:cross-surface-knowledge-publication` (umbrella
  `.ai/work-intake/cross-surface-knowledge-publication.md` in `r3dlex/ai-tool-workspace`)
- **Delivery posture:** one readiness-contract/2 generation
  (`xskp-p5c-02-catalog-audit-sync`) with one goal, `XSKP-P5C-02`, in one PR. It
  completes the audit-regeneration remainder of the predecessor plan
  `xskp-p5c-skill-producers` (`XSKP-P5C-01` planning merged as #128). The carried
  implementation PR #129 applies the four SKILL.md pointer blocks; at its historical
  pre-fixer basis `2ce69ca67000aae0ff446fe220b03271f665591d` the tracked
  `.ai/skills/catalog-audit.json` was stale and the catalog test red. PR #129 is
  open at `d73f2e9d617a63d15e1664f6546125703d1aaf5e`, whose fixer commit (after a
  coordinator takeover notice, 2026-10-10T07:46:54Z) regenerates the audit through
  the validator, touching only that file, byte-identical to this plan's
  regeneration; its thread records (2026-10-10T08:51:06Z) that the fix sits outside
  the declared P5C-01 scope and names the parallel corrected-scope successor
  `xskp-p5d-skill-producers` (PR #130 merged as this publication's base, open
  implementation PR #131). #129 defines no planning publication registering
  `XSKP-P5C-02` and carries no red-to-green record for the audit sync; #129 is
  never edited by this plan, so the take-over of the audit-sync remainder is
  disclosed here. The audit delta is produced only by
  `python3 scripts/validate-skill-catalog.py --write-audit`. Planning complete is not
  implementation readiness; implementation needs one verified plan approval for this
  generation.
- **Hard boundaries:**
  - Never touch `04-validate-handoff/autobahn/**`, the frozen v1 registry and corpus,
    or the retained policy JSON files.
  - `.ai/skills/catalog-audit.json` changes only the four `body_lines` values via the
    validator; it is never hand-edited.
  - The four `SKILL.md` pointer blocks are carried unchanged from
    `refs/pull/129/head`; no other path changes outside the planning publication
    surfaces.
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created.

## Traceability

- Spec: [P5c-02 — Skills catalog audit sync — plan-scoped planning specification](../../docs/specifications/ACTIVE/cross-surface-knowledge-publication-xskp-p5c-02-catalog-audit-sync.md)
  (graph node `prd:skills:xskp-p5c-02-catalog-audit-sync`).
- Handoff: `.ai/handoff/readiness-v2/xskp-p5c-02-catalog-audit-sync/<generation>/` and
  `.ai/workflows/northstar-readiness-v2.json`.

## Acceptance criteria

Per-goal acceptance is authoritative in the published `goals.json`.