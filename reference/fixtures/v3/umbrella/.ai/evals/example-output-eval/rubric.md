# Rubric — example-output-eval

Scoring rubric for the example skill. Both output and trajectory dimensions are
scored. Weights sum to `1.0`. The passing threshold is `0.8`.

| Criterion | Dimension | Weight | Passing bar |
| --- | --- | --- | --- |
| Structural correctness | output | 0.4 | Generated artifact matches the documented v3 tree. |
| No silent overwrite | output | 0.2 | Existing files are preserved with an audit entry. |
| Sound tool sequence | trajectory | 0.3 | Reads state before writing; emits the audit step last. |
| No prohibited calls | trajectory | 0.1 | No network or hosted-mutation calls during evaluation. |

Quality of this rubric is verified out-of-band via an LM-judge run; CI only
checks that the rubric exists and is non-empty.
