# README Documentation Module

Read when initializing, augmenting, or rewriting a repo's `README.md` so the result is user-focused GitHub documentation rather than an internal governance dump. The module applies a both-by-mode strategy: a full template for new or sparse repos, and a safe augmentation/rewrite for existing READMEs.

## Both-by-mode

| Mode | Trigger | Behavior |
| --- | --- | --- |
| Template | Repo is new, empty, or the existing `README.md` is sparse/stub. | Generate a complete README from supplied, project-specific onboarding facts. |
| Augmentation | Repo already has a meaningful `README.md` (one or more populated sections matching the catalogue). | Preserve project-specific facts and append only complete sections backed by supplied facts. Never overwrite existing content without backup/audit. |

Sparseness classification MUST run before any write. Do not pick a mode from vibes.

## Sparse-vs-existing classification

Classify the existing `README.md` as **sparse** if any of the following are true, otherwise treat it as **existing**:

- File does not exist, or
- File size is below the size threshold (default 600 bytes), or
- File contains only a top-level heading plus a placeholder line (e.g. `# project-name`, `WIP`, `TBD`, `Coming soon`, `TODO: write README`), or
- File lacks every required template section listed below (after case-insensitive heading match).

Classify as **existing** if it has at least one of: real quick start code block, real feature list, real installation instructions, real usage example, real project description beyond a placeholder.

## Required template sections (template mode)

A full template README contains, in order:

1. **Hero / title / tagline** — repo name, one-sentence value proposition, optional one-line audience.
2. **Real applicable badges** — license, build/CI, release/version, package registry, code coverage, downloads/stars when public and applicable. Badges must come from real host/package/license data; never invent.
3. **Quick start** — install, configure, run the first success path. Keep it copy-paste runnable.
4. **Requirements** — runtime, language, OS, network or credentials needed.
5. **Setup and first success path** — minimum steps to verify a working install.
6. **Update path** — how to upgrade, migrate, or pull latest without losing state.
7. **Why / who / features / workflows / mental model** — explain the problem, audience, key features, and how the pieces fit.
8. **Community** — maintainers, contributors, code of conduct, contributing link, support channels.
9. **License / support** — license file link, support policy, sponsorship or commercial support if applicable.
10. **Concise AI-SDLC governance block** — one short block linking to `AGENTS.md`, `CONTRIBUTING.md`, ADRs, and the BRD/PRD traceability chain. Do not dump the entire governance payload into the README.

The hero, runnable Quick Start, observable first-success evidence, value statement,
and archetype mental model are mandatory. Requirements, update, community,
license, and governance sections are emitted only when their
repository facts or explicit inputs exist. Missing optional facts are omitted;
they are never represented by placeholders.

## Executable generator contract

`scripts/readme-generate.sh` is a repository convenience wrapper. The canonical,
installed implementation and template live at
`03-configure-generate/ai-catapult-init/scripts/readme-generate.sh` and
`03-configure-generate/ai-catapult-init/assets/readme/template.md`.

The generator supports two deliberately narrow archetypes:
`cli-tool` and `skill-catalog`. Template and augmentation modes require:

- `--project` and `--tagline` for identity and value.
- `--why`, distinct from the tagline, for the repository-specific value case.
- `--archetype cli-tool|skill-catalog`, `--primary-surface`, and
  `--mental-model` for the repository-specific operating model.
- `--install-command` and `--first-success-command`, each containing an
  executable, non-comment command.
- `--success-evidence` naming observable output or a generated artifact.

Use `--requirements` and `--update-command` when those facts are known. For
example:

```sh
bash scripts/readme-generate.sh --mode template --repo . \
  --project "Example CLI" --tagline "Checks an example repository." \
  --why "Catch invalid repository state before publishing." \
  --archetype cli-tool --primary-surface 'example-cli <command>' \
  --mental-model "Each command validates one repository and reports evidence." \
  --install-command "npm install -g example-cli" \
  --first-success-command "example-cli doctor" \
  --success-evidence 'prints "example repository ready"' \
  --out README.md
```

Generation fails with actionable missing-input guidance instead of emitting an
incomplete README. Output validation rejects explicit placeholder syntax,
template tokens, filler text, and invented static proof badges while preserving
valid HTML tags and Markdown autolinks.

## Augmentation behavior (existing mode)

- Pass `--source-sha <sha256>` for the reviewed README. The write is rejected if
  that SHA changes before backup or replacement.
- Run a backup step before any rewrite. See "Backup and audit manifest" below.
- Preserve every existing section verbatim unless the user explicitly asks for reorganization.
- Detect missing onboarding sections and append them in the right order without disturbing existing content. Use the same required project, archetype, command, and success-evidence inputs as template mode.
- Detect duplicate or near-duplicate sections (e.g. two installation blocks); consolidate by adding a pointer to the canonical section, but do not delete user content without an explicit confirmation step.
- Reject augmentation when the existing README contains private/internal markers unless the host is private; surface a confirmation prompt before any rewrite.

## Real proof-signal gating

A proof signal is any badge, count, link, or claim that depends on external state (host stars, package downloads, license file, build status, release version). All proof signals MUST satisfy these rules:

- **Real data only.** Reject hardcoded status, release, coverage, or download claims. The deterministic generator emits only a license badge backed by a real `LICENSE` file; add other badges separately only after deriving their URLs from real host or registry configuration.
- **No synthesized dynamic proof.** Star history, downloads, build state,
  releases, and contributor claims are outside this offline generator's
  contract. Add them separately only from current host or registry evidence.
- **License accuracy.** The license badge must match the actual `LICENSE` file in the repo. Do not assume a default.
- **No marketing tone for internal or library-only repos.** Internal tooling and small libraries get accurate, restrained documentation; no "blazing fast", "production ready", or other unverified adjectives.
- **Validation.** Tests MUST reject invented claims, fake badges, fake star history, and any private/internal marker that leaks into a public README.

## Public/private host awareness

- Detect host visibility from the host API or explicit user input. Default to private if the host cannot be reached.
- Public repos: full template; externally verified dynamic proof may be added outside this generator.
- Private/internal repos: suppress star history, downloads counts, public contributor lists, and any social proof; keep license, build, and version badges only when real and applicable.
- Non-GitHub hosts: gracefully degrade. Use the host's own badge/CI mechanisms or omit the section. Do not add explanatory filler to the generated README.

## Backup and audit manifest

Before any augmentation or rewrite:

1. Compute the reviewed README SHA-256 and pass it as `--source-sha`. This is
   required for augmentation and `template --force`.
2. Copy the existing `README.md` to a timestamped backup path. Default pattern: `.ai/drift/readme-backups/README-<ISO8601-timestamp>.bak`.
3. Emit an audit manifest at `.ai/drift/readme-backups/audit-<ISO8601-timestamp>.json` with:
   - Source path, source SHA, byte size, line count, section heading list.
   - Detected mode (template or augmentation), reason.
   - Planned additions (section title, intended content summary).
   - Planned modifications (section title, before/after summary).
   - Planned deletions (none in v1; the augmenter never deletes without explicit confirmation).
   - Operator-visible confirmation prompt and the user's response.
4. Refuse to write when the source SHA changes before backup, when the backup
   SHA differs from the reviewed SHA, or when the source changes before write.
5. Tests MUST assert that a backup path and audit manifest both exist for every augmentation/rewrite and that the manifest records the reviewed source SHA.

## Concise AI-SDLC governance block

Append a short, link-only block at the end of the README. The block must:

- Link to `AGENTS.md` (or `CLAUDE.md` when only that exists), `CONTRIBUTING.md`, `docs/architecture/adr/`, and any BRD/PRD traceability doc that exists.
- Stay under 10 lines.
- Use neutral wording: "This repository follows the AI-SDLC methodology. See [AGENTS.md] for the operating contract, [docs/architecture/adr/] for architectural decisions, and [BRD/PRD] for traceability."
- Never inline `.rules.ts`, ADR bodies, BRD/PRD bodies, or full governance payloads.

## Safety rules

- Truth preservation. No invented claims, fake badges, fake star history, fake contributor counts, or private/internal leakage.
- Backup before rewrite. Augmentation and template-over-existing flows MUST produce a backup and audit manifest before any write.
- Idempotent marker writes. The AI-SDLC block is keyed on a marker comment; do not duplicate when the marker is already present.
- Do not delete user content. The augmenter never removes user-written content without explicit confirmation. The pointer/merge strategy above is the default.
- Validation runs after every write. The `validation.md` module's `tests/test-skills.sh` and `scripts/verify-golden-dir.sh` commands must pass for the affected fixtures.

## Verification commands

Run from `skills/` after touching the module, the module map, the SKILL, or the README fixtures:

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

The README-specific golden fixtures live under `reference/fixtures/readme/` and cover:

- `sparse-repo/` — empty repo triggers template mode.
- `existing-repo/` — populated README triggers augmentation mode.
- `private-repo/` — host visibility is private, public proof signals are suppressed.
- `fake-badges/` — invented claims and fake badges are rejected.
- `private-leak/` — private/internal markers are rejected in public READMEs.
- `fact-retention/` — augmentation preserves project-specific facts and emits a backup/audit manifest.
