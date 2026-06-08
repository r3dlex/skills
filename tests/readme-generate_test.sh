#!/bin/bash
#
# readme-generate_test.sh
# Tests for scripts/readme-generate.sh:
#   - template mode produces a full README from the template
#   - audit-only mode emits a manifest
#   - augment mode appends missing sections to existing READMEs
#   - is_sparse classifier: missing file, size <600, no catalogue headings
#   - proof-signal guard rejects fake badges and private leakage in public READMEs
#   - private visibility suppresses public proof signals
#
# Exit 0 on all pass, non-zero on any failure.
#

set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/readme-generate.sh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then ok "$msg (=$want)"; else bad "$msg (got=$got want=$want)"; fi
}

# -----------------------------------------------------------------------------
# Test 1: template mode produces a full README.
# -----------------------------------------------------------------------------
cd "$TMPDIR" && mkdir -p .ai/drift/readme-backups
bash "$SCRIPT" --mode template --project "T1Tool" --tagline "Tagline1" \
  --visibility public --license MIT \
  --badges license,build,release \
  --star-history "https://star-history.com/#t1tool" \
  --out README.md >/dev/null
[[ -f README.md ]] && ok "template mode creates README.md" || bad "template mode did not create README.md"
grep -q "^# T1Tool" README.md && ok "template contains project name" || bad "template missing project name"
grep -q "Tagline1" README.md && ok "template contains tagline" || bad "template missing tagline"
grep -q "license-MIT" README.md && ok "template contains license badge" || bad "template missing license badge"
grep -q "## Quick Start" README.md && ok "template has Quick Start" || bad "template missing Quick Start"
grep -q "## License" README.md && ok "template has License" || bad "template missing License"
grep -q "## Community" README.md && ok "template has Community" || bad "template missing Community"
grep -q "AI-SDLC:start" README.md && ok "template has AI-SDLC marker" || bad "template missing AI-SDLC marker"
grep -q "star-history.com" README.md && ok "template has star-history URL" || bad "template missing star-history URL"

# -----------------------------------------------------------------------------
# Test 2: template refuses to overwrite without --force.
# -----------------------------------------------------------------------------
set +e
bash "$SCRIPT" --mode template --project "T2" --out README.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "1" "template refuses to overwrite existing file without --force"

bash "$SCRIPT" --mode template --project "T2" --out README.md --force >/dev/null
ok "template --force overwrites"

# -----------------------------------------------------------------------------
# Test 3: audit-only mode emits a manifest without modifying README.
# -----------------------------------------------------------------------------
sha_before=$(shasum -a 256 README.md | awk '{print $1}')
bash "$SCRIPT" --mode audit-only --out README.md >/dev/null
sha_after=$(shasum -a 256 README.md | awk '{print $1}')
assert_eq "$sha_before" "$sha_after" "audit-only does not modify README"
ls .ai/drift/readme-backups/audit-*.json >/dev/null 2>&1 && ok "audit-only emits manifest" || bad "audit-only did not emit manifest"

# -----------------------------------------------------------------------------
# Test 4: is_sparse classification and augment behavior.
# -----------------------------------------------------------------------------
# Build a clearly-existing README (well over 600 bytes, with Quick start, Features, License).
{
  echo "# Existing Project"
  echo ""
  for i in $(seq 1 30); do
    echo "Filler line $i to push the file size well over the 600 byte sparse threshold so the classifier treats this as an existing README. The classifier also looks for catalogue headings like Quick start, Features, License, Community, etc."
  done
  echo ""
  echo "## Quick start"
  echo ""
  echo '```sh'
  echo "install"
  echo "run"
  echo '```'
  echo ""
  echo "## Features"
  echo ""
  echo "- one"
  echo "- two"
  echo ""
  echo "## License"
  echo ""
  echo "MIT"
} > existing.md

wc -c existing.md | awk '{ if ($1 < 600) exit 1 }' && ok "fixture existing.md exceeds sparse threshold" || bad "fixture existing.md is too small"

set +e
bash "$SCRIPT" --mode augment --out existing.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "0" "augment succeeds on existing.md"

# Check that the augmentation preserved existing sections verbatim.
grep -q "## Quick start" existing.md && ok "augment preserves Quick start" || bad "augment dropped Quick start"
grep -q "## Features" existing.md && ok "augment preserves Features" || bad "augment dropped Features"
grep -q "## License" existing.md && ok "augment preserves License" || bad "augment dropped License"

# Check that augmentation added missing required sections.
grep -q "## Why" existing.md && ok "augment adds Why section" || bad "augment did not add Why"
grep -q "## Community" existing.md && ok "augment adds Community section" || bad "augment did not add Community"
grep -q "## Workflows / mental model" existing.md && ok "augment adds Workflows section" || bad "augment did not add Workflows"

# Check that backup/audit manifest were emitted.
ls .ai/drift/readme-backups/README-*.bak >/dev/null 2>&1 && ok "augment emitted backup" || bad "augment did not emit backup"
ls .ai/drift/readme-backups/audit-*.json >/dev/null 2>&1 && ok "augment emitted audit manifest" || bad "augment did not emit audit manifest"

# -----------------------------------------------------------------------------
# Test 5: is_sparse refuses augment and points user to template.
# -----------------------------------------------------------------------------
echo "stub" > sparse.md
set +e
bash "$SCRIPT" --mode augment --out sparse.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "1" "augment refuses sparse README"

# -----------------------------------------------------------------------------
# Test 6: proof-signal guard rejects fake badges in existing README (public visibility).
# -----------------------------------------------------------------------------
{
  echo "# Fake Project"
  for i in $(seq 1 30); do
    echo "Filler line $i to push the file size well over the 600 byte sparse threshold so the classifier treats this as an existing README."
  done
  echo ""
  echo "## Quick start"
  echo ""
  echo "Run it."
  echo ""
  echo "## Features"
  echo ""
  echo "- one"
  echo ""
  echo "## License"
  echo ""
  echo "MIT"
  echo ""
  echo "[![Fake](https://img.shields.io/badge/license-fake-blue)](LICENSE)"
} > fake-badges.md
set +e
bash "$SCRIPT" --mode augment --visibility public --out fake-badges.md 2>&1 >/dev/null
ec=$?
set -e
assert_eq "$ec" "3" "guard rejects fake badge (exit 3)"

# -----------------------------------------------------------------------------
# Test 7: proof-signal guard rejects private/internal markers in public visibility.
# -----------------------------------------------------------------------------
{
  echo "# Public Project"
  for i in $(seq 1 30); do
    echo "Filler line $i to push the file size well over the 600 byte sparse threshold so the classifier treats this as an existing README."
  done
  echo ""
  echo "## Quick start"
  echo ""
  echo "Run it."
  echo ""
  echo "## Features"
  echo ""
  echo "- one"
  echo ""
  echo "## License"
  echo ""
  echo "MIT"
  echo ""
  echo "internal-only workflows documented here."
} > public-private-leak.md
set +e
bash "$SCRIPT" --mode augment --visibility public --out public-private-leak.md 2>&1 >/dev/null
ec=$?
set -e
assert_eq "$ec" "3" "guard rejects private/internal marker in public visibility (exit 3)"

# -----------------------------------------------------------------------------
# Test 8: private visibility suppresses public proof signals.
# -----------------------------------------------------------------------------
{
  echo "# Private Project"
  for i in $(seq 1 30); do
    echo "Filler line $i to push the file size well over the 600 byte sparse threshold so the classifier treats this as an existing README."
  done
  echo ""
  echo "## Quick start"
  echo ""
  echo "Run it."
  echo ""
  echo "## Features"
  echo ""
  echo "- one"
  echo ""
  echo "## License"
  echo ""
  echo "MIT"
  echo ""
  echo "Check our public contributors and star-history here."
} > private-with-public-leak.md
set +e
bash "$SCRIPT" --mode augment --visibility private --out private-with-public-leak.md 2>&1 >/dev/null
ec=$?
set -e
assert_eq "$ec" "3" "guard rejects public proof signal in private visibility (exit 3)"

# -----------------------------------------------------------------------------
# Test 9: private visibility template does not include star-history.
# -----------------------------------------------------------------------------
cd "$TMPDIR" && mkdir -p sub && cd sub
bash "$SCRIPT" --mode template --project "Priv" --visibility private --out README.md >/dev/null
grep -q "star-history" README.md && bad "private template should not include star-history" || ok "private template excludes star-history"
grep -q "public-contributors" README.md && bad "private template should not include public-contributors" || ok "private template excludes public-contributors"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
