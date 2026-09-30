# Command-Surface Schema (shared)

Read when generating `.ai/commands/omx/<skill>.json`,
`.ai/commands/omc/<skill>.json`, and `.ai/commands/opencode/<skill>.json`. No
exemplar existed before this skill, so the schema is **designed once here** and
shared: `ai-catapult-init`'s future command generator and the catalog skills
emit identical shapes. (If `ai-catapult-init`'s generator lands first, adopt its
schema instead.) Cross-referenced from
`ai-catapult-init/modules/phases/README.md`.

## Schema

One JSON object per file (extension `.json`) with these fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | command name (equals the skill name) |
| `surface` | `"omx"` \| `"omc"` \| `"opencode"` | which harness this file registers |
| `skill` | string | the skill the command delegates to (same in every file) |
| `invocation` | string | how the user triggers it on that surface (see below) |
| `args` | array | accepted argument descriptors (may be empty) |
| `description` | string | one-line trigger description |
| `delegates_to` | array | skills/engines this command composes |

## Surface invocations

The surfaces differ only in the invocation token; every file points at the same
`skill`:

- **omx:** `invocation` is the `$<name>` form — e.g. `$northstar`.
- **omc:** `invocation` is the `/oh-my-claudecode:<name>` form — e.g.
  `/oh-my-claudecode:northstar`.
- **opencode:** `invocation` is the `/<name>` form — e.g. `/northstar`
  (opencode's own slash commands, not the omc plugin namespace).

## Example — `.ai/commands/omx/northstar.json`

```json
{
  "name": "northstar",
  "surface": "omx",
  "skill": "northstar",
  "invocation": "$northstar",
  "args": [{ "name": "spec", "required": false }],
  "description": "Intake intent into a tracked, sliced plan and write the A→B handoff.",
  "delegates_to": ["deep-interview", "grill-with-docs", "grill-me", "to-issues", "triage", "ralplan"]
}
```

The omc file is identical except `surface: "omc"` and
`invocation: "/oh-my-claudecode:northstar"`. The opencode file is identical
except `surface: "opencode"` and `invocation: "/northstar"`.
