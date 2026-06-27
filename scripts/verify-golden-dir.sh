#!/usr/bin/env bash
# verify-golden-dir.sh -- Developer-local diff verification
# Usage: ./scripts/verify-golden-dir.sh <repo-path> <golden-dir-path>
#
# Compares the REAL repo state against the golden directory.
# The golden directory contains:
#   - Full copies of net-new files (.agents/, docs/adr/, raw/docs/, etc.)
#   - Marker-only presence checks for modified files (AGENTS.md, etc.)
#
# The developer runs init-ai-repo manually first, then runs this.
# This is NOT a CI step -- verification is developer-local.

set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <repo-path> <golden-dir-path>"
  echo "Example: $0 /path/to/skills/repo reference/golden-skills"
  exit 1
fi

REPO_PATH="$1"
GOLDEN_DIR="$2"

if [ ! -d "$GOLDEN_DIR" ]; then
  echo "FAIL: Golden directory not found: $GOLDEN_DIR"
  exit 1
fi

errors=0

echo "=== Verify Golden Dir ==="
echo "Repo:       $REPO_PATH"
echo "Golden dir: $GOLDEN_DIR"
echo ""

# --- Net-new file checks ---
# Compare all golden-dir files except .MARKER assertion files.
# EXCLUDES upstream.lock from content diff — the pinned_sha changes whenever
# upstream pushes new commits, which would cause perpetual false failures.
# upstream.lock is validated separately below (structure-only check).
echo "--- Net-new file content check ---"
for f in $(cd "$GOLDEN_DIR" && find . -type f ! -name '*.MARKER' | sort); do
  f="${f#./}"

  # Skip upstream.lock content comparison (SHA drifts)
  if [ "$f" = "upstream.lock" ]; then
    echo "SKIP: upstream.lock (SHA field excluded from content diff, validated below)"
    continue
  fi

  golden_file="$GOLDEN_DIR/$f"
  repo_file="$REPO_PATH/$f"

  if [ ! -f "$repo_file" ]; then
    echo "MISSING: $f"
    errors=$((errors + 1))
    continue
  fi

  if ! diff -q "$golden_file" "$repo_file" > /dev/null 2>&1; then
    echo "CONTENT MISMATCH: $f"
    echo "  Expected (golden) differs from actual (repo)"
    echo "  Run: diff -u \"$golden_file\" \"$repo_file\""
    errors=$((errors + 1))
  else
    echo "OK: $f"
  fi
done

# --- Marker presence checks for modified files ---
echo ""
echo "--- Modified file marker checks ---"
marker_pattern='<!-- ai-sdlc-init:start -->'

for marker_file in "AGENTS.md" "CLAUDE.md" "README.md" ".gitignore"; do
  repo_file="$REPO_PATH/$marker_file"
  if [ -f "$repo_file" ]; then
    if grep -q "$marker_pattern" "$repo_file" 2>/dev/null; then
      echo "OK: $marker_file has ai-sdlc-init marker"
    else
      echo "MISSING MARKER in $marker_file"
      echo "  Expected to find: $marker_pattern"
      echo "  The skill's step 9-11 should have inserted this marker."
      errors=$((errors + 1))
    fi
  else
    echo "NOT FOUND: $marker_file (expected modified file missing?)"
    errors=$((errors + 1))
  fi
done

# --- ci-prek.yml presence check ---
echo ""
echo "--- CI workflow check ---"
ci_file="$REPO_PATH/.github/workflows/ci-prek.yml"
if [ -f "$ci_file" ]; then
  echo "OK: ci-prek.yml exists"
else
  echo "MISSING: .github/workflows/ci-prek.yml"
  errors=$((errors + 1))
fi

# --- upstream.lock structure validation (M1 fix) ---
echo ""
echo "--- upstream.lock structure check ---"
lock_file="$REPO_PATH/upstream.lock"
if [ -f "$lock_file" ]; then
  for field in "source:" "via:" "pinned_sha:" "sync_script:"; do
    if grep -q "$field" "$lock_file" 2>/dev/null; then
      echo "OK: upstream.lock has $field"
    else
      echo "MISSING FIELD in upstream.lock: $field"
      errors=$((errors + 1))
    fi
  done
else
  echo "NOT FOUND: upstream.lock"
  errors=$((errors + 1))
fi

# --- .rules.ts structural validation check (C1 fix: uses validate-rules.sh, not prek --rules) ---
rules_file="$REPO_PATH/.rules.ts"
validator="$REPO_PATH/scripts/validate-rules.sh"
if [ -f "$rules_file" ]; then
  echo ""
  echo "--- Archgate .rules.ts structural validation ---"
  if [ -x "$validator" ]; then
    if bash "$validator" "$rules_file" &>/dev/null; then
      echo "OK: validate-rules.sh passes on .rules.ts"
    else
      echo "WARNING: validate-rules.sh failed on .rules.ts"
      echo "  Run: bash scripts/validate-rules.sh .rules.ts"
      errors=$((errors + 1))
    fi
  else
    echo "SKIP: scripts/validate-rules.sh not found or not executable"
    echo "  .rules.ts exists at: $rules_file"
  fi
else
  echo "NOT FOUND: .rules.ts"
  errors=$((errors + 1))
fi

echo ""
echo "=== Result ==="
if [ "$errors" -eq 0 ]; then
  echo "PASS: All checks passed."
  exit 0
else
  echo "FAIL: $errors check(s) failed."
  exit 1
fi
