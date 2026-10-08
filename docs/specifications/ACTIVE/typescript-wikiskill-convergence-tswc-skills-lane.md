# TSWC skills lane (`skills`, plan `tswc-skills-lane`)

ID: `TSWC-20261004-SKILLS`
Status: **Planning copy (readiness-contract/2); execution unauthorized**
Execution authorization: **none**. Registration, visibility or discovery never grants approval, readiness or execution authority.

## Umbrella authority and precedence

This plan-scoped specification restates the `skills`-repo slices of the TSWC
master intake in `r3dlex/ai-tool-workspace`, read from that repository's
`origin/main` at `575d3edf702996d0df367700ab1ea117539ce32f` (both files last
changed by `a828cfa`, root PR #98):

- master `.ai/work-intake/typescript-wikiskill-convergence.md`, sha256
  `242fb2c928f75dc64aaa0a4ce6961599d1ce602e2ae7527b68cc926470239fc6`;
- scoped intake `.ai/work-intake/tswc-skills.md`, sha256
  `8b5b38aa0dc7b1c8ccb9422e930e80b7686c157abe8eb2623a2e240b1ce306c4`.

These re-pin the pre-revision values (`c29fafd3…`, `89aa227f…`) per master
§9.2 FU-1. Metrics (§5), locked decisions (§4), references (§3) and the
interview brief (§8) are defined there. Precedence: a user or coordinator
decision dated after the pinned bytes (§Decisions) wins over them; otherwise
the pinned umbrella wins over this copy, and any other disagreement blocks
preparation until a new planning copy is published.

## Decisions after the pinned bytes

User decisions (2026-10-07), relayed by the coordinator; the root intake does
not record them yet (root follow-up):

1. **"Change it all to TypeScript."** Every new non-test executable is strict
   TypeScript in E6's `ts-tooling` package. No goal adds a non-test `.py` or
   `.sh` file. New test logic is plain bash with no embedded Python (E6 counts
   embedded Python as legacy surface), or TypeScript once E6's runner exists.
2. **E6 owns A4 and A5.** E6 (`r3dlex/skills#120`, plan `e6-skills-legacy-ts`)
   is the conversion vehicle and owns A4 (legacy freeze, baseline ratchet) and A5
   (strict-TS tooling package and runner), both in `e6-sk-00-ledger`.
   `tswc-sk-a4` and `tswc-sk-a5` leave TSWC; the A4/A5 settings recorded at
   `efa30b11bb4ae698d950d470e47cfdfdc889e623` are E6 input.

Coordinator decisions (2026-10-08, after the round-1 and round-2 critic reviews):

3. **Split.** This plan publishes B2 only (`tswc-sk-b2`). E5-H1/H3/H4 move to a
   successor plan (§Successor plan).
4. **`experimental` with no hosts.** The three role skills are `experimental` with
   `supported_hosts: []` until ai-catapult's B1 (`evolve/` layout, `tswc-ac-b1`)
   and B3 (the validation CLI, `tswc-ac-b3`) land.
   - This follows the pre-G-03 `edit-article` precedent: the entry stays
     catalogued for docs, the validator and lifecycle, but resolves into no host
     bundle.
   - `experimental` alone does not keep a skill out of plugin payloads.
     ai-catapult's `src/skill-resolver.js:122-128` (ai-catapult `origin/main`
     `f31de08`) bundles every non-deprecated entry whose `supported_hosts`
     names the host. The empty host list is therefore what keeps a
     `skills.lock` bump from shipping these procedures before their
     dependencies exist.
   - `scripts/catalog.py` accepts an empty `supported_hosts` (lines 56-60). The
     round-3 committed simulation passed the catalog validator and every
     catalog, parity and installer test with it.
   - Default installs, default counts and the host golden do not change.
   - Promotion means listing the hosts. It belongs to the successor plan, or to
     a later goal once B1 and B3 land.
5. **Retained policy snapshots are historical evidence.** The byte-retained
   policies `.ai/handoff/xskp-p5-readiness-policy.retained.json` and
   `.ai/handoff/ach-skills-contract-v2/s01-readiness-policy-v1.retained.json`
   pin `AGENTS.md`'s digest, so any catalog regeneration breaks the
   "every source digest is current" assertions in
   `tests/xskp_p5_readiness_policy_test.sh` and
   `tests/ach_s01_readiness_policy_test.sh`.
   - B2 narrows both tests. Each still verifies its retained bytes against its
     pinned digest.
   - Source-digest currency is asserted for a live policy only.
   - The contract-acceptance simulation relaxes only source-digest currency,
     as it already relaxes repository-root equality.
   - The retained JSON is never edited.
   - Both review lanes must explicitly accept the narrowing.
   - E6's v1-port goal later ports these two tests in their narrowed form.

## Plan scope: B2, three role skills with environment-enforced blindness

`evolution-rollout`, `wiki-maintainer` and `skill-proposer` live in
`02-govern-plan/` as SSOT catalog entries (`experimental`, `supported_hosts: []`).

The role bodies speak B1's `evolve/` vocabulary (master §5.4):
- `raw/<run-id>/` write-once traces;
- `wiki/` with append-only `logs.md` and `skill-impact.md`;
- `proposals/` overlays and `PURPOSE.md`;
- the audit-entry and judgment-record schemas.

The proposer is atomic single-skill, and the wiki is append-only even on reject.

Blindness (F3) is enforced by the environment, never by a prompt check:
- A rollout runs in a wiki-stripped export with path denial, so the wiki is
  unreachable, including through git history.
- The commands that build that export live in one fenced
  `bash blindness-sandbox` block in `evolution-rollout`.
- The blindness test executes exactly that block, so procedure and proof
  cannot drift.
- The prompt-grep gate is only a pre-check, and the records say so.

The roles also speak the loop's locked economics:
- the $100/cycle ceiling (§5.5);
- human out-of-band judges (§4.4);
- no citation of the WikiSkill paper for any threshold (§3a).

B2 adds no executable tooling. Its test changes are:
- the new plain-bash `tests/blindness_sandbox_test.sh`;
- the two retained-policy narrowings (decision 5);
- the SKILL.md guard re-pin (§Sequencing);
- a data-driven count in `tests/catalog_contract_test.sh`. With empty host
  lists the codex default view stays at 36, so the literal would still pass.
  The change keeps promotion from editing that test again.

Only the new test must be plain bash. The narrowings and the re-pin edit
existing Python test logic in place, in its own language, and E6 ports those
files later.

## Sequencing and boundaries

- **No gates.** B2 has no dispatch gate, no dependency, and is not gated by D1
  or O8. It converts nothing E6 converts. It does edit `.ai/ci/local-ci.json`,
  but only the existing `sources` hash value of
  `tests/readiness_v2_migrate_test.py`, so `e6-sk-00-ledger` waits for B2's
  merge.
- **SKILL.md no-growth guard.** `tests/readiness_v2_migrate_test.py:661-664`
  (ACH-S-05) runs `git diff --exit-code 977ed13b -- '*/SKILL.md'`. Once B2's
  three SKILL.md files are committed, that assertion fails, and with it
  `bash tests/run-tests.sh`. B2 therefore re-pins the guard in #118's digest
  form: sha256 over every tracked `*/SKILL.md` path, index mode and
  working-tree bytes (#118 at `9299b7c`, lines 661-682, unchanged at its
  current head `02154d1`). Whichever of #118 and B2 merges first sets the
  form, and the other advances the digest.
- **Serialization.** Never two open PRs on one shared file. The waits are
  one-way, so there is no cycle.
  - XSKP-P5-02 (#118) serializes with B2 in either order: whichever opens
    second waits for the first to merge and rebases on it. They share
    `.ai/skills/catalog-audit.json`, `.ai/ci/local-ci.json` and the migrate test.
  - Every E6 goal that edits `.ai/ci/local-ci.json` waits for B2's merge. At
    #120 head `a514f18` (generation `5e11d668…`) all eight E6 goals scope that
    file, starting with `e6-sk-00-ledger`. Three of them also scope a B2 test:
    - `e6-sk-02-v1-port`: the two retained-policy tests, ported in their
      narrowed form;
    - `e6-sk-03-py-lib`: the migrate test;
    - `e6-sk-05-test-harness`: `tests/catalog_contract_test.sh`.
- **Simulations commit first.** Every simulation of B2 commits its tree before
  running tests. Untracked files hide the SKILL.md guard.
- **Approval re-signing.** E6's planned node/npm policy amendment voids every
  existing approval in the repository when it merges. If B2 is approved before
  that amendment lands, B2 must be re-signed. A live-mode generation keeps its
  identity, so the same generation is re-signed against the amended policy
  (`modules/readiness-v2.md`, policy amendments).
- Never touch `04-validate-handoff/autobahn/**` or frozen v1 bytes.
- **Born v2.** The plan is born readiness-contract/2 (umbrella R1; ADR-0016
  freezes the v1 corpus) and is published by
  `02-govern-plan/northstar/handoff-write.sh` v2 dispatch.
- **Withdrawn candidates.** These were never on main:
  - the v1 candidate `81b1d4ea…` (at `efa30b11…`);
  - the round-1 v2 candidate `c5e7de57…` (at `a79ef406…`);
  - the round-2 v2 candidate `27acc095…` (at `0c962a10…`).
- Out of scope: legacy py/sh conversion and A4/A5 (E6), A6 (root), and
  B1/B3/B4/B5 (ai-catapult).
- **Cross-lane note (ai-catapult, not a dependency):** an ai-catapult follow-up
  should make `src/skill-resolver.js` exclude `experimental` entries by
  default, the way the skills installers already do (`scripts/catalog.py`
  `DEFAULT_LIFECYCLES`). Until it does, an empty host list is the only guard.

## Successor plan: `tswc-skills-lane-matrix` (E5-H1, E5-H3, E5-H4)

Publish it only after E6's `e6-sk-01-py-leaf` has merged. That slice converts
`scripts/catalog.py` and `scripts/validate-skill-catalog.py`, and may convert
the leaf parity and installer scripts. The successor is written against the
TypeScript catalog and tooling.

- **E5-H1 (alias layer).** The payload-truthful enum (`auggie, claude-code,
  codex, copilot, gemini, opencode`) stays the build truth. `omc` and `omx`
  alias the claude-code and codex payloads, and OpenCode v2 consumes the
  `opencode` payload. The OMO adapter stays quarantined, and no name may
  collide with root `tests/fixtures/omo-names.json`.
- **E5-H3 (matrix parity, ← H1).** A TS checker in `ts-tooling` generalizes
  the codex/opencode parity scripts to every matrix host.
- **E5-H4 (all-host delivery, ← H1, ← H3).** Each skill is delivered to every
  host in its declared host set.

Carried review notes for the successor:
- **M-4:** H4 must depend on H3, because it consumes H3's matrix parity.
- **M-5:** "every skill to every host" silently reverses the deliberate
  opencode-only `edit-article` decision (#82/G-03). It needs an explicit
  carve-out or a user decision.
- **M-6:** `omo-ai` has no payload, mechanism or entrypoint contract. Define
  one, or drop it from H1/H3/H4, before publication.

The successor plan keeps two rules:
- `catalog.json` serializes with B2: never two open PRs on it.
- The intake's catalog lock-bump batch (mega choke points 3 and 7) is the
  successor's concern. B2 ships `supported_hosts: []`, so a `skills.lock` bump
  that vendors it puts it in no host payload.

Promoting the three role skills (listing their hosts) also belongs to the
successor, or to a later goal once B1 and B3 land.

## Goals

The published `.ai/handoff/readiness-v2/tswc-skills-lane/<generation>/goals.json`
is authoritative for B2's scope, acceptance and verification. Its sidecar is
authoritative for readiness, and it is registered in
`.ai/workflows/northstar-readiness-v2.json`.
