---
name: ai-sdlc-init
description: Bootstrap the AI SDLC methodology in any repository — skill scaffold, CI pipeline with prek (Rust-based), Archgate rules, Karpathy baseline guidelines, and seed ADRs. Use when initializing the AI SDLC methodology in a repository, setting up AI-assisted development workflows, or when the user says "ai-sdlc-init", "bootstrap AI SDLC", or wants to add AI engineering practices to a project.
---

# AI SDLC Init

Run this skill in any repo's Claude Code session via `/ai-sdlc-init`. With `-p` flag it prints the plan without writing files (dry-run). Interactive mode (default) prompts for tracker and CI platform only when the repo has no existing setup-skills marker.

## Workflow

### 1. Detect repo state
Read existing `AGENTS.md`/`CLAUDE.md` for brownfield/greenfield signals. Scan for `<!-- setup-skills:start -->`. If present, read config from `docs/agents/issue-tracker-{github,gitlab,local}.md` and `docs/agents/triage-labels.md` — skip tooling questions. Otherwise ask: issue tracker? (GH Issues / Jira / ADO) and CI platform? (GH Actions / ADO Pipelines / GitLab CI).

### 2. Create `.agents/` directory
Create `.agents/skills/karpathy-guidelines/SKILL.md` and `REFERENCE.md` from templates in REFERENCE.md.

### 3. Write `upstream.lock`
Run `git ls-remote https://github.com/mattpocock/skills.git HEAD`, populate `pinned_sha`. Fields: `source`, `via`, `pinned_sha`, `updated`, `sync_script`.

### 4. Write `.gitignore` + `.gitkeep`
Append AI SDLC entries to `.gitignore` with marker guard. Create `upstream-pocock/.gitkeep`.

### 5. Create `raw/docs/incident-template.md`
Postmortem template with `INC-YYYY-MM-DD-slug.md` naming convention. See REFERENCE.md for template.

### 6. Write `scripts/sync-upstream.sh`
Design pattern only — document as a sync scaffold, not a runnable script.

### 7. Create CI files
Create `.github/workflows/ci-prek.yml` as a SEPARATE workflow (never modify existing `ci.yml`). Use `j178/prek-action@v2` with `extra-args: '--all-files'`. Create `prek.toml` for hook config. Create `scripts/validate-rules.sh` as a `.rules.ts` structural validator. See REFERENCE.md for templates.

### 8. Write `.rules.ts`
Archgate rules covering 5 domains: backend, frontend, data, architecture, general. See REFERENCE.md for schema.

### 9. Append to `AGENTS.md`
Idempotency guard: scan for `<!-- ai-sdlc-init:start -->` marker AND "AI SDLC Methodology" header. If both present → skip. If header present but marker missing → log warning and skip. Insert only when neither is found. Wrap inserted block with `<!-- ai-sdlc-init:start -->` / `<!-- ai-sdlc-init:end -->`.

### 10. Append to `CLAUDE.md`
Same idempotency pattern as step 9.

### 11. Append to `README.md`
Same idempotency pattern as step 9.

### 12. Create `docs/adr/ADR-TEMPLATE.md`
MADR format. See REFERENCE.md for template.

### 13. Create `docs/adr/ADR-0001-record-architecture-decisions.md`
Bootstrap ADR documenting the decision to record architecture decisions. See REFERENCE.md for template.

See REFERENCE.md for full template content and detailed step instructions.
