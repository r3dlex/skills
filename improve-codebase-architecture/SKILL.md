---
name: improve-codebase-architecture
description: Explore a codebase to find opportunities for architectural improvement by deepening shallow modules. Use when user wants to improve architecture, find refactoring opportunities, consolidate tightly-coupled modules, or make a codebase more testable.
---

# Improve Codebase Architecture

## Quick Start

1. Explore codebase organically — note friction points
2. Present numbered deepening candidates with cluster, coupling, test impact
3. User picks a candidate
4. Frame problem space with constraints and code sketch
5. Spawn 3+ sub-agents to design radically different interfaces
6. Compare designs, give recommendation
7. Create GitHub issue RFC

## Core Concept

A **deep module** has a small interface hiding a large implementation. Deep modules are more testable, more AI-navigable, and let you test at the boundary instead of inside.

## Exploration

Use Agent tool (subagent_type=Explore) to navigate organically. Note friction:
- Understanding one concept requires bouncing between many small files?
- Interface nearly as complex as implementation?
- Tightly-coupled modules creating integration risk in seams?
- Untested or hard-to-test areas?

**The friction you encounter IS the signal.**

## Presenting Candidates

For each candidate, show:
- **Cluster**: Which modules/concepts involved
- **Why coupled**: Shared types, call patterns, co-ownership
- **Test impact**: What existing tests replaced by boundary tests

Do NOT propose interfaces yet. Ask user which to explore.

## Framing Problem Space

Before spawning sub-agents, write user-facing explanation:
- Constraints any new interface must satisfy
- Dependencies it needs to rely on
- Rough illustrative code sketch (not a proposal — just grounding)

Show user, then proceed to Step 5 while user reads.

## Designing Multiple Interfaces

Spawn 3+ sub-agents in parallel. Give each different constraint:
- Minimize interface (1-3 entry points)
- Maximize flexibility
- Optimize for most common caller
- Ports & adapters pattern (if applicable)

Each outputs: interface signature, usage example, internal complexity, dependency strategy, trade-offs.

Present designs, compare in prose. Give your recommendation (be opinionated — user wants a strong read, not a menu).

## Creating Issue

Create refactor RFC as GitHub issue via `gh issue create`. Do NOT ask user to review before creating — just create and share URL.
