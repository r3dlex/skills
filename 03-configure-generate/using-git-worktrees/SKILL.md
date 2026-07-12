---
name: using-git-worktrees
description: "Create isolated git worktrees with safety checks and setup guidance. Use when starting feature work that needs separation from the main checkout."
---

# Using Git Worktrees

## Quick Start

1. Check for existing worktree directory (`.worktrees` or `worktrees`)
2. Verify directory is git-ignored (for project-local)
3. Create worktree with new branch: `git worktree add <path> -b <branch>`
4. Run project setup (auto-detect: npm install, cargo build, etc.)
5. Verify clean test baseline

**Announce at start:** "I'm using the using-git-worktrees skill to set up an isolated workspace."

## Directory Selection Priority

1. `.worktrees/` (preferred, hidden)
2. `worktrees/` (alternative)
3. CLAUDE.md preference (if specified)
4. Ask user

## Safety Verification

For project-local directories, **MUST verify is git-ignored:**

```bash
git check-ignore -q .worktrees || git check-ignore -q worktrees
```

**If NOT ignored:** Add to .gitignore, commit, then proceed. Prevents accidentally committing worktree contents.

No verification needed for global directories (outside project).

## Creation Steps

### 1. Detect project name
```bash
project=$(basename "$(git rev-parse --show-toplevel)")
```

### 2. Create worktree
```bash
git worktree add "$path" -b "$BRANCH_NAME"
cd "$path"
```

### 3. Auto-setup
```bash
# Node.js: [ -f package.json ] && npm install
# Rust: [ -f Cargo.toml ] && cargo build
# Python: [ -f requirements.txt ] && pip install -r requirements.txt
# Go: [ -f go.mod ] && go mod download
```

### 4. Verify baseline
Run project tests. If they fail: report failures, ask whether to proceed.

### 5. Report
```
Worktree ready at <path>
Tests passing (<N> tests, 0 failures)
Ready to implement <feature>
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Skipping ignore verification | Always `git check-ignore` before creating project-local worktree |
| Assuming directory location | Follow priority: existing > CLAUDE.md > ask |
| Proceeding with failing tests | Report, get explicit permission |
| Hardcoding setup commands | Auto-detect from project files |

## Integration

**Called by:** brainstorm (Phase 4), subagent-driven-development, executing-plans — REQUIRED before executing tasks.

For detailed examples and reference material, see [REFERENCE.md](REFERENCE.md).
