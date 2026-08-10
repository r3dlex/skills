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
  "args": [
    { "name": "goal", "required": false, "description": "Path to one implementation-ready goal record for direct intake, bypassing a handoff." },
    { "name": "engine", "required": false, "description": "Override the per-goal engine (ultraqa|ultrawork|ralph|team)." }
  ],
  "description": "Ship a northstar handoff's sliced goals, or one implementation-ready goal record, one PR per goal.",
  "delegates_to": ["ultragoal", "implement", "tdd", "team", "ralph", "ultrawork", "ultraqa", "triage"]
}
```

The omc file is identical except `surface: "omc"` and
`invocation: "/oh-my-claudecode:autobahn"`.

`implement` and `tdd` appear here because the delegation is now real:
[modules/implementation.md](implementation.md) makes `implement` the named
implementation step driving `tdd` red-green under both postures. They were
deliberately absent while autobahn only selected a TDD *posture* without
invoking the skill. `tests/delegate_contract_test.sh` treats the shipped command
JSON as authoritative, so this list may only claim delegations that happen.
