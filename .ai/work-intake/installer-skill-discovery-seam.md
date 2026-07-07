# Work intake: installer skill-discovery seam

- **Slug**: installer-skill-discovery-seam
- **Type**: refactor (architecture deepening)
- **Spec**: docs/specifications/ACTIVE/installer-skill-discovery-seam.md
- **Status**: in-progress

## Problem

The five installers in `scripts/` duplicate the skill-discovery logic
(iterate skill dirs, require `SKILL.md`, skip internal dirs, read
frontmatter). One exclusion-rule change requires five edits.

## Goal

One `scripts/lib-skill-discovery.sh` module owns discovery
(`list_skills`, `is_excluded_dir`, frontmatter helpers); installers keep
only tool-specific install steps. Behavior stays byte-identical.

## Acceptance criteria

- `bash tests/run-tests.sh` green, including new
  `tests/lib-skill-discovery_test.sh`.
- Installers keep CLI flags, output lines, and destinations exactly.
