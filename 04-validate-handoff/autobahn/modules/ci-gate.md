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
Azure and GitLab remain inventory-only.

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
  and two reviewed Python validation scripts from the captured verification contract.

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
is not an executable manifest and is never consumed automatically. In
particular, an unsupported multiline grep guard remains blocked pending its own
reviewed safe grammar; it is not reinterpreted as a successful check.

## Safety rules

- Never treat a repo with no derivable CI as passing.
- Never guess at a workflow construct the reader does not support.
- Never execute a verification command that is not allowlisted and
  metacharacter-free.
- Never merge on an unread `verification[]`.
