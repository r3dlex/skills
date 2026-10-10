# P5c-02 — Skills catalog audit sync (`skills`, plan `xskp-p5c-02-catalog-audit-sync`)

ID: `XSKP-20261010-P5C-02`
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

The predecessor plan `xskp-p5c-skill-producers` (live generation
`14f98166c8a42bbebf74d4af2aa961cdf68fc1c5d7efe5931e8d608f68f8fed4` in
`.ai/handoff/readiness-v2/xskp-p5c-skill-producers/`, registered in
`.ai/workflows/northstar-readiness-v2.json`, published by PR #128 squash
`656d64e1759a27f97248d50bf613e8d31839fde5`) defined goal `XSKP-P5C-01`: the four
remaining producer pointers — `handoff`, `retro`, `domain-modeling` and `code-review`
— plus the generated surfaces that follow in the same change set. Its implementation PR #129 (`feat/xskp-p5c-skill-producers-XSKP-P5C-01`) applies the
four pointer blocks and their test/golden follow-on surfaces. The tree this plan and
its published bundle snapshot is that PR at its historical pre-fixer branch basis
`2ce69ca67000aae0ff446fe220b03271f665591d`; at that basis the committed tree left
`.ai/skills/catalog-audit.json` stale — `bash tests/skill-catalog_test.sh` failed
with `AssertionError: catalog audit artifact drift at skills` because the tracked
audit still recorded the pre-pointer body_lines values, and the audit regeneration
was outside the registered goal's scope, so the remainder was red and scope-blocked
on that file.

PR #129 is still open and its thread moved after this branch was snapped. After a
coordinator takeover notice (`br4vesirrobin`, 2026-10-10T07:46:54Z), fixer commit
`d73f2e9d617a63d15e1664f6546125703d1aaf5e` — the current `refs/pull/129/head` —
regenerates the audit through `python3 scripts/validate-skill-catalog.py
--write-audit`, touching only that file; the result is byte-identical to this plan's
regeneration. The same thread records (2026-10-10T08:51:06Z) that this fix sits
outside XSKP-P5C-01's declared scope and names the parallel corrected-scope successor
`xskp-p5d-skill-producers` (`XSKP-P5D-01`; published by PR #130 and squashed as this
plan's base `0620130d8bc805c2e9f36765d81f05297488a09e`, implemented by open PR #131).

What neither open PR delivers is this registration: the audit regeneration stays
outside the registered XSKP-P5C-01 scope before and after that fixer, #129 defines
no planning publication registering `XSKP-P5C-02` and carries no red-to-green record
for the audit sync. The P5D-01 registration and this one overlap on the regenerated
audit file and the four producer skills; duplicate-delivery resolution between this
PR and open PR #131 is a merge-order coordination concern outside this publication.
PR #129 is never edited by this plan — the take-over of the audit-sync remainder
into this publication is disclosed here.

This plan restates the remainder at the corrected scope under a fresh plan id: the
readiness-v2 registry replaces same-id entries on republish, so the fresh id is what
keeps this planning registration distinct from the predecessor generation. The
predecessor generation's registration, evidence and PR are unchanged.

## Plan

### P5c-02 — sync the catalog audit with the four producer pointers

The four producer skills carry their pointer blocks inherited from
`refs/pull/129/head`: defined at its historical pre-fixer basis
`2ce69ca67000aae0ff446fe220b03271f665591d` against base
`656d64e1759a27f97248d50bf613e8d31839fde5`, and byte-identical at the current
`refs/pull/129/head` `d73f2e9d617a63d15e1664f6546125703d1aaf5e`, whose fixer commit
touches only the audit file. At the inherited basis the tracked audit was stale by
exactly four `body_lines` values. This plan registers the completion: regenerate
`.ai/skills/catalog-audit.json` only through
`python3 scripts/validate-skill-catalog.py --write-audit` (code-review 78 to 81,
domain-modeling 50 to 53, handoff 10 to 13, retro 36 to 39; every other field and
exception entry untouched), preserve the four `SKILL.md` pointer blocks byte-for-byte,
and keep the catalog budgets (description at most 160 characters, body at most 100
lines) and Codex/OpenCode parity that `tests/run-tests.sh` asserts.

## Goals

The published `.ai/handoff/readiness-v2/xskp-p5c-02-catalog-audit-sync/<generation>/goals.json`
is authoritative for `XSKP-P5C-02`'s scope, acceptance and verification. Its sidecar
is authoritative for readiness, and it is registered in
`.ai/workflows/northstar-readiness-v2.json`. No goal depends on a goal in another plan
or repository.