# Autobahn local-CI execution repair — 2026-09-09

## Defect

`run-gates.sh` treated `ci-gate.sh --derive` as a passing pre-merge gate. That
mode only prints an inventory; it never executes a command. A successfully
parsed workflow was therefore reported as green local CI.

## Locked behavior before implementation

1. Keep legacy `--derive` inventory-only and compatible.
2. Add structured `--derive-json`; preserve command order, duplicates, and a
   block-scalar command as one JSON element.
3. Executable derivation admits only a deliberately narrow GitHub workflow
   subset. Missing/malformed CI, non-GitHub providers, action prerequisites,
   environment/default overrides, conditional/custom-shell/working-directory
   steps, and job execution contexts such as strategy/matrix, needs, services,
   or containers block rather than run under guessed semantics.
4. `local-ci.sh` obtains structured commands, writes a mode-0600 temporary goal
   record, delegates execution to `ci-gate.sh --verify`, and removes the record
   on every exit. It is composition, not a second command executor.
5. The existing verification adapter prevalidates the entire command list before
   any subprocess starts. A forbidden later command therefore prevents an
   earlier allowed command from creating a marker.
6. `run-gates.sh` invokes `local-ci.sh`; successful discovery alone is never a
   green execution gate. Report-all and fail-fast behavior remain unchanged.
7. This local safe subset is not hosted-CI equivalence. Exact-SHA required-check
   evidence remains a separate merge requirement.
8. Package/task runner targets are semantically constrained: `npm run` and
   `moon run` admit only local evidence verbs and reject deployment,
   publication, release, promotion, shipping, and upload targets. The entire
   list is rejected before execution when any later target violates this rule.

## Regression matrix

- allowed commands execute at repository root and in declared order;
- a nonzero command blocks;
- later forbidden input prevents all execution;
- deployment/release/publication targets prevent all execution, including an
  earlier otherwise-valid marker command;
- missing, malformed, empty, or unsupported-context CI blocks;
- block-scalar content remains one structured element and is safely rejected;
- duplicate commands remain duplicates and execute twice;
- the temporary goal record is removed after success and failure;
- the driver retains report-all/fail-fast semantics and uses a real local fixture
  command rather than a nonexistent package script.

## Red evidence

The regressions were added before production edits. On the pre-repair scripts,
`tests/autobahn_local_ci_test.sh` failed because `local-ci.sh` and
`--derive-json` did not exist, while the existing driver still passed a fixture
whose derived `npm test` was never executed. This directly reproduced the
false-green path.
