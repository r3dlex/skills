---
name: agents
description: Agent-facing documentation for this skills repository
---

# Skills Repository

This repository contains agent skills following progressive disclosure principles.

## Quick Start

Pick the skill matching the user's request. Each skill has:
- **name** — skill identifier
- **description** — when to trigger it
- **body** — workflow and Quick Start

## Skills

| Skill | When to Use |
|-------|-------------|
| `write-agent-docs` | Creating or auditing agent-facing .md files |
| `write-a-skill` | Creating new skills |
| `design-an-api-or-interface` | Designing APIs, interfaces, modules |
| `improve-codebase-architecture` | Finding refactoring opportunities, deepening modules |
| `tdd` | Test-driven development with red-green-refactor |
| `edit-article` | Editing articles, tightening prose |
| `ubiquitous-language` | Building DDD-style glossaries |
| `using-git-worktrees` | Setting up isolated workspaces |
| `publish-semver` | Publishing packages with semver, GitHub Actions, and multi-ecosystem registries |
| `ai-sdlc-init` | Initialize AI SDLC methodology in a repo -- 13-step scaffold, CI pipeline, Archgate, Karpathy baseline, and ADRs |

## Writing Rules

All skills follow Layer 2 guidelines:
- Quick Start first
- Numbered steps for workflows
- Bullet points for options
- Reference deeper files with "when to read" context
- No "Overview" or "Background" sections
- Under 100 lines

## Layers

| Layer | File | Size |
|-------|------|------|
| 1 – Signal | frontmatter `description` | < 150 words |
| 2 – Core | SKILL.md body | < 100 lines |
| 3 – Detail | REFERENCE.md | unlimited |

## Domain Language

[CONTEXT.md](CONTEXT.md) defines the canonical vocabulary for the skills ecosystem — terms like _skill_, _progressive disclosure_, _AFK_, _HITL_, _tracer bullet_, _deep module_. Use these terms exactly in all agent output. When skills operate on target repos, they read that repo's CONTEXT.md and use its vocabulary.

See [write-agent-docs/SKILL.md](write-agent-docs/SKILL.md) for full audit and refactor workflow.
