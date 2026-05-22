#!/usr/bin/env bash
# sync-upstream.sh — DESIGN PATTERN (not a working script)
# Future implementation guide for syncing with mattpocock/skills upstream.
#
# Pseudocode:
#   1. Fetch the current HEAD SHA from upstream:
#        UPSTREAM_SHA=$(git ls-remote https://github.com/mattpocock/skills.git HEAD | cut -f1)
#   2. Read the pinned_sha from upstream.lock:
#        PINNED_SHA=$(grep 'pinned_sha:' upstream.lock | awk '{print $2}')
#   3. If UPSTREAM_SHA == PINNED_SHA: echo "Already up to date." && exit 0
#   4. Run git diff between pinned_sha and upstream HEAD on the remote (sparse clone or API diff):
#        Generate list of changed files since PINNED_SHA
#   5. For each changed file in .agents/skills/:
#        - Show the diff to the developer
#        - Ask: "Apply this change? [y/N]"
#        - If yes: copy the updated file into the local .agents/skills/ tree
#   6. Update upstream.lock with the new SHA and today's date.
#   7. Stage the changes for review: git add -p
#
# This script is intentionally incomplete. Upstream sync should be a deliberate
# human-reviewed process, not an automated overwrite.

echo "sync-upstream.sh is not yet implemented."
echo "See REFERENCE.md → upstream.lock Sync Procedure for the design intent."
exit 1
