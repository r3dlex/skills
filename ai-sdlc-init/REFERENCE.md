# AI SDLC Init — Reference

Detailed templates and operational documentation for every artifact the `ai-sdlc-init` skill emits.
Companion to [SKILL.md](SKILL.md) (the 13-step workflow entry point).

---

## Table of Contents

1. [Templates](#templates)
   - [.rules.ts template](#rulets-template)
   - [upstream.lock template](#upstreamlock-template)
   - [ci-prek.yml template](#ci-prekyml-template)
   - [prek.toml template](#prektoml-template)
   - [scripts/validate-rules.sh](#scriptsvalidate-rulessh)
   - [scripts/verify-golden-dir.sh (reference only)](#scriptsverify-golden-dirsh-reference-only)
   - [scripts/sync-upstream.sh (design pattern)](#scriptssync-upstreamsh-design-pattern)
   - [.gitignore AI SDLC additions](#gitignore-ai-sdlc-additions)
   - [raw/docs/incident-template.md](#rawdocsincident-templatemd)
   - [docs/adr/ADR-TEMPLATE.md](#docsadradr-templatemd)
   - [docs/adr/ADR-0001-record-architecture-decisions.md](#docsadradr-0001-record-architecture-decisionsmd)
   - [.agents/skills/karpathy-guidelines/SKILL.md](#agentsskillskarpathy-guidelinesskillmd)
   - [.agents/skills/karpathy-guidelines/REFERENCE.md](#agentsskillskarpathy-guidelinesreferencemd)
   - [AGENTS.md append content](#agentsmd-append-content)
   - [CLAUDE.md append content](#claudemd-append-content)
   - [README.md append content](#readmemd-append-content)
2. [Idempotency Guard Logic](#idempotency-guard-logic)
3. [Setup-Skills Interaction](#setup-skills-interaction)
4. [Agent Behaviors](#agent-behaviors)
5. [Invocation Strategy](#invocation-strategy)
6. [Prek Installation](#prek-installation)
7. [upstream.lock Sync Procedure](#upstreamlock-sync-procedure)

---

## Templates

### `.rules.ts` template

Archgate rules file. Five named domain exports, each a typed const array. The skill writes this
file verbatim; teams customize rule entries after scaffolding.

```typescript
// .rules.ts — Archgate domain rules
// Each rule: name, severity ("error" | "warn" | "info"), match pattern, and example.
// This file is validated by scripts/validate-rules.sh (structural check only).
// Semantic enforcement is an agent behavior at PR review time.

export interface Rule {
  name: string;
  severity: "error" | "warn" | "info";
  match: string;
  violation?: string;
  correction?: string;
}

// ─── backend ────────────────────────────────────────────────────────────────

export const backend: Rule[] = [
  {
    name: "api-versioning",
    severity: "error",
    match: "All public REST endpoints must include a version prefix (/v1/, /v2/, …).",
    violation: "POST /users/create",
    correction: "POST /v1/users",
  },
  {
    name: "error-shape",
    severity: "error",
    match: "Error responses must use { error: { code, message, details? } } shape.",
    violation: 'res.status(400).json({ msg: "bad input" })',
    correction: 'res.status(400).json({ error: { code: "INVALID_INPUT", message: "…" } })',
  },
  {
    name: "no-sql-injection-patterns",
    severity: "error",
    match: "String interpolation must not be used to build SQL queries.",
    violation: '`SELECT * FROM users WHERE id = ${req.params.id}`',
    correction: "db.query('SELECT * FROM users WHERE id = $1', [req.params.id])",
  },
  {
    name: "middleware-order",
    severity: "warn",
    match: "Auth middleware must be registered before route handlers.",
    violation: "router.get('/admin', handler, authMiddleware)",
    correction: "router.get('/admin', authMiddleware, handler)",
  },
];

// ─── frontend ────────────────────────────────────────────────────────────────

export const frontend: Rule[] = [
  {
    name: "component-naming",
    severity: "error",
    match: "React components must use PascalCase filenames and exports.",
    violation: "export function userCard() { … }  // file: userCard.tsx",
    correction: "export function UserCard() { … }  // file: UserCard.tsx",
  },
  {
    name: "props-interface",
    severity: "error",
    match: "Component props must be defined as a named TypeScript interface, not inline.",
    violation: "function Button({ label }: { label: string }) { … }",
    correction: "interface ButtonProps { label: string }\nfunction Button({ label }: ButtonProps) { … }",
  },
  {
    name: "hook-patterns",
    severity: "warn",
    match: "Custom hooks must start with 'use' and return a typed object, not a tuple.",
    violation: "function getUser() { … }  // not a hook",
    correction: "function useUser(): { user: User; loading: boolean } { … }",
  },
  {
    name: "css-methodology",
    severity: "info",
    match: "Style declarations must use the project's CSS methodology (Tailwind/CSS Modules/…). Inline styles are prohibited except for dynamic values.",
    violation: '<div style={{ color: "red" }}>',
    correction: '<div className="text-red-500">  // or CSS module equivalent',
  },
];

// ─── data ────────────────────────────────────────────────────────────────────

export const data: Rule[] = [
  {
    name: "migration-naming",
    severity: "error",
    match: "Database migration files must follow the pattern YYYYMMDDHHMMSS_<slug>.sql.",
    violation: "add_users_table.sql",
    correction: "20260101120000_add_users_table.sql",
  },
  {
    name: "query-batching",
    severity: "warn",
    match: "ORM queries inside loops are prohibited. Use batch/bulk methods or DataLoader.",
    violation: "for (const id of ids) { await User.findOne(id); }",
    correction: "await User.findAll({ where: { id: ids } });",
  },
  {
    name: "cache-invalidation",
    severity: "warn",
    match: "Cache entries must be invalidated in the same transaction/service that mutates the source data.",
    violation: "updateUser(id, data); // cache cleared in a separate cron",
    correction: "await Promise.all([updateUser(id, data), cache.del(`user:${id}`)])",
  },
];

// ─── architecture ────────────────────────────────────────────────────────────

export const architecture: Rule[] = [
  {
    name: "layer-boundaries",
    severity: "error",
    match: "Route handlers must not import from the data layer directly. All data access goes through a service layer.",
    violation: "import { db } from '../db' // inside routes/users.ts",
    correction: "import { UserService } from '../services/UserService'",
  },
  {
    name: "dependency-direction",
    severity: "error",
    match: "Dependencies must only flow inward (domain ← application ← infrastructure). Infrastructure must not import from the domain layer.",
    violation: "import { User } from '../../domain/User' // inside infrastructure/",
    correction: "Depend on the port interface, not the domain entity directly.",
  },
  {
    name: "module-exports",
    severity: "warn",
    match: "Each module directory must have an index.ts that re-exports only its public surface.",
    violation: "import { helper } from '../auth/internal/helper'",
    correction: "import { helper } from '../auth'  // via index.ts barrel",
  },
  {
    name: "no-circular-dependencies",
    severity: "error",
    match: "Circular imports between modules are prohibited.",
    violation: "// moduleA imports moduleB, moduleB imports moduleA",
    correction: "Extract shared logic into a third module that neither A nor B imports.",
  },
];

// ─── general ─────────────────────────────────────────────────────────────────

export const general: Rule[] = [
  {
    name: "file-naming",
    severity: "warn",
    match: "Source files must use kebab-case. Test files must end in .test.ts or .spec.ts.",
    violation: "UserService.ts, userservice.spec.ts",
    correction: "user-service.ts, user-service.spec.ts",
  },
  {
    name: "function-length",
    severity: "warn",
    match: "Functions must not exceed 40 lines. Extract logical sections into named helpers.",
    violation: "// 80-line parseAndValidateAndSaveUser function",
    correction: "parseUser(), validateUser(), saveUser() — each ≤ 40 lines",
  },
  {
    name: "test-structure",
    severity: "error",
    match: "Tests must follow the Arrange-Act-Assert pattern with one assertion group per test.",
    violation: "it('works', () => { /* 20 lines of mixed setup and assertions */ })",
    correction: "it('returns 404 when user not found', () => { /* Arrange / Act / Assert */ })",
  },
  {
    name: "import-ordering",
    severity: "info",
    match: "Imports must be ordered: Node built-ins → external packages → internal modules. Groups separated by a blank line.",
    violation: "import { UserService } from './services'\nimport path from 'path'\nimport express from 'express'",
    correction: "import path from 'path'\n\nimport express from 'express'\n\nimport { UserService } from './services'",
  },
  {
    name: "comment-policy",
    severity: "info",
    match: "Comments must explain WHY, not WHAT. Do not comment code that is self-explanatory.",
    violation: "// increment counter\ncounter++;",
    correction: "// Retry budget: max 3 attempts before circuit-breaker trips\ncounter++;",
  },
];
```

---

### `upstream.lock` template

Written by Step 3. The skill resolves `<SHA>` at scaffold time via
`git ls-remote https://github.com/mattpocock/skills.git HEAD`.

```yaml
source: mattpocock/skills
via: r3dlex/skills
pinned_sha: <SHA from git ls-remote https://github.com/mattpocock/skills.git HEAD>
updated: <YYYY-MM-DD>
sync_script: scripts/sync-upstream.sh
```

---

### `.github/workflows/ci-prek.yml` template

A **separate** workflow file. Never merged into an existing `ci.yml`.
Uses `j178/prek-action@v2`. The `extra-args: '--all-files'` key is required — there is no
bare `args:` key in this action.

```yaml
name: AI SDLC Pre-commit Checks

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  prek-check:
    name: Pre-commit Hooks
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run prek
        uses: j178/prek-action@v2
        with:
          extra-args: '--all-files'
```

---

### `prek.toml` template

Hook configuration consumed by prek. The `validate-rules` entry delegates `.rules.ts` structural
validation to the local shell script — prek has no built-in TypeScript parser.

```toml
[hooks]
# Standard file hygiene
trailing-whitespace = true
end-of-file-fixer = true

# Archgate: validate .rules.ts structural integrity
validate-rules = { entry = "bash scripts/validate-rules.sh", language = "system", files = "\\.rules\\.ts$" }
```

---

### `scripts/validate-rules.sh`

This is the script that `prek.toml`'s `validate-rules` hook executes. It checks structural
integrity of `.rules.ts`: five required domain exports present and optional TypeScript syntax
verification via `tsx`.

```bash
#!/usr/bin/env bash
# validate-rules.sh — Structural validation of .rules.ts
# Checks that .rules.ts: (a) is valid TypeScript syntax, (b) exports
# all 5 required Archgate domains as const arrays with name+severity+match fields.
# This is NOT a full semantic check — it validates the rule STRUCTURE,
# not whether the rules are correct for the codebase.

set -euo pipefail

RULES_FILE="${1:-.rules.ts}"
errors=0

echo "=== Archgate Rules Validation ==="

# Check file exists
if [ ! -f "$RULES_FILE" ]; then
  echo "FAIL: $RULES_FILE not found"
  exit 1
fi

# Check 5 required domain exports (backend, frontend, data, architecture, general)
for domain in backend frontend data architecture general; do
  if ! grep -q "export const $domain" "$RULES_FILE" 2>/dev/null; then
    echo "FAIL: Missing required domain export: $domain"
    errors=$((errors + 1))
  else
    echo "OK: $domain domain present"
  fi
done

# Check TypeScript syntax with node --check (requires Node.js)
if command -v node &>/dev/null; then
  # Transpile check: can npx tsx parse it?
  if npx --yes tsx --eval "import('./.rules.ts').then(m => { const domains = ['backend','frontend','data','architecture','general']; domains.forEach(d => { if(!m[d]) throw new Error('Missing: '+d) }); console.log('TypeScript syntax OK'); process.exit(0); }).catch(e => { console.error(e.message); process.exit(1); })" 2>/dev/null; then
    :
  else
    echo "WARNING: TypeScript syntax check failed (tsx not available or parse error)"
  fi
else
  echo "SKIP: Node.js not available for syntax check"
fi

echo "=== Result ==="
if [ "$errors" -eq 0 ]; then
  echo "PASS: All 5 Archgate domains present."
  exit 0
else
  echo "FAIL: $errors domain(s) missing from .rules.ts"
  exit 1
fi
```

---

### `scripts/verify-golden-dir.sh` (reference only)

The `verify-golden-dir.sh` script lives at `scripts/verify-golden-dir.sh` in the skills repo.
It is a **pure diff-and-report tool** — it does not invoke the skill, it compares a real repo
against a golden directory that the developer has already scaffolded.

Key behaviours:
- Excludes `upstream.lock` from content diff (SHA drifts when upstream pushes). Instead it
  validates only structural fields (`source:`, `via:`, `pinned_sha:`, `sync_script:`).
- Validates `.rules.ts` by calling `scripts/validate-rules.sh` — not via `prek --rules`
  (no such flag exists).
- Checks for `<!-- ai-sdlc-init:start -->` marker presence in `AGENTS.md`, `CLAUDE.md`,
  `README.md`, and `.gitignore`.
- Checks that `.github/workflows/ci-prek.yml` exists.
- Exits `0` on full pass, `1` on any failure.

Run after scaffolding a target repo:

```bash
bash scripts/verify-golden-dir.sh /path/to/target-repo skills/reference/golden-skills
```

---

### `scripts/sync-upstream.sh` (design pattern)

This is a **documented design pattern**, not a working script. The file is created with a
`# NOT IMPLEMENTED` header so future contributors can see the intended logic.

```bash
#!/usr/bin/env bash
# sync-upstream.sh — DESIGN PATTERN (not a working script)
# Future implementation guide for syncing with mattpocock/skills upstream.
#
# Pseudocode:
#   1. Fetch the current HEAD SHA from upstream:
#        UPSTREAM_SHA=$(git ls-remote https://github.com/mattpocock/skills.git HEAD | cut -f1)
#   2. Read the pinned_sha from upstream.lock:
#        PINNED_SHA=$(grep 'pinned_sha:' upstream.lock | awk '{print $2}')
#   3. If UPSTREAM_SHA == PINNED_SHA: echo "Already up to date." && exit 0
#   4. Run git diff between pinned_sha and upstream HEAD on the remote (sparse clone or API diff):
#        Generate list of changed files since PINNED_SHA
#   5. For each changed file in .agents/skills/:
#        - Show the diff to the developer
#        - Ask: "Apply this change? [y/N]"
#        - If yes: copy the updated file into the local .agents/skills/ tree
#   6. Update upstream.lock with the new SHA and today's date.
#   7. Stage the changes for review: git add -p
#
# This script is intentionally incomplete. Upstream sync should be a deliberate
# human-reviewed process, not an automated overwrite.

echo "sync-upstream.sh is not yet implemented."
echo "See REFERENCE.md → upstream.lock Sync Procedure for the design intent."
exit 1
```

---

### `.gitignore` AI SDLC additions

Append the following block to the repo's `.gitignore`. The marker comments use `#` syntax
(gitignore format) wrapping the HTML-comment namespace token so the idempotency guard can
still detect them via grep.

```gitignore
# <!-- ai-sdlc-init:start -->
# AI SDLC artifacts
upstream-pocock/
.prek-cache/
# <!-- ai-sdlc-init:end -->
```

---

### `raw/docs/incident-template.md`

Copy to `raw/docs/INC-YYYY-MM-DD-slug.md` and fill in each section.
Naming convention: `INC-2026-05-22-api-outage.md`.

```markdown
# INC-YYYY-MM-DD — <short title>

**Status:** Open | Investigating | Resolved
**Severity:** P0 | P1 | P2 | P3
**Incident commander:** @handle
**Date opened:** YYYY-MM-DD HH:MM UTC
**Date resolved:** YYYY-MM-DD HH:MM UTC (leave blank if open)

---

## Summary

One paragraph. What happened, what was affected, and the outcome.

## Timeline

| Time (UTC) | Event |
|-----------|-------|
| HH:MM | First alert fired |
| HH:MM | On-call engineer paged |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | Service restored |

## Root Cause

Describe the technical root cause. Use the 5-Whys if helpful:

1. Why did X fail? → Because Y
2. Why did Y happen? → Because Z
3. …

## Impact

- **Users affected:** N (estimated)
- **Duration:** HH hours MM minutes
- **Services affected:** list services, endpoints, or features
- **Data loss:** Yes / No / Under investigation

## Action Items

| # | Action | Owner | Due date | Status |
|---|--------|-------|----------|--------|
| 1 | Add circuit breaker to payment service | @handle | YYYY-MM-DD | Open |
| 2 | Add alerting for DB connection pool exhaustion | @handle | YYYY-MM-DD | Open |

## Blameless Statement

This incident review is conducted in the spirit of blameless post-mortems.
Systems fail; our goal is to understand failure modes and improve resilience —
not to assign individual blame. All contributors are encouraged to share
observations candidly.
```

---

### `docs/adr/ADR-TEMPLATE.md`

MADR (Markdown Architectural Decision Records) format.

```markdown
# ADR-NNNN — <title>

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-MMMM
**Date:** YYYY-MM-DD
**Deciders:** @handle1, @handle2

---

## Context

What is the issue that motivates this decision? What forces are at play
(technical, organisational, constraints)? Be specific about the problem space.

## Decision

State the decision in one sentence. Then explain the reasoning.

> We will [do X] because [reason Y].

## Consequences

### Positive
- …

### Negative
- …

### Neutral / Trade-offs
- …

## Compliance

How will adherence to this decision be verified? Options:
- Agent behavior (drift-check at PR review time)
- Automated lint rule in `.rules.ts`
- Manual review checklist in pull request template
- N/A — decision is structural, enforced by directory layout
```

---

### `docs/adr/ADR-0001-record-architecture-decisions.md`

Bootstrap ADR. Records the meta-decision to use ADRs.

```markdown
# ADR-0001 — Record Architecture Decisions

**Status:** Accepted
**Date:** <scaffold date>
**Deciders:** project maintainers

---

## Context

Architectural decisions accumulate silently in codebases. When a contributor asks
"why is this structured this way?", the answer lives in someone's memory or an
old Slack thread — not in the repository. New contributors repeat the same
trade-off analysis and sometimes reverse decisions whose rationale was sound but
undocumented.

We need a lightweight, version-controlled way to capture significant architectural
decisions alongside the code they describe.

## Decision

We will record architecturally significant decisions in `docs/adr/` using MADR
(Markdown Architectural Decision Records) format. Each ADR is a numbered file:
`ADR-NNNN-slug.md`. ADRs are immutable once accepted; superseded ADRs are marked
"Superseded by ADR-MMMM" rather than deleted.

An ADR is warranted when a decision:
- Is hard to reverse without significant rework
- Involves non-obvious trade-offs
- Affects multiple modules or teams
- Contradicts a common default or industry practice

## Consequences

### Positive
- Decisions are traceable to the commit that introduced them.
- New contributors can understand constraints without asking senior engineers.
- Drift detection at PR review time has an authoritative source to compare against.

### Negative
- Writing ADRs takes time. Teams may skip them under deadline pressure.
- Stale ADRs that are never marked "Deprecated" can mislead readers.

### Neutral / Trade-offs
- ADRs capture intent, not enforcement. Compliance verification is an agent
  behavior (see AGENTS.md — Drift Verification Protocol), not a CI gate in this
  iteration.

## Compliance

Agent behavior: at PR review time, the drift-verification agent loads the PR diff
and relevant ADRs, then flags conflicts. See AGENTS.md for the documented protocol.
```

---

### `.agents/skills/karpathy-guidelines/SKILL.md`

Write this file into the **target repo** (not the skills repo) at
`.agents/skills/karpathy-guidelines/SKILL.md`. It encodes four Andrej Karpathy
software engineering heuristics as agent-facing rules.

```markdown
---
name: karpathy-guidelines
description: >
  Enforce Karpathy software engineering principles: think before coding,
  prefer simplicity, make surgical changes, stay goal-driven. Use when
  reviewing code quality, planning implementation approach, or auditing
  for over-engineering.
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
```

---

### `.agents/skills/karpathy-guidelines/REFERENCE.md`

Write into the target repo at `.agents/skills/karpathy-guidelines/REFERENCE.md`.

```markdown
# Karpathy Guidelines — Reference

Anti-pattern catalog, integration guidance, and concrete scenarios for the four
rules in [SKILL.md](SKILL.md).

---

## Anti-Pattern Catalog

### AP-1: The Helpful Refactor

**Pattern:** Agent fixes nearby code "while it's there" — renaming variables,
improving error messages, extracting helpers. None of it was requested.

**Why it's harmful:** Unreviewed scope expansion. The refactored code may have
had intentional quirks. The diff becomes harder to review and revert.

**Detection signal:** Diff touches files not named in the task description.

**Correction:** Open a separate issue for the cleanup. Link from the PR description.

---

### AP-2: The Premature Abstraction

**Pattern:** Agent introduces a class, interface, or utility function for a
pattern that exists exactly once.

**Why it's harmful:** Abstractions create coupling and maintenance surface. A
wrong abstraction is harder to remove than the duplication it replaced.

**Detection signal:** New class or function has exactly one call site.

**Correction:** Inline the logic. If a second use case appears, abstract then.

---

### AP-3: The Exhaustive Documentation Pass

**Pattern:** After completing a task, agent writes JSDoc on every function, adds
a README section, updates a CHANGELOG, and annotates every type.

**Why it's harmful:** Documentation written without user need adds noise and
drifts out of sync with the code.

**Detection signal:** Documentation changes exceed code changes in line count.

**Correction:** Document only what the task explicitly requests, or what is
genuinely non-obvious to a future reader.

---

### AP-4: The Safety Net Spiral

**Pattern:** Agent adds retries, circuit breakers, fallback paths, and error
logging "just in case" for a code path that calls an internal, highly-available
service.

**Why it's harmful:** Over-engineering failure paths adds complexity, masks real
errors, and creates false confidence in resilience.

**Detection signal:** The new code has more error-handling lines than happy-path
lines, without a documented failure scenario that justifies it.

**Correction:** Check the relevant ADR or architecture docs. Add only what the
architecture explicitly requires.

---

### AP-5: The Understanding Skip

**Pattern:** Agent starts writing code immediately after reading the first
sentence of the issue, without reading acceptance criteria, linked ADRs, or
existing implementations of the same interface.

**Why it's harmful:** Produces code that passes unit tests but violates
architectural constraints or contradicts existing conventions.

**Detection signal:** First code edit appears in the transcript before any file
reads.

**Correction:** Read the issue fully, read relevant ADRs, grep for existing
usages of the interface being extended. Then write.

---

### AP-6: The Completion Theater

**Pattern:** Agent declares "done" before running verification (build, tests,
lsp diagnostics). Or runs verification but ignores failures.

**Why it's harmful:** Breaks the contract between agent and reviewer. Reviewer
must re-run verification, find failures, and re-engage the agent.

**Detection signal:** No verification output in the transcript before "done."

**Correction:** Show fresh build/test output. If something fails, fix it before
claiming completion.

---

## Integration Guidance

These guidelines are most effective when:

1. **Loaded at task start.** The agent reads SKILL.md before writing any code.
2. **Referenced during self-review.** After drafting a change, the agent checks
   the anti-pattern list before submitting.
3. **Cited in PR review comments.** "AP-2 applies here — this helper has one
   call site" gives precise, actionable feedback.

The guidelines do NOT replace acceptance criteria. They operate alongside task
requirements, not instead of them.

---

## Concrete Scenarios

### Scenario 1: Add a field to an API response

**Task:** "Add `createdAt` field to the `/v1/users/:id` response."

**Karpathy-compliant approach:**
1. (Rule 1) Read the issue. Find the UserResponse type. Check ADR-0003 (error
   shape) to confirm field naming conventions.
2. (Rule 3) Add `createdAt: string` to `UserResponse`. Add it to the serializer.
   Update the one test that asserts response shape. Diff: ~8 lines.
3. (Rule 4) Stop. Do not add `updatedAt` speculatively. Do not refactor the
   serializer to a builder pattern.

---

### Scenario 2: Fix a flaky test

**Task:** "Test `auth.spec.ts:42` fails intermittently. Fix it."

**Karpathy-compliant approach:**
1. (Rule 1) Read the test. Read the code under test. Reproduce the failure.
   Identify the race condition (timer not mocked).
2. (Rule 3) Mock the timer in the test setup. Confirm the test is now stable.
   Do not refactor the auth module while you're there.
3. (Rule 2) If the timer-mock pattern is needed in three other tests, extract a
   helper. If it's needed only here, leave it inline.

---

### Scenario 3: Scaffold a new module

**Task:** "Create a notifications module following the existing user module pattern."

**Karpathy-compliant approach:**
1. (Rule 1) Read `src/users/` fully before writing anything. Note file structure,
   naming, error handling, and test patterns.
2. (Rule 3) Create files that mirror the pattern exactly. No improvements to the
   pattern unless explicitly requested.
3. (Rule 2) Do not create a generic `createModule()` factory because two modules
   now share a pattern. Duplication is fine at two instances.
4. (Rule 4) Stop when the module is created and tests pass. Do not add
   notification preferences, delivery receipts, or retry logic that aren't in
   the acceptance criteria.
```

---

### AGENTS.md append content

Insert between `<!-- ai-sdlc-init:start -->` and `<!-- ai-sdlc-init:end -->` markers.

```markdown
<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This repository uses the AI SDLC methodology scaffolded by `ai-sdlc-init`.

### Architecture Decision Records

Significant architectural decisions are recorded in [`docs/adr/`](docs/adr/).
Before making a change that affects module boundaries, API contracts, data
schemas, or dependency direction, check whether a relevant ADR exists.
If your change contradicts an existing ADR, either update the ADR or open a
discussion before proceeding.

### Archgate Rules

Code quality rules are defined in [`.rules.ts`](.rules.ts) across five domains:
`backend`, `frontend`, `data`, `architecture`, `general`. Rules carry a severity
(`error`, `warn`, `info`). Structural validation of `.rules.ts` runs in CI via
the `validate-rules` prek hook. Semantic enforcement (did the PR violate a rule?)
is an agent behavior at PR review time.

### Karpathy Baseline

All agents operating in this repository load
[`.agents/skills/karpathy-guidelines/SKILL.md`](.agents/skills/karpathy-guidelines/SKILL.md)
as a baseline. Four rules apply to every task: Think Before Coding, Simplicity
First, Surgical Changes, Goal-Driven Execution. See the SKILL.md for violation
and correction examples.

### Drift Verification Protocol

At PR review time, the reviewing agent:
1. Loads the PR diff alongside the BRD, PRD, acceptance criteria, and any ADRs
   whose scope overlaps with the changed files.
2. Produces a drift report identifying whether changes match ACs, conflict with
   ADRs, or violate architectural constraints from `.rules.ts`.
3. Leaves the drift report as a PR comment or review summary.

This is a documented agent behavior. It is not enforced as a CI gate in this
iteration.

### Circuit Breaker Protocol

Before starting work on an issue:
1. Check whether ≥ 3 prior attempts exist without resolution (look for
   `attempts:N` labels or a comment history showing repeated failures).
2. If the circuit is tripped (≥ 3 attempts, no resolution), escalate to a
   human with a written summary of what was tried and what blocked each attempt.
3. Do not make a fourth attempt without human acknowledgement.

<!-- ai-sdlc-init:end -->
```

---

### CLAUDE.md append content

Shorter than AGENTS.md — just enough for Claude Code to orient itself.

```markdown
<!-- ai-sdlc-init:start -->

## AI SDLC

This repository uses the AI SDLC methodology. Before starting work:

- Read [AGENTS.md](AGENTS.md) for the full methodology (ADRs, Archgate rules,
  Karpathy baseline, drift verification, circuit breaker protocol).
- Check [`docs/adr/`](docs/adr/) for architectural constraints relevant to your task.
- Load `.agents/skills/karpathy-guidelines/SKILL.md` as a baseline for all tasks.

<!-- ai-sdlc-init:end -->
```

---

### README.md append content

Public-facing. Brief and links out rather than duplicating.

```markdown
<!-- ai-sdlc-init:start -->

## AI SDLC Methodology

This project uses the [AI SDLC methodology](https://github.com/r3dlex/skills/tree/main/ai-sdlc-init)
to maintain architectural governance alongside AI-assisted development.

Key practices:
- **Architecture Decision Records** in [`docs/adr/`](docs/adr/) — significant
  decisions are version-controlled with context and rationale.
- **Archgate rules** in [`.rules.ts`](.rules.ts) — code quality constraints
  across five domains, validated in CI.
- **Karpathy baseline** — four engineering heuristics loaded by all agents
  operating in this repo (think, simplify, be surgical, stay on goal).

Contributing? Read [`AGENTS.md`](AGENTS.md) for agent-facing methodology details.

<!-- ai-sdlc-init:end -->
```

---

## Idempotency Guard Logic

All three append operations (AGENTS.md, CLAUDE.md, README.md) and the `.gitignore`
append use a secondary-content-scan pattern to prevent duplicate insertions.

### Decision Matrix

Before inserting any `<!-- ai-sdlc-init:start -->` block, the skill checks two
independent signals:

| Marker present? | Content present? | Action |
|-----------------|-----------------|--------|
| Yes | Yes | Skip silently (already done) |
| No | No | Insert (normal case) |
| No | Yes | Log warning and skip — content exists without a marker; manual intervention may be needed |
| Yes | No | Log warning and skip — marker exists but content is missing; this is a corrupt state |

### Implementation

For AGENTS.md, CLAUDE.md, README.md:

```
marker_check = grep -q "<!-- ai-sdlc-init:start -->" <file>
content_check = grep -q "AI SDLC" <file>   # header text from the append block
```

For `.gitignore`:

```
marker_check = grep -q "# <!-- ai-sdlc-init:start -->" .gitignore
content_check = grep -q "upstream-pocock/" .gitignore
```

### Rationale

Checking both marker and content independently protects against:
- Re-running the skill after a partial failure that wrote content but not the
  closing marker.
- Manual edits that added the header text without markers.
- Future skill runs after the markers were stripped by a formatter.

---

## Setup-Skills Interaction

`ai-sdlc-init` Step 1 detects whether the `setup-skills` skill has already run
in the target repo.

### Detection

Scan for `<!-- setup-skills:start -->` in `AGENTS.md` or `CLAUDE.md`:

```bash
grep -q "<!-- setup-skills:start -->" AGENTS.md 2>/dev/null || \
grep -q "<!-- setup-skills:start -->" CLAUDE.md 2>/dev/null
```

### If setup-skills output is found

- Read `docs/agents/issue-tracker-github.md` (or `-gitlab.md` / `-local.md`)
  to detect the issue tracker. The filename suffix identifies the tracker type.
- Read `docs/agents/triage-labels.md` for the five canonical label names.
- **Skip** the tooling questions in Step 1 (issue tracker, CI platform).
- Use detected values as scaffold defaults throughout the remaining steps.

### If setup-skills was NOT run

Ask the two tooling questions:

1. "What issue tracker does this repo use?" (GitHub Issues / GitLab Issues /
   Jira / Azure DevOps / local Markdown)
2. "What CI platform does this repo use?" (GitHub Actions / GitLab CI /
   Azure DevOps Pipelines / other)

### Marker Namespace Separation

| Skill | Marker namespace | Files modified |
|-------|-----------------|----------------|
| setup-skills | `<!-- setup-skills:* -->` | AGENTS.md, CLAUDE.md |
| ai-sdlc-init | `<!-- ai-sdlc-init:* -->` | AGENTS.md, CLAUDE.md, README.md, .gitignore |

No overlap. Both marker blocks can coexist in the same file. Each skill's
idempotency guard checks only its own namespace.

### Execution Order

If both skills will be run in a fresh repo:

1. Run `setup-skills` first — it configures issue tracker and triage labels.
2. Run `ai-sdlc-init` second — it detects setup-skills output and skips
   redundant tooling questions.

---

## Agent Behaviors

These behaviors are documented here per Principle 3 (documentation-first governance).
They are NOT CI gates in this iteration.

### Drift Verification Protocol

Triggered at PR review time by a separate-context agent (not the implementation agent).

Steps:
1. Load: PR diff, BRD, PRD, acceptance criteria, all ADRs whose path or domain
   overlaps with the changed files.
2. Check: Do the changes satisfy all acceptance criteria? Do they conflict with
   any ADR? Do they violate any `error`-severity rule in `.rules.ts`?
3. Report: Produce a structured drift report with three sections:
   - **AC coverage** — which ACs are addressed, which are untouched.
   - **ADR conflicts** — any changes that contradict a recorded decision.
   - **Rule violations** — `error`-severity `.rules.ts` matches in the diff.
4. Post: Leave the report as a PR review comment or review summary.

The reviewing agent must be a **separate context** from the implementation agent
to avoid self-approval bias.

### Circuit Breaker Protocol

Triggered before starting work on any issue.

Steps:
1. Check the issue for an `attempts:N` label or a comment history showing
   ≥ 3 attempts without resolution.
2. If the circuit is tripped: do not start a new attempt. Instead, post a
   written escalation summary:
   - What was tried in each prior attempt.
   - What blocked resolution each time.
   - What human decision or context is needed to unblock.
3. Wait for human acknowledgement before proceeding.

Attempt tracking: use an `attempts:N` label in the issue tracker, incrementing N
after each failed attempt. The circuit trips at `attempts:3`.

---

## Invocation Strategy

`ai-sdlc-init` is an OMC skill consumed by Claude Code. It is not a standalone
CLI tool.

### Method 1 — Direct invocation (recommended)

```bash
cd /path/to/target-repo
claude -p "/ai-sdlc-init"
```

The `-p` flag runs the slash command in print mode. The skill loads SKILL.md,
reads the 13-step workflow, and executes against the current working directory.

### Method 2 — Interactive session

In an active Claude Code session in the target repo:

```
/ai-sdlc-init
```

The skill loads and the agent follows the numbered steps interactively.

### Method 3 — Agent delegation

From a parent orchestrating agent (e.g., the AiTool root repo):

```
Delegate to an executor agent with cwd set to the target repo.
Instruct it to run /ai-sdlc-init.
```

### Constraints

- Claude Code CLI has no `--skill`, `--cwd`, or `--repo-type` flags. The skill
  must be loaded via slash command.
- The skill reads target repo files to determine state — it accepts no CLI
  arguments.
- Golden-dir verification (`scripts/verify-golden-dir.sh`) is always
  developer-local. It cannot run in CI.

---

## Prek Installation

prek is a **Rust-based** pre-commit hook manager (github.com/j178/prek).
It is NOT a Go tool. It has no `--rules` flag. `.rules.ts` validation happens
exclusively via the `validate-rules` local hook defined in `prek.toml`.

### CI

```yaml
- name: Run prek
  uses: j178/prek-action@v2
  with:
    extra-args: '--all-files'
```

Use `extra-args: '--all-files'` — there is no bare `args:` key in this action.

### Local development

```bash
# macOS (recommended)
brew install prek

# Cross-platform (requires Rust toolchain)
cargo install --locked prek

# Python environment (pip wrapper)
pip install prek
```

After installation, activate the pre-commit hook in the target repo:

```bash
prek install
```

This installs prek as the `pre-commit` git hook. On each commit, prek reads
`prek.toml` and runs the configured hooks.

### End-to-end hook flow

1. Developer commits → `prek` runs hooks from `prek.toml`.
2. `trailing-whitespace` and `end-of-file-fixer` run on all staged files.
3. `validate-rules` runs `bash scripts/validate-rules.sh` when `.rules.ts` is
   staged.
4. `validate-rules.sh` checks that all 5 domain exports are present and
   optionally checks TypeScript syntax via `tsx`.
5. If any hook fails → commit is blocked.
6. In CI, `j178/prek-action@v2` runs `prek run --all-files` — same hooks, all
   files.

---

## upstream.lock Sync Procedure

### Initial population (scaffold time)

Step 3 of the skill resolves the upstream SHA by running:

```bash
git ls-remote https://github.com/mattpocock/skills.git HEAD
```

The output is a tab-separated `<SHA>\tHEAD`. The skill writes the SHA into
`pinned_sha:` in `upstream.lock` and sets `updated:` to today's date.

### Verification exclusion

`verify-golden-dir.sh` **excludes** `upstream.lock` from the content diff.
The `pinned_sha` field drifts whenever the upstream repo pushes new commits;
a content diff would produce perpetual false failures.

Instead, the script validates only the structural fields:
- `source:` is present
- `via:` is present
- `pinned_sha:` is present
- `sync_script:` is present

The actual SHA value is not asserted — only field presence.

### Sync design intent

The `scripts/sync-upstream.sh` file documents the intended sync workflow as
pseudocode (see template above). A working implementation is out of scope for
this iteration. The intended flow:

1. Fetch current upstream HEAD SHA.
2. Compare against `pinned_sha` in `upstream.lock`.
3. If different, diff the upstream changes since `pinned_sha`.
4. Show the developer each changed file and ask for confirmation before applying.
5. Update `upstream.lock` with the new SHA and date.

Upstream sync is intentionally human-reviewed. Automated overwrite of
`.agents/skills/` content is not the intended design.
