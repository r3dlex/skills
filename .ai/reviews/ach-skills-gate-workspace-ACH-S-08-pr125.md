# Independent review: PR #125 (ACH-S-08, the O8 anchor)

**Subject:** `r3dlex/skills` PR #125 — goal ACH-S-08 / D1-02, the goal whose merge is the O8 anchor.
**Merge commit:** `f5e338b92bb754c2bfffdf542b498530258fdbc0`.
**PR head (branch `feat/ach-skills-gate-workspace-ACH-S-08`):** `1691051cbaad32830f7c4e55241406f28591f39a`.
**Base (origin/main before the merge):** `809006bf84c918b2e4198a0b1169f4772478a9ae`.
**Reviewed at:** 2026-10-09.

## Why this file exists

The merged PR #125 body claims its review lane ran. No review artifact was ever
persisted for it. The only traces were two *reviewer prompts* and one interrupted run:

- `/tmp/s08-scripts/review_s08.md` and `/tmp/s08-scripts/review_s08.final.md` — 25-line
  instructions to a reviewer, identical apart from the head sha (`.final` names head
  `48b30c74`, base `809006bf`).
- `/tmp/s08-scripts/review_s08.out` — a 124 KB model run that ends `RC=130` (SIGINT)
  mid-run and contains no verdict string.

A claimed review with no verdict is not a review. This record does not treat it as one.
It is replaced by the review below, run out-of-band from the #125 authoring lane.

## Method and provenance

- **Reviewer:** a fresh `code-reviewer` sub-agent (`oh-my-claudecode:code-reviewer`,
  session `<session>`), spawned for this reconciliation task with no shared context
  with, and no authorship of, PR #125.
- **Posture:** read-only — the reviewer was instructed to edit, create, delete, commit,
  push, rebase or merge nothing anywhere, and to use only read-only commands.
- **Evidence base:** the reviewer worked from a clean checkout whose tree is
  byte-identical to the merge (`<home>/Ws/Personal/worktrees/ach-skills-s08-20261009`,
  HEAD `1691051`; both trees `3341558f6849157766c6cd0422645aa7d1e21ec7`), the goal
  contract's ACH-S-08 entry as the authority, and by running the declared verification
  and the AC-6 untouched-test list itself.
- **Scope note:** AC8 (the consumer scratch-run record) was declared out of scope for
  this reviewer; the reconciliation lane handles it separately. This review covers the
  code and every in-scope AC.
- **Redaction:** the prompt and report below are verbatim except that home-directory
  paths are replaced with `<home>` and the reviewer session id with `<session>`, per the
  repository's publication policy *Private content* rules for the `review` kind. No
  finding, number or verdict was changed by the redaction.

## Prompt (verbatim, redaction aside)

```text
You are an INDEPENDENT REVIEWER. READ-ONLY: do NOT edit, create, delete, commit, push, rebase, or merge anything anywhere. Only read files and run read-only commands (git show/rev-parse/diff/log/status, python3, bash on test entry points, gh api --method GET, ls, cat, grep).

SUBJECT: merged PR `r3dlex/skills#125` (goal ACH-S-08 / D1-02, the "O8" anchor).
- merge commit: f5e338b92bb754c2bfffdf542b498530258fdbc0
- PR head (branch `feat/ach-skills-gate-workspace-ACH-S-08`): 1691051cbaad32830f7c4e55241406f28591f39a
- base (origin/main before the merge, merge-base): 809006bf84c918b2e4198a0b1169f4772478a9ae
- an existing CLEAN checkout whose tree is byte-identical to the merge: <home>/Ws/Personal/worktrees/ach-skills-s08-20261009 (HEAD 1691051). Use it; do not modify it.
- goal contract (ACH-S-08 acceptance criteria + declared scope[]): `.ai/handoff/readiness-v2/ach-skills-gate-workspace/22d460b273badda208918248b877c362ea72585fd8269fcdb685e50b4e8645fa/goals.json` in that checkout — read the ACH-S-08 entry. It is the authority; never trust this prompt's framing over the contract and the code.

YOUR TASK — verify the merged change against the ACH-S-08 acceptance criteria from PRIMARY EVIDENCE and report what YOU find.

1. `git -C <wt> diff --stat 809006bf84c918b2e4198a0b1169f4772478a9ae..1691051cbaad32830f7c4e55241406f28591f39a` — list changed files and confirm they fall within the declared scope[] (13 paths; a 14th, tests/readiness_v2_gate_shadowing_test.py, is claimed as an authorized addition). Report any file changed outside scope and any scoped file NOT touched.
2. Read the diff and judge each AC by the code+tests, not by commit messages or the PR body:
   - [Declaration] local-ci/2 schema: workspace with exactly bootstrap/dependencies/outputs; bootstrap entries exactly `npm ci`, `npm ci --ignore-scripts`, or `bash <path>` with <path> a pinned sources key; npm form requires a pinned package-lock.json/npm-shrinkwrap.json; dependencies/outputs unique, normalized, repo-relative literals, no glob char, no `..`, no `.git` component in any case, no entry equal to/containing/inside another; local-ci/1 unchanged; local-ci/2 without workspace refused.
   - [Observed at head] observer reads .ai/ci/local-ci.json from the head tree, validates with the pinned lib/local_ci_contract.py, refuses tracked/containing/not-ignored declared paths as gate_workspace_declaration_invalid:<reason> before any command.
   - [Bootstrap] each bootstrap entry run as argv with shell=False, stdin closed, env hardened with GIT_CONFIG_NOSYSTEM=1, GIT_CONFIG_GLOBAL=/dev/null, GIT_TERMINAL_PROMPT=0, npm_config_userconfig=/dev/null, npm_config_cache inside the derivation temp dir; non-zero -> gate_workspace_bootstrap_failed:<command> and no gate runs.
   - [Outputs] untracked paths allowed only under dependencies+outputs; tracked checks after every gate; observed-root checks unchanged; refusal code gate_workspace_undeclared_output:<path>.
   - [Provenance] one gate-workspace/1 record per certify-v2/merge-v2 derivation with the full field list; results and driver log carry its path and sha256.
   - [Compatibility] skills' own .ai/ci/local-ci.json stays local-ci/1; lib/verification.py not modified; the listed tests pass unmodified.
   - [Documentation, consumers] modules/ci-gate.md documents local-ci/2 with the ai-catapult and ai-factory consumer shapes; modules/readiness-v2.md and ADR 0017 add the declaration, policy, provenance and codes.
   - [Hygiene] both readiness-dependency-v2.json copies and .ai/ci/local-ci.json re-pinned; .ai/evidence/ACH-S-08.json present with red and green legs; autobahn and northstar SKILL.md unchanged.
   Note explicitly: AC8 (the PR-body scratch-run record) is OUT OF SCOPE for you — do not attempt the network consumer runs; another lane handles AC8.
3. Run from the checkout and report EXIT CODES + tails: `bash tests/run-tests.sh`; `git diff --check`; and the AC-6 untouched list: tests/readiness_v1_freeze_test.sh, readiness_v2_core_test.py, readiness_v2_approval_test.py, readiness_v2_certificate_test.py, readiness_v2_identity_test.py, readiness_v2_gate_shadowing_test.py, local_ci_contract_test.py, autobahn_local_ci_test.sh, autobahn_run_gates_test.sh, autobahn_ci_gate_test.sh, readiness_v2_context_test.py, northstar_v2_publish_test.py, readiness_v2_migrate_test.py, readiness_v2_e2e_test.py, readiness_v2_fixture.py, readiness_v2_gate_workspace_test.py, plus new local_ci_contract_v2_test.sh and readiness_v2_gate_bootstrap_test.sh. Run python tests as `python3 -I -B <file>`.
4. Look for the failure modes that matter: stubs/skipped/`.only` tests; assertions that cannot fail; a gate weakened to pass; a check reading the observed root instead of the workspace; shell=True in the bootstrap; credentials reachable; a provenance record written but never referenced; the AC1/AC6 byte-pin re-pin materially weakening an assertion.
5. State a clear line: `VERDICT: VERIFIED` only if scope and every in-scope AC hold and all listed suites pass; otherwise `VERDICT: MISMATCH` naming the exact failing AC and the raw evidence. Then `MERGE ADVICE: MERGEABLE ON FULL GREEN` or `MERGE ADVICE: DO NOT MERGE (reason)`.

Report raw numbers and command output you actually observed. If you cannot verify something, say so explicitly rather than guessing. End your reply with the two lines VERDICT and MERGE ADVICE, then a short list of any residual uncertainties.
```

## Report (verbatim, redaction aside)

**Checkout reviewed (read-only):** `<home>/Ws/Personal/worktrees/ach-skills-s08-20261009`
(HEAD `1691051`, tree byte-identical to merge `f5e338b92bb754c2bfffdf542b498530258fdbc0`;
both trees = `3341558f6849157766c6cd0422645aa7d1e21ec7`).
**Contract read:** `<home>/Ws/Personal/worktrees/ach-skills-s08-20261009/.ai/handoff/readiness-v2/ach-skills-gate-workspace/22d460b273badda208918248b877c362ea72585fd8269fcdb685e50b4e8645fa/goals.json`
(ACH-S-08 entry).

### Scope verification (AC: declared scope[])

The raw `git diff --stat 809006bf..1691051` reports **18 files, +1336/-97**. That is NOT
the PR's change set: HEAD `1691051` is a merge of origin/main (`829e5d3`) into the branch,
and main's commit **`85f624e`** ("docs: align four working plans with TypeScript-only final
state", parent `809006bf`) is an ancestor of `829e5d3`. The four extra files therefore
arrive from main, not from the goal:

- `.ai/work-intake/autobahn-fail-closed-gates.md`
- `.ai/work-intake/autobahn-startup-fail-closed.md`
- `docs/specifications/ACTIVE/init-ai-repo-agentic-engineering-end-state.md`
- `docs/specifications/ACTIVE/init-ai-repo-omx-omc-4-phase-sdlc.md`

The branch's own seven commits (`7842904`, `5884cc4`, `a72568e`, `dc9b95c`, `56e6a94`,
`1973436`, `48b30c7`) touch exactly the **13 declared scope paths +
`tests/readiness_v2_gate_shadowing_test.py`** (the claimed 14th). **Every scoped path is
touched; none is missing.** No branch-authored file lies outside scope.

### AC-by-AC (judged on code + tests, not commit messages)

- **AC1 [Declaration, local-ci/2]** — Holds. `lib/local_ci_contract.py` gains
  `SCHEMAS={'local-ci/1','local-ci/2'}`, `declared_path` (normalized/repo-relative, no glob
  `[*?\[]`, no `..`, no `.git` in any case, no backslash), `validate_workspace` (workspace
  exactly bootstrap/dependencies/outputs; bootstrap ∈ {`npm ci`, `npm ci --ignore-scripts`,
  `bash <pinned source>`}; npm form requires `package-lock.json`|`npm-shrinkwrap.json` in
  sources; uniqueness + mutual non-nesting across both lists), `read_record` (local-ci/2 =
  local-ci/1 fields + workspace; local-ci/1 = the 4 fields only; /2-without-workspace
  refused), `read_declaration` (None for /1). `read_contract` preserved.
  `tests/local_ci_contract_v2_test.py` = **11 tests OK**.
- **AC2 [Declaration observed at head]** — Holds. `gate_declaration(workspace)` reads
  `workspace/.ai/ci/local-ci.json` and validates via `local_ci.read_record` (the pinned
  lib); `declaration_refusals(workspace, head, ...)` uses `git(workspace, ls-tree …)` and
  `ignored_at_head(workspace, …)` (`git check-ignore --no-index`), refusing
  `gate_workspace_declaration_invalid:<reason>` **before** any command. local-ci/1 or
  absent → declares nothing. Covered by `DeclarationTests`.
- **AC3 [Bootstrap policy]** — Holds. `bootstrap_argv` → list; `command()` uses
  `subprocess.run([...], stdin=DEVNULL)` (no `shell=True` anywhere in observer.py),
  executed in the workspace before the gates. `bootstrap_env` = `gate_env(home)`
  (PATH/LANG/LC_ALL/TMPDIR/HOME/PYTHONDONTWRITEBYTECODE only) + `GIT_CONFIG_NOSYSTEM=1`,
  `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`, `npm_config_userconfig=/dev/null`,
  private `npm_config_cache` under the derivation tmpdir. Non-zero →
  `gate_workspace_bootstrap_failed:<command>`, no gate runs (asserted by
  `test_a_failing_bootstrap_refuses_and_no_gate_runs`).
- **AC4 [Outputs]** — Holds. `workspace_violations` rewritten to allow untracked paths only
  under declared dependencies (post-bootstrap) / dependencies+outputs (post-gates); tracked
  re-check after the gates; observed-root checks (`tree_state`,
  `worktree_changed_during_gates`, `git_metadata_changed_during_gates`) unchanged;
  `gate_workspace_undeclared_output:<path>` preserves the shallowest-ignored-ancestor
  reporting (npm-fixture `dist-snapshot` case asserted).
- **AC5 [Provenance]** — Holds. `write_gate_workspace_record` writes one `gate-workspace/1`
  record per derivation (schema, head, tree, contract sha256+schema, bootstrap entries with
  executable/`--version`/node_version/exit/duration, `inputs`, `dependencies`/`outputs`
  streaming rows via `declared_path_rows`+`streamed_sha256`, `network: bootstrap`,
  workspace). `op_certify` results carry `gate_workspace_record`; `op_merge` too; `log_exit`
  writes it to `driver-log.jsonl`. Certificate `gate_workspace` binds the certify-op record
  (merge binds certify, writes its own merge record). All asserted in `ProvenanceTests`.
- **AC6 [Compatibility]** — Holds, with one documented deviation (Finding 1). skills' own
  `.ai/ci/local-ci.json` schema = **`local-ci/1`**; `lib/verification.py` untouched; no file
  added to `readiness-dependency-v2.json` (only two sha256 values re-pinned); SKILL.md files
  untouched.
- **AC7 [Documentation]** — Holds. `ci-gate.md` documents local-ci/2 with both consumer
  shapes (ai-catapult `bash setup.sh`/vendor/dist/dist-snapshot, ai-factory
  `npm ci --ignore-scripts`/node_modules) and the re-pin-same-change rule;
  `readiness-v2.md` + ADR-0017 add the declaration, network/credential policy, the record
  and codes `gate_workspace_declaration_invalid`/`gate_workspace_bootstrap_failed`. Asserted
  by `DocumentationTests`.
- **AC8 [PR-body scratch run]** — OUT OF SCOPE per instructions; not attempted.

### Commands actually run (raw results)

- `bash tests/run-tests.sh` → **EXIT 0**; tail: `Passed: 2 / Failed: 0 / OVERALL: PASSED`
  (Shell Script Tests PASSED; Skill Structure `Results: PASS=184 FAIL=0 WARN=0 SKIP=0`).
- `git diff --check` (range and worktree) → **EXIT 0**; working tree clean, no untracked
  files.
- New tests: `python3 -I -B tests/local_ci_contract_v2_test.py` → **Ran 11 tests … OK**;
  `python3 -I -B tests/readiness_v2_gate_bootstrap_test.py` → **Ran 18 tests in 73.3s …
  OK**.
- AC-6 untouched list (python): core **21 OK**, identity **18 OK**, gate_shadowing **8 OK**,
  local_ci_contract **25 OK**, context **11 OK**, northstar_v2_publish **29 OK**, migrate
  **16 OK**, e2e **24 OK**, gate_workspace **16 OK**; wrapper-only: approval **15 OK**,
  certificate **59 OK**. Shell: readiness_v1_freeze **PASS=19**, autobahn_local_ci
  **PASS=88**, autobahn_run_gates **PASS=18**, autobahn_ci_gate **PASS=130** (all FAIL=0).
  `readiness_v2_fixture.py` is a fixture module with no standalone tests.
- Note: direct `python3 -I -B tests/readiness_v2_approval_test.py` /
  `…certificate_test.py` fail with `ModuleNotFoundError: readiness_v2_core_test` — an
  *invocation* artifact, not a repo defect: those two (unlike the new tests) omit
  `sys.path.insert`, and their repo wrappers use `python3 -B` without `-I`. Both pass via
  their wrappers and in `run-tests.sh`.
- Byte pins verified: `local_ci_contract.py`=`5ba151b8…`, `observer.py`=`b6c839d3…`,
  `readiness_v2_gate_shadowing_test.py`=`23bff269…`, and the four new test pins all match
  `.ai/ci/local-ci.json` / `readiness-dependency-v2.json`.

### Issues / observations

1. **[MEDIUM / confidence HIGH] AC6 literal deviation —
   `tests/readiness_v2_gate_shadowing_test.py` is modified (4+/2–) although AC6 lists it
   "pass unmodified."** Materially **not** a weakening: only `LOCAL_CI_CONTRACT_SHA256` is
   re-pinned (`1e57533c…`→`5ba151b8…`) plus the adjacent comment; the assertion
   `sha256(AUTO/lib/local_ci_contract.py) == LOCAL_CI_CONTRACT_SHA256` and the whole
   isolation property (shadow-module non-supply, outcome equality, runpy-from-pinned-lib)
   are unchanged. It is documented in `.ai/evidence/ACH-S-08.json` `reconciliation[]` and
   self-declared an authorized 14th scope addition. The stop clause in AC6 ("…if a merged
   test turns out to assert **in-place gate execution**…") is not triggered — the test
   asserts byte-pin isolation, not in-place execution. Fix: none required; flag for the
   consumer that AC6's "unmodified" is satisfied in spirit, not literally.
2. **[LOW / confidence HIGH] Raw base..head diff over-reports scope** — 4 files from main's
   merged commit `85f624e`. Not PR-authored; no goal scope violation.
3. **[LOW / confidence LOW] `bootstrap_inputs` and `head_local_ci` read the contract blob
   from the observed root at `head` (`git cat-file head:.ai/ci/local-ci.json`), not from the
   workspace file.** Equivalent (workspace borrows the same objects; head is bound) and
   arguably preferable as an immutable provenance pin; AC2's workspace read is done
   separately by `gate_declaration`. Not a defect.
4. **[LOW / confidence MEDIUM] "tracked checks after every gate" is executed after all four
   gates complete** — the `for _ in gates:` loop re-checks the identical final workspace
   state. Carried verbatim from ACH-S-07 (which AC4 cites as the authority) and the "change
   undone within one gate is not seen" residual risk is documented. Not introduced by this
   PR.

### Failure-mode sweep

No `skipTest`/`@unittest.skip`/`.only`/TODO/`assert True` stubs; no `shell=True`; bootstrap
credentials unreachable (test asserts `GH_TOKEN`/`SSH_AUTH_SOCK`/`GH_CONFIG_DIR` absent, no
user config/global git); the record is written **and** referenced (certificate + result +
driver log); no gate relaxed (observed-root `tree_not_clean`/`worktree_changed_during_gates`/
`git_metadata_changed_during_gates` unchanged; local-ci/1 path returns `declaration=None` →
strict workspace). The AC1/AC6 byte-pin re-pin does not weaken an assertion (Finding 1).

### Positive observations

Byte-exact pin discipline (7/7 pins verified); bootstrap hardening proven by executable
tests, not prose; clean reuse of ACH-S-07 fixtures (`GateWorkspaceTests`); negative cases per
declaration rule; docs updated in lockstep with behavior.

### Residual uncertainties

- AC red legs (exit 1 at `809006bf`) are **recorded**, not independently re-run (would
  require building a base worktree). Consistent with the code delta: `read_declaration` and
  the `gate-workspace/1` record did not exist at base, so the new tests would fail there.
- AC8 not evaluated by design.

## Verdict

```text
VERDICT: VERIFIED
MERGE ADVICE: MERGEABLE ON FULL GREEN
```
