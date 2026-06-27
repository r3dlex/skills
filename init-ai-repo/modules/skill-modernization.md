# Skill Modernization Module

Read when auditing or updating a skill catalog for compact metadata, progressive disclosure, trigger clarity, runnable validation, cross-skill workflow links, and AI-SDLC compatibility.

## Generated outputs

| Output | Purpose |
| --- | --- |
| `.ai/skills/catalog-audit.json` | Machine-readable audit of every first-class skill description, body length, trigger boundary, and compatibility status. |
| `.ai/skills/description-exceptions.json` | Explicit exceptions for descriptions that exceed the hard budget; default is no exceptions. |
| `.ai/skills/modernization-report.md` | Human report summarizing fixes, warnings, and remaining follow-up. |

## Budget policy

- Target description length: `<= 180` characters.
- Hard-fail description length: `> 280` characters unless listed in `.ai/skills/description-exceptions.json` with owner, reason, and expiry.
- `SKILL.md` body stays under 100 lines.
- Descriptions state capability plus concrete trigger conditions; move examples, background, and variants to modules or references.

## Required checks

1. Audit only first-class catalog skill directories plus the `ai-sdlc-init` compatibility shim; exclude `.agents/`, hidden/runtime directories, reference fixtures, and golden outputs.
2. Verify every first-class skill has `name` and `description` frontmatter.
3. Warn when a description exceeds the 180-character target; fail when it exceeds 280 without an audited exception.
4. Verify body line limits and progressive-disclosure anti-patterns through `tests/test-skills.sh`.
5. Verify generated workflow links remain discoverable for skills that create PRDs, issues, releases, traces, or AI-SDLC artifacts.
6. Emit a stable catalog audit artifact and keep exceptions explicit, reviewed, and time-bounded.

## Cross-skill workflow links

- `init-ai-repo` owns generated workflow, traceability, cascade, and catalog audit artifacts.
- `setup-skills` owns tracker/domain-doc configuration that downstream issue and PRD skills consume.
- `to-prd`, `to-issues`, and `triage` must preserve traceability IDs and tracker backlinks.
- `publish-semver` must link release evidence to specs, PRs, and tests.
- `write-a-skill` and `write-agent-docs` own authoring guidance for future catalog changes.

## Safety rules

- Do not weaken validators to make existing skills pass; fix the skill or add a reviewed exception.
- Do not add new runtime dependencies for catalog validation.
- Do not rewrite skill workflows for style only; preserve behavior unless a validation gate proves a problem.
