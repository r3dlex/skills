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
3. Select the one local document to publish, materializing a hosted-only
   output first (see *Which document is published*).
4. Run publication from the repository root: the descriptor's `argv` array
   followed by `publish <path> --kind <kind> --producer <skill>` (verb grammar
   `publish <path> [--id] [--kind] [--title] [--producer]`). If no local
   document could be written, or the run exits non-zero, record
   `unpublished: publish-failed` and return SUCCESS. Publication is
   best-effort by contract.
5. On success, report the canonical `sha256` and entry id the tool prints in
   the skill's final report.

## Which document is published

`<path>` is one repository-relative Markdown file this run produced, never a
URL, an issue number or text held only in the conversation.

- Local output: the file the skill wrote, such as a research note, a spec or
  a plan. A native harness document matching a `native_rules` glob of
  `publication-policy.json` (for example `.omc/plans/*.md` or
  `.omx/plans/**/*.md`) is passed where it is; the publisher copies it to the
  kind's canonical target and leaves the native file untouched.
- Hosted-only output (`to-prd`, `to-issues`, or `to-spec` when it only raised
  an issue): materialize it first. Write the exact text the run published,
  preceded by its tracker reference(s), to `<target><slug>.md`, where
  `<target>` is the declared kind's entry in `canonical_targets` of
  `publication-policy.json` (`prd` → `docs/specifications/ACTIVE/`, `plan` →
  `docs/plans/`) and `<slug>` is the title in lowercase hyphenated form
  (`[a-z0-9][a-z0-9.-]*`). `to-issues` writes one file per run with every
  slice it published, in dependency order. The publisher keeps a file that
  is already under its kind's canonical target in place.
- Never overwrite a file that holds a different document; choose a distinct
  slug instead.

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
- Path classes come from `publication-policy.json`, never a broader summary.
  Its `deny` paths are private and never scanned or published by this step:
  for example `**/.env`, `.memory/**`, `.omc/state/**`, `.omc/sessions/**`,
  `.omc/logs/**`, `.omc/project-memory.json`, `.omx/state/**`,
  `.omx/context/**`, `.omx/notepad.md` and `.omo/boulder.json`. Native
  durable documents in the same harness directories stay publishable sources
  through `native_rules` (first match wins): for example `.omc/plans/*.md`,
  `.omc/research/**/*.md`, `.omx/plans/**/*.md` and `.omo/plans/*.md`.
- The kind and the pointer live in the skill body (at the end); they are part
  of the skill's audited body budget, not the frontmatter description.