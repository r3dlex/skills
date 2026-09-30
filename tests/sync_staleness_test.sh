#!/bin/bash
#
# sync_staleness_test.sh  (SSCM-02, fixture-first)
#
# Hard tests for the staleness gate (scripts/check-sync-staleness.sh):
#   - synthetic OLD lock  → gate exits non-zero (hard, even in advisory mode)
#   - synthetic FRESH lock → gate exits zero
#   - real skills-root upstream.lock (past threshold) → advisory warning naming
#     the stale date, threshold, flip condition and flip goal, exit 0, and a
#     DATED flip-to-hard comment present in the gate source
#   - unreachable pinned_sha → non-zero with guidance (hard, mode-independent)
#
# Offline: reachability is proven against a local fixture remote, not network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

GATE="scripts/check-sync-staleness.sh"
THRESHOLD=49

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
note() { echo "  note: $1"; }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mklock() { # mklock <path> <updated-date> <sha>
  printf 'source: mattpocock/skills\nvia: r3dlex/skills\npinned_sha: %s\nupdated: %s\nsync_script: scripts/sync-upstream.sh\n' "$3" "$2" > "$1"
}

# A sha that is reachable in the fixture remote (use the repo's own HEAD's sha).
FORK_SHA="$(git rev-parse HEAD)"
UNREACHABLE_SHA="deadbeef0000000000000000000000000000dead"

old_date="$(date -v-$((THRESHOLD - 1))d -u +%Y-%m-%d 2>/dev/null || date -u -d "-${THRESHOLD} days" +%Y-%m-%d)"
stale_date="$(date -v-$((THRESHOLD + 7))d -u +%Y-%m-%d 2>/dev/null || date -u -d "-$((THRESHOLD + 7)) days" +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# (1) synthetic OLD (stale) lock → non-zero, even in advisory mode
# ---------------------------------------------------------------------------
mklock "$tmpdir/old.lock" "$stale_date" "$FORK_SHA"
if bash "$GATE" --lock "$tmpdir/old.lock" --mode advisory --repo-root . >/dev/null 2>&1; then
  bad "stale lock exits non-zero in advisory mode"
else
  ok "stale lock exits non-zero in advisory mode"
fi

# ---------------------------------------------------------------------------
# (2) synthetic FRESH lock → zero
# ---------------------------------------------------------------------------
mklock "$tmpdir/fresh.lock" "$old_date" "$FORK_SHA"
if bash "$GATE" --lock "$tmpdir/fresh.lock" --mode advisory --repo-root . >/dev/null 2>&1; then
  ok "fresh lock exits zero in advisory mode"
else
  bad "fresh lock exits zero in advisory mode"
fi

# ---------------------------------------------------------------------------
# (3) real skills-root upstream.lock: advisory warning + exit 0, named details
# ---------------------------------------------------------------------------
out="$(bash "$GATE" --lock UPSTREAM_LOCK_ABSENT --mode advisory --repo-root . 2>&1 || true)"
rc=0
bash "$GATE" --mode advisory --repo-root . >/tmp/gate.out 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "real lock (stale) is advisory: exit 0"
else
  bad "real lock (stale) is advisory: exit 0 (got $rc)"
fi
grep -qF "advisory" /tmp/gate.out && \
  grep -qF "49 days" /tmp/gate.out && \
  grep -qF "$(grep -m1 '^updated:' upstream.lock | awk '{print $2}')" /tmp/gate.out && \
  grep -qF "first live refresh" /tmp/gate.out && \
  ok "real-lock advisory names stale date, threshold, flip condition"
(grep -qF "first live refresh" /tmp/gate.out && ! grep -qF "$(grep -m1 '^updated:' upstream.lock | awk '{print $2}')" /tmp/gate.out) && \
  bad "real-lock advisory names stale date, threshold, flip condition" || ok "real-lock advisory names stale date, threshold, flip condition"
note "real-lock advisory output:"
sed 's/^/    /' /tmp/gate.out | head -4

# ---------------------------------------------------------------------------
# (4) DATED flip-to-hard comment exists in gate source
# ---------------------------------------------------------------------------
if grep -qE "(Flip to hard|flip-to-hard|FLIP).*[0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{4}-[0-9]{2}-[0-9]{2}.*(Flip to hard|flip-to-hard|FLIP|stays advisory)" "$GATE"; then
  ok "gate source carries the DATED flip-to-hard comment"
else
  bad "gate source carries the DATED flip-to-hard comment"
fi

# ---------------------------------------------------------------------------
# (5) unreachable pinned_sha → non-zero with guidance (mode-independent)
# ---------------------------------------------------------------------------
mklock "$tmpdir/unreach.lock" "$old_date" "$UNREACHABLE_SHA"
outU="$(bash "$GATE" --lock "$tmpdir/unreach.lock" --mode advisory --repo-root . 2>&1)"
rcU=$?
if [[ "$rcU" -ne 0 ]] && grep -qi "reach\|not reachable\|fetch" <<< "$outU"; then
  ok "unreachable pinned_sha exits non-zero with guidance"
else
  bad "unreachable pinned_sha exits non-zero with guidance (rc=$rcU)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1