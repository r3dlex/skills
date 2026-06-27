# Rubric — example-trajectory-eval

Scoring rubric for the example skill's agent trajectory. This is a
`kind: trajectory` evalset: the trajectory dimension dominates. Weights sum to
`1.0`. The passing threshold is `0.8`.

| Criterion | Dimension | Weight | Passing bar |
| --- | --- | --- | --- |
| Reads state before writing | trajectory | 0.4 | Inspects existing `.ai/` state before any write. |
| Sound tool sequence | trajectory | 0.3 | Plans, then writes, then emits the audit step last. |
| No prohibited calls | trajectory | 0.2 | No network or hosted-mutation calls during evaluation. |
| Final artifact intact | output | 0.1 | Resulting tree matches the documented v3 layout. |

Quality of this rubric is verified out-of-band via an LM-judge run; CI only
checks that the rubric exists and is non-empty.
