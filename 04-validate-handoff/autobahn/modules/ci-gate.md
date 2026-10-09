# Autobahn CI Gate

Read at the final gate, after review and before merge. Supporting local evidence
and hosted-CI evidence are distinct; both fail closed.

## Layer 1 — inventory and executable local subset

`ci-gate.sh --derive` is a legacy, line-oriented **inventory only**. It reads
runnable shell steps from the first configured provider (GitHub, Azure, then
GitLab), preserves block-scalar bodies, and never proves that a command ran.
Because one inventory entry may contain embedded newlines, its text output must
not be split or reparsed for execution.

`ci-gate.sh --derive-json` is the executable structured interface. It preserves
workflow order and duplicates and keeps a block scalar as one JSON element. It
admits only a narrow GitHub workflow shape with literal root-cwd `run:` steps.
Exact `actions/checkout@v4` without `with:` is a local no-op because the owning
repository root is already checked out. Other actions and execution-affecting
context—including `with`, `env`, `defaults`, `if`, `working-directory`, custom
`shell`, `needs`, strategy/matrix, services, containers, `continue-on-error`,
timeouts, expressions, and duplicate mappings—block rather than being guessed.
YAML quoted escapes and unmodeled shell comments/expansions also block;
workflow syntax must not silently become literal arguments. Azure and GitLab
remain inventory-only.

`local-ci.sh` composes that structured list into a mode-0600 temporary goal
record and delegates to `ci-gate.sh --verify`, which prevalidates the complete
list before running anything. The record is removed on every exit. Discovery
alone is therefore never a green gate, and there is only one command executor.

A multiline shell command remains one structured element, but the verification
adapter rejects its newline/metacharacter content. Supporting it would require a
reviewed command grammar, not unsafe shell execution.

This safe local command subset is deliberately narrower than an ordinary hosted
workflow and is **not hosted-CI equivalence**. Required remote checks must still
be verified for the exact commit SHA under current host policy. No configuration,
no runnable steps, malformed structure, unsupported context, an unallowlisted
command, or a nonzero command blocks.

## Explicit supporting local CI contract

When hosted YAML is outside the safe executable subset, a repository can review
and version `.ai/ci/local-ci.json` instead of weakening the parser:

```json
{
  "schema": "local-ci/1",
  "workflows": {".github/workflows/ci.yml": "<sha256>"},
  "sources": {"tests/run-tests.sh": "<sha256>"},
  "verification": ["bash tests/run-tests.sh"]
}
```

The exact schema rejects unknown/duplicate keys. `workflows` must pin the entire
current GitHub YAML inventory and root Azure/GitLab YAML configs. `sources` pins
all direct script commands and the repository-reviewed supporting inputs. Paths
must be normalized, root-contained regular files with no symlink components.
All hashes and the whole command list are checked before any command executes.
The unchanged verification adapter handles command forms and cwd objects.

The fixed declaration is optional: absence preserves strict derivation; a present
invalid, stale, incomplete, or unsafe declaration blocks without fallback.
`--derive-json` and the separate remote-CI gate remain unchanged. Declaration
hashes prove freshness only, not approval, authority, complete dependency tracing,
or hosted-CI equivalence. Review the check selection and indirect dependencies in
source review; refresh pins only as part of that reviewed change. Execution still
requires independent repository authority. See ADR 0015.

## Declared workspace install (`local-ci/2`)

A repository whose gates need dependency installs that a clean tree forbids —
gitignored `vendor/` or `node_modules/`, or outputs the gates write — upgrades the
same contract to schema `local-ci/2`: exactly the `local-ci/1` fields plus a
required `workspace` object with exactly `bootstrap`, `dependencies` and
`outputs`:

```json
{
  "schema": "local-ci/2",
  "workflows": {".github/workflows/ci.yml": "<sha256>"},
  "sources": {
    "tests/run-tests.sh": "<sha256>",
    "setup.sh": "<sha256>",
    "skills.lock.json": "<sha256>",
    "package-lock.json": "<sha256>"
  },
  "verification": ["bash tests/run-tests.sh"],
  "workspace": {
    "bootstrap": ["bash setup.sh"],
    "dependencies": ["vendor"],
    "outputs": ["dist", "dist-snapshot"]
  }
}
```

- Each `bootstrap` entry is exactly `npm ci`, `npm ci --ignore-scripts` or
  `bash <path>` with `<path>` a pinned `sources` key; an npm form requires
  `package-lock.json` or `npm-shrinkwrap.json` to be a pinned `sources` key.
  The pinned `sources` digests are the input pins — there is one pin map, not two.
- `dependencies` (written by the bootstrap) and `outputs` (written by the gates)
  are unique, normalized, repository-relative literal paths with no glob
  character, no `..` and no `.git` component in any letter case, and no entry
  equals, contains or lies inside another. They must be untracked at the head,
  contain no tracked path, and be ignored by the head's ignore rules — the
  observer refuses anything else (`gate_workspace_declaration_invalid`).
- The bootstrap is the only step the declaration grants, and it runs under the
  network and credential policy (see the readiness-v2 module): network access is
  permitted for the bootstrap and recorded; no token, keychain credential helper,
  agent socket or user configuration reaches it, and a non-zero exit refuses with
  `gate_workspace_bootstrap_failed:<command>` before any gate runs.
- `local-ci/1` is unchanged, and `local-ci.sh` runs the same `verification[]`
  subset for both schemas.

The two consumer shapes, recorded for reference:

- **ai-catapult**: `sources` pin `setup.sh` and `skills.lock.json`; bootstrap
  `["bash setup.sh"]`; dependencies `["vendor"]`; outputs `["dist",
  "dist-snapshot"]`.
- **ai-factory**: `sources` pin `package-lock.json` and the scripts; bootstrap
  `["npm ci --ignore-scripts"]`; dependencies `["node_modules"]`; outputs `[]`.

A change to a pinned lockfile or bootstrap script re-pins the contract in the same change; the pin map is reviewed code, never maintained separately.

## Layer 2 — `verification[]`

Each entry is either a legacy non-empty command string, whose cwd remains `.`,
or an exact `{"cwd":"…","command":"…"}` object. Object cwd values use
normalized POSIX syntax relative to the owning root. `ci-gate.sh --verify`
requires the directory to exist and its physical path to remain inside that
root; absolute paths, `..`, non-normal paths, and symlink escapes block.

The adapter validates **every** entry, cwd, referenced script, and executable
before starting its first process. It parses with `shlex` and passes argv to
`subprocess` with `shell=False`; verification text is never evaluated by a
shell. ASCII controls, shell metacharacters, newlines, and traversal block.
Contained `bash tests/...` scripts and the exact reviewed repo scripts must
resolve to regular files physically inside the owning root.

### The allowlist

`verification[]` arrives from a goal record. Test-runner forms are exact:
`pytest` (optionally `-q`), `npm test`, `python3 -m pytest` (optionally `-q` or
`--version`), `python3 -m unittest` (optionally `-v`, `discover`, or `--help`),
and `prek run` (optionally `--all-files`). Arbitrary paths, plugin/config flags,
and additional arguments are rejected rather than interpreted. Contained
`bash tests/...` scripts remain available. `npm run` is limited to script names
beginning with a local evidence verb (`test`, `lint`, `check`, `typecheck`,
`build`, `verify`, `validate`, `coverage`, or `ci`). `moon run` applies the same
rule to its task segment after the final `:`. Both accept exactly one target
argument and reject any target containing
deployment, publication, release, promotion, shipping, or upload semantics.
This semantic check happens before any command runs, so a later delivery step
also prevents earlier verification steps from running.

Additional forms are exact argv tuples, not tool prefixes:

- Mix: `format --check-formatted`, `compile --warnings-as-errors`,
  `credo --strict`, `test`, `test --warnings-as-errors`, `coveralls`, `dialyzer`;
- Cargo: `fmt --check`, `clippy --all-targets --all-features -- -D warnings`,
  `test --all-features`, the one `xtask fixtures verify` run, and the exact
  pinned `llvm-cov` threshold form;
- Poetry: exact Ruff, Pytest/coverage, and `pipeline-runner` checks (`check`,
  `test`, `lint`, `archgate`, `spec-check`);
- exact `git diff --check`, `docker compose config`, two reviewed Bash scripts,
  and two reviewed Python validation scripts recorded by the Obra plan.

Package installation, other `cargo run` binaries, arbitrary Mix tasks,
arbitrary `poetry run` targets, other repo scripts, and shell wrappers remain
denied.

Direct argv execution and raw-input rejection make the allowlist real. A prefix
check alone is defeated by
`npm test && curl … | sh` — the command starts with `npm test` and does
something else entirely. Prefixes also respect word boundaries, so `npm test`
does not authorise `npm testfoo`.

Rules 1 and 3 were both narrowed after an adversarial pass ran real code past
the gate:

- **A bare `python3 -m` admitted any module.** `python3 -m pip install <x>` is
  arbitrary package installation — arbitrary code execution straight from a goal
  record, with no metacharacter in sight. Fixed by naming the two test runners
  instead of the interpreter flag.
- **`bash tests/` was not a boundary.** `bash tests/../evil/x.sh` satisfies the
  prefix and executes a script outside `tests/` entirely. A prefix that names a
  directory means nothing if the path can climb out of it.

The lesson generalises: a prefix ending in a directory or a plugin flag is a
prefix that admits *anything after it*. Treat every addition as a security
change, and ask what the most hostile completion of that prefix does.

This is the line between `verification[]` being **data** and being **code**.
Widening the allowlist widens what a goal record can execute; treat additions as
a security change, not a convenience one. A planning `verification_inventory`
is not an executable manifest and is never consumed automatically.

## Safety rules

- Never treat a repo with no derivable CI as passing.
- Never guess at a workflow construct the reader does not support.
- Never execute a verification command that is not allowlisted and
  metacharacter-free.
- Never merge on an unread `verification[]`.

## Merge readiness versus supporting local validation

Before either merge-authority route, run the gate driver with `--phase pre-merge`,
`--goal-record <exact-selected-goal.json>`, the same generation-addressed `--handoff`
(or direct `--goal` envelope) and fresh independently established `--context`.
It invokes shared `--stage merge` admission before local/goal verification and
rejects records that differ from the selected goal, even when IDs match.
Use `--phase local-validation` for supporting checks without a merge context;
its success is explicitly **not merge admission or authority**. Remote exact-head
CI and independent host authority remain separate required gates.
