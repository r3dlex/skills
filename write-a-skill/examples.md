# Skill Examples

## Good: Minimal reference skill (api-conventions)

```yaml
---
name: api-conventions
description: API design patterns for this codebase. Use when writing API endpoints, designing routes, or reviewing API code.
---

# API Conventions

When writing API endpoints, follow these rules:

1. RESTful resource naming. Plural nouns. No verbs in URLs.
2. Return `{ data, error, meta }` envelope on every response.
3. Validate request body before any business logic.
4. Use HTTP status codes correctly: 201 for creation, 204 for deletion.
5. Log every 5xx with request ID and stack trace.

See `references/error-codes.md` for the full error catalog.
See `references/auth-patterns.md` for authentication middleware patterns.
```

Why it works: 15 lines. Declarative. No workflow. Points to references for depth.

## Good: Task skill with clear process (generate-migration)

```yaml
---
name: generate-migration
description: Generate database migration files from schema changes. Use when adding tables, columns, or indexes.
---

# Generate Migration

1. Read the current schema from `prisma/schema.prisma`.
2. Identify the diff between current schema and requested change.
3. Generate the migration SQL using `npx prisma migrate dev --name <name>`.
4. Verify the migration applies cleanly: `npx prisma migrate deploy --preview`.
5. If verification fails, show the error and suggest a fix.

## Rules

Migration names use snake_case: `add_user_email_column`.
Never drop columns without explicit user confirmation.
Always generate a rollback file alongside the migration.
```

Why it works: Clear steps. Exit condition (verification). Safety rule (no silent drops).

## Bad: Everything in one file

```yaml
name: full-stack-helper
description: Helps with full stack development
---
[400 lines of React, API, database, deploy, CSS, testing...]
```
Problems: Description has no trigger. Name is too broad. One file does everything.
Split into 6 skills: react-patterns, api-conventions, db-queries, deploy, css, testing.

## Bad: No trigger in description

```yaml
---
name: code-review
description: Reviews code for quality and correctness
---
```

Fix: "Review code changes for quality, correctness, and style. Use when the user shares a diff, PR, or asks to review code before merging."

## Bad: First person description

```yaml
name: test-helper
description: I help you write better tests by suggesting patterns and catching anti-patterns
```

Fix: "Suggests test patterns and catches anti-patterns. Use when writing tests, debugging flaky tests, or improving test coverage."

## Bad: Script logic in SKILL.md

```yaml
name: format-imports
description: Sorts and groups imports. Use when organizing import statements.
---
# Steps
1. Read the file
2. Parse imports using this regex: /^import\s+(\{[^}]+\}|\w+)\s+from\s+'([^']+)'/gm
3. Group into: builtin, external, internal, relative
4. Sort alphabetically within each group
```

Fix: Move regex and sorting into `scripts/format-imports.mjs`.
SKILL.md says: "Run `scripts/format-imports.mjs <file>` to sort and group imports."
