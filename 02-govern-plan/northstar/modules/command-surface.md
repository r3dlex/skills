# Command surface

Bootstrap registers `$northstar` on omx and `/oh-my-claudecode:northstar` on omc for the same planning-only
workflow: deep interview, optional two adversarial passes, local-first tracked
issue, consensus slices, and durable v1 handoff publication.

| Command | Description | Arguments |
|---------|-------------|-----------|
| northstar | Turn intent into tracked slices and an explicitly non-authorizing v1 readiness handoff | `<intent>`; publish reviewed plan with `handoff-write.sh --root <repo> --bundle <handoff-goals-v1.json>` |

Publish exact repository/spec/goal IDs and per-goal preparation, implementation
and merge readiness. Report remaining gaps together; planning complete never
means implementation ready. Use the matched shared helper and separate v1
registry; missing/mixed dependencies stop without legacy discovery or writer
fallback. Autobahn is a separate explicit invocation with exact selectors and
independently checked live authority.

The bootstrap owns OMC/OMX command surfaces; RT-03/04 coordinate delivery and
umbrella adoption. No source edit claims that a loaded host is already refreshed.

## Shared command registration schema

One JSON object per `.ai/commands/<surface>/<skill>.json` carries:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | Command name, equal to the skill name |
| `surface` | `"omx"` or `"omc"` | Harness owning this registration |
| `skill` | string | Same delegated skill on both surfaces |
| `invocation` | string | Exact harness-specific invocation above |
| `args` | array | Argument descriptors for the v1 command contract above |
| `description` | string | One-line trigger description |
| `delegates_to` | array | Skills/engines actually composed by this command |

The schema is shared with `ai-catapult-init/modules/phases/README.md`; only
`surface` and `invocation` differ between equivalent omx/omc registrations.
Registration metadata is not execution or merge authority.

## Reusable command example

This OMX registration matches the reusable fixture; OMC changes only the surface
and invocation. `spec` is planning input, not a legacy writer argument.

```json
{
  "name": "northstar",
  "surface": "omx",
  "skill": "northstar",
  "invocation": "$northstar",
  "args": [
    {
      "name": "spec",
      "required": false,
      "description": "Path to the active spec to plan from; publication pins it in the reviewed bundle."
    },
    {
      "name": "bundle",
      "required": false,
      "description": "Reviewed handoff-goals/1 bundle for explicit version-isolated publication after planning."
    }
  ],
  "description": "Plan tracked slices and publish a non-authorizing v1 handoff; planning completion is not implementation readiness.",
  "delegates_to": [
    "deep-interview",
    "grill-with-docs",
    "grill-me",
    "to-issues",
    "triage",
    "ralplan"
  ]
}
```
