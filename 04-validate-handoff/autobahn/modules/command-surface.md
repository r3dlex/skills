# Command surface

Bootstrap registers `$autobahn` on omx and `/oh-my-claudecode:autobahn` on omc. Both delegate the same
public seam; neither chooses an arbitrary registered handoff.

| Command | Description | Arguments |
|---------|-------------|-----------|
| autobahn | Admit an exact v1 plan/direct goal, then ship one ready goal per PR | `--handoff <registered-id-or-path> --goal-id <id> --context <independent-context.json>` OR `--goal <direct-v1.json> --context <independent-context.json>`; optional `--engine <engine>` |

1. Run `prereq-check.sh` with exact selectors and `--stage implementation` for
   feature work. Use `--stage preparation` only for an explicitly selected,
   bounded preparation goal with separate authority; never for feature scope.
2. Require zero exit, the exact requested stage, `execution_ready=true` and the
   exact requested repository/subject/goal set in the report.
3. Independently check live policy approval and operation authority for the same
   subject/scope/stage using the host's supported boundary. The helper always
   says `dispatch_authorized=false`; context issuer labels cannot satisfy this.
4. Only after both boundaries succeed, extract the selected goal and run TDD
   posture and engine selection. Planning-only, unknown, blocked or absent live
   authority stops before either call. No new dispatch loop is introduced.

Preparation and implementation both retain existing TDD, review, gate-driver,
CI, merge authority and cascade rules. Preparation admission never authorizes
dependent implementation or waives its current fixture, policy or trust gates.
No command alias infers merge permission. RT-03/04 coordinate installed delivery
and umbrella command projection; changing reusable source does not update an
already loaded runtime.

## Shared command registration schema

One JSON object per `.ai/commands/<surface>/<skill>.json` carries:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | Command name, equal to the skill name |
| `surface` | `"omx"`, `"omc"` or `"opencode"` | Harness owning this registration |
| `skill` | string | Same delegated skill on every surface |
| `invocation` | string | Exact harness-specific invocation above |
| `args` | array | Argument descriptors for the v1 command contract above |
| `description` | string | One-line trigger description |
| `delegates_to` | array | Skills/engines actually composed by this command |

The schema is shared with `ai-catapult-init/modules/phases/README.md`; only
`surface` and `invocation` differ between equivalent omx/omc/opencode registrations.
Registration metadata is not execution or merge authority.

## Reusable command example

This OMX registration matches the reusable fixture; OMC changes only the surface
and invocation. Mode exclusivity and goal selection are validated by the shared
helper, not inferred from these argument descriptors.

```json
{
  "name": "autobahn",
  "surface": "omx",
  "skill": "autobahn",
  "invocation": "$autobahn",
  "args": [
    {
      "name": "handoff",
      "required": false,
      "description": "Exact v1 registration ID or registered generation handoff path; required with goal-id unless goal is supplied."
    },
    {
      "name": "goal-id",
      "required": false,
      "description": "Explicit selected goal ID; repeat for a set. Required with handoff; incompatible with direct goal."
    },
    {
      "name": "goal",
      "required": false,
      "description": "Path to one nested direct-goal/1 envelope, instead of handoff and goal-id; no discovery fallback."
    },
    {
      "name": "context",
      "required": true,
      "description": "Independent readiness-context/1 input for exact subject, goals and stage; live authority must be verified separately before dispatch."
    },
    {
      "name": "engine",
      "required": false,
      "description": "Override the per-goal engine (ultraqa|ultrawork|ralph|team) only after admission and live authority checks."
    }
  ],
  "description": "Admit exact v1 goals with independent policy context, then ship one ready goal per PR after live authority verification.",
  "delegates_to": [
    "ultragoal",
    "implement",
    "tdd",
    "team",
    "ralph",
    "ultrawork",
    "ultraqa",
    "triage"
  ]
}
```

## OpenCode surface

`.ai/commands/opencode/autobahn.json` uses `surface: "opencode"` and
`invocation: "/autobahn"` (the `/<name>` form), not the OMC plugin namespace.
All other fields and v1 readiness semantics match the OMX/OMC registrations.
