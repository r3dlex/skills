# MCP/A2A Module

Read when generating the `.ai/mcp/` scaffold: the MCP-server registry stub and
the A2A cross-agent handoff convention. This promotes the single passing MCP/A2A
mention into a real, reviewed surface. See ADR-0005.

## Principle

Adopt open standards now: **MCP** (Model Context Protocol) for tool access and
**A2A** (Agent2Agent) for cross-agent delegation. Choosing them at init time
preserves multi-vendor/framework optionality and avoids re-platforming later.
The generated surface is **offline and deterministic** — a registry stub plus a
convention doc. `ai-catapult-init` resolves no live endpoint and makes no network or
model call at generation time.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/mcp/registry.json` | MCP-server registry stub: declared servers, their transport, advertised tools, and an `a2a` block pointing at the handoff convention. |
| `.ai/mcp/a2a-handoff.md` | A2A cross-agent handoff convention: the handoff envelope, its fields, and the rules that keep delegation auditable. |

## Registry stub shape

`registry.json` declares `schema_version`, a `servers` array, and an `a2a`
block. Each server entry carries `name`, `transport`, `status`, `endpoint`, and
a `tools` array. Every server `status` is `"stub"` and `endpoint` is `null`: the
registry documents the shape an out-of-band runner consumes, never a resolved
live connection. The `a2a` block declares the `protocol`, a `handoff_convention`
pointer to `.ai/mcp/a2a-handoff.md`, and `correlation_id_required`. Umbrella
repos additionally set `a2a.cross_repo: true` and may register a workspace-sync
server for managed-repository operations.

## A2A handoff convention

`a2a-handoff.md` defines a single JSON handoff envelope carried on every
cross-agent delegation. Required fields: `correlation_id` (preserved end-to-end
so the trajectory stays one trace), `from_agent`, `to_agent`, `task` (with an
acceptance check), `context_refs` (pointers, not copied context), and
`constraints` (offline-only, no hosted mutation). The receiving agent opens a
child span linked by `correlation_id`, mirroring the trace conventions in
`.ai/observability/conventions.md`. Envelopes never inline secrets; large
context is referenced by pointer. In an umbrella, cross-repo handoffs reference
the managed repository by its matrix path and never bypass the physical-copy
sync boundary.

## Validation

The MCP/A2A surface is validated offline and structurally by
`modules/validation.md` check #17: for both v3 fixtures, `.ai/mcp/registry.json`
parses, declares `schema_version`, a `servers` array of stub entries, and an
`a2a` block with a `handoff_convention` pointer; `.ai/mcp/a2a-handoff.md` exists,
is non-empty, and carries the handoff-envelope and `correlation_id` keywords.
The discoverable runner is `tests/mcp_a2a_test.sh`.

## Safety rules

- Do not add a model or network dependency to the generated MCP/A2A path; the
  registry is a stub and the handoff doc is a convention.
- Do not record a resolved live `endpoint`; servers stay `status: "stub"` until
  an out-of-band operator wires them.
- Do not drop `correlation_id` from the handoff envelope; the trace and the
  cross-agent trajectory depend on it.
