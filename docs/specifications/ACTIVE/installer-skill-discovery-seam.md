# Spec: Extract the installer skill-discovery seam

## A — Current state

The five tool installers under `scripts/` — `install-claude-code.sh`,
`install-codex.sh`, `install-copilot.sh`, `install-gemini.sh`,
`install-auggie.sh` — each inline the same skill-discovery logic:

- iterate top-level directories of the repo root (`"$SKILLS_DIR"/*/`),
- skip the internal-dir exclusion list (`.claude`, `.omc`, `scripts`, `raw`),
- require a `SKILL.md` in the directory to treat it as a skill,
- (3 of 5) extract the frontmatter `description` with the same
  `grep -A1 '^description:' | tail -1 | sed` pipeline,
- (3 of 5) strip YAML frontmatter with the same
  `sed -n '/^---$/,/^---$/d;p'` invocation.

Adding one exclusion rule (or changing what counts as a skill) requires five
coordinated edits, and the copies have already drifted in check order.

## B — Target state

`scripts/lib-skill-discovery.sh` owns the discovery seam:

- `SKILL_DISCOVERY_EXCLUDES` — the single, centralized exclusion list,
- `is_excluded_dir <name>` — membership test against that list,
- `list_skills <root>` — emits the discovered skill names (one per line,
  glob order): top-level dirs that have a `SKILL.md` and are not excluded,
- `skill_frontmatter_description <skill-dir>` — the shared frontmatter
  `description` reader,
- `skill_body_without_frontmatter <skill-md>` — the shared frontmatter strip.

Each installer sources the lib and keeps only its tool-specific install step
(copy layout, format conversion, destination, CLI surface).

## Acceptance criteria

- `bash tests/run-tests.sh` is green (both suites), including the new
  `tests/lib-skill-discovery_test.sh` fixture-tree unit test.
- The five installers behave identically to before the refactor: same CLI
  flags, same output lines, same destinations, same discovered skill set.
- The exclusion list lives in exactly one place.
