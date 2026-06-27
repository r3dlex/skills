# ADR 0004: AGENTS.md as single source of truth; CLAUDE.md/GEMINI.md as thin stubs; full Codex parity

## Status
Accepted.

## Context
The whitepaper classifies AGENTS.md, CLAUDE.md, and GEMINI.md as static-context rule files and stresses portability across tools/vendors as a core reason Agent Skills exist. The user requires that `CLAUDE.md` only refer to `AGENTS.md` (same as `GEMINI.md`) and that skills work tool-agnostically across Claude Code and Codex. The in-flight PR6 scope instead links workflow content into CLAUDE.md, which conflicts. This repo's own `skills/CLAUDE.md` currently carries an "AI SDLC" section and a stale `docs/adr/` reference, and `AGENTS.md` (AI SDLC Methodology section, line 66) points at the legacy `docs/adr/` path.

## Decision
- `AGENTS.md` is the single source of truth for rule-file/static context.
- `init-ai-repo` generates `CLAUDE.md` and `GEMINI.md` as **thin pointers** to `AGENTS.md` with no content-bearing sections. This overrides the PR6 CLAUDE-content rule.
- Self-apply: reduce this repo's `skills/CLAUDE.md` to a pointer; fix the legacy `docs/adr/` link in `AGENTS.md` (line 66) to `docs/architecture/adr/`.
- The AGENTS.md skill index lists **every catalog skill with no exclusion allowlist** (resolved 2026-06-27); full index↔catalog parity is the P1 bar.
- Every skill reaches **full Codex parity** with a phased bar: P0 mechanical (SDLC-core skills, AGENTS.md-discoverable, no Claude/OMC-only hard deps) → P1 mechanical (all skills; abstract or make-optional Claude-only constructs; remediate `improve-codebase-architecture`) → P2 verified (representative skills actually run under Codex).

## Consequences
- One canonical rule file to maintain; CLAUDE/GEMINI never drift from it.
- Claude-only constructs (`AskUserQuestion`, `Task`, `Skill(...)`) must degrade gracefully or be abstracted behind tool-agnostic prose.
- AGENTS.md skill index becomes the cross-tool discovery surface.
