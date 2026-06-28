# Rubric — autobahn-eval

Scoring rubric for the `autobahn` ship skill (trajectory-weighted: correctness is
mostly in the *sequence* — engine-pick, review loop, CI gate, fail-closed merge,
idempotent closure — not a single final artifact). Output and trajectory
dimensions are both scored. Weights sum to `1.0`. The passing threshold is `0.8`.

| Criterion | Dimension | Weight | Passing bar |
| --- | --- | --- | --- |
| Fail-closed merge authority | trajectory | 0.3 | Consumes the host-policy verdict verbatim (no re-derived token regex / admin rule); merges only on approved + valid token; else stops at ready-for-human or fails closed. Never self-approves. |
| Deterministic engine-pick | trajectory | 0.25 | Applies ultraqa > ultrawork > ralph > team precedence; honors --engine; unknown engine exits non-zero. |
| Review + CI gate before merge | trajectory | 0.2 | Runs the architect+reviewer+executor loop, resolves all comments, and requires remote AND local CI green before the merge decision. |
| One PR per goal | output | 0.15 | Each sliced goal from the handoff ships as exactly one PR; none merged together or skipped. |
| Idempotent cascade closure | output | 0.1 | Closes the issue via the cascade engine with the canonical triage status; a repeated close creates no duplicate and appends an audit event. |

Quality of this rubric is verified out-of-band via an LM-judge run; CI only checks
that the rubric exists and is non-empty.
