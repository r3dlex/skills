# Spec (repo slice): skills-catalog-evals-consolidation in skills

- **Canonical spec:** umbrella `r3dlex/ai-tool-workspace` → `docs/specifications/ACTIVE/skills-catalog-evals-consolidation.md`
- **Canonical spec SHA-256:** `79e3295adbb1ddabcca921b8bdd567f596f5202ada581d8a2ed5afbfeb9ece3d`
- **This file:** the skills goals of that plan, so autobahn can admit them from this repo's root. Acceptance criteria and verification details live in the canonical spec; on any conflict, the canonical spec wins.
- **State:** planned; wave-1 goals have direct-goal intake files under `.ai/handoff/autobahn-goals/`.

## Goals in this repo

### SCE-S1
- **Wave 1:** yes
- **Covers:** AC-1, AC-2, G10
- **Scope:** Routing evalset schema + description-blind cases for all 36 shipped skills. The deterministic gate fails on: a shipped skill with no cases; a case whose expected skill isn't in the catalog; schema errors; trigger-phrase collisions; TF-IDF cosine similarity over the threshold without an allowlist entry; an allowlist entry that matches nothing (so the allowlist can only shrink). Threshold = highest similarity among non-cluster skill pairs + 0.05, with the value and its calibration recorded in the gate config. Allowlist pre-seeded with the 4 clusters + 2 aliases. Wired into `ci.yml`

### SCE-S2
- **Wave 1:** no (depends: SCE-S1, SCE-H1)
- **Covers:** AC-3, AC-4, G5, G9
- **Scope:** Provider-agnostic live harness (env `base_url`/`model`/`key`, temp 0, 3x majority, top-1 + per-case-id flip report) + `routing-eval.yml` (nightly `schedule` + `workflow_dispatch` with `ref` and `provider` inputs; uploads the results artifact; if the secret is absent, fails with a message and never echoes it) + local reverso run doc

### SCE-S3
- **Wave 1:** no (depends: SCE-S2, SCE-H2)
- **Covers:** AC-5
- **Scope:** Baseline freeze: dispatch on main, commit `baseline.json` keyed by case id + document the refresh command; apply the H2 fixes

### SCE-S4b
- **Wave 1:** yes
- **Covers:** G4
- **Scope:** ADR "consolidate overlaps into upstream-named survivors", superseding skills-upstream-port decision #2

### SCE-S5
- **Wave 1:** no (depends: SCE-S3, SCE-S4b)
- **Covers:** AC-6, AC-8, G1, G6
- **Scope:** `grilling` absorbs `grill-me` + `grill-with-docs` (docs-grounded mode). Re-points northstar `modules/loop.md` + `SKILL.md` + the umbrella-facing command JSONs in skills; rewrites `tests/northstar_lineage_test.sh:40-61` and `tests/interview_decomposition_test.sh`; adds both names to `dead_reference_gate_test.sh` scans; relabels the cases (same id, expected → `grilling`); drops their allowlist entry; re-freezes `baseline.json` from this PR's evidence run

### SCE-S6
- **Wave 1:** no (depends: SCE-S5)
- **Covers:** AC-7, AC-8
- **Scope:** `to-tickets` ← `to-issues` (northstar issue module, triage refs); same sweep / gate / relabel / re-freeze rule

### SCE-S7
- **Wave 1:** no (depends: SCE-S6)
- **Covers:** AC-7, AC-8
- **Scope:** `to-spec` ← `to-prd`; same rule

### SCE-S8
- **Wave 1:** no (depends: SCE-S7)
- **Covers:** AC-7, AC-8
- **Scope:** `codebase-design` ← `design-an-api-or-interface`; same rule

### SCE-S9
- **Wave 1:** no (depends: SCE-S8)
- **Covers:** AC-7, AC-8
- **Scope:** Remove the `ai-sdlc-init` + `init-ai-repo` skills. Rewrite `tests/ai-catapult-init_rename_test.sh:35-41` and `tests/init-ai-repo_docs_test.sh`. Sort **all 68** files matching `init-ai-repo` into identifier vs skill reference; rename the skill references; allowlist the identifier uses **by path glob with a stated reason** (not by the `init-ai-repo:` shape, which misses the quoted and backtick forms). Scan both names; same rule
