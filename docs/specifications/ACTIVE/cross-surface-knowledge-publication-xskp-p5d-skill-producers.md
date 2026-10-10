# P5d — Corrected-scope skills producer pointers (`skills`, plan `xskp-p5d-skill-producers`)

ID: `XSKP-20261010-P5D`
Status: **Planning copy (readiness-contract/2); execution unauthorized**
Execution authorization: **none**. Registration and publication grant no execution
authority. Implementation requires a separate explicit Autobahn invocation and
fresh exact-generation admission after the plan approval verifies.

## Next action and completion

Publish one goal, `XSKP-P5D-01`, through the pinned Northstar v2 publisher. Planning
completion means an intact generation and tail-appended registration, independently
reviewed at its exact PR head with local and hosted gates green. Stop after merge,
the mechanism-authorized approval tag and admission probes; no implementation
belongs to this publication.

## Umbrella authority and precedence

This plan-scoped specification restates the remaining producer-pointer slice of
`XSKP-20261002` in `r3dlex/ai-tool-workspace`,
`docs/specifications/ACTIVE/cross-surface-knowledge-publication.md`, pinned at sha256
`d50488d9b480fdfdea6c2fa2b7265a507d98fdae97758c3b1d2f501951415586`. Precedence is
scoped to its D1–D11 decisions, glossary, verbs and AC-1 to AC-7: disagreement there
blocks preparation until a new planning copy resolves it.

The pinned XSKP umbrella describes readiness-v1 handoffs; it does not authorize v2.
The readiness-contract/2 version is grounded instead in `ACH-20261002`,
`r3dlex/ai-tool-workspace docs/specifications/ACTIVE/admission-complete-handoffs.md`,
pinned at sha256 `2d9a247ace71f21b6b72fb9b852f53b6721f862161791ddc658ec9b9e54337dd`:
R1 ("New plans publish v2") and R4 (skills' scoped ACH-S-01 bootstrap policy
rollover, followed by republishing remaining skills goals on v2). Skills
`docs/architecture/adr/0016-git-native-plan-approval.md` records that v1 remains
unchanged and its bytes and outputs are frozen.

## Predecessor and required scope correction

Predecessor `xskp-p5c-skill-producers`, generation
`14f98166c8a42bbebf74d4af2aa961cdf68fc1c5d7efe5931e8d608f68f8fed4`, goal
`XSKP-P5C-01`, was published by PR #128, squash
`656d64e1759a27f97248d50bf613e8d31839fde5`. Its implementation PR #129 remains
OPEN at `2ce69ca67000aae0ff446fe220b03271f665591d`, with Test Suite FAILURE.
These are observations on 2026-10-10, not an instruction to modify that PR.

The authoritative scope-hold diagnosis is the coordinator receipt
`AiTool/.omc/plans/receipts-p5c01-20261010/checkpoint-scope-hold.md`. Both catalog
test invocations fail with `AssertionError: catalog audit artifact drift at skills`:
the four pointer blocks increase four body lengths, while the registered nine-path
scope excludes `.ai/skills/catalog-audit.json`. The necessary audit update changes
only `body_lines`: code-review 78→81, domain-modeling 50→53, handoff 10→13 and
retro 36→39. No budget exception or description change is required or authorized.

This fresh plan id adds that tenth path and binds its own evidence file; it
supersedes only the blocked remaining delivery, not historical bytes or facts.
The predecessor registration, generation, evidence and PR #129 stay untouched.
A fresh id prevents the publisher's same-id replacement from overwriting the old
registration. This generation has one independent goal and one future goal PR.

## Implementation recipe after separate dispatch

1. Extend `tests/knowledge_producers_test.sh` §3 from five to nine producers and
   observe its missing-pointer red leg before the four edits. The closing assertion
   reports all nine. Completion: same-command producer red and subsequent green
   receipts name actual trees and exit codes.
2. Apply exactly the four SKILL.md pointer-block diffs from PR #129's pinned head,
   including its relative Markdown links, kinds and retro newline. This reference
   overrides the scratch draft's raw-path spelling. With the audit still stale,
   observe `bash tests/skill-catalog_test.sh` fail with the catalog-drift assertion;
   then update only the four `body_lines` values and observe the same command pass.
3. Advance the tracked SKILL.md multiset pin from
   `6236c6c0eccfb9363e9359095d9f9722defc9ba1d9ce7c350494f2c0d18441e4` to the
   recomputed post-edit value, preserving every other test assertion. Rebind only
   that test's existing sources hash in `.ai/ci/local-ci.json`. Run
   `bash scripts/regen-host-golden.sh`; commit its fixture only if these edits
   propagate, otherwise record the observed zero delta without inventing a red leg.
4. Record both honest red→green pairs and final verification in
   `.ai/evidence/XSKP-P5D-01.json`, then complete the exact-head review and gate loop.
   Keep coverage unknown and legacy-safe TDD; no absent or unrelated failure is
   reported as red evidence. No generated-file exemption, pin/gate weakening,
   policy or signer change is permitted; preserve those controls instead.

The scratch recipe is `worktrees/xskp-p5-ctx-20261005/p5-03-draft.md`; its old
commit-based pin recipe is superseded by the current multiset-digest guard.
Producer kinds are handoff→`handoff`, retro→`learning`, domain-modeling→`adr`
(target `docs/architecture/adr/`) and code-review→`review`. Catalog limits remain
description ≤160 characters and body ≤100 lines; Codex/OpenCode parity holds.

## Authoritative goal record

The published `.ai/handoff/readiness-v2/xskp-p5d-skill-producers/<generation>/goals.json`
owns scope, acceptance and verification. Its sidecar records readiness and risk;
`.ai/workflows/northstar-readiness-v2.json` owns completion registration. All
predecessor bytes, frozen v1 payloads, retained policy files and
`04-validate-handoff/autobahn/**` remain unchanged.

Next after publication: the coordinator selects this exact generation and
`XSKP-P5D-01` for a separate Autobahn invocation; first re-observe its admission.
