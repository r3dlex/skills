---
name: eval-a-skill
description: 'Scaffold a structurally valid eval triplet for a target skill under .ai/evals/. CI checks structure only; the LM-judge runs out-of-band, never in CI.'
---

# Eval a Skill

## Quick Start

Given a TARGET skill, scaffold the eval triplet under `.ai/evals/<skill>/`,
matching the P0 eval shape (see `init-ai-repo/modules/evals.md` and the golden
fixture `reference/fixtures/v3/standalone/.ai/evals/example-output-eval/`).

Run the generator:

```bash
python3 eval-a-skill/scaffold-eval.py --skill <target> --root .
```

This writes three artifacts and makes no model or network call. Re-running is
idempotent — it rewrites the triplet in place, never duplicates.

## The eval triplet (P0 shape)

| Artifact | Purpose |
| --- | --- |
| `.ai/evals/<skill>/evalset.json` | Labelled cases: `schema_version`, stable `set_id`, `kind` (`output` or `trajectory`), and a non-empty `cases` array. |
| `.ai/evals/<skill>/rubric.md` | Required scoring rubric. Criteria, dimensions, weights summing to `1.0`, and a passing threshold. |
| `.ai/evals/<skill>/judge-config.json` | LM-judge harness stub: judge `tier`, `mode`, `harness`, `evaluates`, threshold, and `execution: out-of-band`. |

After scaffolding, fill the rubric and cases with behavior specific to the
target skill. A missing or empty rubric fails the eval-coverage gate.

## Structural validation — CI only

In CI the bar is **structural only** and offline: the triplet must exist and be
well-formed (both JSON files parse and carry their required keys; the rubric is
non-empty). CI performs no model or network call. This mirrors the eval-coverage
gate in `init-ai-repo/modules/ci-policy.md`.

Validate the scaffolded triplet structurally:

```bash
python3 -m json.tool .ai/evals/<skill>/evalset.json     >/dev/null
python3 -m json.tool .ai/evals/<skill>/judge-config.json >/dev/null
test -s .ai/evals/<skill>/rubric.md
```

CI proves the eval is **declared**, not that it passes. Eval quality is a
separate, out-of-band step.

## Judge execution — out-of-band only

The LM-judge that scores the target skill against the rubric runs
**out-of-band**, outside CI, and is **never invoked in CI**. `judge-config.json`
declares `execution: out-of-band` and ships a non-executing `stub` harness: it
documents the shape an out-of-band runner consumes, nothing more.

The opt-in out-of-band runner (Option B in the plan) is the only path that
actually invokes the judge. Run it manually, away from CI, and record the
judgment as evidence — see the worked example
`reference/fixtures/v3/standalone/.ai/evals/example-output-eval/judgment-demo.json`
and its discoverable offline checker `tests/lm_judge_demo_test.sh`. The recorded
judgment carries a per-criterion score, the rubric-weighted aggregate, and a
verdict against the passing threshold.

## Safety rules

- Do not weaken the structural validator to make a missing triplet pass; author
  the triplet or record an audited exception in
  `.ai/evals/coverage-exceptions.json`.
- Do not add a model or network dependency to the CI eval path.
- Do not claim a passing eval in CI; CI proves declaration, the judge proves
  quality out-of-band.

## References

- [init-ai-repo/modules/evals.md](../init-ai-repo/modules/evals.md) — eval scaffold spec and the coverage gate.
- [ADR 0002](../docs/architecture/adr/0002-evals-as-verification-gate.md) — evals as a verification gate.
