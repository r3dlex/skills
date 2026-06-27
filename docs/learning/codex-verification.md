# Codex Parity P2 — Out-of-Band Verification Procedure

This is the **verification layer** for Codex parity (ADR-0004, plan P2-3). It is
how a human verifies that representative skills actually run under OpenAI Codex,
and where the recorded evidence lives.

> **Disclaimer:** This is a **recorded out-of-band verification, not a CI gate.**
> A live Codex run requires the `codex` CLI plus model/network access, which is
> not available in CI or an offline sandbox. CI never invokes Codex. The
> evidence artifacts under
> `reference/fixtures/v3/standalone/.ai/evals/codex-verification/` are recorded
> transcripts of out-of-band runs (or illustrative placeholders until a
> maintainer records a real run); the offline test only asserts their shape and
> disclaimers, never a live run.

## Why three bars

Codex parity has three bars (ADR-0004):

1. **P0/P1 — mechanical (enforced in CI).** `scripts/check-codex-parity.sh`
   greps each skill body for Claude/OMC-only invocations and fails on any
   unmarked occurrence. Offline, deterministic, runs in CI.
2. **P2 — verified (this doc).** A human runs representative skills under Codex
   and confirms they behave. This cannot run in CI; it is recorded here.

The mechanical bar proves a skill *contains no hard dependency* on Claude-only
constructs. The verified bar proves a skill *actually works* end-to-end under
Codex. Both are required for full parity.

## Procedure: run a skill under Codex

1. **Install Codex and the `codex` CLI** per OpenAI's instructions, and confirm
   `codex --version` works.
2. **Install the skills into Codex** from this repo root:
   ```sh
   ./scripts/install-codex.sh --skill <skill-name>   # one skill
   ./scripts/install-codex.sh --all                  # the whole catalog
   ```
   This copies each skill directory (with its `SKILL.md`) into
   `~/.codex/skills/`, where Codex auto-discovers it on restart.
3. **Restart Codex** so the new skills are discovered.
4. **Run a representative scenario** for the skill — a short task that exercises
   the skill's primary trigger (e.g. for `init-ai-repo`, ask Codex to scaffold
   the v3 tree in a scratch repo; for `write-a-skill`, ask it to draft a new
   skill).
5. **Record the transcript evidence** (see below).

## What to record

For each verified skill, add a `<skill>.transcript.json` artifact under
`reference/fixtures/v3/standalone/.ai/evals/codex-verification/` with:

- `skill_under_test` — the catalog skill directory name (must be a real skill).
- `codex_command` — the exact command used (e.g. the `install-codex.sh`
  invocation and/or the `codex` run command).
- `codex_model` — the Codex model the run used.
- `scenario` — the representative task given to Codex.
- `outcome` — `pass` or `fail` plus a one-line summary of what Codex produced.
- `transcript_excerpt` — a short, redacted excerpt of the Codex session showing
  the skill being invoked and its result (trim secrets and noise).
- `recorded_at` — an ISO-8601 timestamp (or a placeholder until a real run is
  recorded).
- `disclaimer` — must contain the literal string
  `recorded out-of-band verification, not a CI gate`, and state that no live
  Codex run happened in CI.

## Pass criteria

A representative skill **passes** the verified bar when, under Codex:

- the skill is discovered and invoked for its representative scenario;
- it produces the same class of output it produces under Claude Code, using its
  documented plain-markdown fallbacks for any `<!-- codex:optional -->`
  construct;
- no Claude/OMC-only invocation is required for the core path to complete; and
- the recorded transcript shows the successful invocation and result.

Record `outcome: "fail"` with notes when a skill does not pass, and file a
remediation follow-up (abstract the construct or add a fallback per
`init-ai-repo/modules/skill-modernization.md`).

## Representative skills

Start with the SDLC-core skills and grow the set over time. The committed
evidence currently covers `init-ai-repo` and `write-a-skill`; add more
`<skill>.transcript.json` artifacts as maintainers record real out-of-band runs.

## See also

- ADR-0004 — `docs/architecture/adr/0004-agents-md-single-source-codex-parity.md`
- Mechanical bar — `scripts/check-codex-parity.sh`, `tests/codex_parity_test.sh`
- Offline structural test for this layer — `tests/codex_verification_test.sh`
- Skill remediation — `init-ai-repo/modules/skill-modernization.md`
