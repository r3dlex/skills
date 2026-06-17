# ADR 0002: Use physical-copy sync for AI SDLC scaffold assets

- Status: Accepted
- Date: 2026-06-07

## Context

The v3 scaffold must work in standalone repositories and umbrella workspaces without requiring repository-local support for symlinks or nested Git submodules. Agent skills, matrix files, memory scaffolds, and documentation modules must remain auditable as normal files in each target repository.

## Decision

Use `sync_strategy: "physical-copy"` as the only canonical synchronization mode for scaffold-managed assets. Reject `symlink` and `git-submodule` as canonical modes during validation.

## Consequences

- Each repository owns a concrete copy of the scaffold files that can be reviewed, diffed, and reverted with normal Git tooling.
- Standalone repositories must declare `max_allowed_depth: 0` and `current_depth: 0`.
- Umbrella repositories must declare `max_allowed_depth: 3` and block any candidate whose `current_depth` or managed repository depth exceeds that limit.
- Updates are propagated by explicit copy/sync operations with audit evidence instead of by implicit filesystem indirection.
