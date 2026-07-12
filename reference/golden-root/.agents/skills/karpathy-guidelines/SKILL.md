---
name: karpathy-guidelines
description: Apply think-before-coding, simplicity, surgical-change, and goal-driven engineering rules. Use when planning, implementing, or reviewing code.
---

# Karpathy Guidelines

Four principles that prevent the most common AI-assisted coding failure modes.
Load this skill when reviewing implementation plans or code output.

## Rules

### Rule 1 — Think Before Coding

Spend time understanding the problem before writing a single line.
Re-read the issue, the acceptance criteria, and any relevant ADRs.

**Bad:**
```
// Immediately add a retry wrapper because the API call might fail
async function fetchWithRetry(url) { … }
```

**Good:**
```
// 1. Read the issue: the API is internal, on the same VPC. Retries not needed.
// 2. Check ADR-0005: we use circuit-breakers at the gateway, not per-caller.
// Conclusion: a plain fetch() is correct here.
async function fetchConfig(url) { return fetch(url).then(r => r.json()); }
```

---

### Rule 2 — Simplicity First

Do not add abstraction until you have two concrete use cases that share it.
The cost of wrong abstraction is higher than the cost of duplication.

**Bad:**
```typescript
// Premature factory for a single use case
class DataFetcherFactory {
  static create(type: 'user' | 'post'): DataFetcher { … }
}
```

**Good:**
```typescript
// Concrete function for the one case that exists today
async function fetchUser(id: string): Promise<User> { … }
// If fetchPost() is needed later and shares logic → extract then, not now.
```

---

### Rule 3 — Surgical Changes

Change only what the task requires. Do not refactor adjacent code, rename
variables "while you're here", or fix unrelated linting warnings in the same
commit.

**Bad:**
> Task: "Add timeout to fetchData()."
> Agent refactors all callers, introduces RetryConfig class, renames three
> variables for clarity, fixes unrelated import order.

**Good:**
> Task: "Add timeout to fetchData()."
> Agent adds one parameter with a default, threads it to the fetch call,
> updates the one test that exercises fetchData. Diff: 4 lines.

---

### Rule 4 — Goal-Driven Execution

Keep the original task visible. Before each action, ask: "Does this directly
advance the stated goal?" Stop when the goal is met — do not add polish,
documentation, or "nice to have" features beyond scope.

**Bad:**
```
// Task complete, but agent adds:
// - JSDoc on every function (not requested)
// - A README section for the new parameter (not requested)
// - A CHANGELOG entry (not requested)
```

**Good:**
```
// Task complete. Verification run. No out-of-scope additions.
// Noted potential improvement → opened separate issue #47.
```

---

## When to Apply These Rules

- Before starting any implementation: apply Rule 1 and Rule 4 (understand goal,
  confirm scope).
- During implementation: apply Rule 3 (surgical).
- During review of your own output: apply Rule 2 (simplicity check).

See [REFERENCE.md](REFERENCE.md) for anti-pattern catalog and concrete scenarios.
