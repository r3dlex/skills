# Command-Surface Schema (shared)

Read when generating `.ai/commands/omx/autobahn.json` and
`.ai/commands/omc/autobahn.json`. Autobahn reuses the **shared** command-surface
schema designed once in `northstar/modules/command-surface.md` (and
cross-referenced from `ai-catapult-init/modules/phases/README.md`); both surfaces emit
identical shapes. This module records autobahn's entries only.

## Schema (recap)

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

- **omx:** `invocation` is the `$<name>` form — e.g. `$autobahn`.
- **omc:** `invocation` is the `/oh-my-claudecode:<name>` form — e.g.
  `/oh-my-claudecode:autobahn`.

## Example — `.ai/commands/omx/autobahn.json`

```json
{
  "name": "autobahn",
  "surface": "omx",
  "skill": "autobahn",
  "invocation": "$autobahn",
  "args": [{ "name": "engine", "required": false }],
  "description": "Ship a northstar handoff's sliced goals one PR per goal.",
  "delegates_to": ["ultragoal", "team", "ralph", "ultrawork", "ultraqa", "triage"]
}
```

The omc file is identical except `surface: "omc"` and
`invocation: "/oh-my-claudecode:autobahn"`.
