# Release Versioning Module

Read when initializing, configuring, or auditing a repo's release tagging, versioning, and CI/CD release workflows. This module covers strategy selection (Hybrid default, with SemVer and CalVer variants), provider-specific release workflows (GitHub Actions, Azure Pipelines, GitLab CI), tag guardrails, and the release metadata manifest. It is scaffold guidance only; the CI/CD release workflows it emits default to active-on-main but tag creation is guardrail-gated, and **no production deploys or history rewrites** are included in the first pass.

## Strategy selection

The default strategy is **Hybrid**: a semantic base (SemVer-derived or CalVer-derived) plus a timestamp/trace metadata envelope recorded in a release manifest. Pure SemVer and pure CalVer are still supported strategy variants.

| Strategy | When to read |
| --- | --- |
| **Hybrid (default)** | Use for AI-assisted delivery where every release needs an auditable trace to the source commit, CI run, and tag-creation decision. |
| **SemVer** | Use when the project follows strict semantic versioning with conventional commits and a single source of truth for breaking-change signaling. |
| **CalVer** | Use when the project is date-driven and version communicates release cadence rather than compatibility. |

The strategy selector writes a `release.json` manifest at the repo root (or `.ai/release.json` if the project prefers hidden). The manifest is the audit anchor; the tag is derived from the manifest strategy.

## Release manifest (`release.json`)

A complete release manifest contains, at minimum:

```json
{
  "schema_version": "1.0",
  "strategy": "hybrid|semver|calver",
  "tag": "v1.4.0+2026.06.08.trace-7f3a",
  "base_version": "1.4.0",
  "base_sha": "<full 40-char git SHA>",
  "timestamp_utc": "2026-06-08T12:34:56Z",
  "trace_id": "<CI run id or local UUIDv4>",
  "provider": "github-actions|azure-pipelines|gitlab-ci",
  "guardrails": {
    "green_ci": "pass|fail|skipped",
    "conventional_commits": "pass|fail|skipped",
    "secrets_permissions_preflight": "pass|fail|skipped",
    "no_dirty_generated_state": "pass|fail|skipped",
    "protected_tag_policy": "pass|fail|skipped"
  },
  "guardrail_reasons": {
    "<key>": "<one-line explanation on fail; empty on pass>"
  },
  "tag_creation": "blocked|allowed",
  "tag_creation_reason": "<one-line explanation>"
}
```

For Hybrid, the tag format is `<base>+<utc-date>.<trace-token>`. For SemVer, the tag format is `v<MAJOR>.<MINOR>.<PATCH>`. For CalVer, the tag format is `v<YYYY>.<MM>.<DD>` or `v<YYYY>.<0X>` depending on cadence.

The manifest is the only authoritative record. Tag push is a derived action that happens only when every guardrail is `pass` or `skipped` and `tag_creation` is `allowed`.

## Tag guardrails

Five guardrails gate every tag-creation attempt. All five must pass (or be `skipped` with a documented reason) before any tag is created.

1. **Green CI required** — the latest CI run on the candidate SHA must report `success`. The release workflow must not bypass or override the CI status.
2. **Conventional commits required** — every commit in the candidate range must match the conventional commit grammar (`feat:`, `fix:`, `BREAKING CHANGE:`, etc.). Non-conventional commits block the tag.
3. **Secrets/permissions preflight required** — required secrets/registry tokens must be present and the workflow's `permissions` block must be explicit (no default broad grants). The preflight must not log secret values; it logs only the key names and presence/absence.
4. **No dirty generated state required** — the working tree must not contain uncommitted changes to generated artifacts (e.g. `dist/`, `build/`, golden fixtures). Generated files must be either committed or gitignored.
5. **Protected tag policy required** — the tag must be created via the CI-controlled release identity, not via a local push. The provider must reject local tag pushes for protected tag patterns (`v*`, `release/*`).

A guardrail that fails produces a `guardrail_reasons` entry naming the failure. The release workflow must surface the failed guardrail to the operator and exit non-zero without creating the tag.

## Provider release workflows

The module emits provider-specific executable templates. Each template implements the same strategy contract (Hybrid default; SemVer/CalVer variants) and the same five guardrails. Templates default to **active on main** (the release workflow runs on push to `main` and on tag push), but tag creation is blocked by the guardrail gate.

### GitHub Actions (`.github/workflows/release.yml`)

- Triggers: `push` to `main`, `push` of tags matching `v*`, `workflow_dispatch`.
- Permissions: explicit `permissions:` block scoped to `contents: read`, `id-token: write` for OIDC, and any package-specific scopes (e.g. `packages: write` for GitHub Packages). No default broad `write-all`.
- Steps: checkout → setup language toolchain → install publish-semver-derived helpers → run guardrail preflight → run strategy selector → emit `release.json` → compute tag → push tag via GH API (not local) → optionally publish via publish-semver.
- Reuses `publish-semver` for ecosystem-specific publishing semantics (npm, PyPI, crates.io, Maven Central, etc.).
- Fails closed on any guardrail failure.

### Azure Pipelines (`azure-pipelines-release.yml`)

- Triggers: `trigger` on `main`, `pr` for validation only, manual via `parameters`.
- Variables: explicit `variables:` block; sensitive values from an Azure DevOps variable group (linked secret store). `secrets/permissions` preflight runs as the first task.
- Steps: checkout → use Node/Python/Rust task → install publish-semver helpers → run guardrail preflight → run strategy selector → emit `release.json` → push tag via `git push` from the agent with a service-principal identity, not a personal access token → optionally publish.
- Fails closed on any guardrail failure.

### GitLab CI (`.gitlab-ci-release.yml`)

- Stages: `validate` → `release`.
- Triggers: `rules:` on push to `main`, on tag push, manual via `when: manual`.
- Variables: explicit; protected CI/CD variables masked; `secrets/permissions` preflight runs first.
- Steps: checkout → install toolchain → install publish-semver helpers → run guardrail preflight → run strategy selector → emit `release.json` → create protected tag via the GitLab Releases API (not a local push) → optionally publish.
- Fails closed on any guardrail failure.

The provider release templates are checked in but do not run unless the user explicitly enables them. Enabling is a checklist/decision, not a hidden mutation.

## Tag creation, protected tags, and audit

- **Protected tags.** Each provider has a tag-protection mechanism: GitHub `rulesets` for tag patterns, Azure DevOps branch/tag policies, GitLab `protected tags`. The module emits a checklist for tag protection per provider but does not call provider APIs to apply it.
- **CI-controlled release identity.** Tag creation runs inside the CI job with the CI-provided identity, not from a developer machine. The audit trail in the `release.json` manifest records the CI run id as `trace_id` and the runner provider as `provider`.
- **No history rewrites.** The module does not include tag deletion, force-push, or commit-history rewriting. If a bad tag is pushed, the recovery path is to push a new tag (e.g. `v1.4.1`) and emit a manifest entry explaining the prior tag's retirement; the prior tag is not deleted.
- **No production deploys.** The release workflows stop at tag creation and (optional) package publish. They do not deploy to production environments, run database migrations, or invoke cloud provisioning. Production deployment is a separate downstream concern.

## Credential and registry boundary

- **Package/registry publishing is conditional.** The release workflow only attempts to publish when (a) the project has a recognized package manifest (e.g. `package.json`, `pyproject.toml`, `Cargo.toml`, `pom.xml`) and (b) the required publishing credentials are present and scoped.
- **Full automation allowed when permissions allow.** If the host and registry permit and the operator has confirmed the scope, the release workflow may publish automatically after tag creation. If the host rejects or the scope is missing, the workflow stops after tag creation and surfaces a clear next-step message.
- **No secret value logging.** Preflight logs only the names of the secrets it found and the scopes it detected. Secret values are never echoed to logs.

## Reuse of `publish-semver`

This module reuses the `publish-semver` skill (installed under `~/.codex/skills/publish-semver/`) for ecosystem-specific publishing semantics — npm, PyPI, crates.io, Maven Central, NuGet, pub.dev, Hex, Erlang Hex, and Gradle/Maven Central via Azure DevOps. The release workflow invokes `publish-semver` to do the actual publish step; this module owns the strategy, manifest, and guardrails, not the publish semantics.

## Safety rules

- **Truth preservation.** The `release.json` manifest is the only authoritative record. Provider APIs may tag; the manifest is what auditors read.
- **No fake tags.** Tags must come from a real guardrail-passed release run. No manual tag pushes for protected tag patterns.
- **No production deploys in this module.** Production deploys are out of scope and live in a downstream module.
- **No history rewrites.** Tag retirement is forward-only; the prior tag is recorded as retired, not deleted.
- **Idempotent manifest writes.** A re-run with the same input must produce a byte-identical manifest (timestamps and trace ids come from the CI run, not the wall clock; the CI run id is stable per run).
- **Verification commands run after every provider-template change.** See the verification section below.

## Verification commands

Run from `skills/` after touching this module, the module map, the SKILL, `ci-policy.md`, or any provider release template:

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

The release-versioning-specific golden fixtures live under `reference/fixtures/release/` and cover:

- `hybrid-default/` — Hybrid strategy selector emits a Hybrid-shaped manifest with base+timestamp+trace.
- `semver-only/` — SemVer strategy selector emits a pure-SemVer manifest.
- `calver-only/` — CalVer strategy selector emits a CalVer-shaped manifest.
- `guardrail-fail/` — at least one guardrail fails; the manifest records the failure and `tag_creation: "blocked"`.
- `protected-tag/` — the provider template declares protected-tag semantics; local-push paths are explicitly rejected.
- `no-history-rewrite/` — the template contains no `git push --force`, no tag deletion, no commit-history rewrite.
- `no-production-deploy/` — the template contains no `azure webapp deploy`, no `kubectl apply`, no `aws s3 sync` style production steps.
- `secrets-preflight/` — the preflight logs key names only, never values.
