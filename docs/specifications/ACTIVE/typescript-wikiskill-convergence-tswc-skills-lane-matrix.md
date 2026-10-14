# TSWC skills successor: harness matrix (`skills`, plan `tswc-skills-lane-matrix`)

ID: `TSWC-20261014-SKILLS-MATRIX`
Status: **Planning publication (readiness-contract/2, live mode); published on skills `origin/main` `823d699cb063b5cc2fe1674baf137f6b2efdb8e4`; execution unauthorized**
Execution authorization: **none**. Publication, registration, visibility or discovery never grants approval, readiness or execution authority. Agent-self: no human approved this plan.

> Prepared against skills `origin/main` `848a3dd6375d3552ea118914d4584d39aaa351ba`
> (= `git ls-remote origin refs/heads/main` at 2026-10-14T04:17Z) and published
> against `origin/main` `823d699cb063b5cc2fe1674baf137f6b2efdb8e4` (= `git ls-remote` at 2026-10-14T08:08:31Z)
> after coordinator #3 green-light 2026-10-14T07:09:32Z on the human PUB authorization of the same timestamp (root .omc/plans/hitl-answers-20261014.md).
> This file is `docs/specifications/ACTIVE/typescript-wikiskill-convergence-tswc-skills-lane-matrix.md`.
> The draft base was an observation, not a pin; the publication base is the one the
> generation binds. Publication grants no authority; a fresh own-plan approval is
> still required before implementation admission and is not sought here.

## Read first

1. This plan is the successor the bound B2 spec names
   (`docs/specifications/ACTIVE/typescript-wikiskill-convergence-tswc-skills-lane.md`,
   sha256 `ffd7315396a9801c58c68ddbe890611cc1fd29f812e24848841836a7c201a172`,
   section "Successor plan: `tswc-skills-lane-matrix`"). It registers **three goals**,
   `tswc-sk-e5-h1`, `tswc-sk-e5-h3` and `tswc-sk-e5-h4`, with in-plan edges
   H3 ← H1 and H4 ← H1, H3. It does not replace plan `tswc-skills-lane`
   (generation `f68755fc…`, goal `tswc-sk-b2` merged as `28f813bf…`): a replay may
   replace an entry only without merged goal PRs, so this is a fresh-plan ADD with
   its own spec file. The bound B2 spec copy is not edited.
2. Publication gate: "publish only after `e6-sk-01-py-leaf` has merged" is met.
   PR #137 merged 2026-10-13T21:18:15Z as squash
   `10a650db711f5a3fd91315ee70ac94990ce0fe7d`, an ancestor of the base. The plan is
   written against the TypeScript catalog and tooling that goal left
   (`ts-tooling/src/leaf/catalog-model.mts`, `catalog-query.mts`, `skill-parity.mts`,
   `install-hosts.mts`; compat shims `scripts/catalog-query.py`,
   `scripts/check-codex-parity.sh`, `scripts/check-opencode-parity.sh`).
3. Decisions D1–D13 of E6 (`docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md`,
   sha256 `981f1f80182180c02837d9eabba4f15f6383725bab89e67d713fc69dc4e01834`) bind
   every file this plan touches under `ts-tooling/`, `scripts/lib/` and `tests/`.
   Per D9 this plan cites `e6-sk-00-ledger` (merged `a389a52528d58ba209203f582e6735c3e40fa145`,
   PR #135), `e6-sk-01-py-leaf` (merged `10a650db…`, PR #137) and
   `e6-sk-06-names-batch` (not published, not merged). Those goal ids are stable;
   only E6 plan ids change.
4. No goal of this plan edits `catalog.json`, `prek.toml`, `.ai/ci/local-ci.json`,
   `.ai/rules/legacy-freeze-baseline.json`, `tests/readiness_v2_migrate_test.py`,
   any workflow, any moon task, any SKILL.md, `04-validate-handoff/autobahn/**`
   or frozen v1 bytes. `ts-tooling` and `scripts/lib` are scoped by exact file.
5. Bundle `dependencies[]` carry in-plan edges only. Cross-plan predecessors are
   prose plus AC-1, re-observed by git ancestry at prereq-check time, because a
   bundle cannot depend on a goal of another plan (`bundle_dependency_unknown`).

## Umbrella authority and precedence

This plan-scoped specification restates the `skills`-repo E5 slices of the TSWC
master intake in `r3dlex/ai-tool-workspace`, read from that repository's
`origin/main` at `f4a6241e07bc8beddc4ff8a3e43816b71f3160f5` (both files last
changed by root commit `10c39a03`, root PR #120):

- master `.ai/work-intake/typescript-wikiskill-convergence.md`, sha256
  `5f54c26aa8017844b1ddf457a038d03411071a2c10aad891ce42b0ea19f2ed38`;
- scoped intake `.ai/work-intake/tswc-skills.md`, sha256
  `f35bc99cc43d1b4807be6b26b88fc7499e46299f06cad64e6278797553f1dc2c`.

These re-pin the values the B2 spec carried (`242fb2c9…`, `8b5b38aa…`) per master
§9.2 FU-1. Metrics (§5), locked decisions (§4), references (§3) and the interview
brief (§8) are defined there. Precedence: a user or coordinator decision dated after
the pinned bytes (§Decisions) wins over them; otherwise the pinned umbrella wins over
this copy, and any other disagreement blocks preparation until a new planning copy
is published.

Carried from the B2 spec and the master: E5-H1 is an **alias/mapping layer**
(master §9.2 FU-4, mega-plan §2b): the payload-truthful enum
`auggie, claude-code, codex, copilot, gemini, opencode` stays the build truth;
`omc` aliases the claude-code payload; `omx` aliases the codex payload; OpenCode v2
consumes the `opencode` payload through payload merges plus commands/skills, never
the v2 `plugin` array; the `oh-my-openagent` OpenCode-plugin adapter stays retired
and quarantined (root `AGENTS.md`; root `tests/opencode_omo_coexistence_test.py`).

## Decisions after the pinned bytes

User decisions (2026-10-07), relayed by the coordinator and carried from the B2
spec: (1) every new non-test executable is strict TypeScript in E6's `ts-tooling`
package; no goal adds a non-test `.py` or `.sh` file; new test logic is plain bash
with no embedded Python. (2) E6 owns A4 and A5.

Coordinator decisions (2026-10-08, B2 spec): the split (B2 only; E5-H1/H3/H4 here),
the role skills `experimental` with `supported_hosts: []` until ai-catapult's B1 and
B3 land, and the two successor rules (`catalog.json` serialization; the lock-bump
batch is the successor's concern).

Decisions of this plan (2026-10-14, agent-run on the coordinator's RECOMMENDED path
per the lane brief; ratified at green-light, see `stop-questions.md`):

1. **M-4 (dependency).** `tswc-sk-e5-h4` depends on `tswc-sk-e5-h3` and
   `tswc-sk-e5-h1`; `tswc-sk-e5-h3` depends on `tswc-sk-e5-h1`. Bundle
   `dependencies[]` carry both edges; admission enforces them as
   `dependency_incomplete` until each predecessor's goal-branch PR merge commit
   reaches `origin/main`.
2. **M-5 (carve-out).** The declared host set (`supported_hosts`) is the truth.
   Delivery means each skill to **every host in its declared host set**, never a
   forced all-host fan-out. `edit-article` stays `["opencode"]` (SSCM S3 excluded it
   from every host; #82/G-03 restored opencode only, by user decision 2026-10-01).
   The three role skills stay `[]` until promotion. No goal of this plan changes a
   `supported_hosts` value. Widening `edit-article`'s host set is a user decision
   that would reverse SSCM S3 for the other five hosts; it is recorded as
   stop-question SQ-1 with default "keep", and its supersession path is a new
   generation plus an SSCM amendment, never an edit of this plan.
3. **M-6 (omo-ai).** `omo-ai` has no payload, mechanism or entrypoint contract in
   skills or ai-catapult. It is **dropped** from H1, H3 and H4: not a payload host,
   not an alias, recorded in `host-matrix.json` under `excluded` with that reason.
   The `oh-my-openagent` adapter stays quarantined and is recorded there too. This
   decision is dated after the pinned master bytes (§3e, FU-4 call it first-class)
   and wins under the precedence rule; the root follow-up to record it in the master
   intake is stop-question SQ-2. Re-admission needs a published contract (payload,
   delivery mechanism, entrypoint, parity rule) and a new generation.
4. **Minimal predecessor set.** H1 proceeds after `e6-sk-00-ledger` and
   `e6-sk-01-py-leaf` only, both merged. No goal waits for `e6-sk-06-names-batch`,
   because no goal touches the surfaces D7 reserves for it: the `.ai/ci/local-ci.json`
   `verification` list, the workflow inventory, `prek.toml`, any workflow or moon task.
   A goal that would need one of them stops and waits for `e6-sk-06-names-batch`'s
   merge commit (re-observed by ancestry) and a new generation; it never edits around
   the reservation. New tests reach the suite because `tests/test-scripts.sh`
   discovers every `tests/**/*_test.sh`.
5. **Shim retirement deferred.** The intake's "retire executable shell mirrors" is
   not done here. `scripts/check-codex-parity.sh` and `scripts/check-opencode-parity.sh`
   are D3 permanent compat shims (ledger class `compat-shim`); a class change is red
   (D6) and "retiring a compatibility name is outside E6 and needs its own decision"
   (D3). H3 keeps both shims byte-identical and makes their `.mts` sources delegate to
   the one rule table.
6. **Path realization.** The intake's proposed `scripts/check-host-parity.ts` is
   realized per ADR-0018/D4 as `ts-tooling/src/leaf/check-host-parity.mts`, compiled
   and committed as `scripts/lib/leaf/check-host-parity.mjs` (plus `.d.mts` and
   `.mjs.map`). It has no shim: new entrypoints get none (D3 covers converted
   entrypoints), and user decision (1) forbids a new non-test `.sh`. Tests invoke it
   as `node scripts/lib/leaf/check-host-parity.mjs`, the pattern `prek.toml` already
   uses for `scripts/lib/check-legacy-freeze.mjs`.
7. **Promotion is a later goal.** Listing hosts for `evolution-rollout`,
   `wiki-maintainer` and `skill-proposer` is not in this plan. Publication-time
   correction (first-hand, 2026-10-14T08:08:31Z): ai-catapult's `tswc-ac-b1` and
   `tswc-ac-b3` **are merged** (PR #63 squash `3fa658b2142c8874aa3fd78986cff487be3b521d`,
   2026-10-12T03:39:44Z; PR #70 squash `a29d9e3ab12ae3878392a189793e1b25746c640e`,
   2026-10-12T15:47:52Z; both ancestors of `5d0c5bd5609d4ae2d3cb65d66c72256cea3ec5ae`
   and of ai-catapult `origin/main` `fcdc6f66e4bd67b8ccc624bdeb3603e11594df71` at publication), so
   the draft's "not merged" observation was wrong and the B1/B3 gate of the later
   promotion goal is met. Promotion stays a later goal, gated on the `catalog.json`
   window and on its own interview, review and publication; its id is assigned at
   its own publication (none is invented here).

## Plan scope

Three tracer bullets, one PR each:

| Goal | Depends on (in-plan) | Slice |
|---|---|---|
| `tswc-sk-e5-h1` | — | **Alias layer.** `host-matrix.json` (schema `host-matrix/1`), the TS resolver `host-matrix.mts`, alias-aware `catalog-query`, the plain-bash matrix test, README host table rows for the aliases and OpenCode. |
| `tswc-sk-e5-h3` | `tswc-sk-e5-h1` | **Matrix parity checker.** One per-payload-host rule table (`host-parity.mts`), the entrypoint `check-host-parity.mts`, `skill-parity.mts` delegating to the table, per-host fixtures and the plain-bash parity test. |
| `tswc-sk-e5-h4` | `tswc-sk-e5-h1`, `tswc-sk-e5-h3` | **Declared-host delivery gate.** The plain-bash delivery test over every payload host and alias, the README delivery statement and matrix table, the lock-bump batch note. |

### Host matrix (`host-matrix.json`, H1)

One file at the repository root beside `catalog.json`, hand-maintained, read by the
TS resolver and the checker. Keys are fixed so the tests can be red-first:

```json
{
  "schema": "host-matrix/1",
  "payload_hosts": ["auggie", "claude-code", "codex", "copilot", "gemini", "opencode"],
  "aliases": { "omc": "claude-code", "omx": "codex" },
  "consumers": {
    "claude-code": { "installer": "scripts/install-claude-code.sh", "also": ["omc"] },
    "codex": { "installer": "scripts/install-codex.sh", "also": ["omx"] },
    "gemini": { "installer": "scripts/install-gemini.sh" },
    "auggie": { "installer": "scripts/install-auggie.sh" },
    "copilot": { "installer": "scripts/install-copilot.sh" },
    "opencode": { "installer": null, "delivery": "ai-catapult payload merge into the OpenCode config root (skills/ and command/); never the OpenCode v2 plugin array" }
  },
  "excluded": {
    "omo-ai": "no payload, mechanism or entrypoint contract (M-6); re-admission needs a contract and a new generation",
    "oh-my-openagent": "OpenCode-plugin adapter, retired and quarantined (root AGENTS.md); OpenCode payload names stay disjoint from root tests/fixtures/omo-names.json"
  }
}
```

Invariants (tested by `tests/host_matrix_test.sh`, enforced fail-closed by
`loadHostMatrix`): `payload_hosts` equals the TS catalog model's `HOSTS` as a set;
every alias target is a payload host; no alias is a payload host; no alias or
payload host equals a catalog skill name; `omo-ai` and `oh-my-openagent` appear
only under `excluded`; every `consumers` key is a payload host and every
`consumers[*].also` entry is an alias of that host. `catalog-model.mts` is not
edited: `HOSTS` stays the enum and `supported_hosts` values naming an alias stay
refused.

Resolution lives in `catalog-query.mts`: `--host <alias>` resolves to its payload
host before `select()`, so rows and `--projection` bytes are identical to the
payload host's. `--host omo-ai` (and any name outside hosts ∪ aliases) exits 2 with
`unknown host: <name>`, the message `select()` already prints.

### Checker contract (H3)

`node scripts/lib/leaf/check-host-parity.mjs --host <payload-host|alias> <SKILL.md>...`

- `--host` is required; an alias resolves through `host-matrix.json`; an unknown
  name exits 2 with `unknown host: <name>`.
- Exit 0 when every file passes; 1 when any file fails (`FAIL: <file>` then
  `  line N: unmarked <label>-incompatible construct: <construct>`, where `<label>`
  is the resolved payload host's table label); 2 on usage or a missing file
  (`MISSING: <file>`). `PASS: <file>` per passing file. This is today's diagnostic
  shape, and for `codex` and `opencode` the output is byte-identical to today's
  shims because their labels stay the frozen `Codex` and `opencode`.
- Markers name payload hosts only: `<!-- <payload-host>:optional -->` on the
  construct line or the line above. An alias has no marker of its own.
- Rule table (`host-parity.mts`), one entry per payload host: `codex` and
  `opencode` are today's regexes, markers and labels (`Codex`, `opencode`),
  byte-for-byte; `claude-code` is the canonical source (empty denylist: every
  readable file passes, so it has no unmarked-construct fixture; its negative case
  is `MISSING`); `gemini`, `auggie` and `copilot` use the codex denylist with their
  own markers and their payload-host names as labels. A tighter rule for any host
  is a later decision with its own red fixtures.
- Corpus of the parity test: every skill that declares at least one host (the
  union of `catalog-query` over every payload host with every lifecycle included;
  39 entries at the base). The three host-less role skills carry no parity
  obligation until promotion lists their hosts; the test records that.
- `skill-parity.mts` `codexMain`/`opencodeMain` delegate to the table, so the two
  shims' outputs stay byte-identical (proved by `tests/codex_parity_test.sh`,
  `tests/opencode_parity_test.sh` and the e6 differential test). Backtick and
  fenced-block exemptions and the marker convention are unchanged.

### Delivery gate (H4)

`tests/host_matrix_delivery_test.sh`, plain bash, per matrix row:

- payload hosts with a skills installer (`claude-code`, `codex`, `gemini`,
  `auggie`, `copilot`): install into a temporary HOME/repo and assert the delivered
  set equals the declared set for that host at default lifecycles, and that every
  delivered body or projection passes the H3 checker for that host;
- `opencode`: `catalog-query --host opencode --projection` names exactly the declared
  set (`edit-article` included; the three role skills excluded) and every named
  body passes the opencode rule;
- aliases: `--host omc` / `--host omx` projections equal `claude-code` / `codex`
  byte-for-byte;
- the README "Install for another host" table names every payload host and alias
  exactly once (already true after H1), and README carries the verbatim delivery
  rule sentence, the two carve-out names and the literal
  `tests/host_matrix_delivery_test.sh` — three assertions that are red at H1's
  merge and green after H4's README edit (H4's same-command red→green);
- negative fixtures: a seeded undelivered skill, a seeded unmarked construct in a
  projection, and a temporary catalog copy that widens a carve-out are red.

README ownership between H1 and H4 is disjoint: H1 adds the three matrix rows and
the one `host-matrix.json` sentence; H4 adds the delivery rule, the carve-outs and
the proof reference, and nothing else.

## Sequencing and boundaries

- **In-plan order.** H1 → H3 → H4, enforced by bundle dependencies. One goal PR
  open at a time is the recommended cadence; the dependency makes it mandatory for
  H3 and H4.
- **Cross-plan predecessors (prose, AC-1).** O8 `f5e338b92bb754c2bfffdf542b498530258fdbc0`
  (PR #125), `tswc-sk-b2` `28f813bf9fd767960b96e9d54857964de8181a53` (PR #127),
  `e6-sk-00-ledger` `a389a52528d58ba209203f582e6735c3e40fa145` (PR #135) and
  `e6-sk-01-py-leaf` `10a650db711f5a3fd91315ee70ac94990ce0fe7d` (PR #137) are
  ancestors of the base; prereq-check re-observes them. `e6-sk-06-names-batch` is
  cited (D9) as the boundary described in decision 4, not as a predecessor.
- **E6 hot files.** Every active E6 goal scopes `ts-tooling`, `scripts/lib`,
  `.ai/ci/local-ci.json`, the ledger, `prek.toml`, `mypy.ini`, `ruff.toml` and
  `.shellcheckrc`. This plan scopes exact files under `ts-tooling/src/leaf/` and
  `scripts/lib/leaf/` that no E6 goal names individually, and none of the others.
  The cross-plan rule (E6 spec) therefore blocks neither side: an E6 goal waits only
  if it edits one of this plan's exact files, and vice versa. Never two open PRs on
  one shared file: at the base, PR #139 (`e6-sk-02-v1-port`) touches
  `ts-tooling/src/v1/**`, `ts-tooling/tsconfig.build.json`,
  `ts-tooling/tsconfig.v1.json`, `.ai/ci/local-ci.json` and v1 files — none of this
  plan's paths. The `ts-build-drift` hook recompiles all of `ts-tooling`; disjoint
  compiled files merge clean.
- **Ledger and strict stack.** New `.mts` sources pass the D5 TS stack (tsc strict,
  eslint `complexity` 10 / cognitive 15 / `no-floating-promises`, build drift). New
  test shells are plain bash with no embedded Python, so the ledger inventories
  none of them; they must pass shellcheck `-S error`, `shfmt -d` and `bash -n`, since
  `freeze-measure` checks every tracked `.sh` and growth is red. The ledger's
  `measured` baseline grows by no entry.
- **`catalog.json`.** Never two open PRs on it. No goal of this plan edits it, so
  the hot file stays free for other lanes. The rule binds the later promotion goal.
- **Lock-bump batch (mega choke points 3 and 7).** The ai-catapult `skills.lock.json`
  bump that vendors this plan's results is one batched bump after H4 merges,
  coordinated with af-06 PR2 and any pending skills change, in an ai-catapult PR.
  It is this successor's concern to record, not a skills goal and not a dependency.
  At the base the lock pins skills `28f813bf…` (B2); B2 ships `supported_hosts: []`,
  so a bump that vendors it puts the role skills in no host payload. ai-catapult's
  `src/skill-resolver.ts` still bundles every non-deprecated entry whose
  `supported_hosts` names the host; the cross-lane note (exclude `experimental` by
  default) stands and is not a dependency.
- **OMO guard.** Root `tests/opencode_omo_coexistence_test.py` (sha256
  `476ec53c9fa57f7369e57f0ddf5b1f8eec50d39ef481b00f814a194eaafffe8a`) with fixture
  `tests/fixtures/omo-names.json` (sha256
  `fd9b62ee01d416435d1f073a87261ee4eac6927c15f39a4dcf936ccdce1bb792`, 13 skills,
  5 commands) is the guard. This plan adds no opencode-declared skill and no alias
  that appears there; each goal's evidence records a run of that test against the
  PR head from the umbrella checkout. No fixture copy enters skills.
- **Policy and approvals.** Live policy digest
  `d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962` (node and npm
  are required tools). Publication mints no approval; a fresh own-plan approval is a
  later admission with the verbatim disclosure "AGENT-SELF — no human approved it".
- Never touch `04-validate-handoff/autobahn/**` or frozen v1 bytes. Out of scope:
  legacy conversion and A4/A5 (E6), A6 (root), B1/B3/B4/B5 (ai-catapult), E5-H2
  (ai-factory).

## Goals

The canonical scope, acceptance and verification strings are `goals.json`
(`handoff-goals/2`); the sidecar (`readiness-sidecar/1`) is authoritative for
readiness. Both are in the packet beside this file. Summary:

### `tswc-sk-e5-h1` (alias layer)

Scope (12 literal paths): `host-matrix.json`; `ts-tooling/src/leaf/host-matrix.mts`;
`scripts/lib/leaf/host-matrix.mjs`, `.d.mts`, `.mjs.map`;
`ts-tooling/src/leaf/catalog-query.mts`; `scripts/lib/leaf/catalog-query.mjs`,
`.d.mts`, `.mjs.map`; `tests/host_matrix_test.sh`; `README.md`;
`.ai/evidence/tswc-sk-e5-h1.json`.

Acceptance: AC-1 dispatch gate; AC-2 matrix file and invariants; AC-3 alias
resolution in `catalog-query` with byte-identical payloads and `catalog-model.mts`
untouched; AC-4 OMO guard and no name collision; AC-5 README rows; AC-6 red-first
plain-bash test with negative fixtures; AC-7 D5/D7 maintenance without touching the
reserved surfaces; AC-8 old corpus untouched (differential and parity suites green);
AC-9 TDD evidence.

### `tswc-sk-e5-h3` (matrix parity checker)

Scope (14 literal paths): `ts-tooling/src/leaf/host-parity.mts`;
`scripts/lib/leaf/host-parity.mjs`, `.d.mts`, `.mjs.map`;
`ts-tooling/src/leaf/check-host-parity.mts`; `scripts/lib/leaf/check-host-parity.mjs`,
`.d.mts`, `.mjs.map`; `ts-tooling/src/leaf/skill-parity.mts`;
`scripts/lib/leaf/skill-parity.mjs`, `.d.mts`, `.mjs.map`;
`tests/host_matrix_parity_test.sh`; `tests/fixtures/host-matrix-parity`;
`.ai/evidence/tswc-sk-e5-h3.json`.

Acceptance: AC-1 dispatch gate and H1 dependency; AC-2 one rule table with the
frozen codex/opencode rules and the default rules for the other four hosts; AC-3
entrypoint contract; AC-4 shims byte-identical and delegating; AC-5 red-first
plain-bash test over every host-declaring skill, with per-host fixtures (none for
claude-code's empty denylist) and old-corpus equivalence; AC-6 negative
tests never satisfied by `node_unavailable`/`node_version_unsupported`; AC-7 D5/D7
maintenance; AC-8 TDD evidence.

### `tswc-sk-e5-h4` (declared-host delivery gate)

Scope (3 literal paths): `tests/host_matrix_delivery_test.sh`; `README.md`;
`.ai/evidence/tswc-sk-e5-h4.json`.

Acceptance: AC-1 dispatch gate and H1/H3 dependencies; AC-2 delivered set equals
declared set per payload host and alias, every delivered body passes the checker;
AC-3 carve-outs hold (`edit-article` opencode-only, role skills host-less, no
`supported_hosts` change); AC-4 README delivery rule, carve-outs and proof reference (H1 owns the matrix
rows); AC-5 red-first test whose three README sentence assertions are red at H1's
merge, plus negative fixtures; AC-6 lock-bump batch
note and TDD evidence.

## Verification commands

Each goal's `verification[]` names only commands the publisher allowlists and
scripts present at the base (`verification_not_at_base` is never relaxed): focused
existing suites, `bash tests/run-tests.sh`, `prek run --all-files` and
`git diff --check`. The new tests are named in scope and acceptance, not in
`verification[]`; they reach the suite through `tests/test-scripts.sh` discovery.
Each goal's evidence also records the root OMO test run and the observed
same-command red→green.

## Non-goals

- Promotion of the role skills; any `supported_hosts` edit; widening `edit-article`.
- An `omo-ai` host, alias, payload, installer or parity rule; any `oh-my-openagent`
  re-enablement.
- Retiring or editing `scripts/check-codex-parity.sh`, `scripts/check-opencode-parity.sh`,
  `check-codex-parity.mts`, `check-opencode-parity.mts`, `tests/codex_parity_test.sh`,
  `tests/opencode_parity_test.sh` or any ledger entry.
- Hook, workflow, moon-task or local-ci `verification` wiring (post-`e6-sk-06-names-batch`).
- A skills-repo OpenCode installer; any change to ai-catapult or ai-factory.
- A tighter parity rule for gemini/auggie/copilot than the codex denylist.
- Editing the bound B2 spec, the B2 generation, the root intake, AGENTS.md
  (a policy source; its edit invalidates in-flight contexts), any SKILL.md
  (the no-growth guard digest), or `tests/readiness_v2_migrate_test.py`.

## Risks

- **A declared (skill, host) pair fails the new rule at the PR head.** Only
  `04-validate-handoff/autobahn/SKILL.md:69` carries a live marker today, on a
  construct-free line; `03-configure-generate/write-a-skill/SKILL.md:56` carries one
  inside a fenced example, which the fence exemption already covers; and every skill
  passes the codex denylist; still, H3 and H4 require a committed simulation at the
  PR head. A failure is cured by a marker in that skill —
  which trips the SKILL.md no-growth guard and the migrate test re-pin, both hot —
  so the cure is a separate reviewed change, never silent widening of the rule.
- **The matrix and the enum drift.** `loadHostMatrix` fails closed when
  `payload_hosts` ≠ `HOSTS`; the test asserts it; both live in one commit.
- **Alias resolution breaks the differential corpus.** Resolution is in
  `catalog-query.mts`, not `catalog-model.select`; the e6 corpus's unknown-host case
  is `nope`; `tests/e6_py_leaf_parity_test.sh` is in each goal's `verification[]`.
- **Contention with the E6 chain.** Exact-file scoping and the shared-file rule;
  at the base no open PR shares a path with this plan.
- **README drift.** H4's test asserts the host table against `host-matrix.json`
  and the delivery rule, carve-outs and proof reference as literal text.

## Northstar loop (agent-run)

- Prereq: `bash 02-govern-plan/northstar/prereq-check.sh --root .` exit 0 in the
  read-only reference worktree at `848a3dd6`.
- Deep-interview: agent-run, threshold 20% (default), 7 rounds, final 12.75%;
  record `.omc/specs/deep-interview-tswc-skills-lane-matrix.md` (root `.omc/`).
- Adversarial pass: `grill-with-docs` then `grill-me`, agent-run (work-intake.md).
- Issue: local-first markdown (`work-intake.md`); no hosted issue; tracker writes
  not authorized.
- Ralplan: consensus slicing recorded in `work-intake.md` (three goals, edges M-4).
- Publisher: invoked at publication (`02-govern-plan/northstar/handoff-write.sh`, v2
  dispatch) on `origin/main` `823d699cb063b5cc2fe1674baf137f6b2efdb8e4`; the generation it wrote is the one the registry
  entry `northstar-plan-tswc-skills-lane-matrix` names.
- Planning-stage admission: run by the publisher against the simulated post-merge
  target; readiness unknown; approval and deferred gaps expected.
- Knowledge kind: `plan`. unpublished: no-registry (skills `origin/main` has no
  `.ai/knowledge/registry.json`); the umbrella registry was not written.
