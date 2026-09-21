---
name: autobahn-fail-closed-gates
status: validation-pending
---

# Autobahn fail-closed gates

Repair three boundaries: inventory must not count as executed local CI, verification must validate the complete command list before running anything, and a bypass verdict must carry explicit approval and matching readback.

## Contract

1. Local CI executes the supported literal workflow command list instead of treating inventory as execution.
2. Unsupported workflow syntax or execution context, absent runnable CI, and failed commands block the local gate; hosted checks remain independently required at the exact commit SHA.
3. Every verification command, executable, script, and contained cwd is validated before any command runs; execution uses argv without a shell.
4. Legacy verification strings retain root cwd; exact cwd/command objects permit only normalized physically contained directories.
5. Merge-policy bypass requires an explicit approved marker, matching readback, and confirmation token; missing, malformed, conflicting or rejected verdicts fail closed.
6. An explicitly authorized ordinary merge uses normal host policy after exact-head CI and review gates; it never fabricates bypass evidence.
7. Regression tests, final local validation, independent review, and hosted CI are recorded before delivery; no readiness or approval is inferred from this document.

## Supported scope

The executable CI reader supports a bounded literal GitHub workflow shape and root-cwd commands. It preserves order and duplicates. Exact checkout without configuration is a local no-op. Unsupported actions, expressions, execution context, duplicate mappings, malformed structure, and shell constructs block. Azure and GitLab remain inventory-only. This is not a general YAML interpreter or hosted-CI emulator.

Verification uses an explicit allowlist with argv execution. It validates all entries before starting the first process, including cwd normalization, physical containment, script paths, and executable availability. Existing root-cwd strings remain supported; objects contain exactly cwd and command.

## Non-goals

No branch-policy changes, invented approval tokens, dependency installation, deployment commands, or relaxation of hosted checks. No claim that all ordinary hosted workflow syntax can run locally.

## Validation and delivery

Run the four focused Autobahn suites and the repository test suite listed in the goal record. Record actual red/green evidence, coverage measurement status, final review, and exact-head hosted CI separately. A conservative zero coverage policy input selects legacy-safe TDD while instrumentation is unavailable; it is not measured coverage. Implementation is still being finalized; these documents do not assert green tests, readiness, approval, or merge completion.

Goal: `.ai/handoff/autobahn-goals/autobahn-fail-closed-gates.json`.
Evidence: `.ai/evidence/autobahn-fail-closed-gates.json`.
