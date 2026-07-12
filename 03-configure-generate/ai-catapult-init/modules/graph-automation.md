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
| Codex hooks | `.codex/hooks.json` (Stop + SessionStart entries) | Yes |
| Engine knob | `graph-automation/config.json` | Yes |

Git hook bodies are installed idempotently into `.git/hooks/` — they are never committed to child repos. The wrapper and harness configs are committed (tracked content).

## Wrapper semantics (`graph-refresh.sh`)

The wrapper implements the **lock+coalesce** contract:

1. **Engine-absent no-op.** `command -v {{ENGINE}} || exit 0` — safe on machines without the engine.
2. **Lock.** Acquires `${ENGINE}-out/graph-refresh-lock` (mkdir, POSIX-atomic, co-located with the log file in the repo root — no TMPDIR). Write a `"RUNNING"` sentinel to `pid` immediately; the background subshell overwrites it with its real PID. If the lock is already held (and the holder PID is live), touches a `.pending` marker and exits 0. Stale locks (empty or dead PID) are reclaimed with a single retry.
3. **Run.** Dispatches via per-engine case block from `REPO_ROOT` with stdout/stderr appended to `${ENGINE}-out/refresh.log`: `graphify` → interpreter-detected `python -c "_rebuild_code(Path('.'))"` (no `--update` flag; graphify v0.4.x has no such flag); `graphwiki` → `graphwiki build . --update`; generic fallback → `"$ENGINE" . --update`. A `GRAPH_REFRESH_ENGINE_CMD` env var bypasses all engine logic for tests.
4. **Coalesce.** Inside the background runner, after each engine run, if a new `.pending` marker appeared during the run, the loop continues (clearing the marker first). After the run loop exits the lock is released; a bounded post-release re-check handles the lost-update window. N triggers → at most 2 engine runs total.
5. **Always exits 0.** Never blocks a git operation or harness session.
6. **`.git`-dir precondition.** The sentinel walk in `hook-body.sh` only stops at a directory that has both `scripts/graph-refresh.sh` and a `.git/` dir. This wrapper is therefore always invoked from a git repository root. Invocations outside a git repo are unsupported.
7. **`--status` flag.** Prints lock/pending/log-tail info and exits 0 without running the engine. Used by the `SessionStart` hook for a validate-only check.

The `{{ENGINE}}` token is substituted by `ai-catapult graph-hooks install` using the value in `graph-automation/config.json`.

**Engine output directory** — derived in shell as `${ENGINE}-out` (e.g. `graphify-out` or `graphwiki-out`). No separate `{{ENGINE_OUT_DIR}}` token is needed; the shell derivation handles both engine choices automatically, and Slice 6 token normalization only needs to track `{{ENGINE}}`.

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

All four template files are classified as **mechanical** in `boundary-manifest.json` — their bodies are fixed (or contain only well-typed `{{TOKEN}}` placeholders) and require no per-repo judgment to emit.

### Stage-then-activate convention

`ai-catapult init` **stages** all four templates under `graph-automation/` in the target repo. The `path` field in `boundary-manifest.json` records this init-emit (staging) location for every graph-automation entry.

`ai-catapult graph-hooks install` then **activates** them: the wrapper is stamped with `{{ENGINE}}` and written to `scripts/graph-refresh.sh`; hook bodies are written to `.git/hooks/post-commit` and `.git/hooks/post-checkout`. These activation destinations are recorded in each entry's `install_destination` field in the manifest.

| Template (staged under `graph-automation/`) | Activation destination |
| --- | --- |
| `graph-automation/graph-refresh.sh` | `scripts/graph-refresh.sh` (committed) |
| `graph-automation/hook-body.sh` | `.git/hooks/post-commit`, `.git/hooks/post-checkout` (not committed) |
| `graph-automation/harness-hooks.json` | merged into `.claude/settings.json` + `.codex/hooks.json` |
| `graph-automation/config.json` | `graph-automation/config.json` (in-place, no move) |

## Non-goals

- No `graphify --watch` daemon (lifecycle burden; Stop+git hooks suffice).
- No per-child graphs; one umbrella-root graph per workspace.
- No blocking hooks (pre-push or synchronous pre-commit).
- No LLM-invoking full rebuilds from hooks — incremental `--update`/AST paths only.
