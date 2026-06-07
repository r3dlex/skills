# Validation Module

Read when proving the scaffold matches the v3 baseline. v3 validation covers structural checks, depth validation, physical-copy sync semantics, host-policy safety wording, and the v3 fixture set.

## Commands

Run from `skills/` when validating this repository:

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

In addition, the v3 check set is exercised against `reference/fixtures/v3/`:

```sh
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
python3 -m json.tool reference/fixtures/v3/standalone/.ai/matrix.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/matrix.json >/dev/null
python3 -c "import json,sys; d=json.load(open('reference/fixtures/v3/umbrella/.ai/matrix.json')); sys.exit(0 if d['current_depth']<=d['max_allowed_depth'] else 1)"
python3 -c "import json,sys; d=json.load(open('reference/fixtures/v3/depth-violation/.ai/matrix.json')); sys.exit(1 if d['current_depth']>d['max_allowed_depth'] else 0)"
python3 -m json.tool reference/fixtures/v3/legacy-migration/migration-manifest.json >/dev/null
```

## Expected interpretation

- `tests/test-skills.sh` is authoritative only after its frontmatter-aware body-line parser passes focused regression fixtures.
- Corrected line-count failures identify progressive-disclosure cleanup targets; do not hide them by weakening the validator.
- Golden verification compares scaffolded files and marker presence; `upstream.lock` SHA content is intentionally structure-checked, not byte-compared.
- v3 fixtures are reference outputs. They must parse as JSON, obey the matrix schema, and demonstrate the depth rule.

## v3 structural checks

The validator runs the following v3 checks on the v3 fixtures and any candidate v3 repo:

1. **Top-level layout** — required entry files (`AGENTS.md`, `CLAUDE.md`, `CONTRIBUTING.md`, `README.md`) and required directories (`.ai/`, `.memory/`, `docs/architecture/`, `docs/specifications/ACTIVE/`, `docs/specifications/ARCHIVED/`, `docs/learning/`) are present for a standalone repo.
2. **Topology matrix** — `.ai/matrix.json` exists, parses as JSON, declares `schema_version: "1.0"`, has a valid `topology_type` (`standalone` or `umbrella`), and uses `sync_strategy: "physical-copy"`.
3. **Depth rule** — for `umbrella` topology, `max_allowed_depth` is `3` and `current_depth` is `<= max_allowed_depth`. The validator fails or blocks the apply path when `current_depth > max_allowed_depth`.
4. **Sync-strategy rule** — `sync_strategy` is `physical-copy`. The validator rejects `symlink` and `git-submodule` as canonical.
5. **Memory layer** — `.memory/human-override/` exists and is treated as terminal priority (validator never overwrites files there). `.memory/self-learned/` declares `schema_version` on every JSON file.
6. **Host-policy safety wording** — host-policy documentation contains the dry-run / confirmation / audit / negative-test language and the non-admin auto-approval prohibition. See `modules/host-policy-automation.md`.
7. **Migration audit** — when migrating from a legacy scaffold, `.ai/drift/migration-manifest.json` exists with the action vocabulary (`migrate`, `copy`, `deprecate`, `supersede`) and a confirmation token for every `migrate` action.
8. **Marker blocks** — `<!-- ai-sdlc-init:start -->` ... `<!-- ai-sdlc-init:end -->` markers are present in the entry files when the v3 marker format is in use.

## v3 fixture set

The v3 fixture set lives under `reference/fixtures/v3/`. Each fixture documents the expected v3 output for one scenario.

### Fixture A — standalone repo

`reference/fixtures/v3/standalone/.ai/matrix.json` declares `topology_type: "standalone"`, `max_allowed_depth: 0`, `current_depth: 0`, and `sync_strategy: "physical-copy"`. No `managed_repositories` are required. The fixture is a reference for the standalone tree under `.ai/`, `.memory/`, and `docs/`.

### Fixture B — umbrella repo

`reference/fixtures/v3/umbrella/.ai/matrix.json` declares `topology_type: "umbrella"`, `max_allowed_depth: 3`, and at least one entry in `managed_repositories` with a path and depth. The fixture demonstrates physical-copy inheritance and shows the audit log format under `.ai/drift/`.

### Fixture C — depth violation

`reference/fixtures/v3/depth-violation/.ai/matrix.json` declares `topology_type: "umbrella"`, `max_allowed_depth: 3`, and `current_depth: 4`. The validator must detect the violation and return a non-zero exit code. The error message names the offending repo path and the offending depth.

### Fixture D — legacy migration

`reference/fixtures/v3/legacy-migration/migration-manifest.json` documents the migration of a legacy scaffold to v3, including at least one `migrate` action with a `confirmation_token` and a `backup_path` under `.ai/drift/backups/<timestamp>/`. The fixture also includes a `migration-audit.jsonl` snippet that demonstrates the audit format.

## Host-policy negative tests

The v3 regression suite asserts:

- `apply-blocked-no-confirmation` is recorded when admin credentials are present without confirmation.
- `apply-rejected-non-admin` is recorded when the actor is not an admin and the host does not support a non-admin bypass.
- `apply-rejected-dry-run-mismatch` is recorded when the readback differs from the intended shape.

These negative tests are documented in `modules/host-policy-automation.md`; the live assertions are scoped to mocked host adapters in the regression suite.

## Static safety checks

The validator also runs a static check pass on the documentation modules:

- `modules/host-policy-automation.md` contains the keywords `dry-run`, `confirmation`, `audit`, `Negative test`, and `Non-admin auto-approval is disallowed`.
- `modules/sync.md` contains the keywords `physical-copy`, `max_allowed_depth`, and `current_depth`, and never mentions `symlink` or `git-submodule` as a canonical `mode` value.
- `modules/migration.md` contains the action vocabulary (`migrate`, `copy`, `deprecate`, `supersede`) and the manifest path `migration-manifest.json`.
- `modules/memory.md` declares `.memory/human-override/` as terminal priority and never lists it as inherited or syncable.
- `modules/topology.md` defines the matrix schema and the depth rule.
- `modules/language-packs.md` covers .NET Core / EF Core and legacy .NET / EF in the pack matrix.

A missing or weakened wording fails the static check pass; the validator never re-words the safety rules to satisfy a missing match.

## Regression commands

```sh
cd skills && tests/test-skills.sh
cd skills && tests/test-scripts.sh
cd skills && tests/run-tests.sh
cd skills && bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
cd skills && ./scripts/verify-golden-dir.sh . reference/golden-root
cd skills && ./scripts/verify-golden-dir.sh . reference/golden-skills
```

## E2E acceptance

- A clean standalone fixture can be initialized and validated.
- A clean umbrella fixture can be initialized, sync inherited assets by physical copy, and detect drift.
- A legacy fixture can migrate with backups/audit logs.
- A depth-violation fixture blocks the apply path with a clear error.
- Host-policy dry-run shows exact intended changes and required confirmations.
- Host-policy apply without explicit confirmation is rejected, including for admin credentials.
- All skills repo tests pass.
