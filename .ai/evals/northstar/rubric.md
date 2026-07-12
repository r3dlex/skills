# Rubric — northstar-eval

Scoring rubric for the `northstar` intake skill (output-weighted: the value is in
the artifacts it produces — a tracked issue, sliced goals, and a sound A→B
handoff). Output and trajectory dimensions are both scored. Weights sum to `1.0`.
The passing threshold is `0.8`.

| Criterion | Dimension | Weight | Passing bar |
| --- | --- | --- | --- |
| Handoff completeness | output | 0.3 | A→B handoff carries every sliced goal (none dropped) plus the workflow-manifest `optional_branches` entry and traceability nodes; an `autobahn` run could consume it unaided. |
| Issue always raised, fail-closed | output | 0.25 | An issue is always raised; hosted only when a tracker is configured AND authorized, otherwise local-first with no hosted mutation. |
| Interview/grill-me discipline | trajectory | 0.2 | Asks one question at a time; runs grill-me unless explicitly skipped; raises the issue only after both passes are satisfied. |
| Prerequisite honesty | trajectory | 0.15 | When init-ai-repo is not initialized, stops with guidance and writes no partial handoff. |
| No implementation or prohibited calls | trajectory | 0.1 | Stops after the verified handoff; makes no product/source/test changes, executes no sliced goal, starts no implementation engine, and makes no unauthorized hosted-mutation or network calls. |

Quality of this rubric is verified out-of-band via an LM-judge run; CI only checks
that the rubric exists and is non-empty.
