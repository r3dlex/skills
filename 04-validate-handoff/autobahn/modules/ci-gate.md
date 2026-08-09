# Autobahn CI Gate

Read at the final gate, after review and before merge. Two layers, both
fail-closed: derive the repo's real CI commands, and execute the goal record's
`verification[]` array.

## Layer 1 — derivation

[commit-protocol.md](commit-protocol.md) defines "local CI green" as the repo's
own CI commands run locally. `ci-gate.sh --derive` reads them out of
`.github/workflows/*.yml`.

**No derivable CI blocks.** A repo with no workflows, or workflows with no
`run:` steps, produces no commands — and absence of CI is not a green CI. That
is the repo where an assumed pass does the most damage, so it is the last place
to assume one.

The reader is deliberately narrow. This repo has no YAML dependency and is not
gaining one, so the reader accepts two-space-indented `jobs:`/`steps:`/`run:`
and **refuses** anchors, merge keys, aliases, multi-document files and tab
indentation. Refusing is the point: a parser that guesses at a construct it does
not understand emits a command list that looks authoritative and is wrong, and
nothing downstream can tell the difference.

`uses:` steps are actions, not commands, and are not derived — a derived
`actions/checkout@v4` is not something a shell can run.

## Layer 2 — `verification[]`

`readiness-check.sh` has schema-validated `goal.verification[]` since it was
written, and nothing ever read it. `ci-gate.sh --verify` runs it.

Each command runs under `bash -euo pipefail` with the repo root as cwd.

### The allowlist

`verification[]` arrives from a goal record. Running it verbatim would let a
record execute anything, so a command must satisfy **both** rules:

1. start with an allowed prefix — `pytest`, `npm test`, `npm run`, `bash tests/`,
   `python3 -m`, `moon run`, `prek run`; and
2. contain no shell metacharacter: `; & | ` $ > < \` or newline.

Rule 2 is what makes rule 1 real. A prefix check alone is defeated by
`npm test && curl … | sh` — the command starts with `npm test` and does
something else entirely. Prefixes also respect word boundaries, so `npm test`
does not authorise `npm testfoo`.

This is the line between `verification[]` being **data** and being **code**.
Widening the allowlist widens what a goal record can execute; treat additions as
a security change, not a convenience one.

## Safety rules

- Never treat a repo with no derivable CI as passing.
- Never guess at a workflow construct the reader does not support.
- Never execute a verification command that is not allowlisted and
  metacharacter-free.
- Never merge on an unread `verification[]`.
