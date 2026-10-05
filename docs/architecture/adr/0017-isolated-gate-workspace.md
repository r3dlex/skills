# ADR-0017: Isolated gate workspace

- Status: Accepted for ACH-S-07 (readiness-contract/2)
- Date: 2026-10-05
- Specification: `ach-skills-gate-workspace` (D1 gate isolation; `docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-gate-workspace.md`), decisions W1–W9

## Context

`merge-certificate/1` is issued only at one exact, clean head: the observer's
`tree_state` before and after the local gates counts ignored files, and the
admission worktree snapshot must survive the gates unchanged. The local gates
therefore ran in place, in the observed root, with `--root <observed root>`.

Two consumer repositories cannot satisfy this. ai-catapult's local CI contract
and every goal run `npm test`, which needs the gitignored `vendor/` and writes
`dist/` and `dist-snapshot/`. ai-factory needs `node_modules/`. Either the
observed tree holds those paths, which refuses as `tree_not_clean`, or the
gates fail. Those plans can never be certified as the code stood (D1).

## Decision

**`certify-v2` and `merge-v2` run the four local gates only in an
observer-built gate workspace, never in the observed root; the observed root
keeps every existing check unchanged, and the certificate binds the isolated
copy's provenance.**

- **The workspace.** A new repository under the observed root's parent (a
  sibling of the observed root, never inside it), under the parent's `.omc/`
  tree — a name the existing `.omc/` ignored pattern of the umbrella and root
  `.gitignore` covers — with an empty template, no remote and no hooks. It
  borrows the observed repository's objects read-only through
  `objects/info/alternates` (the pattern of the planning simulation) and checks
  the PR head out detached, so its HEAD is the certified head and its files are
  that head's tree. Its location is on the same filesystem as the repository,
  and it sits inside the umbrella whenever the repository does. The workspace
  is removed when the derivation ends, on success and on failure, and a
  leftover from an interrupted run is removed, never reused.
- **Integrity.** Before any gate runs, `tree_state(workspace)` must equal the
  head tree, or the derivation refuses with `gate_workspace_unfaithful` (and
  `gate_workspace_unavailable` when it cannot be built). After every gate the
  observer re-checks: HEAD, the index entries (`git ls-files --stage`, so a
  stat-only index refresh by `git diff --check` is not a change) and every
  tracked path's bytes and mode must equal the head tree, and no untracked or
  ignored path may exist outside declared paths (this goal declares none). Each
  violation refuses with `worktree_changed_during_gates` plus
  `gate_workspace_tracked_changed:<path>` or
  `gate_workspace_undeclared_output:<path>`.
- **Observed root unchanged.** `tree_state` before and after the gates, ignored
  files included (`tree_not_clean`), the head checks (`head_changed_during_gates`,
  `pr_head_mismatch`) and the admission worktree snapshot
  (`worktree_changed_during_gates`) all stay exactly as they were. Certify still
  runs from a clean, registered worktree at the PR head. No gate is relaxed.
- **Git metadata and the target.** Inside the workspace, a gate's `git` reaches
  only the workspace's own git directory. The observer snapshots the observed
  common directory's `config`, `hooks/`, `info/` and
  `objects/info/alternates` around the gates and refuses any change with
  `git_metadata_changed_during_gates`. The target commit is resolved before the
  gates, and every check after them — `goal_reserved_refusals` included — uses
  that commit, never a re-read of `origin/<target>`.
- **Environment.** `gate_env` keeps exactly its variables: `PATH`, `LANG`,
  `LC_ALL`, `TMPDIR`, a throwaway `HOME` and `PYTHONDONTWRITEBYTECODE=1`.
  Every path handed to a gate (`--root`, `--goal-record`, the working
  directory, `HOME` and `TMPDIR`) is its physical path (`os.path.realpath`);
  `run-gates.sh` exports `PYTHONDONTWRITEBYTECODE=1` in its readiness-contract/2
  branch. `pre-commit` and `local-validation` keep running in place, because
  they validate the working tree, not a commit.
- **Provenance.** Every derivation writes one `gate-workspace/1` record to
  `<git common dir>/ai-catapult/observer/gate-workspaces/<plan>/<goal>/<pr>-<head>-<op>.json`
  (head, tree, the local CI contract's sha256 and schema, the bootstrap it ran,
  and the declared outputs; this goal runs no bootstrap and declares nothing).
  The certificate's single new field, `gate_workspace`, binds the workspace's
  physical path and the record's path and sha256. Its `local_gates` entries stay
  `{name, exit}` for the four gates, no admission fact is added, and the context
  projection is otherwise unchanged. Certificates issued before this change keep
  validating — the field is simply absent there — and `audit-merges` and
  `export-evidence` results for merged goals are unchanged.

## Rejected alternatives

- **In-place gates with a relaxed snapshot.** Would drop the very check that
  makes the certificate meaningful (`tree_not_clean`, ignored files included).
- **A linked worktree of the observed repository.** Shares the observed
  repository's git directory; a gate's `git config`, hooks or ref writes would
  hit the observed repository, and the workspace could not be a truly separate
  repository.
- **A clone with a remote.** Needs network access at derivation time and a
  credential surface; borrowing objects through `objects/info/alternates` reads
  everything locally and read-only.
- **A `TMPDIR` location.** Sits outside the umbrella whenever the repository
  sits inside one; ai-factory's drift test finds the umbrella by walking
  ancestor directories.

## Consequences

- The observed root's `tree_not_clean` semantics are unchanged; a repository
  that wants the gates to produce `vendor/`, `node_modules/`, `dist/` and the
  like will declare them under `local-ci/2` (ACH-S-08).
- The gates still run PR code with the user's uid. There is no OS sandbox, the
  gates are not network-isolated, and a change a gate undoes within itself is
  not seen. A gate that does `cd ..` out of the workspace lands in the observed
  root's parent. These are recorded residual risks.
- `merge-certificate/1` gains exactly one field; the digest-coupled certificate
  tests were re-derived for it, and both review lanes accepted the re-derivation
  (stated in the goal's PR body).

## Verification

- `tests/readiness_v2_gate_workspace_test.py` (discovered via
  `tests/readiness_v2_gate_workspace_test.sh`) proves, red first: the gates ran
  in a sibling workspace under the observed root's parent at the PR head and
  nothing remains afterwards; the observed root stays byte-identical and still
  refuses a gate writing an ignored file (`gate_workspace_undeclared_output`);
  tracked-file and git-metadata violations refuse with their detail codes; the
  target is resolved once; gate paths are physical; digests are streamed; the
  v2 `run-gates.sh` branch writes no bytecode; and the certificate adds only
  `gate_workspace`. The documentation test asserts every code is documented.
- The digest-coupled cases of `tests/readiness_v2_certificate_test.py` (field
  set, canonical bytes, re-derivation digests) are re-derived for the new field;
  every other case there is unchanged.
