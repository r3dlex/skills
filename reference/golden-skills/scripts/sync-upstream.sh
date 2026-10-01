#!/usr/bin/env bash
#
# sync-upstream.sh  (SSCM-02) — reviewed-apply upstream sync (replaces the stub)
#
# Flow:
#   1. Read upstream.lock (pinned_sha, updated).
#   2. Fetch upstream (or the fork of record when upstream is not configured).
#   3. List files in the sync scope (skills/ subtree) changed since pinned_sha.
#   4. For each changed file: show the diff and prompt "Apply this change? [y/N].
#   5. Copy applied files into the local tree.
#   6. Rewrite upstream.lock with the new sha + today's date, PRESERVING any
#      divergence comment block (see UPSTREAM_DIVERGENCE.md — never regenerate
#      it away; never mass-rename CONTEXT.md references during apply).
#   7. Print a summary for the review/commit step (stage explicitly, per
#      commit-protocol).
#
# Safety:
#   - Non-interactive default is --dry-run (prints the plan, applies nothing).
#   - Applies happen into the worktree only; the commit is human-reviewed.
#   - Upstream references to GLOSSARY.md land as-is (documented divergence);
#     this script must not rewrite them.
#
# Usage:
#   sync-upstream.sh [--dry-run] [--upstream <git-url>] [--ref <ref>] [-y]
# Exit:
#   0  nothing to apply, or applied successfully
#   1  fetch/reachability failure, or aborted by user
#   2  usage / malformed lock
#

set -uo pipefail

UPSTREAM_URL="https://github.com/mattpocock/skills.git"
REF=""
ASSUME_YES=0
DRY_RUN=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --apply)   DRY_RUN=0; shift ;;
    --upstream) UPSTREAM_URL="$2"; shift 2 ;;
    --ref)     REF="$2"; shift 2 ;;
    -y)        ASSUME_YES=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

[[ -f upstream.lock ]] || { echo "FAIL: upstream.lock not found" >&2; exit 2; }
pinned="$(grep -m1 '^pinned_sha:' upstream.lock | awk '{print $2}')"
[[ -n "$pinned" ]] || { echo "FAIL: upstream.lock missing pinned_sha" >&2; exit 2; }

if [[ -n "$REF" ]]; then
  target="$(git ls-remote "$UPSTREAM_URL" "$REF" | awk '{print $1}')"
else
  target="$(git ls-remote "$UPSTREAM_URL" HEAD | awk '{print $1}')"
fi
[[ -n "$target" ]] || { echo "FAIL: could not resolve upstream ref at $UPSTREAM_URL" >&2; exit 1; }

if [[ "$target" == "$pinned" ]]; then
  echo "Already up to date (pinned_sha ${pinned:0:12}…)."
  exit 0
fi

# Fetch into a throwaway local mirror so no shared ref names are touched.
MIRROR="$(mktemp -d)"
trap 'rm -rf "$MIRROR"' EXIT
git init -q --bare "$MIRROR/m.git" || exit 1
git -C "$MIRROR/m.git" fetch -q "$UPSTREAM_URL" "+refs/heads/*:refs/heads/*" || {
  echo "FAIL: fetch from $UPSTREAM_URL failed" >&2; exit 1;
}

# Reachable pinned sha is a hard precondition (staleness gate enforces it too).
if ! git -C "$MIRROR/m.git" cat-file -e "${pinned}^{commit}" 2>/dev/null; then
  echo "FAIL: pinned_sha ${pinned:0:12}… not reachable (not in upstream history or not fetched)" >&2
  echo "guidance: fetch the upstream refs or re-pin to a reachable sha" >&2
  exit 1
fi

# File list in scope: the skills/ subtree (upstream layout), computed from the
# fetched objects without touching the worktree.
changed=()
while IFS= read -r -d '' f; do
  changed+=("$f")
done < <(git -C "$MIRROR/m.git" diff -z --name-only --diff-filter=ACMR "$pinned" "$target" -- skills/ 2>/dev/null)

if [[ "${#changed[@]}" -eq 0 ]]; then
  echo "Already up to date (no skills/ changes since ${pinned:0:12}…)."
  exit 0
fi

echo "Upstream target: ${target:0:12}… (${#changed[@]} changed file(s) under skills/)"
applied=0
skipped=0
for f in "${changed[@]}"; do
  echo ""
  echo "--- $f ---"
  git -C "$MIRROR/m.git" diff --stat "$pinned" "$target" -- "$f"
  git -C "$MIRROR/m.git" diff "$pinned" "$target" -- "$f" | head -80
  local_dest="${f#skills/}"
  if [[ "$DRY_RUN" -eq 1 ]]; then
    echo "[dry-run] would apply to $local_dest"
    skipped=$((skipped + 1))
    continue
  fi
  if [[ "$ASSUME_YES" -eq 0 ]]; then
    printf 'Apply this change? [y/N] '
    read -r answer
    case "$answer" in
      [yY]*) : ;;
      *) echo "[skip] $f"; skipped=$((skipped + 1)); continue ;;
    esac
  fi
  mkdir -p "$(dirname "$local_dest")"
  git -C "$MIRROR/m.git" show "$target:$f" > "$local_dest" || { echo "FAIL: blob extract for $f" >&2; exit 1; }
  applied=$((applied + 1))
  echo "[applied] $local_dest"
done

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo ""
  echo "dry-run complete: 0 applied, ${skipped} pending. Re-run with --apply (interactive) to apply."
  exit 0
fi

if [[ "$applied" -gt 0 ]]; then
  today="$(date -u +%Y-%m-%d)"
  # Rewrite the lock, PRESERVING lines we do not manage (e.g. the divergence
  # comment from S4/#77): update pinned_sha/updated in place, keep the rest.
  tmp="$(mktemp)"
  while IFS= read -r line; do
    case "$line" in
      pinned_sha:*) echo "pinned_sha: $target" ;;
      updated:*)    echo "updated: $today" ;;
      *)            printf '%s\n' "$line" ;;
    esac
  done < upstream.lock > "$tmp"
  mv "$tmp" upstream.lock
  echo ""
  echo "lock updated: pinned_sha=${target:0:12}… updated=$today (comments preserved)"
  echo "Next: stage explicitly and commit per commit-protocol."
else
  echo "No changes applied."
fi
exit 0