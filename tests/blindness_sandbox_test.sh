#!/bin/bash
#
# blindness_sandbox_test.sh  (TSWC B2, master intake F3 / section 6-B2)
#
# Executes the `bash blindness-sandbox` block of
# 02-govern-plan/evolution-rollout/SKILL.md against a seeded source repository,
# so the blindness procedure and its proof cannot drift: the test runs the text
# the SKILL.md ships, not a copy of it.
#
# Asserted on the real block, in a cleanup-bound temporary directory:
#   - the workload is exported and readable;
#   - a direct read of evolve/wiki/ fails (and the export carries no evolve/);
#   - a read through git history fails (the export has no .git);
#   - the export's rollout reader refuses a denied prefix and reads a workload
#     file;
# and, as negative fixtures built by rewriting the extracted text itself:
#   - with the marked path-denial line removed, a tracked wiki file survives the
#     snapshot and the direct read succeeds -> red;
#   - with the marked snapshot line replaced by a history-preserving copy, the
#     wiki is gone from the tree but `git show` still returns it -> red.
# A missing or duplicated block is red.
#
# Plain bash only: no embedded Python or other interpreter program.
#
# Discovered by tests/test-scripts.sh (find tests -name '*_test.sh') under
# tests/run-tests.sh. Exit 0 when all checks pass; non-zero otherwise.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

SKILL="02-govern-plan/evolution-rollout/SKILL.md"
FENCE='^```bash blindness-sandbox[[:space:]]*$'
CLOSE='^```[[:space:]]*$'
DENIAL_MARKER='blindness-sandbox:denial'
SNAPSHOT_MARKER='blindness-sandbox:snapshot'

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- the procedure under test ------------------------------------------------

# fences <file>: how many ```bash blindness-sandbox blocks the file carries.
fences() {
  grep -c "$FENCE" "$1" 2>/dev/null || true
}

# extract_block <file>: print the body of the one blindness-sandbox block.
extract_block() {
  awk -v fence_open="$FENCE" -v fence_close="$CLOSE" '
    $0 ~ fence_open  { inside = 1; next }
    inside && $0 ~ fence_close { inside = 0; next }
    inside { print }
  ' "$1" 2>/dev/null
}

# --- a seeded source repository ----------------------------------------------
#
# The workload is what a rollout executes; the wiki and its raw traces are what
# it must never reach. Everything below is committed, so a plain snapshot of
# HEAD would carry the wiki unless path denial removes it.

SRC="$WORK/source"
mkdir -p "$SRC/03-configure-generate/workload" "$SRC/evolve/wiki" \
         "$SRC/evolve/raw/2026-10-09T00-00-00Z" "$SRC/evolve/proposals/demo"
printf '# Workload skill\n\nRun this.\n' > "$SRC/03-configure-generate/workload/SKILL.md"
printf '{"schema_version":"1.0","skills":[{"name":"workload"}]}\n' > "$SRC/catalog.json"
printf '# wiki log\n\n- run 1 accepted\n' > "$SRC/evolve/wiki/logs.md"
printf '# skill impact\n\n- workload: tighter prompt\n' > "$SRC/evolve/wiki/skill-impact.md"
printf '{"judgment_id":"j1","verdict":"Accepted"}\n' > "$SRC/evolve/raw/2026-10-09T00-00-00Z/judgment.json"
printf 'purpose\n' > "$SRC/evolve/proposals/demo/PURPOSE.md"
if git -C "$SRC" init -q 2>/dev/null \
   && git -C "$SRC" config user.email blindness@example.invalid \
   && git -C "$SRC" config user.name blindness \
   && git -C "$SRC" add -A \
   && git -C "$SRC" commit -qm 'seed workload and wiki' 2>/dev/null; then
  ok "seeded source repository commits the workload and a tracked evolve/ wiki"
else
  bad "seeded source repository could not be built"
fi

# --- running the procedure ---------------------------------------------------

# run_export <block-text> <label>: run the text with SOURCE/EXPORT set.
run_export() {
  ( cd "$WORK" && SOURCE="$SRC" EXPORT="$WORK/export-$2" bash -euo pipefail -c "$1" ) \
    >"$WORK/$2.log" 2>&1
}

# workload_readable <export-dir>
workload_readable() {
  cat "$1/03-configure-generate/workload/SKILL.md" 2>/dev/null | grep -q 'Run this\.'
}

# direct_wiki_read_fails <export-dir>
direct_wiki_read_fails() {
  ! cat "$1/evolve/wiki/logs.md" >/dev/null 2>&1 \
    && ! cat "$1/evolve/wiki/skill-impact.md" >/dev/null 2>&1
}

# history_wiki_read_fails <export-dir>
history_wiki_read_fails() {
  ! git -C "$1" show HEAD:evolve/wiki/logs.md >/dev/null 2>&1
}

BLOCK="$(extract_block "$SKILL")"
COUNT="$(fences "$SKILL")"

if [ "$COUNT" = "1" ] && [ -n "$BLOCK" ]; then
  ok "evolution-rollout carries exactly one bash blindness-sandbox block"
else
  bad "evolution-rollout carries exactly one bash blindness-sandbox block (found ${COUNT:-0})"
fi

if [ -z "$BLOCK" ]; then
  bad "the blindness-sandbox block executes (nothing to execute)"
else
  set +e
  run_export "$BLOCK" real
  real_rc=$?
  if [ "$real_rc" -eq 0 ]; then
    ok "the extracted block runs against the seeded repository"
  else
    bad "the extracted block runs against the seeded repository (exit $real_rc)"
  fi

  EXPORT_REAL="$WORK/export-real"
  if workload_readable "$EXPORT_REAL"; then
    ok "the workload is exported and readable in the rollout tree"
  else
    bad "the workload is exported and readable in the rollout tree"
  fi

  if ! [ -e "$EXPORT_REAL/evolve" ]; then
    ok "no evolve/ directory survives in the rollout tree"
  else
    bad "no evolve/ directory survives in the rollout tree"
  fi

  if direct_wiki_read_fails "$EXPORT_REAL"; then
    ok "a direct read of evolve/wiki/ fails in the rollout tree"
  else
    bad "a direct read of evolve/wiki/ fails in the rollout tree"
  fi

  if history_wiki_read_fails "$EXPORT_REAL"; then
    ok "a read through git history fails in the rollout tree"
  else
    bad "a read through git history fails in the rollout tree"
  fi

  if [ -x "$EXPORT_REAL/bin/rollout-read" ] \
     && "$EXPORT_REAL/bin/rollout-read" "$EXPORT_REAL" 03-configure-generate/workload/SKILL.md \
        2>/dev/null | grep -q 'Run this\.'; then
    ok "the rollout reader returns a workload file"
  else
    bad "the rollout reader returns a workload file"
  fi

  set +e
  "$EXPORT_REAL/bin/rollout-read" "$EXPORT_REAL" evolve/wiki/logs.md >/dev/null 2>&1
  reader_rc=$?
  if [ "$reader_rc" -eq 3 ]; then
    ok "the rollout reader refuses the denied evolve/ prefix (exit 3)"
  else
    bad "the rollout reader refuses the denied evolve/ prefix (exit 3, got $reader_rc)"
  fi
fi

# --- negative fixture 1: path denial removed ---------------------------------
# The extracted text with its marked denial line deleted. A tracked wiki file
# then survives the snapshot, so the direct read succeeds and blindness is red.

DENIED_BLOCK="$(printf '%s\n' "$BLOCK" | grep -v "$DENIAL_MARKER")"

if [ "$DENIED_BLOCK" = "$BLOCK" ] || ! printf '%s\n' "$DENIED_BLOCK" | grep -q "$SNAPSHOT_MARKER"; then
  bad "the block marks its path-denial line for the denial-removed fixture ($DENIAL_MARKER)"
elif [ -z "$DENIED_BLOCK" ]; then
  bad "the denial-removed fixture is nonempty"
else
  set +e
  run_export "$DENIED_BLOCK" no-denial
  denial_rc=$?
  if [ "$denial_rc" -eq 0 ] && [ -f "$WORK/export-no-denial/evolve/wiki/logs.md" ] \
     && ! direct_wiki_read_fails "$WORK/export-no-denial"; then
    ok "negative fixture: denial removed, a tracked wiki file survives and the direct read succeeds (red)"
  else
    bad "negative fixture: denial removed, a tracked wiki file survives and the direct read succeeds (exit $denial_rc)"
  fi
fi

# --- negative fixture 2: history-preserving export ---------------------------
# The snapshot line replaced by a copy that keeps .git. Path denial still strips
# the wiki from the tree, so only the history read catches this export.

HISTORY_BLOCK="$(printf '%s\n' "$BLOCK" \
  | sed "s|.*$SNAPSHOT_MARKER.*|cp -R \"\$SOURCE/.\" \"\$EXPORT/\"|")"

if [ "$HISTORY_BLOCK" = "$BLOCK" ]; then
  bad "the block marks its snapshot line for the history fixture ($SNAPSHOT_MARKER)"
else
  set +e
  run_export "$HISTORY_BLOCK" history
  history_rc=$?
  if [ "$history_rc" -eq 0 ] && direct_wiki_read_fails "$WORK/export-history" \
     && ! history_wiki_read_fails "$WORK/export-history"; then
    ok "negative fixture: history-preserving export, the wiki is gone from the tree but git show returns it (red)"
  else
    bad "negative fixture: history-preserving export, the wiki is gone from the tree but git show returns it (exit $history_rc)"
  fi
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
