# AGENTS

This generated entry surface follows the `init-ai-repo` workflow.

- Workflow doc: [`.ai/workflows/repo-workflow.md`](.ai/workflows/repo-workflow.md)
- Workflow manifest: [`.ai/workflows/repo-workflow.json`](.ai/workflows/repo-workflow.json)

Continue through the mandatory phases and record status in `.ai/phases/<phase>/status.json`.

## Harness Map

The six context types this harness assembles, and where each lives (ADR-0005):

| Context type | Canonical source | Static or dynamic |
| --- | --- | --- |
| `Instructions` | `AGENTS.md`, `.ai/system-prompts/`, `.ai/rules/` | Static |
| `Knowledge` | `docs/architecture/`, `docs/specifications/`, `docs/learning/` | Static |
| `Memory` | `.memory/human-override/`, `.memory/self-learned/` | Dynamic |
| `Examples` | `.ai/evals/<set>/`, `docs/learning/concept-maps/` | Static |
| `Tools` | `.ai/skills/`, `.ai/mcp/registry.json` | Dynamic |
| `Guardrails` | `.ai/rules/security.md`, `.ai/rules/technical-bounds.md`, `.ai/policies/` | Static |

**Static-vs-dynamic boundary.** Static context is fixed at the start of a task and is reviewed and versioned in-repo; dynamic context is assembled per-run (memory written by local agents, tool/MCP results resolved at call time). This boundary is a reviewed, versioned decision (ADR-0005); moving a context type across it requires an ADR update.
