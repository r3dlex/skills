# P5c — Skills producer pointers (`skills`, plan `xskp-p5c-skill-producers`)

ID: `XSKP-20261010-P5C`
Status: **Planning copy (readiness-contract/2); execution unauthorized**
Execution authorization: **none**. Registration, visibility or discovery never grants
approval, readiness or execution authority.

## Umbrella authority and precedence

This plan-scoped specification restates one slice of the umbrella specification
`XSKP-20261002` in `r3dlex/ai-tool-workspace`
(`docs/specifications/ACTIVE/cross-surface-knowledge-publication.md`), pinned at sha256
`d50488d9b480fdfdea6c2fa2b7265a507d98fdae97758c3b1d2f501951415586`. Decisions D1–D11,
the glossary, the verbs and the umbrella acceptance criteria AC-1 to AC-7 are defined
there. Precedence is scoped: the umbrella spec at the pinned sha wins over this copy on
those D-decisions, the glossary, the verbs and the acceptance criteria, and any
disagreement there blocks preparation until a new planning copy is published.

The pinned umbrella does not set the readiness contract version for this registration:
its D5 and "Plans" sections describe its plans as readiness-v1 handoffs and it contains
no v2 rule. This plan is born readiness-contract/2 on documented override authorities,
not on the pinned umbrella: `ACH-20261002` (`r3dlex/ai-tool-workspace`
`docs/specifications/ACTIVE/admission-complete-handoffs.md`, pinned at sha256
`2d9a247ace71f21b6b72fb9b852f53b6721f862161791ddc658ec9b9e54337dd`) decision R1 ("New
plans publish v2") and decision R4 (one last v1 policy rollover, scoped to skills goal
ACH-S-01, displaced skills' v1 policy; after ACH-S-01 merged, the remaining skills
goals were republished as v2 generations on the new path), with skills ADR-0016
(`docs/architecture/adr/0016-git-native-plan-approval.md`) recording that v1 is
unchanged and its bytes and outputs are frozen.

## Predecessor and scope correction

The predecessor plan `xskp-p5-skill-producers` (live generation
`a1fd9619461935776451a8c7c130dc9c7aed305cd58b61d21c2c6e4193c8343d` in
`.ai/handoff/readiness-v2/xskp-p5-skill-producers/`, registered in
`.ai/workflows/northstar-readiness-v2.json`, approval tag
`approval/xskp-p5-skill-producers/a1fd96194619` with tag object
`e4136d16cd92d2601bc91d0cbf97895a3af1c8a2` over the #114 republish commit
`4fee2ef8769e40ae298493df8a92441a82c04713`) is three of four goals merged:
`XSKP-P5-01` (#116), `XSKP-P5-02` (#118) and `XSKP-P5-04` (#121). The `XSKP-P5-03`
slice — the four remaining producer pointers — was registered but never dispatched.

Finishing that slice touches four surfaces the registered `XSKP-P5-03` goal did not
scope: the `*/SKILL.md` digest re-pin in `tests/readiness_v2_migrate_test.py`, the
local-CI hash rebinding for that test in `.ai/ci/local-ci.json`, the host-default
golden `tests/fixtures/host-default-golden.json` and the evidence file
`.ai/evidence/XSKP-P5C-01.json`. This plan restates the slice at the corrected scope
under a fresh plan id: the readiness-v2 registry replaces same-id entries on
republish, so the fresh id is what keeps this planning registration distinct from the
predecessor generation. The predecessor generation's merged goals and history are
unchanged; this plan supersedes only its undispatched remainder.

## Plan

### P5c — finish the producer pointers

Four producer skills — `handoff` (kind `handoff`), `retro` (kind `learning`),
`domain-modeling` (kind `adr`, target `docs/architecture/adr/`) and `code-review`
(kind `review`) — end with the same at most 3-line pointer to the shared producer
module `03-configure-generate/ai-catapult-init/modules/knowledge-publish.md` that
`XSKP-P5-02` wired for `northstar`, `to-spec`, `to-prd`, `to-issues` and `research`.
Generated surfaces follow in the same change set:
`tests/knowledge_producers_test.sh` §3 extends from five producers to nine, the
`*/SKILL.md` digest re-pins, the local-CI test hash rebinds and the host-default
golden regenerates. Catalog limits (description at most 160 characters, body at most
100 lines) and Codex/OpenCode parity are preserved.

## Goals

The published `.ai/handoff/readiness-v2/xskp-p5c-skill-producers/<generation>/goals.json`
is authoritative for `XSKP-P5C-01`'s scope, acceptance and verification. Its sidecar
is authoritative for readiness, and it is registered in
`.ai/workflows/northstar-readiness-v2.json`. No goal depends on a goal in another plan
or repository.