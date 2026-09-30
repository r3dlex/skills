# Upstream divergences

Fork-of-record: `r3dlex/skills`, vendored by consumers (ai-catapult) at the sha
in `upstream.lock`. Upstream of record: `mattpocock/skills`.

## CONTEXT.md vs GLOSSARY.md (registered future goal)

Upstream v1.3 renamed `CONTEXT.md` → `GLOSSARY.md` (see upstream b1f3390 and the
domain-modeling trigger note). This fork and its consumers still run on
`CONTEXT.md`: the umbrella's graph hooks, ADRs, and vendored skill bodies
mid-flight all reference `CONTEXT.md`.

**Decision (consensus, 2026-10-01):** do NOT rename. Divergence is documented
here instead; a rename is registered as a future goal —
`future-glossary-rename-alignment` (see `.ai/workflows/repo-workflow.json`
optional_branches) — to be picked up with upstream review, batched with the
first live lock refresh.

**Consequence for sync:** `scripts/sync-upstream.sh` must carry this comment
forward when it rewrites `upstream.lock` and MUST NOT mass-rename `CONTEXT.md`
references during apply; upstream files introducing `GLOSSARY.md` references
land as-is and are reconciled only under the future goal.
