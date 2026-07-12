---
name: design-an-api-or-interface
description: 'Design APIs/interfaces with Design It Twice: create alternatives, compare tradeoffs, choose one. Use when designing an API, module, class, or boundary.'
---

# Design an API or Interface

## Quick Start

1. Gather requirements (problem, callers, key ops, constraints)
2. Spawn 3+ sub-agents in parallel, each with different design constraints
3. Present each design with signature, examples, trade-offs
4. Compare and recommend
5. Synthesize best elements

## Workflow

### Step 1 — Gather Requirements

Before generating designs, understand:
- **Problem**: What does this interface solve?
- **Callers**: Who will use it? What do they need?
- **Key operations**: Most common operations?
- **Constraints**: Performance, memory, API compatibility?
- **Surface area**: What to hide vs expose?

### Step 2 — Generate Designs in Parallel

Spawn 3+ sub-agents with different constraints:

| Agent | Constraint |
|-------|------------|
| A | Minimize method count — leanest possible |
| B | Maximize flexibility — most general-purpose |
| C | Optimize for common case — prioritize frequent ops |
| D | Ports & adapters pattern for cross-boundary deps |

Each produces: interface signature, usage examples, internal complexity, trade-offs.

### Step 3 — Present Each Design

Show: interface signature, usage code, hidden complexity, key trade-offs.

### Step 4 — Compare Designs

Evaluate on: simplicity, flexibility, implementation efficiency, depth, ease of use vs misuse.

### Step 5 — Synthesize

Combine insights. Often best design borrows from multiple options.

## Key Principles

1. **Interface simplicity**: Fewer methods with focused purpose
2. **General-purpose without over-generalization**: Don't bloat for hypothetical needs
3. **Implementation efficiency**: Interface shape allows performant internals
4. **Depth**: Small surface area hiding significant complexity

Based on "A Philosophy of Software Design" by John Ousterhout — "Design It Twice" principle.
