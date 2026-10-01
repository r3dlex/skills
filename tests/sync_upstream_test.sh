#!/bin/bash
#
# sync_upstream_test.sh  (SSCM-02)
#
# Reviewed-apply sync tool (scripts/sync-upstream.sh) against a LOCAL fixture
# remote (no network):
#   - upstream HEAD == pinned_sha → prints "Already up to date", exit 0
#   - upstream ahead, dry-run → lists changes, applies NOTHING, exit 0
#   - upstream ahead, --apply -y → applies files, rewrites lock, PRESERVES
#     non-managed comment lines (S4 divergence note contract)
#
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="scripts/sync-upstream.sh"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

git init -q --bare "$tmpdir/upstream.git"
up="$tmpdir/upstream.git"
work="$tmpdir/seed"
git init -q "$work"
git -C "$work" config user.email t@t; git -C "$work" config user.name t
mkdir -p "$work/skills/engineering/x"
printf 'v0\n' > "$work/skills/engineering/x/file.md"
git -C "$work" add -A; git -C "$work" commit -qm seed0
base_sha="$(git -C "$work" rev-parse HEAD)"
git -C "$work" push -q "$up" HEAD:refs/heads/main

cut1="$tmpdir/tree1"
mkdir -p "$cut1/scripts" "$cut1/.git"
cp "$REPO_ROOT/$SYNC" "$cut1/scripts/sync-upstream.sh"
printf 'source: fixture\nvia: fixture\npinned_sha: %s\nupdated: 2026-09-01\nsync_script: scripts/sync-upstream.sh\n' "$base_sha" > "$cut1/upstream.lock"
printf '# Divergence note: must survive lock rewrite\n# Divergence note: UPSTREAM_DIVERGENCE.md — do not mass-rename.\n' >> "$cut1/upstream.lock"

# (1) up-to-date
out1="$(cd "$cut1" && git init -q && bash scripts/sync-upstream.sh --upstream "$up" --ref main 2>&1)"
if grep -q "Already up to date" <<< "$out1"; then
  ok "up-to-date upstream prints 'Already up to date'"
else
  bad "up-to-date upstream prints 'Already up to date' (got: $out1)"
fi

# (2) upstream advances; dry-run applies nothing
printf 'v1\n' > "$work/skills/engineering/x/file.md"
printf 'new\n' > "$work/skills/engineering/x/added.md"
git -C "$work" add -A; git -C "$work" commit -qm seed1
git -C "$work" push -q "$up" HEAD:refs/heads/main
lock_before="$(cat "$cut1/upstream.lock")"
out2="$(cd "$cut1" && bash scripts/sync-upstream.sh --upstream "$up" --ref main --dry-run 2>&1)"
rc2=$?
if [[ "$rc2" -eq 0 ]] && grep -q "dry-run complete: 0 applied" <<< "$out2" \
   && [[ "$(cat "$cut1/upstream.lock")" == "$lock_before" ]] \
   && [[ ! -f "$cut1/engineering/x/added.md" ]]; then
  ok "dry-run lists changes, applies nothing, lock untouched"
else
  bad "dry-run lists changes, applies nothing, lock untouched (rc=$rc2)"
fi

# (3) --apply -y applies + rewrites lock + preserves comments
out3="$(cd "$cut1" && bash scripts/sync-upstream.sh --upstream "$up" --ref main --apply -y 2>&1)"
rc3=$?
new_sha="$(git -C "$work" rev-parse HEAD)"
lock_now="$(cat "$cut1/upstream.lock")"
if [[ "$rc3" -eq 0 ]] \
   && [[ -f "$cut1/engineering/x/added.md" ]] && [[ "$(cat "$cut1/engineering/x/file.md")" == "v1" ]] \
   && grep -q "pinned_sha: $new_sha" <<< "$lock_now" \
   && grep -qF "# Divergence note: UPSTREAM_DIVERGENCE.md — do not mass-rename." <<< "$lock_now"; then
  ok "apply lands files; lock updated with comments preserved"
else
  bad "apply lands files; lock updated with comments preserved (rc=$rc3)"
fi

# (4) second run after refresh → up to date
out4="$(cd "$cut1" && bash scripts/sync-upstream.sh --upstream "$up" --ref main 2>&1)"
if grep -q "Already up to date" <<< "$out4"; then
  ok "post-refresh run is up to date"
else
  bad "post-refresh run is up to date (got: $out4)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
