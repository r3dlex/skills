# Autobahn verification adapter repair — 2026-09-09

## Scope

Repair only Autobahn's local `verification[]` adapter and its direct-readiness
schema. Keep legacy non-empty string entries valid, and add exact
`{"cwd": "...", "command": "..."}` entries for monorepo-local checks.

## Safety invariants

- Resolve every `cwd` relative to the owning repository root. Require an
  existing directory whose physical path remains inside that root; reject
  absolute paths, `..` segments, and symlink escapes.
- Parse commands to argv and execute with `shell=False`. Shell wrappers,
  metacharacters, newlines, traversal, package installation, arbitrary Mix
  tasks, and arbitrary `poetry run` targets remain denied.
- Keep test-runner invocations exact rather than accepting arbitrary external
  paths, plugin/config flags, or extra arguments. Restrict `npm run` and
  `moon run` to one locally evidentiary target and explicitly deny delivery,
  publication, release, promotion, shipping, and upload targets.
- Validate the complete array before starting its first process. One malformed
  or unsafe later entry—including an external test/config path or delivery
  target—must prevent every earlier command from running.
- Add only the narrowly reviewed Mix, Cargo, and Poetry forms required by the
  captured verification contract. Do not change remote-CI derivation, host policy,
  merge authority, or the frozen verification inventory.

## Test-first sequence

1. Extend `tests/autobahn_ci_gate_test.sh` for legacy strings, nested cwd
   execution, cwd containment, exact object shape, all-before-any validation,
   literal argv/no shell evaluation, and allowed/denied stack verbs.
2. Extend `tests/autobahn_direct_ready_test.sh` to accept the two entry shapes
   and reject malformed verification objects.
3. Run both focused tests and retain the expected pre-fix failures as RED.
4. Make the smallest adapter/schema/documentation edits.
5. Re-run focused tests, the existing Autobahn test set, local catalog/rule
   parsing checks, and shell syntax checks. Record any unrelated failure rather
   than weakening a gate.

## Out of scope

No product/source changes, package installation, network use, target-repository
runtime mutation, unsupported multiline grep-guard reinterpretation, commit,
push, merge, or authority inference.
