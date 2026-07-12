# Command-Surface Schema (shared)

Read when generating `.ai/commands/omx/<skill>.json` and
`.ai/commands/omc/<skill>.json`. No exemplar existed before this skill, so the
schema is **designed once here** and shared: `ai-catapult-init`'s future command
generator and the catalog skills emit identical shapes. (If `ai-catapult-init`'s
generator lands first, adopt its schema instead.) Cross-referenced from
`ai-catapult-init/modules/phases/README.md`.

## Schema

One JSON object per file (extension `.json`) with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | command name (equals the skill name) |
| `surface` | `"omx"` \| `"omc"` | which harness this file registers |
| `skill` | string | the skill the command delegates to (same in both files) |
| `invocation` | string | how the user triggers it on that surface (see below) |
| `args` | array | accepted argument descriptors (may be empty) |
| `description` | string | one-line trigger description |
| `delegates_to` | array | skills/engines this command composes |

## omx vs omc invocation

The two surfaces differ only in the invocation token; both point at the same
`skill`:

- **omx:** `invocation` is the `$<name>` form — e.g. `$northstar`.
- **omc:** `invocation` is the `/oh-my-claudecode:<name>` form — e.g.
  `/oh-my-claudecode:northstar`.

## Example — `.ai/commands/omx/northstar.json`

```json
{
  "name": "northstar",
  "surface": "omx",
  "skill": "northstar",
  "invocation": "$northstar",
  "args": [{ "name": "spec", "required": false }],
  "description": "Intake intent into a tracked, sliced plan and write the A→B handoff.",
  "delegates_to": ["deep-interview", "grill-me", "to-issues", "triage", "ralplan"]
}
```

The omc file is identical except `surface: "omc"` and
`invocation: "/oh-my-claudecode:northstar"`.
