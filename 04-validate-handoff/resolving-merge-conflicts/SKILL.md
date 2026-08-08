---
name: resolving-merge-conflicts
description: 'Resolve an in-progress git merge or rebase conflict hunk by hunk. Use when a merge or rebase has stopped with conflicts that need resolving.'
---

# Resolving Merge Conflicts

Resolve the conflict by understanding both sides, not by picking whichever diff looks tidier. Always resolve; never `--abort`.

## Process

### 1. See the current state

Check what operation is in flight (merge or rebase), how far it has got, and which files conflict. Read the history on both sides.

**Done when:** you can name both sides of the conflict and list every conflicting file.

### 2. Find the primary sources for each conflict

Understand deeply why each change was made and what the original intent was. Read the commit messages, the PRs, and the original issues or tickets. A conflict is two intents colliding — you cannot merge intents you have not read.

**Done when:** for each conflicting hunk you can state what each side was trying to achieve.

### 3. Resolve each hunk

Preserve both intents where possible. Where they are genuinely incompatible, pick the one matching the merge's stated goal and note the trade-off for the user.

Do **not** invent new behaviour. A resolution that is neither side is a change smuggled into a merge, and review will not catch it.

**Done when:** no conflict markers remain and every resolution traces to one or both stated intents.

### 4. Run the project's automated checks

Discover what the project runs — typically typecheck, then tests, then format — and run them. Fix anything the merge broke.

**Done when:** the checks that passed before the merge pass again.

### 5. Finish the merge or rebase

Stage everything and commit. If rebasing, continue until all commits are rebased, repeating steps 1-4 for each further conflict.

**Done when:** the working tree is clean and the operation is no longer in progress.
