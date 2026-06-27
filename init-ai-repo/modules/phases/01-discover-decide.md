# Phase 1 — Discover & Decide

## Purpose

Discover the repository's real current state and choose the smallest safe AI-SDLC adoption lane before generating governance or implementation artifacts. This phase is intentionally read-mostly and should be safe to rerun.

## Inputs

- Repository metadata, remotes, branch state, existing CI, package manifests, and language/runtime conventions.
- Existing `.ai/`, `.memory/`, `AGENTS.md`, `RULES.md`, `PLANS.md`, `CONTRIBUTING.md`, specs, ADRs, and issue tracker configuration.
- User-selected posture for hosted tickets versus local fallback.

## Outputs

- `.ai/matrix.json`
- `.ai/init/repo-profile.json`
- `.ai/init/sdlc-path.md`
- `.ai/phases/01-discover-decide/README.md` or equivalent phase notes

## Command surfaces

- OMX: `$deep-interview` for ambiguity, `$plan` for straightforward planning, `$ralplan` for consensus planning.
- OMC: equivalent aliases/commands should call into the same generated artifact contract and must not duplicate semantics.

## Gates

- Do not begin coding until the lane, source of truth, and required planning artifacts are known.
- If a hosted tracker is configured and authorized, issue/ticket discovery is fail-closed.
- If hosted tracking is unavailable, local fallback is allowed before coding, but it must be reconciled before final PR merge.

## Idempotence

Reruns update generated discovery files non-destructively and preserve human-owned notes outside managed blocks.
