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
5. Verify trigger/non-trigger/fallback boundaries are present in each first-class description (see "Trigger boundaries").
6. Validate referenced surfaces: no broken relative links, aliases resolve to a real canonical skill, every referenced file exists, and every bundled script passes `bash -n` (see "Link, alias, referenced-file, and script validation").
7. Verify generated workflow links remain discoverable for skills that create PRDs, issues, releases, traces, or AI-SDLC artifacts.
8. Emit a stable catalog audit artifact and keep exceptions explicit, reviewed, and time-bounded.

## Trigger boundaries

Every audited skill description must make three boundaries explicit so an agent can route correctly without loading the body:

- **Trigger** — the concrete conditions under which the skill should run (verbs, artifacts, keywords).
- **Non-trigger** — adjacent situations the skill must *not* claim, to prevent over-eager invocation (e.g. "use X instead for live-app runs"). Audit warns when a skill's description overlaps another skill's trigger without a non-trigger carve-out.
- **Fallback** — what happens when a precondition is missing or an optional tool/host is unavailable (graceful degradation, plain-markdown path, or "defer to <other skill>"). A skill with optional host/tool dependencies must name its fallback.

## Link, alias, referenced-file, and script validation

The audit statically validates a skill's referenced surfaces — offline, no network:

- **Broken link check** — every relative Markdown link and `modules/*`/`reference/*` pointer in `SKILL.md` and its modules resolves to a tracked file.
- **Alias check** — declared aliases/shims (e.g. the `ai-sdlc-init` → `init-ai-repo` compatibility alias) point to a real canonical skill and do not collide with another first-class name.
- **Referenced-file check** — every file a skill names (templates, fixtures, ADRs, golden outputs) exists at the cited path; cite by content where line numbers would drift.
- **Script check** — every bundled `scripts/*` a skill invokes exists and passes `bash -n`; the audit does not execute network- or credential-dependent scripts.

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
