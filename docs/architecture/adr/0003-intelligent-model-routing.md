# ADR 0003: Intelligent model-routing policy

## Status
Accepted.

## Context
The whitepaper's economics section argues that routing every interaction to a single frontier model is financially unviable: a well-designed "factory" uses large models for complex work (requirements, architecture, initial implementation) and routes deterministic, low-complexity work (test generation, code review, CI monitoring) to smaller, cheaper, faster models. The repo has no first-class model-routing artifact today.

## Decision
`init-ai-repo` generates `.ai/policies/model-routing.json` mapping task-class → model tier, aligned with the OMC `haiku`/`sonnet`/`opus` tiers:
- frontier/opus: requirements, architecture, initial implementation, hard verification.
- mid/sonnet: standard implementation, planning.
- cheap/haiku: test generation, first-pass code review, CI/lint monitoring, quick lookups.
The policy is versioned and reviewed like other configuration.

## Consequences
- OpEx token cost driven down without sacrificing quality on hard tasks.
- Tier aliases (not provider-specific IDs) keep the policy portable across providers/proxies.
- Routing decisions become auditable via the observability surface (ADR 0005).
