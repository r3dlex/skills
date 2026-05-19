---
name: setup-skills
description: Sets up an `## Agent skills` block in AGENTS.md/CLAUDE.md and `docs/agents/` so the engineering skills know this repo's issue tracker (GitHub or local markdown), triage label vocabulary, and domain doc layout. Run before first use of `to-issues`, `to-prd`, `triage`, `diagnose`, `tdd`, `improve-codebase-architecture`, or `zoom-out` — or if those skills appear to be missing context about the issue tracker, triage labels, or domain docs.
disable-model-invocation: true
---

# Setup Skills

Scaffold the per-repo configuration that the engineering skills assume:

- **Issue tracker** — where issues live (GitHub by default; local markdown is also supported out of the box)
- **Triage labels** — the strings used for the five canonical triage roles
- **Domain docs** — where `CONTEXT.md` and ADRs live, and the consumer rules for reading them

This is a prompt-driven skill, not a deterministic script. Explore, auto-detect sensible defaults, present everything in one summary, then write. Only ask the user when a genuine ambiguity requires their judgment.

## Process

### 1. Explore

Look at the current repo to understand its starting state. Read whatever exists; don't assume:

- `git remote -v` and `.git/config` — is this a GitHub repo? Which one?
- `AGENTS.md` and `CLAUDE.md` at the repo root — does either exist? Is there already an `## Agent skills` section in either?
- `CONTEXT.md` and `CONTEXT-MAP.md` at the repo root
- `docs/adr/` and any `src/*/docs/adr/` directories
- `docs/agents/` — does this skill's prior output already exist?
- `.scratch/` — sign that a local-markdown issue tracker convention is already in use

### 2. Auto-detect and present defaults

Summarise what's present and what's missing in ONE round. Auto-detect sensible defaults:

**Section A — Issue tracker.** If a `git remote` points at GitHub, default to GitHub. If GitLab, default to GitLab. Otherwise, default to local markdown (`.scratch/`). Only ask the user if none of these are clearly right.

**Section B — Triage labels.** Default to the five canonical names: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. Only ask if the repo already uses different label strings that need mapping.

**Section C — Domain docs.** Default to single-context (one `CONTEXT.md` + `docs/adr/` at repo root). Only switch to multi-context if `CONTEXT-MAP.md` exists.

Present all auto-detected defaults together. If the defaults are clearly correct, proceed without asking. Only ask for confirmation when there's genuine ambiguity.

### 3. Write

Auto-detect the correct file to edit (CLAUDE.md or AGENTS.md) and write the configuration. Only present a draft for review if the auto-detected defaults are ambiguous.

Auto-detect the file to edit (CLAUDE.md if it exists, else AGENTS.md), then write the `## Agent skills` block and the three `docs/agents/` files. Use the seed templates in this skill folder as starting points. Mention which skills will now read from these files.
