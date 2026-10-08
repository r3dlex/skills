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

When `.ai/knowledge/registry.json` exists, read it before the producer saves
its document (see *Placement*), and run the step at the end of the producer
skill, once that document is final. Never as a substitute for the document
itself.

## Who runs the step

Only the outermost producer runs the step. A producer running on behalf of
another producer (`to-issues` delegated from `to-spec` or `northstar`, for
example) skips it and records nothing; the outermost skill publishes its own
document.

Hosts publish through a descriptor: `omc` (Claude Code), `omx` (Codex) and
`opencode` (OpenCode). Gemini, Auggie and Copilot are not XSKP hosts: their
flat projections drop the pointer to this module and never run the step.

## The step

1. Check `.ai/knowledge/registry.json`. If it does not exist, record
   `unpublished: no-registry` and return SUCCESS. The skill never fails
   because of the registry.
2. Read the harness host descriptor `.ai/commands/<host>/knowledge.json`
   (`omc` for Claude Code, `omx` for Codex, `opencode` for OpenCode). If the
   host's descriptor is missing or unreadable, record
   `unpublished: no-descriptor` and return SUCCESS.
3. Name the entry `<id>` = `<repo_id>:<kind>:<slug>`. `<repo_id>` is the
   `repo_id` of `.ai/init/repo-profile.json`, the value the publisher
   validates. `<slug>` comes from the document title: lowercase, each run of
   other characters replaced by one `-`, no leading or trailing `-`, matching
   `[a-z0-9][a-z0-9.-]*`. An ADR slug is `<NNNN>-<slug>` (see *Declared
   kinds*). The *Write rules* may add a suffix.
4. Take the producer's one document from *Declared kinds*. A native source or
   a source record is published from where it is, and the publisher writes
   the canonical copy. Text with no local file, such as a hosted-only `to-prd`
   or `to-issues` output (materialize its exact published text), is written
   to `<target><slug>.md`, where `<target>` is the kind's entry in
   `canonical_targets` of `publication-policy.json`, under the *Write rules*.
   A document the producer saved anywhere else follows *Placement*.
5. Run, from the repository root, the descriptor's `argv` followed by
   `publish <path> --id <id> --kind <kind> --title <title> --producer <skill>`.
   Always pass `--id`: without it the publisher derives the id from the file
   name, which collides or is invalid for names such as `handoff.md` or
   `PRD.md`. With `--id` the publisher skips its own source-collision check,
   so the *Write rules* decide what counts as a revision.
6. If the document could not be written, or the publish run exits non-zero,
   first undo this step's write: delete only the copy this step made, or
   restore the bytes it replaced. Never delete or move the producer's own
   document. Then record `unpublished: publish-failed` and return SUCCESS.
   Publication is best-effort by contract.
7. On success, finish *Placement* if it applies, and report the canonical
   `sha256` and entry id the tool prints in the skill's final report.

## Write rules

They apply to the canonical path `<target><slug>.md` before this step writes
it, and before a source is published from where it is (the publisher then
writes that path itself):

1. Refuse the path if an entry in `.ai/knowledge/registry.json` with another
   `knowledge_id` already uses it as its canonical path (`path`).
2. Write only if the path is absent and `<id>` is not registered, or if the
   run is a revision. A run is a revision only when `<id>` is registered, the
   file at the path carries `knowledge_id: <id>` in its first frontmatter
   block, this run revises that document, and the source is the canonical
   path of the entry or a `derived_from` path of one of its revisions (read
   `.ai/knowledge/entries/<id with : replaced by __>.json`). Refuse a
   registered `<id>` for any other run, and any other existing file.
3. On a refusal, try `<slug>-2`, then `<slug>-3`, up to `<slug>-99`; `<id>`
   follows the slug. If every candidate is refused, record
   `unpublished: publish-failed`.
4. Create a new file exclusively: fail if the path appeared meanwhile, never
   truncate it. For a revision, keep the previous bytes until the publish run
   succeeds.
5. Never write a path the policy lists under `deny` or `immutable`, and never
   write inside a harness directory.

## Source records

A source record is a tracker or intake record that other files read: a local
tracker's `.scratch/<feature-slug>/PRD.md` (and its `issues/` files, which
`to-issues` reads back), or northstar's `.ai/work-intake/` record (the
traceability graph points its issue node at it). A source record stays where
it is: never move, copy or rewrite it. It is passed to `publish` from where it
is; the registry's canonical copy is derived from it, and the publisher
records the source path in the revision's `derived_from`. The source record
stays the working record; the registry copy is the published, derived one.

## Placement

When `.ai/knowledge/registry.json` exists, a producer whose document is not a
native harness file or a source record saves it at `<target><slug>.md` under
the *Write rules* in the first place, instead of a location its own body
suggests (a notes folder, a repo-local ADR folder). The publisher then
registers it in place, and the repo keeps one tracked copy.

If this run already saved the document elsewhere:

- Copy it to `<target><slug>.md` under the *Write rules* and publish the copy.
  Remove the original only after the publish run succeeds, then update the
  references this run made to the new path, and report the new path.
- On a failure the step deletes only its copy; the original stays where the
  producer saved it.
- Never move or remove a file that existed before this run, or one that a
  tracked file links to. It stays where it is: record
  `unpublished: needs-adoption` and leave it to `ai-catapult adopt`.

## Private content

`handoff` and `retro` write only what is safe to track:

- Never copy content read from a path the policy lists under `deny`, such as
  `~/**` (global instructions and session logs in the home directory),
  `.memory/**`, `.omc/project-memory.json`, `.omc/sessions/**`,
  `.omc/logs/**` and `.omx/notepad.md`; cite such a file by name only.
- Before the write, replace home-directory paths with `<home>` and session ids
  with `<session>`, using the patterns below in order.
- `handoff` runs its redaction step before the write; the step never writes
  unredacted text.

```knowledge-scrub
(?:/Users|/home)/[^/\s]+ -> <home>
~(?=/) -> <home>
\bses_[0-9A-Za-z]{8,} -> <session>
\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b -> <session>
```

## Reasons recorded as `unpublished: <reason>`

- `unpublished: no-registry` — no `.ai/knowledge/registry.json`; the produced
  document still counts as delivered.
- `unpublished: no-descriptor` — a registry exists but the host has no
  `knowledge.json` descriptor.
- `unpublished: publish-failed` — a descriptor exists, but the document could
  not be written (every slug up to `<slug>-99` was refused, or the write
  failed) or the publish run exited non-zero; this step's write was undone
  first.
- `unpublished: needs-adoption` — the document lies outside its canonical
  target and existed before this run, or a tracked file links to it; it stays
  where it is for `ai-catapult adopt`.

A publish that did not run (or failed) never invalidates the document the
skill produced, and never marks the skill's own checks as failed.

## Declared kinds

| Producer | kind | canonical target | document |
| --- | --- | --- | --- |
| `northstar` | `plan` | `docs/plans/` | the ralplan plan this run produced when it is a native `plan` source (`.omc/plans/*.md`, `.omo/plans/*.md`, `.omx/plans/**/*.md`); otherwise its `.ai/work-intake/` record, a source record published from where it is |
| `to-spec` | `spec` | `docs/specifications/ACTIVE/` | the spec text, written to the target |
| `to-prd` | `prd` | `docs/specifications/ACTIVE/` | a local tracker's `.scratch/<feature-slug>/PRD.md`, a source record published from where it is; for a hosted tracker, the PRD text it raised, preceded by its tracker reference, written to the target |
| `to-issues` | `plan` | `docs/plans/` | one file with every slice it raised, in dependency order, each with its tracker reference and body, written to the target; the local records stay in `.scratch/` |
| `research` | `research` | `.ai/research/` | the findings file, saved at the target (*Placement*); a native `.omc/research/**/*.md` file is passed where it is |
| `handoff` | `handoff` | `.ai/handoff/` | the handoff document after its redaction step and *Private content*, written to the target; the OS temp-directory copy is not published |
| `retro` | `learning` | `docs/learning/` | the retro findings under *Private content*, written to the target without session-log or transcript content |
| `domain-modeling` | `adr` | `docs/architecture/adr/` | the ADR it wrote, saved at the target as `<NNNN>-<slug>.md`, numbered after the highest existing number in the target (*Placement*); `CONTEXT.md` is not published |
| `code-review` | `review` | `.ai/reviews/` | the `## Standards` and `## Spec` report, written to the target |

A native source counts only when the first `native_rules` glob that matches
its path has the same kind as the producer: a Codex plan under
`.omx/plans/small-work-reviews/**/*.md` matches `review` first, so it is never
a `northstar` source.

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
