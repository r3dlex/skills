# ADR 0005: MCP/A2A open standards and an observability harness surface

## Status
Proposed.

## Context
The whitepaper lists observability (logs, traces, eval/cost/latency metering) as non-optional harness surface — "without observability there is no way to tell whether the agent is doing well or quietly drifting" — and recommends adopting open standards now: Model Context Protocol (MCP) for tool access and Agent2Agent (A2A) for cross-agent delegation. Today the repo has no observability surface and only a single passing mention of MCP/A2A in `documentation-blueprint.md`.

## Decision
- `init-ai-repo` generates an **observability** surface: logging/trace conventions plus a token-cost and trajectory-audit checklist in `validation.md`/`ci-policy.md`.
- Promote **MCP/A2A** from a mention to a real blueprint section/module: a generated MCP-server registry stub and an A2A cross-agent handoff convention.
- Generated `AGENTS.md` carries an explicit **Harness Map** enumerating the six context types (Instructions, Knowledge, Memory, Examples, Tools, Guardrails) and documents the static-vs-dynamic context boundary as a reviewed, versioned decision.

## Consequences
- Agent drift, cost, and trajectory become auditable; supports the model-routing audit in ADR 0003.
- Choosing MCP/A2A now preserves multi-vendor/framework optionality and avoids re-platforming later.
- The static/dynamic boundary becomes a first-class architectural decision rather than an implicit one.
