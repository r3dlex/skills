# Work Item: E6 — node/npm readiness policy prerequisite (`skills`, plan `e6-skills-node-npm`)

- **Traceability node:** `issue:skills:e6-skills-node-npm`
- **Category:** `enhancement`
- **State:** `needs-triage`
- **Owner:** unassigned
- **Repository:** `skills`
- **Parent:** `issue:aitool-root:e6-skills-legacy-ts-conversion` (umbrella
  `.ai/work-intake/e6-skills-legacy-ts-conversion.md` in `r3dlex/ai-tool-workspace`)
- **Delivery posture:** one readiness-contract/2 generation
  (`e6-skills-node-npm`, mode `policy-amendment`) with one goal, `E6-AM-01`, in
  one PR. It is the chain prerequisite the `e6-skills-legacy-ts` attachment
  `policy_tools_prerequisite` and its D4 (section `node and npm as tools`) place
  between O8 and the `e6-skills-00-ledger` dispatch: the live readiness-policy/2
  `tools[]` gains `node` and `npm`, so the tooling gate checks them for later
  skills generations. The publication amends the live digest
  `58bcd9e7ba044479e2f9f64bedd147926e8ea706f9d9c51378294dada52b354a` and carries
  the two D4-mandated test flips with their collateral re-pins (precedents #111
  `773bfde` and the P5 republish `4fee2ef`). Flip mechanics: the publication ran
  while the live policy still carried the pre-amendment bytes, and the flip to
  the candidate bytes lands in the same commit as the generation. The amendment
  mints no approval tag of its own: per the chain's D4 the `e6-skills-legacy-ts`
  generation keeps its identity and its plan approval is minted only after O8
  and this amendment have merged, immediately before goal 00's admission, and is
  re-signed when fewer than 7 days of the 14-day window remain. Planning complete
  is not implementation readiness; the merge voids every existing plan approval
  in the repository, P5's
  `approval/xskp-p5-skill-producers/a1fd96194619` included, and each plan
  recovers by re-signing.
- **Hard boundaries:**
  - Scope is exactly the live policy flip, the two D4-mandated test flips, the
    collateral `.ai/ci/local-ci.json` re-pins, and the planning publication
    surfaces (generation, registry entry, evidence, work-intake, traceability).
  - Never mint any approval tag — the amendment's own approval and the
    post-void re-approvals belong to their later lanes.
  - Never touch `04-validate-handoff/autobahn/**` or any other plan's held
    artifacts; never start `e6-skills-00-ledger`.
- **Hosted reconciliation:** local-first planning record only. No hosted issue was created.

## Traceability

- Spec: [E6: skills tooling to TypeScript — conversion specification](../../docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md)
  (graph node `prd:skills:e6-skills-node-npm`, binding D4 and the
  `policy_tools_prerequisite` attachment).
- Handoff: `.ai/handoff/readiness-v2/e6-skills-node-npm/<generation>/` and
  `.ai/workflows/northstar-readiness-v2.json`.

## Acceptance criteria

Per-goal acceptance is authoritative in the published `goals.json`.