# Using Git Worktrees — Reference

## Table of Contents
1. [Directory Selection Details](#directory-selection-details)
2. [Safety Verification Details](#safety-verification-details)
3. [Setup Auto-Detection](#setup-auto-detection)
4. [Integration References](#integration-references)

---

## Directory Selection Details

### Priority Order

1. `.worktrees/` — preferred (hidden, project-local)
2. `worktrees/` — alternative (project-local)
3. CLAUDE.md preference — if user specified `worktree.*director`
4. Ask user — neither exists and no CLAUDE.md preference

### CLAUDE.md Check

```bash
grep -i "worktree.*director" CLAUDE.md 2>/dev/null
```

If found, use without asking.

### User Prompt (if needed)

```
No worktree directory found. Where should I create worktrees?

1. .worktrees/ (project-local, hidden)
2. ~/.config/superpowers/worktrees/<project-name>/ (global)

Which would you prefer?
```

---

## Safety Verification Details

### Why Ignore Verification Matters

Per Jesse's rule "Fix broken things immediately": if a project-local worktree directory is not ignored, its contents can accidentally get committed to the repository, polluting git status.

### Verification Command

```bash
git check-ignore -q .worktrees 2>/dev/null || git check-ignore -q worktrees 2>/dev/null
```

- Returns exit code 0 if ignored
- Returns exit code 1 if NOT ignored

### If NOT Ignored

1. Add appropriate line to `.gitignore` (e.g., `.worktrees/` or `worktrees/`)
2. Commit the change: `git add .gitignore && git commit -m "chore: ignore worktrees directory"`
3. Proceed with worktree creation

### Global Directories

For `~/.config/superpowers/worktrees/<project-name>/` — no .gitignore verification needed since it's outside the project entirely.

---

## Setup Auto-Detection

### Supported Project Types

| Type | Detection | Setup Command |
|---|---|---|
| Node.js | `package.json` | `npm install` |
| Rust | `Cargo.toml` | `cargo build` |
| Python (pip) | `requirements.txt` | `pip install -r requirements.txt` |
| Python (poetry) | `pyproject.toml` | `poetry install` |
| Go | `go.mod` | `go mod download` |

### Quick Reference Table

| Situation | Action |
|-----------|--------|
| `.worktrees/` exists | Use it (verify ignored) |
| `worktrees/` exists | Use it (verify ignored) |
| Both exist | Use `.worktrees/` |
| Neither exists | Check CLAUDE.md → Ask user |
| Directory not ignored | Add to .gitignore + commit |
| Tests fail during baseline | Report failures + ask |
| No package.json/Cargo.toml | Skip dependency install |

---

## Integration References

### Skills That Call This

- **brainstorming** (Phase 4) — REQUIRED when design is approved and implementation follows
- **subagent-driven-development** — REQUIRED before executing any tasks
- **executing-plans** — REQUIRED before executing any tasks
- Any skill needing isolated workspace

### Skills That Pair With This

- **finishing-a-development-branch** — REQUIRED for cleanup after work complete

---

## Example Workflow

```
You: I'm using the using-git-worktrees skill to set up an isolated workspace.

[Check .worktrees/ - exists]
[Verify ignored - git check-ignore confirms .worktrees/ is ignored]
[Create worktree: git worktree add .worktrees/auth -b feature/auth]
[Run npm install]
[Run npm test - 47 passing]

Worktree ready at /Users/jesse/myproject/.worktrees/auth
Tests passing (47 tests, 0 failures)
Ready to implement auth feature
```

---

## Red Flags

**Never:**
- Create worktree without verifying it's ignored (project-local)
- Skip baseline test verification
- Proceed with failing tests without asking
- Assume directory location when ambiguous
- Skip CLAUDE.md check

**Always:**
- Follow directory priority: existing > CLAUDE.md > ask
- Verify directory is ignored for project-local
- Auto-detect and run project setup
- Verify clean test baseline
