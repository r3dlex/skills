# Autobahn CI Gate

Read at the final gate, after review and before merge. Two layers, both
fail-closed: derive the repo's real CI commands, and execute the goal record's
`verification[]` array.

## Layer 1 — derivation

[commit-protocol.md](commit-protocol.md) defines "local CI green" as the repo's
own CI commands run locally. `ci-gate.sh --derive` reads them out of whichever
provider the repo actually uses:

| Provider | Read from | Runnable steps |
| --- | --- | --- |
| GitHub Actions | `.github/workflows/*.yml` | `run:` |
| Azure Pipelines | `azure-pipelines.yml` | `script:`, `bash:` |
| GitLab CI | `.gitlab-ci.yml` | `script:`, `before_script:`, `after_script:` |

Precedence runs down that table and the first provider present wins. Where
several exist, GitHub's checks are the ones gating the PR, so deriving another
provider's commands would verify something the merge does not depend on.

**No derivable CI blocks.** A repo with no CI configuration, or one whose
configuration has no runnable steps, produces no commands — and absence of CI is
not a green CI. That is the repo where an assumed pass does the most damage, so
it is the last place to assume one.

The reader is deliberately narrow, for every provider alike. This repo has no
YAML dependency and is not gaining one, so it accepts two-space-indented keys
and **refuses** anchors, merge keys, aliases, multi-document files and tab
indentation. Refusing is the point: a parser that guesses at a construct it does
not understand emits a command list that looks authoritative and is wrong, and
nothing downstream can tell the difference. A guessed Azure command is exactly
as wrong as a guessed GitHub one.

Steps that invoke a packaged action rather than a shell are not derived —
GitHub's `uses:` and Azure's `task:`. A derived `actions/checkout@v4` is not
something a shell can run.

**Block scalars are read, and kept whole.** `run: |` is how nearly every real
workflow writes a multi-command step, so refusing it would make the gate
unusable — and the earlier reader matched only the marker line, dropping those
commands entirely while still exiting 0. An incomplete list presented as the
repo's CI is the worst outcome here: "local CI green" then means less than the
real CI, and nothing says so.

The body is one entry, not one per line. A step is a single shell invocation, and
splitting it turns a heredoc or an `if`/`then` into fragments that read like
separate commands and are not. Verified against this repo's own workflows, where
splitting produced nonsense.

## Layer 2 — `verification[]`

`readiness-check.sh` has schema-validated `goal.verification[]` since it was
written, and nothing ever read it. `ci-gate.sh --verify` runs it.

Each command runs under `bash -euo pipefail` with the repo root as cwd.

### The allowlist

`verification[]` arrives from a goal record. Running it verbatim would let a
record execute anything, so a command must satisfy **both** rules:

1. start with an allowed prefix — `pytest`, `npm test`, `npm run`, `bash tests/`,
   `python3 -m pytest`, `python3 -m unittest`, `moon run`, `prek run`;
2. contain no shell metacharacter: `; & | ` $ > < \` or newline; and
3. contain no `..` path segment.

Rule 2 is what makes rule 1 real. A prefix check alone is defeated by
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
a security change, not a convenience one.

## Safety rules

- Never treat a repo with no derivable CI as passing.
- Never guess at a workflow construct the reader does not support.
- Never execute a verification command that is not allowlisted and
  metacharacter-free.
- Never merge on an unread `verification[]`.
