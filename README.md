# skills

A collection of reusable agent skills for Claude Code and compatible AI agents.

Each skill is a self-contained directory with a `SKILL.md` that tells the agent what to do and when to trigger. Skills follow [progressive disclosure](write-agent-docs/SKILL.md) — lean core instructions, with detail in reference files loaded on demand.

## Skills

| Skill | What it does |
|---|---|
| [`design-an-api-or-interface`](design-an-api-or-interface/SKILL.md) | Generate 3+ radically different interface designs in parallel, then compare and synthesize — based on Ousterhout's "Design It Twice" |
| [`improve-codebase-architecture`](improve-codebase-architecture/SKILL.md) | Explore a codebase for shallow modules, present refactoring candidates, design deep replacements, and file a GitHub RFC |
| [`tdd`](tdd/SKILL.md) | Red-green-refactor loop with tracer bullets — one test, one implementation, repeat |
| [`publish-semver`](publish-semver/SKILL.md) | Automated semver publishing for 10 ecosystems (npm, PyPI, crates.io, NuGet, Hex, pub.dev, Maven, Gradle, Burrito) via GitHub Actions or Azure DevOps |
| [`using-git-worktrees`](using-git-worktrees/SKILL.md) | Create isolated git worktrees with auto-setup, safety verification, and test baseline |
| [`ubiquitous-language`](ubiquitous-language/SKILL.md) | Extract a DDD-style glossary from a conversation, flag ambiguities, and save to `UBIQUITOUS_LANGUAGE.md` |
| [`edit-article`](edit-article/SKILL.md) | Restructure and tighten prose section by section, max 240 chars per paragraph |
| [`write-a-skill`](write-a-skill/SKILL.md) | Create new skills with proper structure and progressive disclosure |
| [`write-agent-docs`](write-agent-docs/SKILL.md) | Write and audit agent-facing Markdown using progressive disclosure principles |
| [`init-ai-repo`](init-ai-repo/SKILL.md) | Canonical AI-ready repo initialization skill; `ai-sdlc-init` remains a deprecated compatibility alias during path migration |

## Installation

Copy the skill directories you want into your project's `.claude/skills/` folder (or wherever your agent loads skills from):

```bash
cp -r tdd ~/.claude/skills/
cp -r publish-semver ~/.claude/skills/
```

## Structure

Each skill follows:

```
skill-name/
├── SKILL.md        # Trigger conditions + core workflow (< 100 lines)
├── REFERENCE.md    # Deep detail, loaded on demand
└── scripts/        # Utility scripts if needed
```

The `description` frontmatter in `SKILL.md` is what the agent reads to decide whether to load the skill. Keep it specific and end with `Use when [triggers].`

<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This project uses the [init-ai-repo methodology](https://github.com/r3dlex/skills/tree/main/init-ai-repo)
to maintain architectural governance alongside AI-assisted development.

Migration note: `init-ai-repo` is the canonical skill name and path. The
`ai-sdlc-init/` directory remains only as a deprecated compatibility alias/shim
until downstream skill loaders have migrated.

Key practices:
- **Architecture Decision Records** in [`docs/adr/`](docs/adr/) — significant
  decisions are version-controlled with context and rationale.
- **Archgate rules** in [`.rules.ts`](.rules.ts) — code quality constraints
  across five domains, validated in CI.
- **Karpathy baseline** — four engineering heuristics loaded by all agents
  operating in this repo (think, simplify, be surgical, stay on goal).

Contributing? Read [`AGENTS.md`](AGENTS.md) for agent-facing methodology details.

<!-- ai-sdlc-init:end -->

<!-- v3-ai-sdlc-init:start -->
## init-ai-repo v3
This repo follows the v3 AI-ready repository layout. See `.ai/matrix.json`, `.memory/human-override/`, and `docs/architecture/adr/`. Modules currently live at `r3dlex/skills/init-ai-repo/modules/` while the deprecated path alias is preserved.
<!-- v3-ai-sdlc-init:end -->
