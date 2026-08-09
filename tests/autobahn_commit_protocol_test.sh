#!/bin/bash
#
# autobahn_commit_protocol_test.sh  (northstar-autobahn-hardening, Slice 4)
#
# autobahn's per-goal sequence ran Implement -> Peer-review -> CI -> Merge with
# nothing in it that creates the PR being reviewed. The commit and PR seam was
# simply missing, which is also why the lint and CI gates (slices 5 and 6) had
# nowhere to attach.
#
# This pins that seam, and pins the replacement for the undefined noun at
# modules/review-loop.md: "local CI green" named no commands, so it could be
# satisfied by whatever the agent happened to run.
#
#   1. modules/commit-protocol.md exists and defines branch naming, one-goal
#      diff scope, glossary-conformant messages, and PR creation.
#   2. The per-goal sequence in orchestration.md includes the commit/PR step
#      before review — a PR cannot be reviewed before it exists.
#   3. "local CI green" is defined in terms of commands, not left as a noun.
#   4. The definition is fail-closed: an undetermined local suite blocks.
#   5. Commit messages are bound to the CONTEXT.md glossary rule.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PROTOCOL="04-validate-handoff/autobahn/modules/commit-protocol.md"
ORCH="04-validate-handoff/autobahn/modules/orchestration.md"
REVIEW="04-validate-handoff/autobahn/modules/review-loop.md"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

has() {
  # has <file> <label> <pattern...> — any pattern matching counts.
  local file="$1" label="$2"; shift 2
  local pattern
  for pattern in "$@"; do
    if grep -qiE "$pattern" "$file"; then ok "$label"; return; fi
  done
  bad "$label"
}

# --- 1. the protocol module ------------------------------------------------
if [[ -f "$PROTOCOL" ]]; then
  ok "modules/commit-protocol.md exists"
else
  bad "modules/commit-protocol.md exists"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

has "$PROTOCOL" "commit-protocol defines branch naming"          'branch nam|branch: |branch is named'
has "$PROTOCOL" "commit-protocol scopes the diff to one goal"    'one goal|single goal|one sliced goal'
has "$PROTOCOL" "commit-protocol requires staging explicitly"    'stage|staged'
has "$PROTOCOL" "commit-protocol binds messages to the glossary" 'glossar'
has "$PROTOCOL" "commit-protocol covers PR creation"             'creates the PR|open the PR|PR creation|create the pull request'

# --- 2. the sequence creates the PR before reviewing it ---------------------
has "$ORCH" "orchestration.md sequences a commit/PR step" 'commit|pull request|open the PR|PR'

# Order matters: a review step listed before PR creation describes reviewing a
# PR that does not exist.
if python3 - "$ORCH" <<'PY'
import re, sys
text = open(sys.argv[1], encoding='utf-8').read()
steps = re.findall(r'^\s*(\d+)\.\s+(.*)$', text, re.M)
pr = next((int(n) for n, body in steps if re.search(r'pr\b|pull request', body, re.I)), None)
review = next((int(n) for n, body in steps if re.search(r'peer-review|review', body, re.I)), None)
sys.exit(0 if pr is not None and review is not None and pr < review else 1)
PY
then
  ok "the PR is created before the review step"
else
  bad "the PR is created before the review step"
fi

# --- 3/4. "local CI green" is defined, and fails closed --------------------
has "$REVIEW" "review-loop.md defines local CI green by command" \
  'commit-protocol|local-ci|the commands|defined in'

if grep -qiE 'fail[- ]closed|never assumed|treated as not-green' "$REVIEW"; then
  ok "the local CI definition is fail-closed"
else
  bad "the local CI definition is fail-closed"
fi

# The specific hole: a repo whose local suite cannot be determined must block,
# not pass by default.
if grep -qiE 'cannot be determined|undetermined|no local suite|cannot resolve' \
   "$REVIEW" "$PROTOCOL"; then
  ok "an undeterminable local suite blocks rather than passes"
else
  bad "an undeterminable local suite blocks rather than passes"
fi

# --- 5. the glossary rule is cited, not paraphrased ------------------------
if grep -qE 'CONTEXT\.md' "$PROTOCOL"; then
  ok "commit-protocol cites CONTEXT.md as the glossary source"
else
  bad "commit-protocol cites CONTEXT.md as the glossary source"
fi

# --- codex parity on the new module ----------------------------------------
if bash scripts/check-codex-parity.sh "$PROTOCOL" >/dev/null 2>&1; then
  ok "commit-protocol.md passes codex parity"
else
  bad "commit-protocol.md passes codex parity"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
