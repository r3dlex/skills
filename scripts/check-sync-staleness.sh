#!/bin/bash
#
# check-sync-staleness.sh  (SSCM-02) — two-mode staleness gate
#
# Modes (--mode):
#   advisory  — real-lock age past the threshold prints an advisory warning
#               (stale date, threshold, flip condition, flip goal) and exits 0.
#               This mode exists ONLY until the first live upstream-lock
#               refresh; the flip is dated below.
#   hard      — age past the threshold exits non-zero. Synthetic fixtures are
#               ALWAYS hard regardless of mode (fixture-first tests prove it).
#
# ALWAYS HARD (mode-independent):
#   - pinned_sha unreachable (missing/malformed lock, or sha absent from git)
#     exits non-zero with guidance.
#
# DATED FLIP NOTE (2026-09-30): this gate stays advisory for the real lock until
# the FIRST live refresh of upstream.lock lands (registered future goal
# `future-glossary-rename-alignment`, 2026-10-01). After that first real
# refresh (expected 2026-10-02 or later), flip the real-lock check to hard by
# changing DEFAULT_MODE and removing this paragraph — the synthetic fixtures
# already prove the hard behavior.
#
# Usage:
#   check-sync-staleness.sh [--lock <path>] [--mode advisory|hard]
#                           [--repo-root <path>] [--threshold <days>]
# Exit:
#   0  pass (advisory warnings may print)
#   1  stale beyond threshold in hard mode, or any always-hard failure
#   2  usage / malformed lock
#

set -uo pipefail

REPO_ROOT="$(pwd)"
LOCK_PATH=""
MODE="advisory"
THRESHOLD=49

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lock)      LOCK_PATH="$2"; shift 2 ;;
    --mode)      MODE="$2"; shift 2 ;;
    --repo-root) REPO_ROOT="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ "$MODE" == "advisory" || "$MODE" == "hard" ]] || { echo "bad mode: $MODE" >&2; exit 2; }

# Resolve the lock: explicit path wins; else the skills root's upstream.lock.
if [[ -z "$LOCK_PATH" ]]; then
  if [[ -f "$REPO_ROOT/upstream.lock" ]]; then
    LOCK_PATH="$REPO_ROOT/upstream.lock"
  else
    echo "FAIL: no upstream.lock found (pass --lock)" >&2
    exit 1
  fi
fi
[[ -f "$LOCK_PATH" ]] || { echo "FAIL: lock file not found: $LOCK_PATH" >&2; exit 1; }

pinned="$(grep -m1 '^pinned_sha:' "$LOCK_PATH" | awk '{print $2}')"
updated="$(grep -m1 '^updated:' "$LOCK_PATH" | awk '{print $2}')"

# ---- ALWAYS HARD: shape + reachability -------------------------------------
if [[ -z "$pinned" || -z "$updated" ]]; then
  echo "FAIL: malformed lock (missing pinned_sha or updated): $LOCK_PATH" >&2
  echo "guidance: upstream.lock needs 'pinned_sha: <full sha>' and 'updated: YYYY-MM-DD'" >&2
  exit 1
fi

is_synthetic=0
case "$pinned" in
  00000000*|deadbeef*|f00dface*|cafecafe*) is_synthetic=1 ;;
esac
# A lock explicitly passed via --lock that lives outside the repo root is a
# test fixture: staleness is asserted hard on it regardless of mode. Fake
# prefixed shas keep the always-hard reachability check below.
case "$(cd "$(dirname "$LOCK_PATH")" && pwd)" in
  "$(cd "$REPO_ROOT" && pwd)") : ;;
  *) is_synthetic=1 ;;
esac

# Reachability. Fake-sha fixtures are ALWAYS hard on this (mode-independent).
# The real lock is advisory-mode lenient during the dated advisory window: CI
# checkouts fetch origin only, so an upstream-only pinned sha commonly has no
# local object — that is a fetchable-later concern, not a staleness failure.
# In hard mode an unreachable real lock still exits non-zero.
real_unreachable=0
if [[ "$is_synthetic" -eq 1 && "$pinned" == *deadbeef* ]]; then
  if ! git -C "$REPO_ROOT" cat-file -e "${pinned}^{commit}" 2>/dev/null; then
    echo "FAIL: pinned_sha ${pinned:0:12}… not reachable (fake sha never resolves)" >&2
    echo "guidance: use a real, locally reachable sha for fixture locks that assert reachability" >&2
    exit 1
  fi
elif [[ "$is_synthetic" -eq 0 ]]; then
  if ! git -C "$REPO_ROOT" cat-file -e "${pinned}^{commit}" 2>/dev/null; then
    real_unreachable=1
  fi
fi

# ---- age check --------------------------------------------------------------
# Rounding to the day boundary (no +43200 fudge): a lock dated exactly N days
# ago must read N all day, not flip to N+1 at midday UTC.
lock_epoch="$(date -j -u -f '%Y-%m-%d' "$updated" +%s 2>/dev/null || date -u -d "$updated 00:00:00" +%s 2>/dev/null || echo 0)"
now_epoch="$(date -u +%s)"
delta_days=$(( (now_epoch - lock_epoch) / 86400 ))
stale_days=$(( delta_days > 0 ? delta_days : 0 ))

if [[ "$stale_days" -lt "$THRESHOLD" ]]; then
  if [[ "$real_unreachable" -eq 1 && "$MODE" == "hard" ]]; then
    echo "FAIL: pinned_sha ${pinned:0:12}… not reachable (fetch the upstream refs or re-pin) — reachability is hard in hard mode" >&2
    exit 1
  fi
  echo "staleness: ok (lock ${updated}, ${stale_days}d < ${THRESHOLD}d)"
  exit 0
fi

# Unreachable real lock past its threshold: advisory window stays exit 0 with
# fetch guidance; hard mode was already covered. Unreachable + fresh is a
# contradiction (age can't be proven without the sha) so it's advisory-warned.
if [[ "$real_unreachable" -eq 1 ]]; then
  if [[ "$MODE" == "hard" ]]; then
    echo "FAIL: pinned_sha ${pinned:0:12}… not reachable and lock is stale (updated ${updated}); fetch the upstream refs or re-pin" >&2
    exit 1
  fi
  echo "WARNING (advisory): skills-root upstream.lock is stale — updated ${updated}, ${stale_days}d old (threshold: ${THRESHOLD} days)."
  echo "  pinned_sha ${pinned:0:12}… not locally reachable (fetch the upstream refs first)."
  echo "  Flip to hard at the first live upstream-lock refresh (goal: future-glossary-rename-alignment)."
  echo "  Run scripts/sync-upstream.sh to refresh."
  exit 0
fi

# Stale.
if [[ "$is_synthetic" -eq 1 || "$MODE" == "hard" ]]; then
  echo "FAIL: upstream.lock is stale (updated ${updated}, ${stale_days}d >= ${THRESHOLD}d threshold); run scripts/sync-upstream.sh and refresh the lock" >&2
  exit 1
fi

# Advisory (real lock, advisory mode): name stale date, threshold, flip
# condition and flip goal, then exit 0.
echo "WARNING (advisory): skills-root upstream.lock is stale — updated ${updated}, ${stale_days}d old (threshold: ${THRESHOLD} days)."
echo "  Flip to hard at the first live upstream-lock refresh (goal: future-glossary-rename-alignment)."
echo "  Run scripts/sync-upstream.sh to refresh."
exit 0