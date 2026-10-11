# ADR-0018: TypeScript tooling runner and packaging

- Status: Accepted for `e6-sk-00-ledger`
- Date: 2026-10-10
- Specification: `docs/specifications/ACTIVE/e6-skills-legacy-ts-conversion.md`, decisions D3, D4 and D13
- Does not amend ADR-0016

## Context

Skills tooling is moving to TypeScript. Goal 00 installs the runner, the packaging
rules and the compatibility-shim contract that every later conversion uses. Two
runners, or a runner that type-strips source, would make the executed bytes depend
on the host's loader instead of the reviewed build.

## Decision

**One runner.** `node` executes `tsc`-compiled ESM emitted as `.mjs` from `.mts`
sources. No type stripping, ts-node, bundler or second runner.

**One node range.** Node.js 26, written `>=26.0.0 <27.0.0`. The same major is
pinned in `ts-tooling/package.json` `engines.node` and in `.github/workflows/ci.yml`
as `node-version: "26"`. A test fails when the three disagree. Each compiled
entrypoint imports `node-version.mjs` first. The guard refuses with
`node_version_unsupported` when `process.versions.node` is outside that range.
The shim also refuses a `node --version` outside `v26.*` before exec.

**Refusals.** `node_unavailable` exits 127. `node_version_unsupported` exits 126.
Both print their code on stderr. Converted tools use 0, 1 and 2, so a test can
tell a runner refusal from a tool refusal. A candidate run that ends in either
code is never a differential pass.

**Imports.** Compiled modules import only `node:` builtins and relative `.mjs`
paths. No bare specifier and no `#` import, so an ancestor `package.json` or a
`node_modules` directory cannot change module resolution.

**Committed output.** Production `tsc` emits into `scripts/lib`, the shipping
directory this goal scopes. Installed payloads run with `node` alone. A drift
check fails on any byte difference from a fresh build. `ts-tooling/build` is the
test output directory: gitignored, never committed, removed by the test wrapper
on exit.

**Shims.** A bash shim (`.sh`) and a python3 shim (`.py`) are rendered from one
template each. The python3 shebang is `#!/usr/bin/env -S python3 -I -B`; those
interpreter flags are `-I -B`. A shim clears the environment to `PATH`, `HOME`,
`LANG`, `LC_ALL` and `TMPDIR`, plus only the names its ledger entry declares,
never a `NODE_*` name. It execs `node` with the fixed flags `--disable-proto=throw`
and the compiled entrypoint beside itself, passing arguments and stdin unchanged.

**Test seam.** ESM module namespaces are immutable, so a later port of a
monkeypatching Python test uses an exported dependency seam: `main(argv, deps)`
with production defaults. A loader hook is rejected because shims never pass
`--import`. `ts-tooling/src/sample.mts` demonstrates the seam.

**Tools.** `node` and `npm` are required. A missing tool fails closed. Legacy
tool provenance, one package per invocation: `brew install shellcheck shfmt`;
`uv tool install ruff`; `uv tool install mypy`; `uv tool install xenon`. Never
`brew install lizard`.

**Provenance.** A TypeScript driver replaces a Python driver only after the
specification's D13 procedure passes in that PR. A rollback is certified by a
source-lane driver pinned to the pre-switch commit. This record states the
principle; it does not switch a driver.

**Bootstrap.** `ts-tooling/bootstrap.sh` stays bash. The local-ci/2 allowlist
runs `bash <pinned source>`, and the observer's sanitized environment, including
`npm_config_*`, must reach `npm ci --ignore-scripts`. It is the one
infrastructure shell, not an eligible legacy file and not a shim.

## Consequences

- Later conversion goals compile into the shipping directory they scope and
  replace the entrypoint with a template-conformant shim.
- A TypeScript compiler upgrade that changes emitted bytes is a reviewed diff,
  not a silent host difference.
- Exit statuses 126 and 127 are reserved for the runner refusals above.

## Verification

`tests/ts_tooling_test.sh` pins the preset, the node range and the drift check.
`tests/e6_shim_conformance_test.sh` and `tests/e6_node_shadowing_test.sh` pin
the templates and the isolation probes. `tests/e6_differential_test.sh` pins
the harness, including a declared `interpreter-diagnostic` class.
