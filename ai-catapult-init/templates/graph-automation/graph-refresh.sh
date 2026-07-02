#!/usr/bin/env bash
# graph-refresh.sh — lock+coalesce wrapper for background graph engine refresh.
#
# Install location: scripts/graph-refresh.sh (umbrella or standalone repo root).
# Called by: child-repo git hooks (hook-body.sh) and harness hooks (Stop event).
#
# Contract:
#   - One run at a time via lockfile; a second trigger while running marks ONE
#     pending rerun (bursts collapse — at most one extra run is queued).
#   - Always exits 0 — never blocks git operations or harness sessions.
#   - stdout/stderr from the engine are appended to:
#       graphify-out/refresh.log (created on first run; directory must exist or
#       the engine itself creates it; fallback: .git/graph-refresh.log)
#   - No-op when the engine binary is absent (command -v check before exec).
#
# Token: {{ENGINE}} — replaced by ai-catapult graph-hooks install.
#        Default value: graphify
#        Alternative:   graphwiki
#
# Usage: called with cwd = repo root.

# ── Interpreter / engine detection ──────────────────────────────────────────
# Only run when the engine is present on PATH.
# shellcheck disable=SC2016
ENGINE="{{ENGINE}}"
command -v "$ENGINE" >/dev/null 2>&1 || exit 0

# ── Paths ────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_FILE="$REPO_ROOT/graphify-out/refresh.log"
LOCK_FILE="${TMPDIR:-/tmp}/graph-refresh-$(echo "$REPO_ROOT" | tr '/' '_').lock"
PENDING_FILE="${LOCK_FILE}.pending"

# ── Lock + coalesce ──────────────────────────────────────────────────────────
# Try to acquire the lock (mkdir is atomic on POSIX).
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
    # Another run is in progress — mark at most one pending rerun and return.
    touch "$PENDING_FILE"
    exit 0
fi

# We hold the lock.  Schedule unlock + pending-rerun loop on EXIT.
# shellcheck disable=SC2329  # invoked via trap
cleanup() {
    rmdir "$LOCK_FILE" 2>/dev/null || true
}
trap cleanup EXIT

# Ensure log directory exists (best-effort).
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || LOG_FILE="${REPO_ROOT}/.git/graph-refresh.log"

# ── Run the engine (background, log output) ──────────────────────────────────
# shellcheck disable=SC2016
run_engine() {
    {
        echo "--- graph-refresh $(date -u +%Y-%m-%dT%H:%M:%SZ) engine=$ENGINE ---"
        "$ENGINE" . --update 2>&1
    } >> "$LOG_FILE"
}

run_engine

# ── Coalesce: drain one pending rerun if queued ───────────────────────────────
if [ -f "$PENDING_FILE" ]; then
    rm -f "$PENDING_FILE"
    run_engine
fi

exit 0
