# Knowledge publish step

Producer skills (`northstar`, `research`, `to-spec`, `to-prd`, `to-issues`,
`handoff`, `retro`, `domain-modeling` (ADRs) and `code-review` (reviews)) end by
publishing the document they just produced when the target repo carries a
knowledge registry. This module defines that step once, host-neutral: a
producer skill points here and never inlines the machinery. The step follows
the frozen contract pack at `.ai/knowledge/contract/` (pack version 1:
`knowledge-publication-policy/1`, `knowledge-entry.schema.json`,
`knowledge-registry/1`).

## When to read

At the end of a producer skill, after the produced document is final. Never as
a substitute for the document itself.

## The step

1. Check `.ai/knowledge/registry.json`. If it does not exist, record
   `unpublished: no-registry` and return SUCCESS. The skill never fails
   because of the registry.
2. Read the harness host descriptor `.ai/commands/<host>/knowledge.json`
   (`omc` for Claude Code, `omx` for Codex, `opencode` for OpenCode). If the
   host's descriptor is missing or unreadable, record
   `unpublished: no-descriptor` and return SUCCESS.
3. Run publication from the repository root: the descriptor's `argv` array
   with the `publish` verb appended, passing the produced document's path and
   the declared kind (consult the tool's `--help` for the exact interface).
   On a non-zero exit, record `unpublished: publish-failed` and return
   SUCCESS. Publication is best-effort by contract.
4. On success, report the canonical `sha256` and entry id the tool prints in
   the skill's final report.

## Reasons recorded as `unpublished: <reason>`

- `unpublished: no-registry` — no `.ai/knowledge/registry.json`; the produced
  document still counts as delivered.
- `unpublished: no-descriptor` — a registry exists but the host has no
  `knowledge.json` descriptor.
- `unpublished: publish-failed` — a descriptor exists and the publish run
  exited non-zero.

A publish that did not run (or failed) never invalidates the document the
skill produced, and never marks the skill's own checks as failed.

## Declared kinds

| Producer | kind | canonical target |
| --- | --- | --- |
| `northstar` | `plan` | `docs/plans/` |
| `to-spec` | `spec` | `docs/specifications/ACTIVE/` |
| `to-prd` | `prd` | `docs/specifications/ACTIVE/` |
| `to-issues` | `plan` | `docs/plans/` |
| `research` | `research` | `.ai/research/` |
| `handoff` | `handoff` | `.ai/handoff/` |
| `retro` | `learning` | `docs/learning/` |
| `domain-modeling` | `adr` | `docs/architecture/adr/` |
| `code-review` | `review` | `.ai/reviews/` |

`to-issues` publishes as `plan`: the kinds enum in
`knowledge-entry.schema.json` has no `issues` kind, and broken-down
implementation slices are plan-family work items.

## Rules

- Producers never create the registry. Initialization happens once via
  `ai-catapult-init` / `ai-catapult adopt`; a skill body only reads.
- Deny-list paths in `publication-policy.json` (`**/.env`, `.memory/**`,
  `.omc/**`, `.omx/**` privates, …) are never scanned or published by this
  step.
- The kind and the pointer live in the skill body (at the end); they are part
  of the skill's audited body budget, not the frontmatter description.