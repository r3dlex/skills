# E6: skills tooling to TypeScript (`skills`, plan `e6-skills-legacy-ts`)

> readiness-contract/2 planning publication, live mode, published against skills
> `origin/main` `980cedb6`. This generation registers **one goal, `e6-sk-00-ledger`**.
> Goals 01–07 are a planned successor publication ([Successor plan](#successor-plan-goals-0107)):
> none is registered, none reserves a path and none grants anything. Publication grants
> no authority: goal 00 waits for O8 and for the node/npm policy amendment
> ([Dispatch gate](#dispatch-gate-o8)). This spec replaces the unmerged candidates of
> PR #120 (generations `5e11d668…` and `b509a730…`), neither of which was ever registered
> on main.

## Read first

1. Goal 00 dispatches only after O8, the node/npm policy amendment (D4) and TSWC's
   `tswc-sk-b2` have merged. Re-observe each by git ancestry at prereq-check time. No
   earlier merge, approval or note counts.
2. Decisions D1–D13 bind goal 00 and every successor goal. A goal that cannot meet one
   stops and asks for a new generation; it never edits around a decision.
3. Only goal 00 is registered. The successor text is planned: it binds a goal only once
   that goal's own publication registers it, and that publication changes it only for
   facts observed at its base, saying so in its own spec.
4. Each conversion PR is self-contained (D7): it carries its own ledger deletions, strict
   checks, local-CI pins, manifest pins and docs. Nothing is deferred to a later goal.
5. The legacy implementation stays in the tree until that PR's differential proof passes
   (D8). The proof's reference comes from git objects by a commit-and-path anchor checked
   against its blob id, so no PR can edit its own oracle.
6. No existing name breaks: every converted entrypoint stays at its path as a permanent
   shim (D3).

## Contents

- [Provenance](#provenance)
- [Decisions](#decisions)
- [Inventory](#inventory-at-980cedb6)
- [Goal 00](#goal-00-registered)
- [Dispatch gate (O8)](#dispatch-gate-o8)
- [Successor plan](#successor-plan-goals-0107)
- [Verification commands](#verification-commands)
- [Non-goals](#non-goals)
- [Risks](#risks)
- [Plan-level acceptance](#plan-level-acceptance)
- [Review corrections (round 2)](#review-corrections-round-2)

## Provenance

- **Intake:** root `r3dlex/ai-tool-workspace` commit `b65d2370`,
  `.ai/work-intake/e6-skills-legacy-ts-conversion.md`, sha256
  `dfc647478776e07a71c0cd08974d9c576292fd7786ed40786cdada55fb85945c`. Traceability issue
  node: `issue:aitool-root:e6-skills-legacy-ts-conversion`.
- **User decisions, 2026-10-07** (they amend the intake where they differ):
  - "Change it all to TypeScript." This supersedes the 2026-10-04 "Keep Python" decision.
    E6 is the vehicle that converts all skills tooling.
  - v1 is converted too. ADR-0016 is amended so the frozen v1 contract can be ported,
    proven by differential tests against the frozen Python. The v1 freeze test becomes
    an output-equivalence test. Provenance pins and certificates keep working, and no
    gate is relaxed.
  - Python in skills #105, #107 and #118 merges as-is; E6's ledger tracks it.
  - E6 owns TSWC A4 and A5 (D9). #120 publishes first. TSWC #107 republishes as v2,
    B2-only (`tswc-sk-b2`); E5-H1/H3/H4 move to a TSWC successor plan published after
    `e6-sk-01-py-leaf` merges. B2 is never gated on E6.
- **User decisions, 2026-10-08:**
  1. #120 republishes E6 with goal 00 only. Goals 01–07 move into this spec as a planned
     successor publication with stable goal ids. The full design (D1–D13 and every
     goal's planned acceptance criteria) stays here. Goal 00's scope is as small as its
     job allows, because it is reserved against non-goal PRs until goal 00 merges.
  2. The v1 differential proof normalizes interpreter diagnostic text as a named class
     ([D2](#the-interpreter-diagnostic-class)). This changes v1's emitted bytes for
     malformed input, by user decision. Every other v1 output byte stays identical.
- **Review:** the independent critic's round 1 on generation `5e11d668…` (PR #120 head
  `a514f182`) found C1, H1–H5, M1–M6 and LOWs.
  [Review corrections](#review-corrections-round-2) maps each one to its fix.
- **Umbrella TypeScript decision:** root `.ai/work-intake/typescript-wikiskill-convergence.md`
  (commit `a828cfa3`, sha256 `242fb2c9…`), §4.1, §4.2, §4.7 and §5 Phase 1.
- **A4/A5 conventions:** skills PR #107 head `efa30b11`, goals `tswc-sk-a4` and
  `tswc-sk-a5` of generation `81b1d4ea…`. They supply conventions, not authority.
- **Tier naming:** root `.ai/work-intake/tci-naming-decision.md` at `15ab63cd` (#112),
  sha256 `cc26b87957e8c35595349e77956cd82d8ac718d19c8f788b6c94707996cbb25b`.
- **Superseded candidates:** `5e11d668031d9ace54c79a6820510f267009012a2c2860d2e453996bcba41786`
  (PR #120 head `a514f182`, eight goals), `b509a730b906f3d00be4f0cc1c18b943e71eafa6f98435dcb2cb3861e29ddae5`
  (head `fb8a493d`) and the unpublished `5e19affa…`. None was registered on main.

## Decisions

| # | Decision |
|---|---|
| D1 | **Target.** All skills tooling moves to TypeScript: the v1 and v2 readiness contracts, the observer, the gate drivers and helpers, the scripts, the evaluator scaffold and the Python test harness. The exceptions are the `kept-language` and scaffold files ([D6](#d6-ledger-and-ratchet), [Non-goals](#non-goals)). |
| D2 | **v1 port and ADR-0016 amendment.** See [below](#d2-v1-port-and-the-adr-0016-amendment). |
| D3 | **Permanent compatibility entrypoints.** See [below](#d3-permanent-compatibility-entrypoints). |
| D4 | **One runner.** See [below](#d4-runner-and-packaging). |
| D5 | **Strict-check stack.** See [below](#d5-strict-check-stack). |
| D6 | **Ledger and ratchet.** See [below](#d6-ledger-and-ratchet). |
| D7 | **Same-PR maintenance.** See [below](#d7-same-pr-maintenance). |
| D8 | **Differential parity.** See [below](#d8-differential-parity). |
| D9 | **Ownership.** E6 owns TSWC A4 (legacy freeze, baseline ratchet, exemption ledger, legacy strict stack, prek and local-CI wiring) and A5 (strict-TS package, preset, TS gates, runner). Goal 00 delivers A5 and A4 except its prek registration, which `e6-sk-01-py-leaf` delivers with its first `prek.toml` change, so goal 00 reserves neither `prek.toml` nor `ci-prek.yml`. TSWC republishes B2-only and cites no E6 goal id. Its successor plan for E5-H1/H3/H4 cites `e6-sk-00-ledger`, `e6-sk-01-py-leaf` and `e6-sk-06-names-batch`; those goal ids stay stable across every successor publication, and only plan ids change ([Successor plan](#publication-rule)). A4's "never touch `.ai/ci/local-ci.json`" clause is superseded: ACH-S-04 released the file, it is a free planning path, and the original ACH-S-08's claim is held and uncredited ([Dispatch gate](#dispatch-gate-o8)). |
| D10 | **af-06 batch and tier names.** See [below](#d10-the-af-06-batch-and-tier-names). |
| D11 | **Scope boundary.** See [Non-goals](#non-goals) for what stays outside E6, and why. |
| D12 | **Dispatch gate.** Every goal is post-O8. O8 is the commit the D1 coordinator records as O8. Goal 00 also waits for the node/npm amendment and for TSWC B2. See [Dispatch gate](#dispatch-gate-o8). |
| D13 | **Provenance preserved.** Every registered generation's `generation`, `goal_revision`, bundle and `sidecar_v0` digests, every approval tag, every merge certificate and every `audit-merges` and `export-evidence` result re-derive unchanged through the TS code, proven by the [D13 procedure](#d13-provenance-procedure). E6 never edits the policy file, the v1 registry, a readiness-v1 payload or a TSWC bundle, and relaxes no required check, gate or refusal. |

### D2: v1 port and the ADR-0016 amendment

Planned for `e6-sk-02-v1-port`. It is recorded now so that goal 00's harness supports it.

ADR-0016 says today, in its Decision (line 39), "v1 is unchanged, and its bytes and
outputs are frozen", and in its Verification section (lines 200–201) that
`tests/readiness_v1_freeze_test.sh` "proves that v1 bytes and outputs are unchanged". The
amendment replaces both passages:

- v1's **outputs** stay frozen, except for one named normalization class,
  [`interpreter-diagnostic`](#the-interpreter-diagnostic-class). **By user decision of
  2026-10-08, the port changes v1's emitted bytes for malformed input inside that
  class**, and the amendment says so in those words. Every other v1 output byte stays
  identical: exit status, keys and their order, codes, statuses, scopes and every
  contract-authored message.
- v1's **implementation** is ported once, by goal 02, to TypeScript. The port is
  admitted only by the differential proof (D8) against the frozen Python. The reference
  is anchored by commit and path, then checked by blob id and sha256. A sha256 alone
  cannot locate a git object; the anchor does, and the two digests prove that it still
  names the frozen bytes.

  | File (under `04-validate-handoff/autobahn/lib`) | Anchor commit | Blob id | sha256 |
  |---|---|---|---|
  | `readiness_contract.py` | `92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3` (#92, its last change) | `0afbebf2bebe81546270e3d1c9ee2499cd16b6d0` | `30cfb9bf7436ff1f6b14c0b16542a62a6893321f5eface820c827ae4ec600166` |
  | `verification.py` | the same commit | `6e47e69a7b8dc8e55f6e89d60f2ff7c156363a8e` | `572819a9c8a1039173c5483d0f7f9a33362588d197e27731bb97b5dd78d33524` |

- After the port, the freeze binds the port's executed bytes plus the output corpus, so
  a later v1 change needs a new amendment.
  - The **executed v1 artifacts** are exactly the compiled v1 contract and validator
    modules (`.mjs`) under `04-validate-handoff/autobahn/lib` that both v1 manifests name.
  - They import only `node:` builtins and each other, so no file outside the pins can
    change v1 behavior.
  - A TypeScript compiler upgrade that changes their emitted bytes is an ADR-0016 event:
    it needs a new amendment and is never a routine bump.
  - Drivers, route preludes and shims are not v1 artifacts. The v2 manifests pin them, so
    goals 03 and 04 change no v1 artifact, v1 manifest or ADR-0016 byte.
- The port exports, stable for later goals, every name the Python v2 modules import
  today: `Invalid`, `canonical`, `require`, `string`, `ID`, `SHA`, `REVISION`, `read` and
  `worktree_observation` from the contract, and `validate` and `VerificationError` from
  the validator.
- `schemas/readiness-contract.json` (`f05119f6…`) stays byte-identical. "A shared core is
  extracted only after no v1 entry remains" is unchanged.
- The amended Verification section says that the freeze test proves output-equivalence,
  masked only for `interpreter-diagnostic`, and pins the executed v1 artifacts.

#### The interpreter-diagnostic class

- **Why.** CPython's exception text is not a function of the frozen source: it changes
  between interpreter versions. The critic's probe gave one malformed JSON input to the
  frozen v1:
  - on 3.14.8: `Illegal trailing comma before end of object: line 1 column 8 (char 7)`;
  - on 3.12.15 and 3.9.6: `Expecting property name enclosed in double quotes: line 1 column 9 (char 8)`.

  v1 prints that text verbatim (`exit 1 {"schema": "readiness-contract/1", "error": "Illegal trailing comma …"}`).
  Freezing those bytes would freeze an interpreter, not v1, and no port could meet it.
- **Definition.** The class is the text `str()` produces for an exception raised by the
  Python runtime or standard library (`OSError`; `ValueError`, including
  `json.JSONDecodeError` and `shlex` errors; `TypeError`; `AttributeError`; `KeyError`)
  that reaches v1 output through a listed site, directly or nested inside a
  `VerificationError` message. Contract-authored text is never in the class: `Invalid`
  codes and details, `require` codes, and the fixed parts of `VerificationError` messages.
- **Sites** (at the anchor):
  - `readiness_contract.py` line 534 (the `trust_source_unavailable` suffix), 644
    (`verification_invalid`), 657 (`goal_requirement_invalid`), 719
    (`policy_context_invalid`), 741 (`authority_unavailable`), 786 (the `gate_failed`
    suffix), 908 (the `--context` read error), 932 (`admission_failed`) and 1165 (the
    top-level `error`);
  - `verification.py` lines 148, 155 and 168 (the `{error}` interpolations in the cwd,
    parse and script messages).
- **Line 785 is a decision, not text.** It tests `str(error)` for `unavailable`,
  `missing`, `required` or `No such file` to choose the gap status `unknown` or
  `blocked`. That status is not masked. The port must reach the same decision from the
  error's kind, and the corpus has a runtime-raised case for each branch.
- **Mask.** The differential harness decodes each JSON document, replaces exactly the
  class's substring with the literal `<interpreter-diagnostic>` in both the reference
  and the candidate, and compares the re-encoded documents byte-for-byte. stderr text is
  masked the same way, located by its fixed site prefix. Two cases are red: a mask that
  would alter any character outside a listed site's class substring, and a class
  substring that the mask fails to locate.
- **Freeze after the port.** The output-equivalence freeze test applies the same mask,
  because a node upgrade changes V8's diagnostic text exactly as a CPython upgrade does.
- **Corpus.** Every listed site is a corpus target. Each site gets at least one input
  that reaches it with a runtime-raised error, plus one with contract-authored text where
  the site can carry both. The evidence records per-site and per-branch coverage. The
  corpus also replays every registered v1 generation of skills and of its consumers, at
  planning stage, through both implementations:
  - skills: `.ai/workflows/northstar-readiness-v1.json`, 2 plans at `980cedb6`;
  - root `r3dlex/ai-tool-workspace` at `575d3edf`: 9 active v1 plans, under its
    readiness-policy/2;
  - ai-catapult at `f31de088`: 2 v1 plans, under its readiness-policy/1;
  - ai-factory at `947e725a`: 2 v1 plans, under its readiness-policy/1.

  Goal 02 re-observes these at its base. A consumer generation registered later joins
  the corpus.

#### Freeze-test transition

1. **Goal 02.** `tests/readiness_v1_freeze_test.sh` becomes output-equivalence. It keeps
   the eleven corpus digests and exit codes, the schema pin and the registered P5 v1
   generation pin. It adds the extended corpus captured from the frozen Python before
   the switch, pins the executed v1 artifacts, and re-pins the two v1 manifest pins to
   the new manifest bytes. The two Python byte pins stay, because the Python v2 modules
   still import those files.
2. **Goal 03.** The v2 conversion retires the last Python importer. The two files leave
   the tree, and the test drops exactly their two pins. A Python module leaves only when
   no tracked Python importer remains; an importer outside goal 03's scope blocks it
   until a later publication converts that importer.

### D3: Permanent compatibility entrypoints

- Every converted entrypoint keeps its path, its exec bit and its argv, stdin, stdout,
  stderr and exit contract, as a permanent shim. This covers `scripts/*.py`, the
  non-scaffold `scripts/**/*.sh`, the autobahn drivers, the northstar wrappers,
  `eval-a-skill/scaffold-eval.py` and `ai-catapult-init/scripts/readme-generate.sh`. It
  does not cover `kept-language` files (D6).
- There is one shim template per extension: bash for `.sh`, python3 for `.py`. A shim does
  only four things:
  1. it clears its environment to an allowlist, with `env -i` semantics;
  2. it locates the compiled `.mjs` entrypoint beside itself;
  3. it resolves `node` on the allowlisted `PATH`, or fails closed with `node_unavailable`;
  4. it execs `node` with the fixed flag set ADR-0018 records and unchanged arguments and
     stdin.
- **Environment allowlist.** The base names follow `contract-run-v2.sh`: `PATH`, `HOME`,
  `LANG`, `LC_ALL` and `TMPDIR`. A shim adds only the names its legacy implementation
  reads, listed in its ledger entry and exercised by its differential environment corpus.
  No allowlist names a `NODE_*` variable, so `NODE_OPTIONS`, `NODE_PATH`, `NODE_DEBUG`
  and the rest never reach node. A shim's only template parameters are its entrypoint
  and its added names.
- **Module isolation.** Compiled modules are `.mjs` and import only `node:` builtins and
  relative paths, never a bare or `#` specifier. Node therefore never consults an
  ancestor `package.json` for the module type, and a `node_modules` directory in the cwd
  or an ancestor cannot shadow an import.
- **Version guard.** Every compiled entrypoint first imports a guard that refuses with
  `node_version_unsupported` when `process.versions.node` is outside the range ADR-0018
  pins.
- **Distinct refusals.** `node_unavailable` and `node_version_unsupported` print their
  code on stderr and exit with dedicated statuses, recorded in ADR-0018 and distinct from
  every converted tool's exit codes. A test can therefore tell them from a tool refusal
  ([D8](#d8-differential-parity)).
- `tests/e6_shim_conformance_test.sh` renders every shim from the template, its
  entrypoint and its added names, compares it byte-for-byte, and checks the exec bit.
- The ledger classifies shims as `compat-shim`. A shim is never counted as a deleted
  implementation, and never as eligible legacy.
- Import-only modules with no command entrypoint (`scripts/catalog.py`,
  `scripts/traceability_schema.py`, `scripts/validate_skill_frontmatter.py`) get no shim.
  Their Python import API retires in goal 01, once no tracked importer remains.
- Callers, procedures, workflows, moon tasks, the policy `fixture` binding
  (`scripts/validate-skill-catalog.py`) and consumer references stay valid without
  edits. Retiring a compatibility name is outside E6 and needs its own decision.

### D4: Runner and packaging

ADR `0018-ts-tooling-runner-and-packaging` (goal 00) records each of the following.

- **One runner:** `node` executing `tsc`-compiled ESM, emitted as `.mjs` from `.mts`
  sources. No type stripping, ts-node, bundler or second runner.
- **One node range:** one supported major range, pinned in ADR-0018, in
  `ts-tooling/package.json` `engines.node` and in the hosted workflow's node version. A
  test fails when the three disagree. The version guard (D3) enforces it at run time.
- **Dependencies:** zero runtime dependencies. devDependencies live only in `ts-tooling/`,
  with a committed lockfile installed by `npm ci --ignore-scripts`. TS sources stay in
  `ts-tooling/` and never enter a catalog payload (A5).
- **Committed output:** compiled JavaScript is committed inside the directory each goal
  scopes: `04-validate-handoff/autobahn/lib`, `04-validate-handoff/eval-a-skill/lib`,
  `03-configure-generate/ai-catapult-init/scripts/lib` or `scripts/lib`. Installed
  payloads therefore run with `node` alone. A drift check fails on any byte difference
  from a fresh build.
- **Manifests:** the dependency manifests pin the executed files (shims and compiled
  modules), so fingerprint and `driver_not_base_copy` checks keep comparing what runs.
- **TS tests:** TS test sources live in `ts-tooling/test/`. They compile through a
  separate `tsconfig.test.json` into `ts-tooling/build/`, which is gitignored, never
  committed or shipped, declared as a gate-workspace output, and removed by the wrapper
  on exit. Production output goes only to the shipping `lib` directories.
- **Test seams:** ESM module namespaces are immutable, so a Python test that monkeypatches
  a module attribute cannot be ported by assignment. Examples are
  `tests/helpers/lock_contention.py`, which wraps a runtime's lock acquisition, and the
  `mock.patch` uses in the v2 Python tests. ADR-0018 chooses one mechanism for every
  later port:
  - an explicit dependency seam: entrypoints export `main(argv, deps)` with production
    defaults, and a test passes a wrapped dependency; or
  - a `node:module` `register()` loader hook that the test starts with `--import`.

  The planned choice is the dependency seam, because a loader hook needs a launch flag
  that shims never pass. Goal 00's sample entrypoint demonstrates the chosen mechanism.
- **No caches in the workspace:** every check runs without writing a cache into the
  repository or gate workspace:
  - `tsc` with `incremental` off and no `tsBuildInfoFile`;
  - eslint without `--cache`;
  - `ruff check --no-cache`;
  - `mypy --cache-dir=/dev/null`;
  - Python with bytecode writing off.

  The only outputs are the declared `ts-tooling/node_modules` and `ts-tooling/build`. A
  test fails when a check leaves anything else.
- **node and npm as tools (a dispatch prerequisite of goal 00):**
  - **The amendment.** node and npm become required tools. The policy's `tools[]` lists
    only bash, python3, git, prek, ssh-keygen and gh, so a separately published
    **policy-amendment generation** adds `node` and `npm`. It merges after O8 and before
    `e6-sk-00-ledger` dispatches, so the tooling gate checks them. This live-mode
    generation cannot carry that change, because it scopes no policy file.
  - **Approval form (rule d).** The amendment is agent-self approvable only while
    `agent-self` stays in the candidate's own `approval.accept`: an amendment's form must
    pass both the candidate's form rule and the live policy's (`check_form` in
    `readiness_contract_v2.py`). The live `accept` lists `agent-self`. An agent-self
    approval emits `agent_self_policy_change`.
  - **Test flips the amendment PR must carry.** The precedents are #111 (`773bfde`) and
    the P5 republish (`4fee2ef`):
    - `tests/readiness_policy_v2_test.sh` pins the live digest (`POLICY_SHA256`, line 25)
      and checks that the live bytes equal, and are bound by, the `ach-skills-agent-mode`
      amendment candidate (lines 51–53). Both flip.
    - `tests/readiness_v2_migrate_test.py` lines 425–426 assert that the live policy
      digest equals P5's registered `policy_sha256`. They flip, and the test's own note
      says a policy change forces another P5 republish plus the same collateral re-pin.
    - `.ai/ci/local-ci.json` re-pins every edited source.
  - **Voided approvals.** The amendment voids every plan approval in the repository,
    including P5's (`approval/xskp-p5-skill-producers/a1fd96194619`) and TSWC B2's if B2
    is signed before it, because each approval binds the live policy digest. Each plan
    recovers by re-signing its own generation. This generation keeps its identity.
  - **E6's approval timing.** E6's plan approval is minted only after O8 and the
    amendment have merged, immediately before goal 00's admission, and never earlier.
    `merge-v2` re-verifies the approval at merge time, so the owner re-signs before
    certification when fewer than 7 days of the 14-day window remain. Each successor
    publication follows the same rule for its own approval.
  - **Defense in depth.** A shim also refuses with `node_unavailable` when no `node`
    resolves on its `PATH`, and `tests/ts_tooling_test.sh` fails closed the same way.
- **Bootstrap and hygiene:** the gate-workspace bootstrap is `bash ts-tooling/bootstrap.sh`
  (pinned), which runs `npm ci --ignore-scripts` in `ts-tooling`. `ts-tooling/.gitignore`
  ignores `node_modules` and `build`. Nothing under them is linted or syntax-checked as
  repository code; `tests/test-scripts.sh` gains only that exclusion, in goal 00.
- **Workflows:** goal 00 edits only `.github/workflows/ci.yml`. Its `Test Suite` job
  installs the pinned node, the legacy tools and `npm ci --ignore-scripts` in
  `ts-tooling`, and its job name stays byte-identical. Goal 01 edits the other two:
  - `ci-prek.yml` gains node and the tools with the prek hooks;
  - `security.yml` gains node when `scripts/scan-secret-material.py` becomes a shim. It
    keeps its literal `python3 scripts/scan-secret-material.py` line, which
    `tests/security_workflow_test.sh` asserts.
- **Provenance principle:** a TS driver replaces a Python driver only after the
  [D13 procedure](#d13-provenance-procedure) passes in that PR, and a rollback is
  certified by a source-lane driver pinned to the pre-switch commit.

### D5: Strict-check stack

| Surface | Checks | Source |
|---|---|---|
| TypeScript | `tsc --noEmit` with the pinned A5 preset: ES2023, NodeNext, `strict`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `noFallthroughCasesInSwitch`, `exactOptionalPropertyTypes`, `forceConsistentCasingInFileNames`, `verbatimModuleSyntax`, `skipLibCheck`, `declaration`, `sourceMap`; `incremental` off. eslint with typescript-eslint `recommendedTypeChecked`, `complexity` 10, `sonarjs/cognitive-complexity` 15 and `@typescript-eslint/no-floating-promises: error`, run with `--max-warnings 0` and without `--cache`. No `eslint-disable`, `@ts-ignore` or `@ts-nocheck`. Build plus drift check. | umbrella §4.2, §5 Phase 1; A5 AC-2/AC-3; ai-factory A1 |
| Python, until converted (`.py` shims and `kept-language` files included) | `ruff check --no-cache` with `C901` 10; xenon `--max-absolute B --max-average A`; `mypy --strict --cache-dir=/dev/null` for new or changed code, with the ledger baseline ratchet. | umbrella §5; A4 AC-1 |
| Shell (shims, test wrappers, templates, `kept-language` and unconverted files) | shellcheck `-S error`; `shfmt -d`; `bash -n`. No lizard shell CCN gate. | umbrella §5; A4 AC-1 |

- **Labels.** `complexity` 10 is a labeled project decision. Cognitive complexity 15 is
  a documented default.
- **Excludes.** The global excludes resolve per repository and are pinned by a test.
- **Red legs.** Every check has a violating negative fixture (umbrella §4.7), and a test
  pins the preset flags and thresholds, so relaxing one is red.
- **Missing tools.** A missing tool fails closed.
- **Tool provenance.** Record `brew install shellcheck shfmt`, then `uv tool install ruff`,
  `uv tool install mypy` and `uv tool install xenon`, one package per invocation. Never
  `brew install lizard`.
- **Coverage.** No coverage threshold is set, because none is decided for skills. E6
  invents none.
- **Registration.**
  - Goal 00: `tests/ts_tooling_test.sh` and `tests/legacy_freeze_test.sh` run every check.
    The runner only executes `tests/**/*_test.sh`, so these wrappers are how the checks
    reach `bash tests/run-tests.sh`, in the hosted `Test Suite` job and in local CI.
  - Goal 01: `prek.toml` hooks run every check, through the hosted `Pre-commit Hooks`
    job and `tests/local_lint.sh`.
  - The gate workspace installs the devDependencies through the local-CI bootstrap that
    O8 delivers.

### D6: Ledger and ratchet

`.ai/rules/legacy-freeze-baseline.json` (A4's home) inventories every tracked `.py`
file, every non-test `.sh` file and every test shell that embeds a Python program, in
exactly five classes.

| Class | Holds | Ratchet |
|---|---|---|
| `eligible` | A legacy implementation that an E6 goal converts. It carries its owning goal id (`e6-sk-01-py-leaf` … `e6-sk-05-test-harness`), never a placeholder. | Shrinks only, in its owning goal's PR. |
| `compat-shim` | A template-conformant shim (D3). | Grows only as an eligible entry converts. |
| `scaffold-template` | A consumer scaffold template or golden mirror ([Non-goals](#non-goals)). | Fixed. |
| `test-wrapper` | A `tests/**/*_test.sh` whose embedded Python an E6 goal has ported. It stays bash (runner contract). | Grows only as an eligible test shell converts. |
| `kept-language` | A file that consumers copy or run outside a skills checkout. It stays in its language until a generation co-plans the consumer change. | Fixed. It leaves only through a generation that co-plans that change. |

- **Kept-language files at `980cedb6`.** A shim needs a compiled module beside it and a
  `node` on the consumer's side; these consumers provide neither.
  - `scripts/matrix-contract.py`:
    - ai-catapult `scripts/build-claude-plugin.sh:85-89` and
      `scripts/build-codex-plugin.sh:88-92` copy it standalone into the plugin;
    - `scripts/stage-matrix-runtime.sh:4-8` stages it as `dist/matrix-runtime.py`;
    - `src/matrix-runtime.js:11-12` resolves it and `:21-22` spawns `python` on it;
    - `.moon/tasks/all.yml:23-24` byte-compiles it, and `test/dpua-distribution.test.js:29`
      reads its bytes.
  - `scripts/render-ci-adapters.py`:
    - `build-claude-plugin.sh:90-96` and `build-codex-plugin.sh:93-99` copy it standalone;
    - `scripts/stage-ci-adapters-runtime.sh:6-18` stages it;
    - `.moon/tasks/all.yml:26-27` byte-compiles it.
  - `scripts/release/strategy-selector.sh`: the consumer release templates run it from the
    consumer's checkout (`scripts/release/release.yml.template:101`,
    `gitlab-ci-release.yml.template:61`, `azure-pipelines-release.yml.template:97`), where
    neither node nor a compiled module is guaranteed.
  - `tests/helpers/lock_contention.py`: it loads the Python runtime of the first two files
    as a module, so it stays with them.

  ai-catapult evidence is at its `origin/main` `f31de088`. E6 co-plans no ai-catapult
  change. These files stay under the D5 legacy checks.
- **In-flight entries.** The 2026-10-07 decision lets open PRs merge their Python as-is.
  Goal 00 lists the legacy paths of every such PR that is open at its base (#105 and #118
  at publication; #107 merged as TSWC's planning publication, and B2's own goal PR edits
  only existing files), each with its owning goal and `in_flight` set to the PR. An
  in-flight entry may be absent, because its PR has not merged, or present. Neither is red.
  - `tests/local_ci_declaration_test.py` from #105 is owned by `e6-sk-05-test-harness`.
    If #105 has merged by goal 00's base, it is an ordinary present entry.
  - Goal 00 never waits for #105, and #105 never fails the ratchet.
- **Red.** Growth, re-adding, reclassification, an unlisted file, a class change outside
  this plan, and a `kept-language` file leaving its class are red. Each has a negative
  fixture.
- **Baseline.** Goal 00 measures the C901, xenon, mypy, shellcheck and shfmt baseline at
  its base. The historical sixteen C901 violations up to complexity 38 are not a
  measurement.

### D7: Same-PR maintenance

Each source-changing PR includes:

- its ledger deletions;
- the D5 checks for every file it converts or touches;
- updates to `prek.toml`, `ruff.toml`, `mypy.ini`, `.shellcheckrc` and the ts-tooling
  configuration, removing any configuration the conversion makes dead;
- `.ai/ci/local-ci.json` maintenance: `sources` re-pinned, added or removed, and hashes
  of the workflows it edits;
- both v2 manifests together, and in goal 02 both v1 manifests together;
- the module docs that describe the converted code.

A stale pin left for a later goal is red. Two changes are reserved for
`e6-sk-06-names-batch`: the local-ci.json `verification` list, and workflow inventory
additions and removals. No E6 goal edits af-06's declaration; goal 06 only hands af-06
the converted-surface list. Goal 00 also moves `.ai/ci/local-ci.json` to the
workspace-bootstrap contract that O8 delivers (local-ci/2 at publication).

### D8: Differential parity

- **Harness (goal 00).** `tests/e6_differential_test.sh` materializes the reference from
  git objects by a commit-and-path anchor, checks its blob id and sha256, and never reads
  the working tree. It runs the reference and the TS candidate on one corpus and compares
  exit status, stdout, stderr and written files byte-for-byte.
- **Normalization classes.** A corpus may declare named normalization classes, each with
  a name, its sites and its mask. None applies unless declared. A mask that would change
  a byte outside its declared sites is red.
  - The plan defines `interpreter-diagnostic` for v1 ([D2](#the-interpreter-diagnostic-class)).
  - Goal 03 may declare the same class for v2 sites that embed runtime exception text.
    It lists those sites by line in its own publication, exactly as D2 does. v2 has no
    byte freeze, so no ADR amendment is needed.
- **Red legs.** The harness is red on each of these:
  - a seeded one-byte divergence;
  - an anchor whose blob id or sha256 does not match;
  - an undeclared mask, or a mask that reaches beyond its sites;
  - a candidate run that ends in `node_unavailable` or `node_version_unsupported`, which
    is never a pass.
- **Corpus.** Each slice's corpus covers its existing goldens, every scenario its current
  tests exercise, and a refusal corpus that reaches every refusal and error code. Each
  tool or driver has a failing-first red leg.
- **Canonical JSON.** Python `json.dumps` with `sort_keys` and compact separators (ASCII
  escaping, code-point key order, number rendering) has dedicated fixtures, because
  every digest depends on it.
- **Python stays until the proof passes.** The legacy code stays in the tree until the
  proof passes in that PR. Afterwards, the committed goldens and the ported tests are
  the permanent regression.
- **Ported tests.** A Python test that imports a converted module is ported in the same
  goal. Every case maps to a TS case recorded in the evidence, and the assertion count
  never drops. Tests that run a tool by its path stay unchanged and pass through the shim.
  A byte pin over a ported file (for example `V1_WORKTREE_PINS` in
  `tests/readiness_v2_identity_test.py`) re-pins in the porting PR; the assertion stays.
- **Negative tests and node.** After a conversion, a negative test must never be
  satisfied by `node_unavailable`.
  - A negative test that runs a converted entrypoint asserts its expected refusal code or
    diagnostic, never only a nonzero exit. A run that ends in `node_unavailable` fails it.
  - A test that narrows `PATH` keeps node resolvable through a bin directory that holds
    only node, so the narrowing still tests what it meant to. Today
    `tests/autobahn_ci_gate_test.sh:493` runs with `PATH="/usr/bin:/bin"`, and
    `tests/autobahn_lint_gate_test.sh:118` runs with an empty bin directory; both would
    pass vacuously once their gate is a shim.
  - Each conversion goal re-audits the negative tests of everything it converts.

### D10: The af-06 batch and tier names

- **One batch.** `e6-sk-06-names-batch` and E7's `tci-meta-af06` are one scheduled batch
  in af-06's lane. Neither plan opens it alone, and no other PR edits those declaration
  files in the window.
- **Fallback.** If E7 has not scheduled its side within 14 days after
  `e6-sk-05-test-harness` merges, goal 06 proceeds alone. This is safe because goal 06
  renames nothing. It records the converted-surface list in its evidence for af-06 to
  consume whenever E7's batch runs.
- **No renames.** With permanent shims, no command reference or procedure path needs
  renaming. E6's side of the batch carries:
  - the converted-surface list (typecheck, lint, complexity and test commands, with what
    each covers), handed to af-06 for skills' `local_ci` declaration in the same window;
  - E6's only change to the local-ci.json `verification` list, made only if a check must
    be declared there.
- **af-06 writes the declaration.** af-06 owns skills' `.ai/workflows/repo-workflow.json`
  `local_ci` declaration and its tier metadata. E6 never edits that file, so it never
  blocks af-06's own PRs.
- **Two contracts.** `.ai/workflows/repo-workflow.json` `local_ci` (af-06's format) and
  `.ai/ci/local-ci.json` (ADR-0015, local-ci/1 or 2) stay distinct.
- **Tier names.** The D-TIERS record is an AGENT-DELEGATED selection, not a human
  exact-name confirmation:
  - Tier-2 fast PR CI: `tier2-fast-<repo>`.
  - Tier-3 merge-queue CI: `tier3-mergequeue-<repo>`.
  - Tier-1 agent-local pre-flight: no hosted name and no `required_checks` entry.
- **Conditions on tier names.**
  - No policy depends on them until both emitted hosted checks exist and pass.
  - Tier-3 stays mandatory full-suite pre-merge validation at the tested revision.
  - The current `Pre-commit Hooks`, `Test Suite` and `Repository Secret Scan` checks stay
    enforced.
  - E6 renames no hosted job and edits no policy. af-06 owns the declaration format and
    tier metadata.

### D13: Provenance procedure

This procedure applies to every goal that replaces a contract module or driver (planned
goals 02, 03 and 04). Goal 00's ADR-0018 records the principle. A goal whose procedure
does not pass does not switch.

1. **Reference and candidate.** The reference is the Python driver at the goal's base,
   run base-copy from a checkout of `origin/main`. The candidate is the TS driver from
   the PR head, run source-lane from a separate clone at the head, with its own git common
   dir. Both run against the same target repository and target ref.
2. **Generations.** For every registered generation of skills and of its consumers, both
   recompute `generation`, every `goal_revision`, and the bundle and `sidecar_v0` digests.
   Every value equals the registry.
3. **Audit and export.** For every registered v2 plan of skills (6 at `980cedb6`, plus
   this one) and of its consumers (root's 5 at `575d3edf`), both run
   `audit-merges --plan <id>` and `export-evidence --plan <id>`. The outputs are equal
   after the documented normalizations only.
4. **Approval tags.** For every `approval/<plan>/<generation12>` tag on origin, in skills
   (5 at `980cedb6`) and in its consumers, both verify the tag. They agree on principal,
   namespace, assurance and outcome.
5. **v1.** Every registered v1 generation of skills and of its consumers replays through
   both (the D2 corpus).
6. **Normalizations.** Only these are masked, and each is listed in the evidence:
   - the time fields the operation stamps (`issued_at`, `observed_at`);
   - the scratch-path placeholder;
   - `interpreter-diagnostic` (D2), and any v2 class goal 03 declares by site.

   Any other difference is red.
7. **Evidence.** The goal's `.ai/evidence/<goal>.json` records the commands, both driver
   commits, the provenance lanes, the output digests and the normalization list. It is
   produced on the anchor host, the host whose `allowed_signers` matches the policy's
   `anchor_sha256`, because tag verification needs that anchor.
8. **Live smoke before the switch (goals 03 and 04).** Before the certifier switches,
   the TS `certify-v2` and `merge-v2` run source-lane from the PR head against a real
   open goal PR (the goal's own PR qualifies), next to the Python base-copy run. The
   certificates are equal except `issued_at`, and the merge decisions are equal. Neither
   TS output is used to merge.
9. **Rollback.** If a switched TS driver proves defective, the revert of goals 02–04 is
   certified and routed by a source-lane driver pinned to the pre-switch commit: a
   separate clone at the last commit before goal 02 merged runs `certify-v2` and
   `merge-v2` for the revert PR, and the certificate records `source-lane`. Goal 03's
   evidence records one dry run of this path against a scratch revert.

## Inventory (at `980cedb6`)

The counts are unchanged since `4ff1d933`: #123, #121 and #107 added no Python or shell
implementation file.

- **Python (42 tracked):**
  - 19 non-test tooling files: five `04-validate-handoff/autobahn/lib` modules
    (`local_ci_contract`, `observer`, `readiness_contract`, `readiness_contract_v2`,
    `verification`), `eval-a-skill/scaffold-eval.py` and thirteen `scripts/*.py`. Two of
    the thirteen (`matrix-contract.py`, `render-ci-adapters.py`) are `kept-language`.
  - 23 `tests/**/*.py`. One of them (`tests/helpers/lock_contention.py`) is
    `kept-language`.
- **Shell (150 tracked):**
  - 104 under `tests/`. Of these, 51 embed a Python program.
  - 46 non-test, in four groups:
    - 13 autobahn gate drivers and 3 northstar wrappers;
    - 14 leaf tools: 13 `scripts/**/*.sh` plus
      `ai-catapult-init/scripts/readme-generate.sh`. One of them,
      `scripts/release/strategy-selector.sh`, is `kept-language`;
    - 3 scaffolded scripts mirrored byte-for-byte in `reference/golden-*`
      (`archgate.sh`, `sync-upstream.sh`, `validate-rules.sh`);
    - 13 scaffold templates and reference files.
- **Later Python.** Goal 00 re-measures at its own base and adds every file merged since
  publication, each with an owning E6 goal. In-flight files are listed even before they
  merge (D6). The S-08 successor's own tests are scoped to goal 03.

## Goal 00 (registered)

| Goal | Depends on | Slice |
|---|---|---|
| `e6-sk-00-ledger` | — (O8, the node/npm amendment and TSWC B2) | **Foundations: A5, and A4 except prek.** The `ts-tooling` package and the strict TS stack; callable `tests/ts_tooling_test.sh`; the ledger, ratchet and legacy strict stack through `tests/legacy_freeze_test.sh`; hosted `Test Suite` and local-CI bootstrap; ADR-0018; the shim template; node isolation; the differential harness. |

Its fourteen acceptance criteria are in the bundle. They cover:

1. the dispatch gate (O8 as recorded by the D1 coordinator, TSWC B2 as a prerequisite,
   held claims exempt);
2. the tool prerequisite and the approval timing (D4);
3. the A5 package;
4. the strict TS stack;
5. callable verification and workspace hygiene;
6. the ledger with five classes and in-flight entries;
7. the ratchet;
8. the legacy strict stack;
9. registration;
10. ADR-0018;
11. the shim template;
12. node isolation;
13. the differential harness;
14. TDD evidence.

**Scope (18 entries).**

| Kind | Entries |
|---|---|
| Free planning path, never reserved | `.ai/ci/local-ci.json` |
| Existing tracked files (reserved until goal 00 merges) | `.github/workflows/ci.yml`, `tests/test-scripts.sh` |
| New paths (reserved, absent at base) | `.ai/evidence/e6-sk-00-ledger.json`, `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`, `docs/architecture/adr/0018-ts-tooling-runner-and-packaging.md`, `mypy.ini`, `ruff.toml`, `scripts/check-legacy-freeze.sh`, `scripts/lib`, `tests/e6_differential_test.sh`, `tests/e6_node_shadowing_test.sh`, `tests/e6_shim_conformance_test.sh`, `tests/fixtures/e6-sk-00-ledger`, `tests/legacy_freeze_test.sh`, `tests/ts_tooling_test.sh`, `ts-tooling` |

`prek.toml`, `ci-prek.yml` and `security.yml` move to goal 01 (D9, D4). Goal 00's job
does not need them: its checks reach CI through the `Test Suite` job.

## Dispatch gate (O8)

**O8 is the commit the D1 coordinator records as O8.** The D1 (ACH gate-workspace)
coordinator records it once, in an O8 receipt beside
`.omc/handoffs/ach-20261004/D5-DECISION-20261006.json`. The receipt names the plan,
goal, PR and merge commit. Under D5-20261006, that is the merge commit of the S-08
successor goal: today goal `ACH-S-08` of plan `ach-skills-s08-gate-workspace-repair`.
Defining O8 by the coordinator's record rather than by plan and goal name keeps it valid
if the successor is renamed or republished. Prereq-check confirms that the recorded
commit is an ancestor of `origin/main` and is the merge commit of a merged PR on that
goal's exact goal branch. Goal 00's evidence cites the receipt by path and sha256. No
waiver exists.

**Facts on main at publication (`980cedb6`).**

- `docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-gate-discovery-repair.md`:
  - line 10: the S-08 successor owner waits for the qualified discovery merge, and "Only
    the final fully governed S-08 successor merge may conditionally establish O8";
  - line 16: D5-20261006 accepted "discovery first, corrected S-08 later, original S-08
    HELD/immutable/uncredited with claims preserved". The receipt is
    `.omc/handoffs/ach-20261004/D5-DECISION-20261006.json`, sha256
    `136279cf2742dc31c74a3d73301fce721052e81aabd0f7505f7f76b8f150d9d8`. Its
    `accepted_sequence` names `ach-skills-s08-gate-workspace-repair` / `ACH-S-08`, and its
    `o8_condition` reads "Only the actual final fully governed S-08 successor merge may
    conditionally become O8".
- `docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-gate-workspace.md`
  lines 154 and 178 still say that O8 is ACH-S-08's merge commit. D5-20261006 supersedes
  this for the held original.
- `.ai/workflows/northstar-readiness-v2.json` registers `ach-skills-gate-workspace`
  (generation `22d460b2…`, whose ACH-S-08 never merged) and
  `ach-skills-gate-discovery-repair` (`2a5d7d0b…`). It has no
  `ach-skills-s08-gate-workspace-repair` entry yet. Its last entry is TSWC's
  `tswc-skills-lane` (`f68755fc…`, published by #107 at `980cedb6`), whose one goal,
  `tswc-sk-b2`, has no goal PR yet.
- ACH-S-06 (#108, `0f7f14af`), ACH-S-07 (#117, `2ac9926f`) and ACH-GW-DISC-01 (#123,
  `de949f90`) are merged. None of them is O8.
- No S-08 successor PR, branch or registry entry exists.

**Held claims are not blocking claims.** The original `ACH-S-08` of
`ach-skills-gate-workspace` (generation `22d460b2…`) is HELD, immutable and uncredited
(D5-20261006). It will never merge, so under a merge-only rule its preserved claims (on
`lib/local_ci_contract.py`, `lib/observer.py`, both v2 manifests, ADR-0017, its tests
and `.ai/ci/local-ci.json`) would block E6 forever. They are therefore not blocking
claims for the cross-plan rule. The same paths are claimed by the S-08 successor goal
while it is active, and that goal's merge is O8 anyway. Non-goal PRs still meet the held
goal's machine reservation; E6 goal PRs are not non-goal PRs.

**TSWC B2 is a prerequisite.** Goal 00 also waits until the goal PR of TSWC's
`tswc-sk-b2` (plan `tswc-skills-lane`, registered at `980cedb6`) has merged. B2's spec
(`docs/specifications/ACTIVE/typescript-wikiskill-convergence-tswc-skills-lane.md`,
§Sequencing and boundaries) states that `e6-sk-00-ledger` waits for B2's merge. Under the
2026-10-07 decision E6 yields to B2: B2 has no E6 gate, and two open PRs never share a
file. This is a dependency, not a cross-plan claim conflict, and it is one-way, so no
cycle exists.

- **What B2 claims that E6 also touches:**
  - `.ai/ci/local-ci.json`, for the migrate test's `sources` hash only (goal 00);
  - `tests/readiness_v2_migrate_test.py` (goal 03);
  - `tests/catalog_contract_test.sh` (goal 05);
  - the two retained-policy tests, `tests/xskp_p5_readiness_policy_test.sh` and
    `tests/ach_s01_readiness_policy_test.sh` (goal 02).
- **Lapse.** If the TSWC coordinator records B2 as withdrawn, or B2's plan entry is
  retired, the prerequisite lapses.
- **Successors.** Every successor goal comes after goal 00, so B2 has merged before any
  of them, and each ports B2's files in the form B2 leaves them.

**Cross-plan rule.** An E6 goal edits a path that an active goal of **another plan**
claims only after that goal's merge commit reaches `origin/main`. Held, uncredited goals
recorded by a coordinator decision are exempt. Paths shared among E6's own goals are
ordered by the successor sequence. This rule is prose: the machinery's goal-PR check
(`goal_reserved_refusals`) covers only fixed reserved paths and bound spec copies, never
another plan's scope, so each goal's reviewer checks it. Example: the S-08 successor's
claims on `lib/observer.py` and `lib/local_ci_contract.py`, which goal 03 converts only
after that goal (O8) has merged.

## Successor plan (goals 01–07)

Planned text. Nothing here is registered, reserves a path or grants authority.

### Publication rule

- **One goal per publication.** Each successor goal is published only after the previous
  goal's merge commit reaches `origin/main`, in the order 01 → 02 → 03 → 04 → 05 → 06 →
  07. Each goal's scope is reserved from its publication to its merge, so one goal at a
  time keeps one goal's paths reserved. This spec defines no batch.
- **A new plan id per publication: `e6-skills-ts-<nn>`.** For example, `e6-skills-ts-01`
  holds `e6-sk-01-py-leaf`. There are two reasons:
  - the replay lane refuses to replace the registry entry of a plan that has merged or
    open goal PRs (`replay_lane` in `observer.py`);
  - this spec is bound to this generation, so a non-goal PR cannot edit it.

  Goal ids stay stable, so TSWC and other cross-references keep working. The new prefix
  differs from `e6-skills-legacy-ts`, so no branch namespace overlaps.
- **Its own spec file**, `docs/specifications/ACTIVE/e6-skills-ts-<nn>.md`. It cites this
  spec for D1–D13 and copies its goal's planned text below. It may change that text
  only for facts observed at its base, and says so.
- **Cross-plan order.** A bundle cannot depend on a goal of another plan
  (`bundle_dependency_unknown`). Each successor goal's first AC therefore names its
  predecessors' merge commits, re-observed by git ancestry at prereq-check time, beside
  O8.
- **Approval.** Each successor generation's approval is minted immediately before its
  goal's admission, and re-signed when fewer than 7 days remain (D4).

### Common planned acceptance (every successor goal)

1. **Dispatch gate.** O8 and the merge commit of every predecessor goal are ancestors of
   `origin/main`, re-observed at prereq-check time. The cross-plan rule applies, held
   goals exempt.
2. **Same-PR maintenance (D7).** The PR deletes the ledger entries it converts, attaches
   the D5 checks to every converted or surviving file it touches, removes configuration
   its conversion makes dead, and re-pins, adds or removes the `.ai/ci/local-ci.json`
   sources keys and workflow hashes its changes require. It never edits the local-ci.json
   `verification` list or the workflow inventory (reserved for goal 06), and never edits
   af-06's declaration. A stale pin left for a later goal is red.
3. **Negative tests (D8).** Every negative test over a converted entrypoint asserts its
   refusal code; none is satisfied by `node_unavailable`.
4. **TDD evidence.** `.ai/evidence/<goal>.json` records an observed red then green for
   the same commands. `bash tests/run-tests.sh`, `prek run --all-files` and
   `git diff --check` pass at the PR head. No coverage percentage is invented.

### `e6-sk-01-py-leaf` (after 00)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-01-py-leaf.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.github/workflows/ci-prek.yml`,
  `.github/workflows/security.yml`, `.moon/tasks/all.yml`, `.shellcheckrc`,
  `03-configure-generate/ai-catapult-init/scripts/lib`,
  `03-configure-generate/ai-catapult-init/scripts/readme-generate.sh`,
  `04-validate-handoff/eval-a-skill/lib`, `04-validate-handoff/eval-a-skill/scaffold-eval.py`,
  `mypy.ini`, `prek.toml`, `ruff.toml`, `scripts/lib`, the eleven converted
  `scripts/*.py` (`catalog-query.py`, `catalog.py`, `check-markdown-links.py`,
  `check-root-discovery.py`, `generate-skill-docs.py`, `scan-secret-material.py`,
  `traceability_schema.py`, `validate-cascade-fixtures.py`, `validate-final-package.py`,
  `validate-skill-catalog.py`, `validate_skill_frontmatter.py`), the twelve converted
  `scripts/**/*.sh` (`catalog-install.sh`, `check-codex-parity.sh`,
  `check-opencode-parity.sh`, `check-sync-staleness.sh`, `install-auggie.sh`,
  `install-claude-code.sh`, `install-codex.sh`, `install-copilot.sh`, `install-gemini.sh`,
  `readme-generate.sh`, `regen-host-golden.sh`, `verify-golden-dir.sh`),
  `tests/e6_py_leaf_parity_test.sh`, `tests/fixtures/e6-py-leaf`,
  `tests/northstar_handoff_test.sh`, `tests/traceability-schema-v11_test.sh`, `ts-tooling`.
- **Planned ACs:**
  1. It converts the eleven `scripts/*.py` tools, the twelve non-scaffold
     `scripts/**/*.sh` tools, `scaffold-eval.py` and the init readme generator to
     TypeScript under the one runner. The three scaffold mirrors and the three
     `kept-language` files are not converted.
  2. **Differential proof before replacement (D8).**
     `tests/e6_py_leaf_parity_test.sh` runs each legacy implementation, materialized by
     its anchor, and its TS port over the existing goldens, every scenario its current
     tests exercise, a per-tool refusal corpus and a per-tool environment corpus (D3).
     Outputs are byte-identical, and each tool has a failing-first red leg.
  3. **Compatibility (D3).** Every converted entrypoint is a template-conformant shim with
     its declared names. `scripts/validate-skill-catalog.py` stays an executable file
     for the policy fixture gate. The import-only modules retire once no tracked
     importer remains, which is recorded in the ledger.
  4. **Ported tests.** `tests/traceability-schema-v11_test.sh` and
     `tests/northstar_handoff_test.sh` load a converted script as a module; they are
     ported. Tests that run a tool by its path stay unchanged and green through the
     shim. `tests/helpers/lock_contention.py` and its two callers stay, because they test
     `kept-language` files.
  5. **prek registration (A4, D9).** `prek.toml` hooks run every TS and legacy check.
     `ci-prek.yml` installs node and the tools, and its job name `Pre-commit Hooks` stays
     byte-identical. `security.yml` installs node and keeps its literal line and its job
     name `Repository Secret Scan`. Moon tasks that only compile converted Python are
     replaced by the TS checks.

### `e6-sk-02-v1-port` (after 01)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-02-v1-port.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`,
  `02-govern-plan/northstar/readiness-dependency-v2.json`,
  `02-govern-plan/northstar/readiness-dependency.json`,
  `04-validate-handoff/autobahn/contract-run.sh`, `04-validate-handoff/autobahn/lib`,
  `04-validate-handoff/autobahn/modules/readiness.md`,
  `04-validate-handoff/autobahn/readiness-dependency-v2.json`,
  `04-validate-handoff/autobahn/readiness-dependency.json`,
  `docs/architecture/adr/0016-git-native-plan-approval.md`, `mypy.ini`, `prek.toml`,
  `ruff.toml`, `tests/ach_s01_readiness_policy_test.sh`,
  `tests/autobahn_worktree_driver_integration_test.py`,
  `tests/autobahn_worktree_driver_integration_test.sh`, `tests/e6_v1_parity_test.sh`,
  `tests/fixtures/e6-v1-port`, `tests/readiness_contract_test.py`,
  `tests/readiness_contract_test.sh`, `tests/readiness_mapped_test.py`,
  `tests/readiness_mapped_test.sh`, `tests/readiness_scoped_test.py`,
  `tests/readiness_scoped_test.sh`, `tests/readiness_v1_freeze_test.sh`,
  `tests/readiness_v2_identity_test.py`, `tests/readiness_worktree_test.py`,
  `tests/readiness_worktree_test.sh`, `tests/xskp_p5_readiness_policy_test.sh`,
  `ts-tooling`.
- **Planned ACs:**
  1. **ADR-0016 amendment (D2)**, in its Decision and Verification sections. It includes
     the explicit statement that, by user decision of 2026-10-08, the port changes v1's
     emitted bytes for malformed input inside `interpreter-diagnostic`, and that every
     other v1 byte is identical. It records the commit-and-path anchors, the `node:`-only
     import rule, and that a tsc upgrade changing executed v1 bytes is an ADR-0016
     event.
  2. **Differential proof before the switch (D8).** `tests/e6_v1_parity_test.sh` runs the
     frozen Python and the TS port on:
     - the eleven-scenario golden corpus;
     - every scenario of the v1 Python tests;
     - a generated corpus reaching every v1 refusal code, every `verification.py`
       refusal, every `interpreter-diagnostic` site and both branches of line 785;
     - every registered v1 generation of skills, root, ai-catapult and ai-factory (D2).

     Outputs are byte-identical with only `interpreter-diagnostic` masked. Canonical
     JSON, digests and generation have dedicated fixtures. The evidence records corpus
     size, per-code coverage and per-site coverage.
  3. **Freeze-test transition** as in [D2](#freeze-test-transition), with the mask applied
     after the switch too.
  4. **Switch.** `contract-run.sh` routes every non-v2 operation to the TS port. Both v1
     `readiness-dependency.json` copies change together, pin the executed artifacts and
     stay producer-consumer equal. The unsupported, incomplete and fingerprint-mismatch
     refusals stay fail-closed, with tests. `prereq-check.sh`, `readiness-check.sh`,
     `migrate-handoff.sh`, the v1 path of `handoff-write.sh` and `contract-run.sh` keep
     their names, arguments and outputs. The validator is ported once, with no second
     allowlist.
  5. **The executed v1 artifacts and exports** are as in D2.
  6. **Ported v1 tests.** The tests that import `readiness_contract` directly or through
     `readiness_worktree_test` are ported, with each case mapped and the assertion count
     kept.
     - **Narrowed form (commitment carried from the superseded e6-sk-02 AC7).**
       `tests/ach_s01_readiness_policy_test.sh` and
       `tests/xskp_p5_readiness_policy_test.sh` are ported in the narrowed form B2
       leaves them, after B2's goal PR merges, and the port keeps that narrowing exactly:
       - each test still verifies its retained policy bytes against its pinned digest;
       - "every source digest is current" is asserted for a live policy only, never for
         a retained snapshot;
       - the contract-acceptance simulation relaxes only source-digest currency (as it
         already relaxes repository-root equality);
       - the retained JSON files
         (`.ai/handoff/xskp-p5-readiness-policy.retained.json`,
         `.ai/handoff/ach-skills-contract-v2/s01-readiness-policy-v1.retained.json`) are
         never edited.

       The port neither widens nor narrows these assertions; a change to them needs its
       own decision and both review lanes.
     - **B2 fallback:** if the TSWC coordinator records B2 as withdrawn, or its plan
       entry is retired, goal 02 ports the two tests in their form on main at its base.
     - `tests/readiness_v2_identity_test.py` re-pins only `V1_WORKTREE_PINS`.
     - Both v2 manifests re-pin the `contract-run.sh` digest; their file set is
       unchanged.
  7. **Provenance.** The [D13 procedure](#d13-provenance-procedure) passes, steps 1–7.

### `e6-sk-03-py-lib` (after 02)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-03-py-lib.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`,
  `02-govern-plan/northstar/readiness-dependency-v2.json`,
  `04-validate-handoff/autobahn/ci-gate.sh`, `04-validate-handoff/autobahn/contract-run-v2.sh`,
  `04-validate-handoff/autobahn/lib`, `04-validate-handoff/autobahn/local-ci.sh`,
  `04-validate-handoff/autobahn/modules/ci-gate.md`,
  `04-validate-handoff/autobahn/modules/readiness-v2.md`,
  `04-validate-handoff/autobahn/modules/worktree-execution.md`,
  `04-validate-handoff/autobahn/readiness-dependency-v2.json`,
  `docs/architecture/adr/0017-isolated-gate-workspace.md`, `mypy.ini`, `prek.toml`,
  `ruff.toml`, `tests/ai-catapult-templates_test.sh`, `tests/autobahn_ci_gate_test.sh`,
  `tests/e6_node_shadowing_test.sh`, `tests/e6_py_lib_parity_test.sh`,
  `tests/fixtures/e6-py-lib`, `tests/local_ci_contract_test.py`,
  `tests/local_ci_contract_test.sh`, `tests/local_ci_contract_v2_test.py`,
  `tests/local_ci_contract_v2_test.sh`, `tests/northstar_v2_publish_test.py`,
  `tests/northstar_v2_publish_test.sh`, `tests/readiness_policy_v2_test.sh`,
  `tests/readiness_v1_freeze_test.sh`, every `tests/readiness_v2_*_test.py` and its
  `.sh` wrapper, `tests/readiness_v2_fixture.py`, `ts-tooling`. The S-08 successor's
  tests join the scope as observed at the goal's base.
- **Planned ACs:**
  1. **Conversion.** It converts `lib/readiness_contract_v2.py`, `lib/observer.py` and
     `lib/local_ci_contract.py`, as the S-08 successor left them, and switches their call
     sites in `contract-run-v2.sh`, `local-ci.sh` and `ci-gate.sh`. A Python module
     leaves only when no tracked Python importer remains. Then `lib/readiness_contract.py`
     and `lib/verification.py` leave too, and the freeze test drops exactly their two
     byte pins. `schemas/readiness-contract-v2.json` stays byte-identical.
  2. **Differential proof (D8).** `tests/e6_py_lib_parity_test.sh` runs the Python
     modules, materialized by anchor, and the TS ports over every scenario of the v2
     Python tests and the dual-mode e2e, plus a corpus reaching every v2 refusal code.
     Results, gap reports, certificates (`issued_at` excepted), publication payloads and
     registry bytes are byte-identical. Every git, gh and ssh-keygen argv the observer
     issues matches under recording stubs. Any v2 `interpreter-diagnostic` sites are
     declared by line.
  3. **Gate shadowing (G3).** The runpy and `python3 -I -B` cases of
     `tests/readiness_v2_gate_shadowing_test.py` map onto `tests/e6_node_shadowing_test.sh`.
     A PR checkout that carries a `package.json` (typeless or commonjs), `node_modules`
     or a preload in `NODE_OPTIONS` changes no gate's outcome.
  4. **Provenance.** The [D13 procedure](#d13-provenance-procedure) passes in full,
     including the live smoke (step 8) before the switch and the rollback dry run
     (step 9). Driver provenance compares the newly pinned executed files, and a
     publish-v2 replay by the TS driver reproduces every registered v2 generation
     byte-for-byte.
  5. **Gate behavior is unchanged.** The gate workspace, the S-08 successor's bootstrap,
     `gate_env` and every tree, head and worktree check keep their codes and outcomes.
     The module docs and ADR-0017 describe the TS implementation without changing a
     decision. No executed v1 artifact, v1 manifest, ADR-0016 byte or v1 freeze pin
     changes, other than the two Python byte pins.
  6. **Ported tests.** Every Python test that imports a converted module is ported, with
     each case mapped and the assertion count kept. Monkeypatching tests use the ADR-0018
     seam. Both v2 manifests move together.
     `tests/readiness_v2_migrate_test.py` is ported in the form B2 leaves it, including
     B2's re-pinned SKILL.md no-growth guard (sha256 over every tracked `*/SKILL.md`
     path, index mode and working-tree bytes) and its `.ai/ci/local-ci.json` hash.

### `e6-sk-04-sh-drivers` (after 03)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-04-sh-drivers.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`,
  `02-govern-plan/northstar/approve.sh`, `02-govern-plan/northstar/handoff-write.sh`,
  `02-govern-plan/northstar/prereq-check.sh`,
  `02-govern-plan/northstar/readiness-dependency-v2.json`, the thirteen autobahn drivers
  (`ci-gate.sh`, `contract-run-v2.sh`, `contract-run.sh`, `engine-pick.sh`,
  `lint-gate.sh`, `local-ci.sh`, `merge-authority.sh`, `migrate-handoff.sh`,
  `prereq-check.sh`, `readiness-check.sh`, `run-gates.sh`, `tdd-evidence.sh`,
  `tdd-mode.sh`), `04-validate-handoff/autobahn/lib`,
  `04-validate-handoff/autobahn/modules/worktree-execution.md`,
  `04-validate-handoff/autobahn/readiness-dependency-v2.json`, `mypy.ini`, `prek.toml`,
  `ruff.toml`, `tests/autobahn_ci_gate_test.sh`, `tests/autobahn_lint_gate_test.sh`,
  `tests/e6_sh_drivers_parity_test.sh`, `tests/fixtures/e6-sh-drivers`, `ts-tooling`.
- **Planned ACs:**
  1. **Conversion.** It converts the logic of the thirteen autobahn drivers and the three
     northstar wrappers, embedded Python included, to TypeScript. Each `.sh` file
     becomes a template-conformant permanent shim.
  2. **Differential proof (D8).** `tests/e6_sh_drivers_parity_test.sh` runs each
     pre-conversion driver, materialized by anchor, and its port over per-driver goldens,
     refusal paths and an environment corpus. Results are byte-identical, and each
     driver has a failing-first red leg. Argument validation, environment handling,
     stdin closure, fail-closed exits and command safety are covered. The v1
     output-equivalence corpus still passes.
  3. **Negative tests (D8).** The narrowed-`PATH` cases in
     `tests/autobahn_ci_gate_test.sh:493` and `tests/autobahn_lint_gate_test.sh:118` keep
     node resolvable and assert the gate's own refusal. A `node_unavailable` exit fails
     them.
  4. **Provenance.** The [D13 procedure](#d13-provenance-procedure) passes in full,
     including the live smoke before the switch. Both v2 manifests pin the shims and the
     compiled driver modules. Both v1 manifests, the v1 freeze pins and ADR-0016 stay
     byte-identical.
  5. Driver tests that run a driver by its path stay unchanged and green. Their embedded
     Python moves in goal 05.

### `e6-sk-05-test-harness` (after 04)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-05-test-harness.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`, `mypy.ini`, `prek.toml`,
  `ruff.toml`, `ts-tooling`, `tests/e6_test_harness_parity_test.sh`,
  `tests/local_ci_declaration_test.py` (#105), every other in-flight test file the
  ledger assigns to goal 05, and the remaining test code that embeds or is Python, as
  observed at its base. At `980cedb6` that is: `tests/autobahn_cascade_test.sh`,
  `tests/autobahn_ci_gate_test.sh`, `tests/autobahn_commit_protocol_test.sh`,
  `tests/autobahn_coverage_unknown_test.sh`, `tests/autobahn_direct_ready_test.sh`,
  `tests/autobahn_engine_input_test.sh`, `tests/autobahn_local_ci_test.sh`,
  `tests/autobahn_merge_authority_test.sh`, `tests/autobahn_prereq_test.sh`,
  `tests/autobahn_run_gates_test.sh`, `tests/autobahn_tdd_mode_test.sh`,
  `tests/autobahn_worktree_run_gates_test.sh`, `tests/cascade-host-adapter-schema_test.sh`,
  `tests/catalog_contract_test.sh`, `tests/ci-adapters-contract_test.sh`,
  `tests/ci_hosted_routing_test.sh`, `tests/codex_verification_test.sh`,
  `tests/command_surface_schema_test.sh`, `tests/delegate_contract_test.sh`,
  `tests/eval_a_skill_test.sh`, `tests/eval_coverage_test.sh`,
  `tests/graph-automation-templates_test.sh`, `tests/host_default_golden_test.sh`,
  `tests/install_cross_host_parity_test.sh`, `tests/interview_decomposition_test.sh`,
  `tests/knowledge_contract_fingerprint_test.sh`, `tests/lifecycle_installers_test.sh`,
  `tests/lm_judge_demo_test.sh`, `tests/matrix-v11-contract_test.sh`,
  `tests/mcp_a2a_test.sh`, `tests/model_routing_test.sh`,
  `tests/northstar_autobahn_evals_test.sh`, `tests/northstar_autobahn_pipeline_e2e_test.sh`,
  `tests/northstar_docs_test.sh`, `tests/northstar_lineage_test.sh`,
  `tests/pointer-surfaces_test.sh`, `tests/readiness_fixture.py`,
  `tests/readiness_legacy_matrix_test.sh`, `tests/readiness_merge_driver_test.py`,
  `tests/readiness_merge_driver_test.sh`, `tests/readiness_v1_freeze_test.sh`,
  `tests/readme-generate_test.sh`, `tests/security_workflow_test.sh`,
  `tests/skill-catalog_test.sh`, `tests/strategy-selector_test.sh`,
  `tests/test-skills-validator_test.sh`, `tests/traceability-fixtures_test.sh`,
  `tests/workflow-fixtures_test.sh`. `tests/ci-adapters-contract_test.sh` and
  `tests/matrix-v11-contract_test.sh` were goal 01's in `5e11d668`; their embedded
  programs port here, while their call to the `kept-language` lock helper stays.
- **Planned ACs:**
  1. **Port.** It ports the remaining Python test code to TypeScript:
     - `tests/readiness_fixture.py`;
     - `tests/readiness_merge_driver_test.py`;
     - `tests/local_ci_declaration_test.py`;
     - every scoped test shell's embedded Python program,
       `tests/readiness_v1_freeze_test.sh` included.

     `tests/catalog_contract_test.sh` is ported in the form B2 leaves it, with its
     data-driven count. Each `*_test.sh` stays a bash wrapper that prints
     `Results: PASS=n`. A byte pin over
     a ported file re-pins in this PR; the assertion stays.
  2. **Parity.** Every ported case maps to its Python case in the evidence, and the
     assertion count per file never drops. `tests/e6_test_harness_parity_test.sh` shows
     that each ported suite fails on the same seeded defect as its Python version.
     `tests/run-tests.sh` and `tests/test-skills.sh` stay byte-identical, and
     `tests/test-scripts.sh` carries only goal 00's exclusion.
  3. **No placeholder owners.** Every in-flight or later test Python that the ledger
     assigns to this goal is ported here. Only `kept-language` files remain.

### `e6-sk-06-names-batch` (after 05)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-06-names-batch.json`,
  `tests/e6_names_batch_test.sh`.
- **Planned ACs:**
  1. **The batch (D10).** E6's side of the one scheduled af-06 batch, co-scheduled with
     E7's `tci-meta-af06`. The fallback applies if E7 has not scheduled its side within
     14 days. af-06 owns the declaration format, its tier metadata and skills'
     `.ai/workflows/repo-workflow.json` `local_ci` declaration, which this goal never
     edits. No command reference or procedure path is renamed.
  2. **Contents.** The converted-surface list is recorded in the evidence. E6's only
     change to the local-ci.json `verification` list or workflow inventory is made only
     if a check must be declared there.
  3. **Tier names (D10).** The selected future names and their conditions apply. This
     goal renames no hosted job and edits no policy.
  4. **Names test.** `tests/e6_names_batch_test.sh` fails when a command named by
     local-ci.json, the declaration, a workflow, a moon task or a SKILL.md procedure does
     not resolve to an existing shim, compiled entrypoint or `kept-language` file. The
     af-06 declaration-shape test stays green when present.

### `e6-sk-07-ratchet-close` (after 06)

- **Planned scope:** `.ai/ci/local-ci.json`, `.ai/evidence/e6-sk-07-ratchet-close.json`,
  `.ai/rules/legacy-freeze-baseline.json`, `.shellcheckrc`, `mypy.ini`, `prek.toml`,
  `ruff.toml`, `scripts/check-legacy-freeze.sh`, `scripts/lib`,
  `tests/e6_zero_legacy_surface_test.sh`, `tests/legacy_freeze_test.sh`, `ts-tooling`.
- **Planned ACs:**
  1. **End state.** No `eligible` entry remains. Every remaining legacy file is a
     template-conformant `compat-shim`, a `scaffold-template`, a `test-wrapper` or a
     `kept-language` file citing its consumer. Zero eligible implementations is not zero
     `.py` or `.sh` files.
  2. **Zero-legacy test.** `tests/e6_zero_legacy_surface_test.sh` is red when an
     implementation reappears on a converted surface, a shim drifts from its template, a
     non-eligible class grows, or a surviving file loses a D5 check. Each case has a
     negative fixture.
  3. **Verification, not deferral.** This goal fixes nothing an earlier goal left red.
     `ts-tooling/README.md` describes the toolchain, the shims and how to run every
     check. README.md, CONTRIBUTING.md and AGENTS.md need no edit, because every
     documented command still resolves.
  4. **Provenance.** D13 steps 2–5 re-run at this goal's head.

### Mapping from the superseded 8-goal generation `5e11d668`

| Goal | Change |
|---|---|
| `00-ledger` | Registered now. Scope from 20 entries to 18, with 2 existing files reserved instead of 5: `prek.toml`, `ci-prek.yml` and `security.yml` move to 01. It gains node isolation, workspace hygiene, five ledger classes and in-flight entries. |
| `01-py-leaf` | Planned. It drops the three `kept-language` files and the lock-contention port, and gains prek registration and the two workflows. |
| `02-v1-port` | Planned. It gains the `interpreter-diagnostic` class, consumer corpora, commit-and-path anchors and the B2 fallback. |
| `03-py-lib` | Planned. It gains the D13 procedure, live smoke, rollback and the G3 mapping. |
| `04-sh-drivers` | Planned. It gains D13, live smoke and the negative-test fix. |
| `05-test-harness` | Planned. It owns #105's `tests/local_ci_declaration_test.py`; owner `successor` is gone. |
| `06-names-batch` | Planned. It gains the 14-day fallback. |
| `07-ratchet-close` | Planned. Its end state counts `kept-language`. |

## Verification commands

Every goal lists only `bash tests/run-tests.sh` and `git diff --check`.

The publisher refuses a `bash tests/...` script that is absent at the base
(`verification_not_at_base`), and that check is never relaxed. The new checks are
therefore named in each goal's scope and acceptance criteria instead. They reach the
suite because the runner executes every `tests/**/*_test.sh`. Each goal's evidence also
records `prek run --all-files`.

## Non-goals

- **Scaffold templates and their mirrors.** E6 does not convert:
  - `03-configure-generate/**/templates/**` and `03-configure-generate/wizard/template.sh`;
  - the two `hitl-loop.template.sh` files;
  - `reference/**`;
  - the three scaffolded `scripts/*.sh` mirrored byte-for-byte in `reference/golden-*`.

  Their language is part of the consumer scaffold contract, owned by ai-catapult-init
  and af-06. They stay shell under the D5 shell checks.
- **Consumer-copied files.** The four `kept-language` files (D6) stay in their language.
  Converting one needs a generation that co-plans the ai-catapult or release-template
  change. E6 plans none.
- **The runner contract.** `tests/run-tests.sh`, `tests/test-scripts.sh`,
  `tests/test-skills.sh` and every `*_test.sh` wrapper stay bash. Only their embedded
  Python moves.
- **Out-of-repo and shared surfaces.** E6 does not touch:
  - root, ai-catapult or ai-factory Python;
  - `catalog.json` or `skills.lock.json`;
  - the policy file, the v1 registry, readiness-v1 payloads or the four TSWC bundles;
  - `README.md`, `CONTRIBUTING.md` or `AGENTS.md` (every command they document still
    resolves);
  - skills' `.ai/workflows/repo-workflow.json` (af-06's declaration);
  - any hosted job name.
- **Retiring compatibility names.** It needs a later decision.

## Risks

- **Canonical JSON drift breaks every digest.** D8 fixtures and the D13 procedure catch
  it before any switch.
- **A defective TS certifier after a switch.** The D13 live smoke runs before the switch.
  Recovery is the source-lane rollback pinned to the pre-switch commit (D13 step 9).
- **The node toolchain is absent in a gate, on CI or on a host.** The policy-tools
  amendment makes the tooling gate check `node` and `npm` before goal 00 dispatches.
  Shims also refuse with `node_unavailable`, `tests/ts_tooling_test.sh` fails closed,
  and the bootstrap is pinned.
- **Environment or ancestor files steer node.** The `env -i` allowlist, `.mjs` output,
  `node:`-only imports and the version guard close this. The G3 node shadowing test
  proves it.
- **Reservation footprint.** An active goal's scope reserves its paths against every
  non-goal PR. This generation reserves only goal 00's scope, until goal 00 merges:

  | | Superseded 8 goals (`5e11d668`) | This generation |
  |---|---|---|
  | Registered goals | 8 | 1 |
  | Scope entries, excluding free planning paths | 193 | 17 |
  | Existing tracked files reserved | 159 (154 files, plus the 5 in `04-validate-handoff/autobahn/lib`) | 2 (`.github/workflows/ci.yml`, `tests/test-scripts.sh`) |
  | New paths reserved | 38 | 15 |
  | Window | publication → each goal's merge, after O8 | publication → goal 00's merge, after O8 and the amendment |

  The spec copy is bound while the plan is active, and the branch namespace
  `(feat|fix|chore)/e6-skills-legacy-ts-*` is reserved. No open non-goal PR touches
  `ci.yml` or `tests/test-scripts.sh` at publication. Each successor reserves only its
  own goal's paths, from its publication to its merge. Goal 05 is the widest: 48
  existing test files at `980cedb6`, plus its parity test and the in-flight files.
- **Hot files.** `.ai/ci/local-ci.json`, the manifests, the ledger and the lint configs
  are touched by every conversion goal. One-goal-at-a-time publication orders them.

## Plan-level acceptance

- After `e6-sk-07-ratchet-close`, no `eligible` entry remains. Every remaining `.py` or
  `.sh` file is a template-conformant shim, a scaffold template, a test wrapper or a
  `kept-language` file.
- v1 outputs equal the frozen Python's outputs byte-for-byte, outside the
  `interpreter-diagnostic` class. ADR-0016 records the amendment, including the explicit
  malformed-input byte change, and the freeze test proves masked output-equivalence.
- Every registered generation, approval tag, certificate and audit result re-derives
  unchanged (D13).
- The ledger's eligible count shrinks monotonically. Every conversion PR carries its own
  checks and pins.

## Review corrections (round 2)

| Finding | Fix |
|---|---|
| **C1** O8 anchored to the held ACH-S-08 | O8 is the commit the D1 coordinator records (today the S-08 successor `ach-skills-s08-gate-workspace-repair`/`ACH-S-08`, per D5-20261006). Facts on main are cited by path and line. Held, uncredited claims are not blocking ([Dispatch gate](#dispatch-gate-o8); goal 00 AC1). |
| **H1** Python exception text in v1 output | The named `interpreter-diagnostic` class. The ADR-0016 amendment states the malformed-input byte change. Every `str(error)` site and both branches of line 785 are corpus targets, and the consumers' v1 generations join the corpus ([D2](#the-interpreter-diagnostic-class)). Goal 00's harness supports declared classes (AC13). |
| **H2** No node isolation | `env -i` allowlist with no `NODE_*` names, `.mjs` output, `node:`-only imports, a version guard, and the G3 test `tests/e6_node_shadowing_test.sh`. Goal 03 maps the runpy and `-I` cases onto it ([D3](#d3-permanent-compatibility-entrypoints); goal 00 AC10–AC12). |
| **H3** D13 not runnable, no rollback | The concrete [D13 procedure](#d13-provenance-procedure): reference and candidate lanes, audit and export for every plan, tag verification, normalizations, anchor-host evidence, live smoke and rollback. ADR-0018 records the principle (goal 00 AC10). |
| **H4** #105's Python unowned | Owner `e6-sk-05-test-harness`, listed as an in-flight entry. Goal 00 never waits for #105 ([D6](#d6-ledger-and-ratchet); goal 00 AC6). |
| **H5** About 170 paths reserved pre-O8 | Goal 00 only: 17 reserved entries, 2 of them existing files ([Risks](#risks)). |
| **M1** Consumer-copied scripts | The `kept-language` class, with the ai-catapult citations ([D6](#d6-ledger-and-ratchet)). |
| **M2** Caches in the gate workspace | No-cache flags, declared outputs and a hygiene red test. ruff joins tool provenance ([D4](#d4-runner-and-packaging), [D5](#d5-strict-check-stack); goal 00 AC5, AC8). |
| **M3** Negative tests satisfied by `node_unavailable` | Distinct refusal statuses, and the D8 negative-test rule with the two cited cases ([D8](#d8-differential-parity); goals 01–05). |
| **M4** Amendment side effects | Named in D4: the test flips, every approval voided, rule (d), and approval timing with re-signing ([D4](#d4-runner-and-packaging); goal 00 AC2). |
| **M5** TS test output and monkeypatching | `ts-tooling/build` via `tsconfig.test.json`; one seam mechanism chosen in ADR-0018 ([D4](#d4-runner-and-packaging); goal 00 AC3, AC10). |
| **M6** Goal 06 waits on E7 | A 14-day fallback ([D10](#d10-the-af-06-batch-and-tier-names)). |
| LOW: dependency text | The PR body's dependency column matches the successor order. |
| LOW: (2b) and #107 | #107 also appends to the registry and graph. It merged first (`980cedb6`), so this publication was rebuilt on it: E6's entry is appended after TSWC's, and the graph keeps both prefixes. |
| LOW: sha256 anchor | Commit-and-path anchors checked by blob id and sha256 ([D2](#d2-v1-port-and-the-adr-0016-amendment)). |
| LOW: v1 imports and tsc | `node:`-only imports; a tsc upgrade is an ADR-0016 event (D2). |
| LOW: ADR-0016 Verification section | It is amended too (D2). |
| LOW: B2 withdrawn | Goal 02's B2 fallback. |

Also applied, by coordinator direction of 2026-10-08:

- TSWC B2 is a one-way prerequisite of goal 00, not a cross-plan claim conflict. B2's
  claims shared with E6 are listed ([Dispatch gate](#dispatch-gate-o8); goal 00 AC1).
- The narrowed-form commitment for the two retained-policy tests, formerly in
  `e6-sk-02` AC7, is carried into goal 02's planned text.
