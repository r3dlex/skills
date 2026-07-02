# Graph Automation Module

Read when scaffolding automatic background knowledge-graph refresh via git hooks and harness hooks. This module adds the `graph-automation` mechanical templates to a target repo and wires the engine knob (default: `graphify`; alternative: `graphwiki`).

## Triggers

This module is activated when:

- The user runs `ai-catapult graph-hooks install` (CLI subcommand, Slice 5).
- The ai-catapult plugin detects a `graph-automation/config.json` in the repo and the install phase has not yet run.
- A brownfield repo already has graphify installed and the user opts in to automation.

## What gets installed

| Artifact | Target path | Tracked? |
| --- | --- | --- |
| Lock+coalesce wrapper | `scripts/graph-refresh.sh` | Yes — committed to the repo |
| Git hook bodies | `.git/hooks/post-commit`, `.git/hooks/post-checkout` | No — git metadata only |
| Claude Code hooks | `.claude/settings.json` (Stop + SessionStart entries) | Yes |
| Codex hooks | `.codex/hooks.json` (post_response + pre_session entries) | Yes |
| Engine knob | `graph-automation/config.json` | Yes |

Git hook bodies are installed idempotently into `.git/hooks/` — they are never committed to child repos. The wrapper and harness configs are committed (tracked content).

## Wrapper semantics (`graph-refresh.sh`)

The wrapper implements the **lock+coalesce** contract:

1. **Engine-absent no-op.** `command -v {{ENGINE}} || exit 0` — safe on machines without the engine.
2. **Lock.** Acquires `$TMPDIR/graph-refresh-<repo-hash>.lock` (mkdir, POSIX-atomic). If already held, touches a `.pending` marker and exits 0 immediately.
3. **Run.** Executes `{{ENGINE}} . --update` with stdout/stderr appended to `graphify-out/refresh.log` (fallback: `.git/graph-refresh.log`).
4. **Coalesce.** On exit, checks for the `.pending` marker; if present, removes it and runs the engine once more. This collapses bursts: N triggers → at most 2 engine runs.
5. **Always exits 0.** Never blocks a git operation or harness session.

The `{{ENGINE}}` token is substituted by `ai-catapult graph-hooks install` using the value in `graph-automation/config.json`.

## Engine knob

`graph-automation/config.json` holds the engine selection:

```json
{ "engine": "graphify" }
```

- `graphify` — default; incremental AST-based knowledge-graph refresh, no LLM required.
- `graphwiki` — opt-in alternative; same wrapper contract, different binary.

To switch engines: update `engine` in `config.json`, then re-run `ai-catapult graph-hooks install` to re-stamp the wrapper and hook bodies.

## Hook-body contract (`hook-body.sh`)

The git hook body is ≤15 non-comment non-blank lines. It:

1. **Skips during rebase/merge/cherry-pick** — guards lifted verbatim from `graphify/graphify/hooks.py:51-55` to match graphify's own behavior.
2. **Resolves the wrapper** — honors `GRAPH_HOOKS_WRAPPER` env first; else walks parent directories looking for `scripts/graph-refresh.sh` in an ancestor that also contains `.git`, stopping at `$HOME`/root. This means child-repo hooks find the umbrella wrapper without hard-coded paths.
3. **Exits 0 silently** if the wrapper is not found (standalone clone, CI, missing umbrella).
4. **Background-execs** the wrapper `cd`'d to its repo root — one root graph for the whole workspace.

## Install via CLI

```
ai-catapult graph-hooks install [--engine graphify|graphwiki] [--dry-run]
```

- Reads `graph-automation/config.json` for the engine default.
- Writes/stamps `scripts/graph-refresh.sh` (substitutes `{{ENGINE}}`).
- Merges harness hook entries into `.claude/settings.json` and `.codex/hooks.json`.
- Installs hook bodies into `.git/hooks/post-commit` and `.git/hooks/post-checkout` (idempotent marker-managed replace).
- `--dry-run` prints the diff without writing.
- `--engine` overrides the config knob for this run only.

## prek vs graph-hooks file ownership

| Hook file | Owner |
| --- | --- |
| `.git/hooks/pre-commit` | prek |
| `.git/hooks/pre-push` | prek |
| `.git/hooks/post-commit` | graph-hooks |
| `.git/hooks/post-checkout` | graph-hooks |

The filenames are disjoint; both can coexist in `.git/hooks/` without conflict.

## Mechanical templates

All four template files are classified as **mechanical** in `boundary-manifest.json` — their bodies are fixed (or contain only well-typed `{{TOKEN}}` placeholders) and require no per-repo judgment to emit:

| Template | Target |
| --- | --- |
| `graph-automation/graph-refresh.sh` | `scripts/graph-refresh.sh` |
| `graph-automation/hook-body.sh` | `.git/hooks/post-commit`, `.git/hooks/post-checkout` |
| `graph-automation/harness-hooks.json` | merged into `.claude/settings.json` + `.codex/hooks.json` |
| `graph-automation/config.json` | `graph-automation/config.json` |

## Non-goals

- No `graphify --watch` daemon (lifecycle burden; Stop+git hooks suffice).
- No per-child graphs; one umbrella-root graph per workspace.
- No blocking hooks (pre-push or synchronous pre-commit).
- No LLM-invoking full rebuilds from hooks — incremental `--update`/AST paths only.
