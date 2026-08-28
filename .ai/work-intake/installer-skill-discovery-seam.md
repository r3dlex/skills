# Work intake: installer skill-discovery seam

- **Slug**: installer-skill-discovery-seam
- **Type**: refactor (architecture deepening)
- **Spec**: docs/specifications/ACTIVE/installer-skill-discovery-seam.md
- **Status**: done

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

## Closure (2026-08-28)

Closed by goal `skills-delete-dead-discovery-seam`: the lib had zero production
consumers, its top-level discovery model predates the phase-dir reorg (returns
zero skills on the live repo), and its parity test was vacuous. The catalog
installers (`scripts/catalog-install.sh` + `scripts/catalog-query.py`) are the
canonical discovery path; the ACTIVE spec is marked SUPERSEDED;
`scripts/check-root-discovery.py` now also flags the shell-glob discovery
class so the seam cannot return.
