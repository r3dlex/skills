# Archgate Module

Read when configuring `.rules.ts` validation, CI governance, or optional semantic/drift checks.

## Default structural check

Structural validation stays fast and default-on:

```sh
bash scripts/validate-rules.sh .rules.ts
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
```

The structural check verifies that `.rules.ts` exports the required rule domains and remains suitable for local/CI execution.

## JSON contract

`bash scripts/archgate.sh --format json` emits one JSON object:

```json
{
  "status": "pass|fail|skipped",
  "mode": "structural|semantic|drift",
  "rulesFile": ".rules.ts",
  "base": "<optional base ref>",
  "head": "<optional head ref>",
  "checks": [
    { "id": "archgate-structural", "status": "pass", "message": "..." }
  ],
  "exitCode": 0
}
```

## Optional semantic/drift checks

Semantic and drift modes are opt-in. They must not block CI until the repo has project-specific rules and `ARCHGATE_SEMANTIC=1` is deliberately configured.

```sh
ARCHGATE_SEMANTIC=1 bash scripts/archgate.sh --mode drift --base origin/main --head HEAD --format json
```

Drift checks compare the PR diff with BRD, PRD, acceptance criteria, relevant ADRs, and `.rules.ts`. Until a project-specific checker exists, the contract returns `skipped` without `ARCHGATE_SEMANTIC=1` and `fail` with it.
