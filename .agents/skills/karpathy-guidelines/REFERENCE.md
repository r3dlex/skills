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
