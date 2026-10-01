# Prerequisites

Run the shared v1 gate with an exact handoff ID/path **and** explicit goal IDs,
or one explicit nested direct-goal envelope. Never discover an unrelated
registered handoff to satisfy a request. Both routes use the same fixed policy,
independent context and validator; see [readiness.md](readiness.md).

```sh
bash autobahn/prereq-check.sh --root /repo --handoff northstar-plan-example \
  --goal-id G1 --context /independent/context.json
```

The root must contain the AI SDLC v3 matrix, workflow manifest and traceability
graph. Registered generation payload, graph and handoff hashes must agree;
repository/spec identities are revalidated. Legacy inputs need explicit
migration. Missing/mismatched local helper fingerprints fail closed without
PATH, network, legacy-writer or permissive fallback.

A zero structural admission exit is not dispatch authorization. The live
orchestrator must separately check independent operation authority. Missing
authority blocks the action, not planning. All helper reports explicitly keep
`dispatch_authorized: false`.
