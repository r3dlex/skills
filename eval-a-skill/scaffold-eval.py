#!/usr/bin/env python3
"""Scaffold a structurally valid eval triplet for a target skill, offline.

Given a target skill name, write the P0 eval shape under
``<root>/.ai/evals/<skill>/``:

- ``evalset.json``      labelled cases (schema_version, set_id, kind, cases)
- ``rubric.md``         scoring rubric (criteria, weights summing to 1.0, threshold)
- ``judge-config.json`` LM-judge harness stub (tier/mode/harness/evaluates,
                        ``execution: out-of-band``)

No model or network call is made. The judge declared in ``judge-config.json`` is
an out-of-band stub: this script never invokes it, and CI never invokes it. See
``eval-a-skill/SKILL.md`` and ``init-ai-repo/modules/evals.md``.

Usage:
    scaffold-eval.py --skill <name> [--root <dir>] [--kind output|trajectory]

Idempotent: re-running rewrites the triplet in place; no duplicate files.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path


def evalset(skill: str, kind: str) -> dict:
    return {
        "schema_version": "1.0",
        "set_id": f"{skill}-eval",
        "kind": kind,
        "skill_under_test": skill,
        "cases": [
            {
                "case_id": "case-001",
                "input": f"Exercise the primary behavior of the '{skill}' skill.",
                "expected_behavior": (
                    "Produces the documented artifact with no silent overwrite "
                    "and a sound, auditable tool-call sequence."
                ),
                "trajectory": ["read-context", "plan", "act", "verify"],
            }
        ],
    }


def judge_config() -> dict:
    return {
        "schema_version": "1.0",
        "judge": {
            "tier": "frontier",
            "mode": "lm-judge",
            "harness": "stub",
            "evaluates": ["output", "trajectory"],
            "passing_threshold": 0.8,
            "execution": "out-of-band",
        },
        "trajectory_trace": {
            "schema_version": "1.0",
            "records": "tool-call sequence with arguments and outcomes",
            "scored_against": "rubric.md trajectory criteria",
        },
    }


def rubric(skill: str, kind: str = "output") -> str:
    # Weights skew to the declared kind's dimension (both dimensions always
    # scored; weights sum to 1.0), so a `--kind trajectory` evalset is genuinely
    # trajectory-weighted rather than carrying an output-dominant rubric.
    if kind == "trajectory":
        rows = (
            "| Sound tool sequence | trajectory | 0.4 | Reads context before acting; verifies last. |\n"
            "| Reads before writes | trajectory | 0.3 | Inspects existing state before mutating it. |\n"
            "| No prohibited calls | trajectory | 0.2 | No network or hosted-mutation calls during evaluation. |\n"
            "| Final artifact intact | output | 0.1 | Produced artifact matches expected behavior. |\n"
        )
    else:
        rows = (
            "| Task correctness | output | 0.4 | Final artifact matches expected behavior. |\n"
            "| No silent overwrite | output | 0.2 | Existing work is preserved with an audit trail. |\n"
            "| Sound tool sequence | trajectory | 0.3 | Reads context before acting; verifies last. |\n"
            "| No prohibited calls | trajectory | 0.1 | No network or hosted-mutation calls during evaluation. |\n"
        )
    return (
        f"# Rubric — {skill}-eval\n\n"
        f"Scoring rubric for the `{skill}` skill ({kind}-weighted). Output and "
        "trajectory dimensions are both scored. Weights sum to `1.0`. The passing "
        "threshold is `0.8`.\n\n"
        "| Criterion | Dimension | Weight | Passing bar |\n"
        "| --- | --- | --- | --- |\n"
        f"{rows}\n"
        "Quality of this rubric is verified out-of-band via an LM-judge run; CI "
        "only checks that the rubric exists and is non-empty.\n"
    )


def scaffold(skill: str, root: Path, kind: str) -> Path:
    out = root / ".ai" / "evals" / skill
    out.mkdir(parents=True, exist_ok=True)
    (out / "evalset.json").write_text(json.dumps(evalset(skill, kind), indent=2) + "\n")
    (out / "judge-config.json").write_text(json.dumps(judge_config(), indent=2) + "\n")
    (out / "rubric.md").write_text(rubric(skill, kind))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skill", required=True, help="target skill name")
    parser.add_argument("--root", default=".", help="repo root to write under")
    parser.add_argument(
        "--kind", default="output", choices=["output", "trajectory"],
        help="evalset kind (default: output)",
    )
    args = parser.parse_args()
    out = scaffold(args.skill, Path(args.root).resolve(), args.kind)
    print(f"scaffolded eval triplet: {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
