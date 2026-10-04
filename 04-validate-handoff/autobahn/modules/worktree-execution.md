# Same-repository worktree execution

Read this when a canonical handoff must execute in an isolated linked Git
worktree of the **same repository**. This is not cross-repository mapping:
keep the original `handoff-goals/1` repository identity and goal revisions.
Never rewrite identity to the worktree or combine this mode with
`--execution-root` / `mapped-handoff-goals/1`.

## Exact binding

Pass the canonical primary checkout as `--root`, the absolute canonical linked
worktree as `--worktree-root`, and a full base commit as `--base-commit`:

```sh
bash autobahn/prereq-check.sh --root /repo --worktree-root /worktrees/goal-1 \
  --base-commit <40-hex-base> --handoff <registered-id> --goal-id <id> \
  --context /input/independent-context.json --stage implementation
```

The observer verifies Git top-level, common directory, worktree registration,
branch and base ancestry against `refs/remotes/origin/main`. Separate clones,
path aliases, symlinks, unsupported glob scopes and mixed modes fail closed.
Git environment overrides and replacement objects cannot supply that proof.
The observer does not run `git status`, avoiding clean/process-filter execution
and submodule-status recursion. Its Git reads use `--no-lazy-fetch` to prevent
implicit object fetching and network/SSH dispatch. This mode requires Git
**2.45.0 or newer**; missing objects or an unsupported `--no-lazy-fetch` option
fail closed, without a fallback.

The worktree's fixed readiness policy must approve an exact `worktree` binding
with `schema: "git-worktree/1"`, `root`, `base_commit` and
`target_ref: "refs/remotes/origin/main"`. Independent context repeats these
fields plus observed `common_dir`, `head`, `branch`, `target_revision` and
`state_sha256`. Store independent context **outside the worktree**. The
observation binds all working files, including ignored and untracked files,
working bytes, modes, applicable nested instructions and explicit missing/deleted
input markers; only the root Git metadata is excluded. Symlink files/directories
and nonregular files are unsupported. HEAD alone does not establish freshness.
Refresh affected evidence through independent review when it changes; never
rewrite a context merely to make a gate green.

The primary supplies identity and Git relationship only. Policy, specification,
registry, bundle, instructions and executable gates come from the worktree.
Dependency receipts retain distinct `execution_commit` and verified
`integration_commit` values; a successor base must contain the integration commit, not reuse its predecessor's
worktree or HEAD. The fixed policy binds only one worktree/base at a time:
successor relocation requires explicit policy rollover and independent approval.
Ancestor-goal branch gates are revalidated against the successor observation;
distinct predecessor/successor branch bindings can therefore block readiness.
There is no historical-goal exemption or transparent concurrent multi-worktree
policy. Resolve the policy conflict through review, not by weakening gates.

## Gate driver and authority

Use the same paired flags with `run-gates.sh`, an exact `--handoff` or `--goal`,
`--goal-record` and independent `--context` in **every phase**. `pre-commit` and
`local-validation` require implementation context; `pre-merge` and `all` require
merge context. Merge rejects sparse-checkout and hidden index flags
(`assume-unchanged` / `skip-worktree`), even if Git status appears clean. All
observed files must match HEAD's file inventory, raw unfiltered blob bytes and
executable bits: ignored extras, filter-normalized differences and line-ending
conversions fail closed. The raw `git ls-files --stage` index must also equal
HEAD's tree by path, object ID and mode, with only stage-zero entries; staged
changes and unmerged entries block independently of disk parity. Raw blob checks
use `hash-object --no-filters`, never clean/process filters. The helper checks
semantic equality of the execution record and selected goal before any gate runs. Every executable gate uses the validated
worktree; primary-checkout green evidence cannot substitute. Admission is
rechecked after gates so changed state, HEAD, policy or instructions blocks the
run. Gate outputs, logs and caches must remain outside the observed worktree;
even ignored generated files invalidate freshness. A mutating check requires
reviewed state reconciliation and fresh independently verified context before
rerunning; merge additionally requires exact committed bytes and modes. This is
not an atomic snapshot or protection against arbitrary concurrent filesystem
mutation.

Reports retain `dispatch_authorized: false`. Structural readiness, matching
hashes and supporting local validation grant neither operation nor merge
authority. Independently verify exact policy/subject/goal/stage authority before
dispatch; require independent reviews, exact-head hosted and local CI, fresh
merge admission and the host's fail-closed merge boundary before merging.

## readiness-contract/2: observed identity

The sections above are v1 (#92) and stay byte-identical; v2 supersedes the
approach without overriding it. For a handoff registered in
`.ai/workflows/northstar-readiness-v2.json`:

- **No policy binding.** v2 never reads `policy.worktree`. A
  `readiness-policy/2` carrying a `worktree` field is refused as
  `policy_unknown_field`, and `run-gates.sh` refuses `--worktree-root`,
  `--base-commit` and `--context` with a v2 selection.
- **Observed identity.** A repository is the policy's `repository.id` plus the
  observed `git rev-parse --git-common-dir`. Pass the checkout you work in as
  `--root`: the primary checkout and every registered linked worktree of one
  common directory admit against one unchanged policy. The path is
  informational. The observer refuses each alias with its own code:
  - `identity_git_env_injected`: `GIT_DIR`, `GIT_COMMON_DIR`, `GIT_WORK_TREE`,
    `GIT_INDEX_FILE` or `GIT_OBJECT_DIRECTORY` is set. `contract-run-v2.sh` passes
    them through only so that the observer refuses them; no command the observer
    starts receives them.
  - `identity_root_symlinked`: `--root` is reached through a symlink.
  - `identity_bare_repository`: `--root` is a bare repository.
  - `identity_root_not_toplevel`: `--root` is below the top level.
  - `identity_worktree_unregistered`: the common directory does not list
    `--root`, as with a copied worktree.
- **Certificate.** `merge-certificate/1` binds the observed common directory. A
  certificate issued in one worktree merges from any worktree of the same
  common directory at the same head; `merge-authority.sh` refuses
  `certificate_common_dir_mismatch` when the merge-time common directory differs.
- **Worktree snapshot.** Every v2 admission records `facts.worktree_state`: HEAD,
  the raw index digest and the state of every path under `--root`, ignored and
  untracked included. For a registered linked worktree on a branch it is the
  `state_sha256` of #92's `worktree_observation`, imported read-only. Every other
  root is walked with the same rows. The certificate re-snapshots after the local
  gates, and `run-gates.sh` admits again after its gates. Any change refuses with
  `worktree_changed_during_gates`. Merge also requires the index and the
  working tree to equal the HEAD tree (`tree_not_clean`).
- **Isolated gates.** The embedded Python of `tdd-evidence.sh`, `tdd-mode.sh`,
  `lint-gate.sh`, `ci-gate.sh` and `local-ci.sh` runs as `python3 -I -B`, so a PR
  checkout's working directory, `PYTHONPATH` and user site-packages never supply
  a module. `local-ci.sh` runs the unedited `lib/local_ci_contract.py` with
  `python3 -I -B -c`, which puts the pinned `lib` directory on `sys.path` and
  runs the module through `runpy`. The five scripts and the module are pinned in
  `readiness-dependency-v2.json`.
