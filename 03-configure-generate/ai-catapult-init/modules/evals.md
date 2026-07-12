# Evals Module

Read when generating the `.ai/evals/` scaffold or wiring the offline eval-coverage gate. Evals are the verification surface for non-deterministic behavior; tests verify deterministic parts, evals verify the rest. See ADR-0002.

## Principle

"Set the bar at the eval, not the demo." A shippable capability is not complete without an eval carrying an explicit rubric. In CI the bar is **structural** (schema + rubric + judge-config present and well-formed) and **offline** — no model or network call. Eval **quality** is verified out-of-band via an LM-judge run, recorded as evidence, not as a CI gate.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/evals/<set>/evalset.json` | Labelled cases for one evalset: inputs, expected behavior, and reference trajectories. |
| `.ai/evals/<set>/rubric.md` | Scoring rubric. Required. Criteria, weights summing to `1.0`, and a passing threshold. |
| `.ai/evals/<set>/judge-config.json` | LM-judge harness configuration (stub by default): judge tier, mode, evaluated dimensions, and threshold. |
| `.ai/evals/coverage-exceptions.json` | Audited exceptions for changes that bypass the coverage gate; owner, reason, expiry. Default is no exceptions. |

## Evalset structure

`evalset.json` declares `schema_version`, a stable `set_id`, a `kind`
(`output` or `trajectory`), an optional `skill_under_test`, and a non-empty
`cases` array. Each case carries a stable `case_id`, an `input`, an
`expected_behavior`, and a reference `trajectory` (the expected tool-call
sequence).

Both evaluation modes are representable in one scaffold:

- **Output evaluation** scores the final artifact against `expected_behavior`
  using the rubric's output criteria.
- **Trajectory evaluation** scores the recorded tool-call sequence against the
  case `trajectory` using the rubric's trajectory criteria. The recorded
  sequence is represented by the `trajectory_trace` block in `judge-config.json`
  and surfaces in the traceability graph as a `trajectory-trace` node.

## Rubric template

`rubric.md` is a required Markdown table. Each row names a criterion, the
dimension it scores (`output` or `trajectory`), a weight, and the passing bar.
Weights sum to `1.0`; the file declares a passing threshold. A missing or empty
rubric fails the coverage gate.

## LM-judge harness stub

`judge-config.json` declares the judge `tier` (a provider-neutral routing tier;
see `modules/documentation-blueprint.md` policy outputs), `mode`
(`lm-judge`), the `harness` (`stub` by default), the `evaluates` dimensions
(`output`, `trajectory`, or both), a `passing_threshold`, and `execution`
(`out-of-band`). The stub is intentionally non-executing: it documents the
shape an out-of-band runner consumes. CI never invokes it.

## Worked example: out-of-band LM-judge demonstration

`reference/fixtures/v3/standalone/.ai/evals/example-output-eval/judgment-demo.json`
is a recorded out-of-band LM-judge judgment for the `example-output-eval`
fixture, committed as evidence. It shows the shape an out-of-band runner
produces end-to-end: which evalset and rubric were judged, the illustrative
judge model and a timestamp placeholder, one per-criterion score and rationale
for every rubric criterion, and an aggregate score (the rubric-weighted sum)
checked against the rubric's passing threshold.

It is a demonstration, not a CI gate — it carries an explicit "recorded
out-of-band demonstration, not a CI gate" disclaimer, was authored without any
live model or network call, and CI never invokes it. It is the in-repo proof
that the structural-in-CI + quality-out-of-band split works. The discoverable
offline runner is `tests/lm_judge_demo_test.sh`.

## Eval-coverage gate (D1/D2)

The gate is diff-aware and offline:

1. **Trigger (D1).** A skill changed in the PR diff that declares a non-empty
   `eval:` key in its frontmatter is a shippable capability. Doc-only or
   unchanged skills are exempt.
2. **Structural check (D2).** The declared evalset directory must exist and be
   structurally valid: `evalset.json` and `judge-config.json` parse and carry
   their required keys; `rubric.md` exists and is non-empty.
3. **Audited exception.** A token in `.ai/evals/coverage-exceptions.json`
   (owner, reason, expiry) bypasses the gate for a non-shippable change. This
   mirrors the `> 280`-character description-exception escape hatch in
   `modules/skill-modernization.md`.

The gate exits non-zero only when a changed shippable skill references a missing
or malformed evalset with no audited exception. It performs no model or network
call. The generated PR-merge-gate text (see `modules/ci-policy.md`) carries the
honest caveat: eval coverage is enforced structurally in CI; eval quality is
verified via an out-of-band LM-judge run.

## Safety rules

- Do not weaken the structural validator to make a missing evalset pass; author
  the evalset or record an audited exception.
- Do not add a model or network dependency to the CI eval path.
- Do not claim a passing eval in CI; CI proves declaration, not quality.
