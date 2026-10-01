# ADR 0015: Explicit supporting local CI contracts

- Status: Accepted
- Date: 2026-09-30
- Scope: Autobahn supporting local checks; hosted CI remains independently required

## Context

The deliberately narrow executable GitHub reader cannot translate this repository's
conditional self-hosted fallback jobs, outputs, or packaged actions. Ignoring those
constructs would falsely claim local equivalence. An inventory is not execution.

## Decision

A repository may review and version `.ai/ci/local-ci.json` with exactly four fields:
`schema: "local-ci/1"`, `workflows` and `sources` SHA256 maps, and nonempty
`verification` commands. The workflow map must equal the complete current GitHub
YAML workflow inventory plus root Azure/GitLab YAML configurations, not a selected
subset. Supporting sources include direct script entrypoints and reviewed indirect
inputs (for this repository: the scanner, test runners, lint script and config).
Every declared path is normalized, root-contained, a regular file, and has no
symlink component. Duplicate JSON keys, unknown fields, unavailable commands,
missing or stale pins, and invalid command lists block without fallback.

The existing verification allowlist and whole-list prevalidation are unchanged.
Commands run as argv without shell interpolation. An absent declaration retains
strict safe-subset derivation; `--derive-json` itself does not change. A present
invalid declaration cannot fall back to a more permissive interpretation.

This is reviewed repository configuration, **not a trust root, approval token,
execution authority grant, or hosted-CI equivalent**. Hashes establish freshness,
not authenticity or semantic completeness; repository review owns whether local
checks are sufficient. The manifest does not statically trace all script imports.
Concurrent mutation of a working tree during validation/execution is not an
isolated snapshot guarantee. Existing repository authority and exact-commit remote
CI checks remain mandatory and separate.

## Adoption

The skills declaration runs the full test runner, `prek run --all-files`, and the
same secret scanner used by the Security workflow. The existing inline scanner is
extracted unchanged into `scripts/scan-secret-material.py`; the workflow and local
wrapper both call it. No hosted action or conditional routing is emulated locally.
Changing any pinned source requires deliberate review and pin regeneration in the
same change. A green local result never changes the independent hosted-CI gate.
