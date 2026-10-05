# Isolated gate workspace (`skills`, plan `ach-skills-gate-workspace`)

ID: `ACH-20261002` follow-up D1, plan `ach-skills-gate-workspace`
Status: **Planning copy; execution unauthorized**
Execution authorization: **none**. Registration, visibility or discovery never grants approval, readiness or execution authority.

Intended repository path once published: `docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-gate-workspace.md`. This is a free planning path. Once a generation binds it, it is reserved against non-goal PRs.

## Relationship to the umbrella

- The umbrella specification `ACH-20261002` (`r3dlex/ai-tool-workspace`, `docs/specifications/ACTIVE/admission-complete-handoffs.md`) is pinned at sha256 `e6feb698bde18356f0d49c497b7f368f242f39bc254b12942f7f1902408cee39` (root `87274a6`).
- This plan is **not** one of the umbrella's four plans. It resolves blocker D1, recorded in the ACH execution log (section 9, 2026-10-04). It does not restate or amend the umbrella.
- It relies on exactly two umbrella statements:
  - **O8** ("merged to skills `main` at a named commit, checked mechanically by git ancestry");
  - **Merge certificate (`merge-certificate/1`)**, which binds "local gate results".
- It supersedes no umbrella statement. The umbrella never requires gates to run in the observed tree. That requirement exists only in merged code and in `modules/readiness-v2.md` ("issues `merge-certificate/1` only at one exact, clean head"), and this plan keeps it for the observed root.
- For any disagreement with the pinned umbrella, the umbrella wins, and this plan's preparation is blocked until a new planning copy is published.

## Problem (D1)

At skills `origin/main` `75e6b75`, the certificate derivation is `lib/observer.py` `derive_certificate`, lines 1210–1262.

1. It calls `tree_state(root)` before and after the gates (lines 702–743). `tree_state` is clean only when every on-disk path except `.git` is a HEAD path whose bytes and mode equal the HEAD blob. Ignored files therefore count.
2. It runs `run_local_gates(root, goal)` (lines 1186–1207), which passes `--root <observed root>` to all four gates.
3. It then compares S-03's `worktree_snapshot(root)` with the admission snapshot (`worktree_changed_during_gates`).

The two consumer repositories cannot satisfy this:

- **ai-catapult `a87c912`.** Its local CI contract and every goal run `npm test`. That needs the gitignored `vendor/`, which `bash setup.sh` vendors from `skills.lock.json`. `npm test` writes `dist/` and `dist-snapshot/`.
- **ai-factory `69ed795`.** `npm test`, `npm run lint` and `npm run typecheck` need `node_modules/`.

Either the observed tree holds those paths, which refuses as `tree_not_clean`, or the gates fail. So the C and F plans can never be certified.

Planning spike, 2026-10-04. Scratch clones only, run under a gate-like environment with a throwaway `HOME`, no credentials, `GIT_CONFIG_NOSYSTEM=1`:

| Repository | Bootstrap | Gates | Untracked paths after the run | Tracked files changed |
|---|---|---|---|---|
| ai-catapult `a87c912` | `bash setup.sh` (exit 0, network fetch of `26d25105`) | `npm test`: 248 of 248 pass | `vendor/`, `dist/`, `dist-snapshot/` | none |
| ai-factory `69ed795` | `npm ci --ignore-scripts` (exit 0) | `npm test`: 237 of 237 pass when the umbrella is reachable, 5 umbrella-drift failures outside it; `lint` and `typecheck` pass | `node_modules/` (vitest writes its cache to `node_modules/.vite`) | none |

## Decisions

**W1. Where gates run.**
- `certify-v2` and `merge-v2` run the four local gates only in an observer-built **gate workspace**:
  - a new repository with an empty template, no remote and no hooks;
  - it borrows the observed repository's objects read-only through `objects/info/alternates`, the same pattern as ACH-S-04's planning simulation;
  - it checks out the PR head detached.
- Location (coordinator ruling): a new directory **under the observed root's parent** (a sibling of the observed root), whose name matches an existing ignored pattern of the umbrella/root `.gitignore` (the concrete name is verified at publication time; the copy never lives inside the observed root). Its physical path is what the observer hands to the gates.
  - The location is on the same filesystem as the repository.
  - No working-tree walk covers it: the observed root's walks never descend into a sibling directory.
  - It sits inside the umbrella whenever the repository does. ai-factory's drift test needs that: it finds the umbrella by walking ancestor directories for `.ai/matrix.json`.
- The workspace is removed when the derivation ends. A leftover from an interrupted run is never reused.

**W2. The observed root keeps every existing check unchanged:**
- `tree_not_clean`, ignored files included;
- the head checks;
- the admission snapshot (`worktree_changed_during_gates`).

Certify still runs from a clean, registered worktree at the PR head, for example `git worktree add --detach <path> <head>`. No gate is relaxed.

**W3. Workspace integrity.**
- Before the gates, `tree_state(workspace)` must be clean at the PR head; otherwise the derivation refuses with `gate_workspace_unfaithful`.
- After the bootstrap and after every gate, these must still equal the head tree:
  - `HEAD`;
  - the index entries (`ls-files --stage`);
  - every tracked path's bytes and mode.
- Untracked and ignored paths may exist only under declared paths.
- Each violation refuses with `worktree_changed_during_gates` plus a detail code: `gate_workspace_tracked_changed:<path>` or `gate_workspace_undeclared_output:<path>`.
- With no declaration, the workspace meets today's byte-clean standard.

**W4. Declaration (`local-ci/2`).**
- `.ai/ci/local-ci.json` may use schema `local-ci/2`: the `local-ci/1` fields plus a required `workspace` object with exactly `bootstrap`, `dependencies` and `outputs`.
- `bootstrap` admits exactly these forms:
  - `npm ci`;
  - `npm ci --ignore-scripts`;
  - `bash <path>`, where `<path>` is a pinned `sources` key.
- An npm form needs a pinned `package-lock.json` or `npm-shrinkwrap.json`.
- `dependencies` (written by the bootstrap) and `outputs` (written by the gates) are literal relative paths that:
  - do not nest in each other;
  - are untracked at the head and contain no tracked path;
  - are ignored by the head's ignore rules.
- The observer reads the declaration from the workspace, so from the head tree.
- `local-ci/1`, or no contract, declares nothing.
- The pins already in `sources` serve as the input pins, so there is one pin map, not two.

**W5. Network and credentials policy.**
- The bootstrap is the only step a declaration grants, and network access is permitted for it. Both `npm ci` and `setup.sh` fetch.
- The bootstrap is constrained by:
  - the allowlisted forms;
  - inputs pinned at the head;
  - `npm ci`'s lockfile integrity check;
  - the bootstrap environment: the gate environment plus `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`, `npm_config_userconfig=/dev/null`, and a private `npm_config_cache`.
- No token, agent socket, keychain credential helper or user configuration reaches the bootstrap.
- Gates are not network-isolated today, and this plan does not add a sandbox. That is recorded as a residual risk.
- An offline mode (an observer-owned content-addressed cache) is a follow-up.

**W6. Provenance.**
- Every `certify-v2` and `merge-v2` derivation writes a `gate-workspace/1` record under `<git common dir>/ai-catapult/observer/gate-workspaces/<plan>/<goal>/<pr>-<head>-<op>.json`.
- The record holds:
  - the head and its tree, and the contract's sha256 and schema;
  - each bootstrap command, with its resolved executable, `--version` output, exit code and duration;
  - the pinned input digests;
  - a streaming digest of each dependency path, excluding nested `.git` directories, which are listed;
  - the outputs present after the gates;
  - `network: bootstrap`.
- The `certify-v2` and `merge-v2` results and the driver log carry the record's path and sha256, and the certificate's `gate_workspace` field (W9) binds them.
- The record is evidence; the certificate is what binds it.

**W7. Git metadata.**
- Inside the workspace, a gate's `git` reaches only the workspace's own git directory.
- The observer snapshots the observed common directory's `config`, `hooks/`, `info/` and `objects/info/alternates` around the gates, and refuses any change with `git_metadata_changed_during_gates`.
- Every check after the gates uses the target commit resolved before them, never a re-read of `origin/<target>`.

**W8. Environment and the in-place phases.**
- `gate_env` keeps its variables: `PATH`, `LANG`, `LC_ALL`, `TMPDIR`, a throwaway `HOME`, and `PYTHONDONTWRITEBYTECODE=1`.
- The gate scripts keep `python3 -I -B`.
- Every path handed to a gate is physical: `--root`, `--goal-record`, the working directory, `HOME` and `TMPDIR`.
- `run-gates.sh` exports `PYTHONDONTWRITEBYTECODE=1` in its v2 branch.
- `pre-commit` and `local-validation` keep running in place, because they validate the working tree, not a commit.

**W9. The certificate adds one field (coordinator ruling, option 6.1-a).**
- `merge-certificate/1` adds exactly one field, `gate_workspace`: the isolated-copy provenance the certificate binds (the workspace's physical path and the `gate-workspace/1` record's path and sha256). Its `local_gates` entries stay `{name, exit}` for the four gates.
- No admission fact is added, and the context projection is otherwise unchanged.
- `readiness_contract_v2.py` and the v2 JSON schema change only for that one field.
- The certificate binds the head; the head binds the declaration and its pinned inputs; `gate_workspace` binds the isolated-copy provenance of that head's derivation.
- Certificates issued before this plan keep validating (`gate_workspace` is absent there), and `audit-merges` and exported evidence of merged goals stay valid.
- The digest-coupling tests for the certificate are re-derived for the new field; every other certificate case is unchanged.

## Acceptance criteria

The bound text is in `goals.json`. Summary:

| AC | Goal | Criterion |
|---|---|---|
| AC-W1 | ACH-S-07 | Gates run only in a faithful workspace at the PR head, in a sibling directory under the observed root's parent, and the workspace is removed afterwards (W1, W3). |
| AC-W2 | ACH-S-07 | Every observed-root check is unchanged. A gate writing an ignored file still refuses, and the root stays byte-identical (W2). |
| AC-W3 | ACH-S-07 | Tracked-file, index and HEAD integrity after every gate; undeclared untracked paths refuse (W3). |
| AC-W4 | ACH-S-07 | Gates cannot change the observed git metadata. The target is resolved once (W7; S-03 LOW d). |
| AC-W5 | ACH-S-07 | `gate_env` is unchanged, and every path is physical (W8; S-03 LOW b). |
| AC-W6 | ACH-S-07 | Streaming digests in `worktree_rows` and in the workspace checks (S-03 LOW c). |
| AC-W7 | ACH-S-07 | `PYTHONDONTWRITEBYTECODE=1` in `run-gates.sh`'s v2 branch (S-03 LOW a). |
| AC-W8 | both | The certificate adds only the `gate_workspace` field (the isolated-copy provenance it binds); the admission facts and the context projection are otherwise unchanged, pre-plan certificates keep validating, and the digest-coupling tests are re-derived for the new field (W9). |
| AC-W9 | ACH-S-08 | `local-ci/2` declaration rules, with `local-ci/1` unchanged (W4). |
| AC-W10 | ACH-S-08 | Bootstrap under the network and credentials policy, failing closed (W5). |
| AC-W11 | ACH-S-08 | Declared outputs allowed only in the workspace (W3, W4). |
| AC-W12 | ACH-S-08 | `gate-workspace/1` provenance record (W6). |
| AC-W13 | ACH-S-08 | Consumer shapes documented, and a scratch dry run recorded for both consumers. |

## Goals

| Goal | Depends on | Lane | Content |
|---|---|---|---|
| ACH-S-07 | none | skills source lane, v2 | Workspace isolation for `certify-v2`/`merge-v2`; the certificate's `gate_workspace` field; the four S-03 carried LOWs; ADR 0017. Nothing is declared yet. |
| ACH-S-08 | ACH-S-07 | skills source lane, v2 | `local-ci/2` declaration, bootstrap, outputs, provenance record, consumer docs. Its merge commit is O8. |

## Non-goals

- Adding an OS sandbox, or network isolation of the gates.
- Running `pre-commit` or `local-validation` in a workspace.
- Relaxing the observed-root `tree_not_clean` check.
- Changing `merge-certificate/1` beyond the one `gate_workspace` field, or changing the admission facts.
- Editing `lib/verification.py`, which the v1 freeze test pins.
- Adding the record to `export-evidence`. That is a follow-up.
- An offline bootstrap cache.
- Any change in ai-catapult or ai-factory. Their adoption is C-01 and F-01.

## Risks

1. **No containment.** Gates run PR code with the user's uid. The workspace prevents accidental writes and detects the classes listed in W3 and W7, but a gate can still write anywhere. One example: a gate that does `cd ..` out of the workspace lands in the observed root's parent directory, which is the umbrella checkout whenever the repository sits inside one, and `git` acts on that repository there. Refs are not snapshotted; W7 resolves the target once, before the gates. A change undone within one gate is not seen.
2. **Network at certify and merge time.** The bootstrap runs again at merge re-derivation. A registry or GitHub outage refuses, failing closed.
3. **Flaky dependency trees.** A bootstrap that is not reproducible changes only the informational record. The certificate stays deterministic because it carries no dependency digest.
4. **Rebase load.** `lib/observer.py`, the two manifests, `.ai/ci/local-ci.json` and `modules/readiness-v2.md` are also in ACH-S-04, ACH-S-05 and ACH-S-06's scope. This plan runs after S-06 merges (see SCOPE.md).
5. **Unknown S-06 test behavior.** If ACH-S-06's e2e fixture asserts in-place gates, ACH-S-07 stops and the plan is republished. No silent scope exception is taken.
6. **Disk use.** A `node_modules` tree is installed twice per goal (certify and merge), under `.git`. It is removed after each derivation.

## Consumer re-derivations (C and F drafts)

- O8 becomes ACH-S-08's merge commit. It descends from ACH-S-06's merge, so ancestry still implies the earlier O8.
- **ai-catapult:**
  - C-01 upgrades `.ai/ci/local-ci.json` to `local-ci/2`: sources pin `setup.sh` and `skills.lock.json`; bootstrap `["bash setup.sh"]`; dependencies `["vendor"]`; outputs `["dist", "dist-snapshot"]`. C-01 must add the file to its scope.
  - C-02 already scopes `local-ci.json`. It must re-pin `skills.lock.json` there when it changes the pin.
- **ai-factory:** F-01 creates `local-ci/2`: sources pin `package-lock.json` and the scripts; bootstrap `["npm ci --ignore-scripts"]`; dependencies `["node_modules"]`; outputs `[]`.
- Both drop "certify from a linked worktree under the umbrella root". The workspace sits under the observed root's parent (a sibling directory), inside the umbrella whenever the repository is.
- Certify still runs from a clean, registered worktree of the PR head.
