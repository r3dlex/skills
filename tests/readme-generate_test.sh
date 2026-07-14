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

CLI_FACTS=(
  --why "Use the CLI to verify one target before continuing."
  --primary-surface 'tool <command>'
  --mental-model "One command inspects one target and reports a deterministic result."
)
CATALOG_FACTS=(
  --why "Install reusable workflows without copying their instructions by hand."
  --primary-surface '<skill>/SKILL.md frontmatter'
  --mental-model "The host discovers metadata, then loads one matching workflow."
)
UNRESOLVED_PATTERN='@@[A-Z_]+@@|\{\{[^}]+\}\}|<(your|insert|replace)[^>]*>|content to be filled in'

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [[ "$got" == "$want" ]]; then ok "$msg (=$want)"; else bad "$msg (got=$got want=$want)"; fi
}

assert_not_grep() {
  local pattern="$1" file="$2" msg="$3"
  if grep -qE "$pattern" "$file"; then bad "$msg"; else ok "$msg"; fi
}

stat_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# -----------------------------------------------------------------------------
# Test 1: template mode produces a full README.
# -----------------------------------------------------------------------------
cd "$TMPDIR" && mkdir -p .ai/drift/readme-backups
printf 'MIT License\n' > LICENSE
printf '# Contributing\n' > CONTRIBUTING.md
printf '# Agent guidance\n' > AGENTS.md
mkdir -p docs/architecture/adr
mkdir -p docs/specifications/ACTIVE .ai/traceability
printf '# Traceability\n' > .ai/traceability/index.md
bash "$SCRIPT" --mode template --project "T1Tool" --tagline "Tagline1" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-t1tool" \
  --first-success-command "t1tool doctor" --success-evidence "prints T1Tool ready" \
  --visibility public --license MIT \
  --badges license \
  --out README.md >/dev/null
[[ -f README.md ]] && ok "template mode creates README.md" || bad "template mode did not create README.md"
grep -q "^# T1Tool" README.md && ok "template contains project name" || bad "template missing project name"
grep -q "Tagline1" README.md && ok "template contains tagline" || bad "template missing tagline"
grep -q "license-MIT" README.md && ok "template contains license badge" || bad "template missing license badge"
grep -q "## Quick Start" README.md && ok "template has Quick Start" || bad "template missing Quick Start"
grep -q "## License" README.md && ok "template has License" || bad "template missing License"
grep -q "## Community" README.md && ok "template has Community" || bad "template missing Community"
grep -q "AI-SDLC:start" README.md && ok "template has AI-SDLC marker" || bad "template missing AI-SDLC marker"
[[ "$(stat_mode README.md)" == "644" ]] && ok "new template uses normal 0644 mode" || bad "new template uses normal 0644 mode"
for governance_link in \
  '[AGENTS.md](AGENTS.md)' \
  '[CONTRIBUTING.md](CONTRIBUTING.md)' \
  '[docs/architecture/adr/](docs/architecture/adr/)' \
  '[docs/specifications/](docs/specifications/)' \
  '[.ai/traceability/](.ai/traceability/)'; do
  grep -Fq "$governance_link" README.md \
    && ok "template governance links $governance_link" \
    || bad "template governance links $governance_link"
done
grep -q "star-history" README.md && bad "template should omit unverifiable star history" || ok "template omits unverifiable star history"

# Generated onboarding must be complete rather than a form the reader has to finish.
assert_not_grep "$UNRESOLVED_PATTERN" README.md \
  "template contains no unresolved placeholders or filler"

quick_start=$(awk '
  /^## Quick Start$/ { in_section=1; next }
  in_section && /^## / { exit }
  in_section { print }
' README.md)
if printf '%s\n' "$quick_start" | grep -qE '^[[:space:]]*[^#`[:space:]].*$'; then
  ok "Quick Start contains an executable command"
else
  bad "Quick Start contains an executable command"
fi

grep -qiE '(expected|verify|success).*(result|output|evidence)|result.*(expected|success)' README.md \
  && ok "template states observable first-success evidence" \
  || bad "template states observable first-success evidence"

# Bash 5 patsub_replacement must not reinterpret ampersands in user content.
bash5_bin="${README_TEST_BASH5:-}"
if [[ -z "$bash5_bin" && "${BASH_VERSINFO[0]}" -ge 5 ]]; then
  bash5_bin="$(command -v bash)"
fi
if [[ -n "$bash5_bin" ]]; then
  mkdir -p "$TMPDIR/bash5-ampersand" && cd "$TMPDIR/bash5-ampersand"
  ampersand_command='./setup.sh && ./doctor.sh'
  "$bash5_bin" -O patsub_replacement "$SCRIPT" --mode template \
    --project "Ampersand Tool" --tagline "Preserves shell commands." \
    --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-ampersand" \
    --first-success-command "$ampersand_command" --success-evidence "prints ready" \
    --out README.md >/dev/null
  grep -Fqx "$ampersand_command" README.md \
    && ok "Bash 5 preserves first-success command byte-for-byte" \
    || bad "Bash 5 preserves first-success command byte-for-byte"
else
  ok "Bash 5 ampersand regression skipped when Bash 5 is unavailable"
fi

# Dynamic proof badges cannot be synthesized from static passing/latest/100% claims.
mkdir -p "$TMPDIR/invented-proof" && cd "$TMPDIR/invented-proof"
set +e
bash "$SCRIPT" --mode template --project "ProofTool" --tagline "Proof" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-proof" \
  --first-success-command "proof doctor" --success-evidence "prints ready" \
  --visibility public --badges build,release,coverage,downloads \
  --out README.md >/dev/null 2>&1
ec=$?
set -e
if [[ "$ec" -ne 0 ]] || ! grep -qE 'CI-passing|release-latest|coverage-100%25|downloads-monthly' README.md; then
  ok "generator does not invent dynamic proof badges"
else
  bad "generator does not invent dynamic proof badges"
fi

cd "$TMPDIR"

# -----------------------------------------------------------------------------
# Test 2: template refuses to overwrite without --force.
# -----------------------------------------------------------------------------
set +e
bash "$SCRIPT" --mode template --project "T2" --tagline "Second tool" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-t2" \
  --first-success-command "t2 doctor" --success-evidence "prints ready" \
  --out README.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "1" "template refuses to overwrite existing file without --force"

force_source_sha=$(sha256_file README.md)
bash "$SCRIPT" --mode template --project "T2" --tagline "Second tool" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-t2" \
  --first-success-command "t2 doctor" --success-evidence "prints ready" \
  --source-sha "$force_source_sha" --out README.md --force >/dev/null
ok "template --force overwrites"

# -----------------------------------------------------------------------------
# Test 3: audit-only mode emits a manifest without modifying README.
# -----------------------------------------------------------------------------
sha_before=$(sha256_file README.md)
bash "$SCRIPT" --mode audit-only --out README.md >/dev/null
sha_after=$(sha256_file README.md)
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
chmod 640 existing.md

wc -c existing.md | awk '{ if ($1 < 600) exit 1 }' && ok "fixture existing.md exceeds sparse threshold" || bad "fixture existing.md is too small"

set +e
existing_sha=$(sha256_file existing.md)
bash "$SCRIPT" --mode augment --project "Existing" --tagline "Existing tool tagline" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-existing" \
  --first-success-command "existing doctor" --success-evidence "prints ready" \
  --source-sha "$existing_sha" --out existing.md >/dev/null 2>&1
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
grep -q "## How it works" existing.md && ok "augment adds mental model" || bad "augment did not add mental model"
grep -q "AI-SDLC:start" existing.md && ok "augment adds governance block" || bad "augment did not add governance block"
for governance_link in \
  '[AGENTS.md](AGENTS.md)' \
  '[CONTRIBUTING.md](CONTRIBUTING.md)' \
  '[docs/architecture/adr/](docs/architecture/adr/)' \
  '[docs/specifications/](docs/specifications/)' \
  '[.ai/traceability/](.ai/traceability/)'; do
  grep -Fq "$governance_link" existing.md \
    && ok "augment governance links $governance_link" \
    || bad "augment governance links $governance_link"
done
[[ "$(stat_mode existing.md)" == "640" ]] \
  && ok "augment preserves existing README mode" \
  || bad "augment preserves existing README mode"

# Check that backup/audit manifest were emitted.
ls .ai/drift/readme-backups/README-*.bak >/dev/null 2>&1 && ok "augment emitted backup" || bad "augment did not emit backup"
ls .ai/drift/readme-backups/audit-*.json >/dev/null 2>&1 && ok "augment emitted audit manifest" || bad "augment did not emit audit manifest"

# -----------------------------------------------------------------------------
# Test 5: is_sparse refuses augment and points user to template.
# -----------------------------------------------------------------------------
echo "stub" > sparse.md
set +e
bash "$SCRIPT" --mode augment --project "Sparse" --tagline "Sparse tool" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-sparse" \
  --first-success-command "sparse doctor" --success-evidence "prints ready" \
  --out sparse.md >/dev/null 2>&1
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
fake_sha=$(sha256_file fake-badges.md)
bash "$SCRIPT" --mode augment --project "Fake" --tagline "Fake project" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-fake" \
  --first-success-command "fake doctor" --success-evidence "prints ready" \
  --visibility public --source-sha "$fake_sha" --out fake-badges.md 2>&1 >/dev/null
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
public_sha=$(sha256_file public-private-leak.md)
bash "$SCRIPT" --mode augment --project "Public" --tagline "Public project" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-public" \
  --first-success-command "public doctor" --success-evidence "prints ready" \
  --visibility public --source-sha "$public_sha" --out public-private-leak.md 2>&1 >/dev/null
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
private_sha=$(sha256_file private-with-public-leak.md)
bash "$SCRIPT" --mode augment --project "Private" --tagline "Private project" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-private" \
  --first-success-command "private doctor" --success-evidence "prints ready" \
  --visibility private --source-sha "$private_sha" --out private-with-public-leak.md 2>&1 >/dev/null
ec=$?
set -e
assert_eq "$ec" "3" "guard rejects public proof signal in private visibility (exit 3)"

# -----------------------------------------------------------------------------
# Test 9: private visibility template does not include star-history.
# -----------------------------------------------------------------------------
cd "$TMPDIR" && mkdir -p sub && cd sub
bash "$SCRIPT" --mode template --project "Priv" --tagline "Private tool" \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-priv" \
  --first-success-command "priv doctor" --success-evidence "prints ready" \
  --visibility private --out README.md >/dev/null
grep -q "star-history" README.md && bad "private template should not include star-history" || ok "private template excludes star-history"
grep -q "public-contributors" README.md && bad "private template should not include public-contributors" || ok "private template excludes public-contributors"
grep -q "AI-SDLC:start" README.md \
  && bad "template should omit governance block when no governance surfaces exist" \
  || ok "template omits governance block when no governance surfaces exist"

# CLAUDE.md is the documented fallback when AGENTS.md is absent.
mkdir -p "$TMPDIR/claude-only" && cd "$TMPDIR/claude-only"
printf '# Claude guidance\n' > CLAUDE.md
bash "$SCRIPT" --mode template --project "Claude Only" --tagline "Uses the available governance surface." \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-claude-only" \
  --first-success-command "claude-only doctor" --success-evidence "prints ready" \
  --visibility private --out README.md >/dev/null
grep -Fq '[CLAUDE.md](CLAUDE.md)' README.md \
  && ok "template governance falls back to CLAUDE.md" \
  || bad "template governance falls back to CLAUDE.md"
grep -Fq '[AGENTS.md](AGENTS.md)' README.md \
  && bad "CLAUDE-only governance must not invent AGENTS.md" \
  || ok "CLAUDE-only governance does not invent AGENTS.md"

# -----------------------------------------------------------------------------
# Test 10: skill-catalog archetype explains discovery without placeholders.
# -----------------------------------------------------------------------------
mkdir -p "$TMPDIR/skill-catalog" && cd "$TMPDIR/skill-catalog"
bash "$SCRIPT" --mode template --project "Agent Skills" --tagline "Reusable agent workflows." \
  --archetype skill-catalog "${CATALOG_FACTS[@]}" --install-command "./install-skills.sh" \
  --first-success-command 'agent "$diagnose example failure"' \
  --success-evidence "the agent loads diagnose/SKILL.md" --out README.md >/dev/null
grep -q '^\*\*Skill discovery surface:\*\* <skill>/SKILL.md frontmatter$' README.md \
  && ok "skill-catalog archetype explains skill discovery" \
  || bad "skill-catalog archetype does not explain skill discovery"
assert_not_grep "$UNRESOLVED_PATTERN" README.md \
  "skill-catalog output contains no unresolved template content"

# -----------------------------------------------------------------------------
# Review regressions: canonical README output must preserve valid Markdown/HTML,
# prove repository facts, and ship with the installed ai-catapult-init skill.
# -----------------------------------------------------------------------------

# Valid HTML and Markdown autolinks are content, not unresolved placeholders.
mkdir -p "$TMPDIR/valid-markdown" && cd "$TMPDIR/valid-markdown"
set +e
bash "$SCRIPT" --mode template --project "Markup Tool" \
  --tagline 'Documents <details> safely; see <https://example.org/docs>.' \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-markup" \
  --first-success-command "markup doctor" --success-evidence "prints ready" \
  --out README.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "0" "valid HTML and autolinks survive placeholder validation"

# Canonical sections need explicit boundaries and a project-specific Why/mental model.
mkdir -p "$TMPDIR/section-boundaries" && cd "$TMPDIR/section-boundaries"
set +e
bash "$SCRIPT" --mode template --project "Boundary CLI" --tagline "Checks boundaries." \
  --why "Use it to catch malformed release inputs before publishing." \
  --archetype cli-tool --primary-surface 'boundary <command>' \
  --mental-model "Commands validate one target and emit a deterministic report." \
  --install-command "install-boundary" --first-success-command "boundary doctor" \
  --success-evidence "prints boundary ready" --out README.md >/dev/null 2>&1
ec=$?
set -e
assert_eq "$ec" "0" "CLI fixture accepts project-specific surface and mental model"
if [[ -f README.md ]]; then
  grep -q '^## Why$' README.md && grep -q '^## How it works$' README.md \
    && ok "generated Markdown sections have explicit heading boundaries" \
    || bad "generated Markdown sections have explicit heading boundaries"
  if awk '/^## Why$/{getline; getline; print; exit}' README.md | grep -Fxq "Checks boundaries."; then
    bad "Why section does not repeat the tagline literally"
  else
    ok "Why section does not repeat the tagline literally"
  fi
  grep -Fq '**Primary command surface:** boundary <command>' README.md \
    && grep -Fq '**Mental model:** Commands validate one target and emit a deterministic report.' README.md \
    && ok "CLI fixture renders its distinct command surface and mental model" \
    || bad "CLI fixture renders its distinct command surface and mental model"
fi

# Unsupported license inference must fail closed instead of trusting --license.
mkdir -p "$TMPDIR/bsd-license" && cd "$TMPDIR/bsd-license"
cat > LICENSE <<'EOF'
BSD 3-Clause License
Redistribution and use in source and binary forms, with or without modification, are permitted.
Neither the name of the copyright holder nor the names of its contributors may be used to endorse products.
EOF
set +e
bash "$SCRIPT" --mode template --project "BSD Tool" --tagline "Checks BSD." \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-bsd" \
  --first-success-command "bsd doctor" --success-evidence "prints ready" \
  --license MIT --badges license --out README.md >/dev/null 2>&1
bsd_ec=$?
set -e
assert_eq "$bsd_ec" "3" "BSD license mismatch fails closed"

mkdir -p "$TMPDIR/gpl-license" && cd "$TMPDIR/gpl-license"
cat > LICENSE <<'EOF'
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
EOF
set +e
bash "$SCRIPT" --mode template --project "GPL Tool" --tagline "Checks GPL." \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-gpl" \
  --first-success-command "gpl doctor" --success-evidence "prints ready" \
  --license Apache-2.0 --badges license --out README.md >/dev/null 2>&1
gpl_ec=$?
set -e
assert_eq "$gpl_ec" "3" "GPL license mismatch fails closed"

# Star history cannot be emitted by a deterministic offline generator.
mkdir -p "$TMPDIR/star-option" && cd "$TMPDIR/star-option"
set +e
bash "$SCRIPT" --mode template --project "Star Tool" --tagline "No unverifiable stars." \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-star" \
  --first-success-command "star doctor" --success-evidence "prints ready" \
  --visibility public --star-history "https://star-history.com/#example/tool" \
  --out README.md >/dev/null 2>&1
star_ec=$?
set -e
assert_eq "$star_ec" "1" "deterministic generator rejects star-history input"

# Forced replacement must require the reviewed source SHA and retain evidence.
mkdir -p "$TMPDIR/guarded-force" && cd "$TMPDIR/guarded-force"
printf '# Reviewed README\n\nOriginal facts.\n' > README.md
force_sha=$(sha256_file README.md)

# The Linux force path must work when coreutils sha256sum is available and
# Perl's shasum is not installed.
linux_path="$TMPDIR/linux-bin"
mkdir -p "$linux_path"
for command_name in awk cat chmod cp date dirname grep mkdir mktemp mv python3 rm sed sha256sum stat tr wc; do
  ln -s "$(command -v "$command_name")" "$linux_path/$command_name"
done
set +e
PATH="$linux_path" /bin/bash "$SCRIPT" --mode template --project "Guarded CLI" --tagline "Guarded writes." \
  --why "Protect reviewed README content from stale overwrites." \
  --archetype cli-tool --primary-surface 'guarded <command>' \
  --mental-model "A reviewed source hash gates the replacement." \
  --install-command "install-guarded" --first-success-command "guarded doctor" \
  --success-evidence "prints guarded ready" --source-sha "$force_sha" \
  --out README.md --force >/dev/null 2>&1
force_ec=$?
set -e
assert_eq "$force_ec" "0" "force succeeds with matching reviewed source SHA"
ls .ai/drift/readme-backups/README-*.bak >/dev/null 2>&1 \
  && ok "force creates a source backup" || bad "force creates a source backup"
grep -Rqs "\"source_sha256\": \"$force_sha\"" .ai/drift/readme-backups/audit-*.json \
  && ok "force audit records reviewed source SHA" || bad "force audit records reviewed source SHA"

mkdir -p "$TMPDIR/no-sha-force" && cd "$TMPDIR/no-sha-force"
printf '# Reviewed without a provider\n' > README.md
no_sha_source=$(sha256_file README.md)
no_sha_path="$TMPDIR/no-sha-bin"
mkdir -p "$no_sha_path"
for command_name in awk cat chmod cp date dirname grep mkdir mktemp mv rm sed stat tr wc; do
  ln -s "$(command -v "$command_name")" "$no_sha_path/$command_name"
done
set +e
PATH="$no_sha_path" /bin/bash "$SCRIPT" --mode template \
  --project "No SHA CLI" --tagline "Rejects unverified writes." \
  --why "Prevent guarded writes without a SHA-256 implementation." \
  --archetype cli-tool --primary-surface 'no-sha <command>' \
  --mental-model "A checksum provider gates the replacement." \
  --install-command "install-no-sha" --first-success-command "no-sha doctor" \
  --success-evidence "prints no-sha ready" --source-sha "$no_sha_source" \
  --out README.md --force >/dev/null 2>no-sha.err
no_sha_ec=$?
set -e
assert_eq "$no_sha_ec" "2" "force fails closed without a SHA-256 provider"
grep -q 'requires sha256sum or shasum' no-sha.err \
  && ok "missing SHA-256 provider reports the portability requirement" \
  || bad "missing SHA-256 provider reports the portability requirement"
grep -q '^# Reviewed without a provider$' README.md \
  && ok "missing SHA-256 provider preserves the reviewed README" \
  || bad "missing SHA-256 provider preserves the reviewed README"

cd "$TMPDIR/guarded-force"
printf '# Changed behind reviewer\n' > README.md
set +e
bash "$SCRIPT" --mode template --project "Guarded CLI" --tagline "Guarded writes." \
  --why "Protect reviewed README content from stale overwrites." \
  --archetype cli-tool --primary-surface 'guarded <command>' \
  --mental-model "A reviewed source hash gates the replacement." \
  --install-command "install-guarded" --first-success-command "guarded doctor" \
  --success-evidence "prints guarded ready" --source-sha "$force_sha" \
  --out README.md --force >/dev/null 2>&1
stale_ec=$?
set -e
assert_eq "$stale_ec" "2" "force rejects a stale reviewed source SHA"
grep -q '^# Changed behind reviewer$' README.md \
  && ok "stale SHA rejection preserves current README" \
  || bad "stale SHA rejection preserves current README"

# Augmentation applies optional facts and is also SHA-guarded.
mkdir -p "$TMPDIR/augment-facts" && cd "$TMPDIR/augment-facts"
{
  echo '# Existing Catalog'
  echo
  echo 'Repository-specific introduction.'
  for i in $(seq 1 35); do echo "Existing project fact $i remains intact for guarded augmentation and sparse classification."; done
  echo
  echo '## Features'
  echo
  echo '- stable catalog'
} > README.md
cat > LICENSE <<'EOF'
BSD 3-Clause License
Redistribution and use in source and binary forms, with or without modification, are permitted.
Neither the name of the copyright holder nor the names of its contributors may be used to endorse products.
EOF
augment_sha=$(sha256_file README.md)
set +e
bash "$SCRIPT" --mode augment --project "Existing Catalog" --tagline "Reusable workflows." \
  --why "Install only the workflows your host needs." \
  --archetype skill-catalog --primary-surface '<skill>/SKILL.md frontmatter' \
  --mental-model "The host discovers metadata, then loads one matching workflow." \
  --install-command "./install-catalog" --first-success-command 'agent "$diagnose failure"' \
  --success-evidence "loads diagnose/SKILL.md" --requirements "Git and Bash" \
  --update-command "git pull --ff-only" --license BSD-3-Clause \
  --source-sha "$augment_sha" --out README.md >/dev/null 2>&1
augment_ec=$?
set -e
assert_eq "$augment_ec" "0" "augment applies reviewed optional facts"
grep -q '^## Requirements$' README.md && grep -q 'Git and Bash' README.md \
  && ok "augment applies requirements" || bad "augment applies requirements"
grep -q '^## Update$' README.md && grep -q 'git pull --ff-only' README.md \
  && ok "augment applies update command" || bad "augment applies update command"
grep -q '^## License$' README.md && grep -q 'BSD-3-Clause' README.md \
  && ok "augment applies verified license" || bad "augment applies verified license"
grep -Fq '**Skill discovery surface:** <skill>/SKILL.md frontmatter' README.md \
  && grep -Fq '**Mental model:** The host discovers metadata, then loads one matching workflow.' README.md \
  && ok "skill-catalog fixture renders its distinct discovery model" \
  || bad "skill-catalog fixture renders its distinct discovery model"
grep -Rqs "\"source_sha256\": \"$augment_sha\"" .ai/drift/readme-backups/audit-*.json \
  && ok "augment audit records reviewed source SHA" \
  || bad "augment audit records reviewed source SHA"
augment_backup=$(find .ai/drift/readme-backups -name 'README-*.bak' -print -quit)
[[ -n "$augment_backup" && "$(sha256_file "$augment_backup")" == "$augment_sha" ]] \
  && ok "augment backup matches reviewed source SHA" \
  || bad "augment backup matches reviewed source SHA"

# A heading and unrelated success prose do not prove the supplied onboarding facts.
mkdir -p "$TMPDIR/incomplete-onboarding" && cd "$TMPDIR/incomplete-onboarding"
{
  echo '# Existing Tool'
  for i in $(seq 1 35); do echo "Existing project fact $i keeps this README non-sparse."; done
  echo
  echo '## Quick Start'
  echo
  echo '## Features'
  echo
  echo '- stable output'
  echo
  echo '## Release process'
  echo
  echo 'Expected result: the release archive is uploaded.'
} > README.md
incomplete_sha=$(sha256_file README.md)
bash "$SCRIPT" --mode augment --project "Existing Tool" --tagline "Documents exact onboarding." \
  --why "Give new users a reproducible first success." \
  --archetype cli-tool --primary-surface 'existing <command>' \
  --mental-model "Each command reports one deterministic result." \
  --install-command "install-existing-exact" --first-success-command "existing exact-doctor" \
  --success-evidence "prints exact onboarding ready" --source-sha "$incomplete_sha" \
  --out README.md >/dev/null
grep -Fq 'install-existing-exact' README.md \
  && grep -Fq 'existing exact-doctor' README.md \
  && grep -Fq 'prints exact onboarding ready' README.md \
  && ok "augment adds all supplied onboarding facts when headings and unrelated prose are incomplete" \
  || bad "augment adds all supplied onboarding facts when headings and unrelated prose are incomplete"

# Existing legal claims must agree with the detected LICENSE file.
mkdir -p "$TMPDIR/license-conflict" && cd "$TMPDIR/license-conflict"
printf 'MIT License\n' > LICENSE
{
  echo '# Conflicting License Tool'
  for i in $(seq 1 35); do echo "Existing project fact $i keeps this README non-sparse."; done
  echo
  echo '## Features'
  echo
  echo '- stable output'
  echo
  echo '## License'
  echo
  echo 'Apache-2.0'
} > README.md
conflict_sha=$(sha256_file README.md)
set +e
bash "$SCRIPT" --mode augment --project "Conflicting License Tool" --tagline "Preserves legal truth." \
  --why "Keep README license claims aligned with the repository license." \
  --archetype cli-tool --primary-surface 'conflict <command>' \
  --mental-model "The LICENSE file is the source of truth." \
  --install-command "install-conflict" --first-success-command "conflict doctor" \
  --success-evidence "prints ready" --source-sha "$conflict_sha" --out README.md \
  >/dev/null 2>&1
conflict_ec=$?
set -e
assert_eq "$conflict_ec" "3" "augment rejects a README License section that conflicts with LICENSE"
assert_eq "$(sha256_file README.md)" "$conflict_sha" "license conflict preserves the reviewed README"

# GPL boilerplate alone cannot distinguish an only license from an or-later grant.
mkdir -p "$TMPDIR/gpl-ambiguous" && cd "$TMPDIR/gpl-ambiguous"
cat > LICENSE <<'EOF'
GNU GENERAL PUBLIC LICENSE
Version 3, 29 June 2007
EOF
set +e
bash "$SCRIPT" --mode template --project "GPL Ambiguous Tool" --tagline "Avoids unsupported legal inference." \
  --archetype cli-tool "${CLI_FACTS[@]}" --install-command "install-gpl-ambiguous" \
  --first-success-command "gpl-ambiguous doctor" --success-evidence "prints ready" \
  --license GPL-3.0-only --badges license --out README.md >/dev/null 2>&1
gpl_only_ec=$?
set -e
assert_eq "$gpl_only_ec" "3" "GPL boilerplate does not infer GPL-3.0-only"

# Audit JSON must round-trip paths containing JSON-significant characters.
audit_repo="$TMPDIR/audit-\"quoted\"\\backslash"
mkdir -p "$audit_repo"
printf '# Audit Path\n' > "$audit_repo/README.md"
bash "$SCRIPT" --mode audit-only --repo "$audit_repo" --out "$audit_repo/README.md" >/dev/null
audit_manifest=$(find "$audit_repo/.ai/drift/readme-backups" -name 'audit-*.json' -print -quit)
python3 -m json.tool "$audit_manifest" >/dev/null \
  && ok "audit manifest is valid JSON for quote and backslash paths" \
  || bad "audit manifest is valid JSON for quote and backslash paths"
python3 - "$audit_manifest" "$audit_repo/README.md" <<'PY' \
  && ok "audit manifest preserves the exact source path" \
  || bad "audit manifest preserves the exact source path"
import json, sys
from pathlib import Path
manifest = json.loads(Path(sys.argv[1]).read_text())
assert manifest['source_path'] == sys.argv[2]
PY

# The canonical generator and template must ship inside the installed skill.
install_home="$TMPDIR/installed-home"
HOME="$install_home" bash "$REPO_ROOT/scripts/install-codex.sh" --skill ai-catapult-init >/dev/null
installed_skill="$install_home/.codex/skills/ai-catapult-init"
[[ -x "$installed_skill/scripts/readme-generate.sh" ]] \
  && ok "installed ai-catapult-init includes executable README generator" \
  || bad "installed ai-catapult-init includes executable README generator"
[[ -f "$installed_skill/assets/readme/template.md" ]] \
  && ok "installed ai-catapult-init includes canonical README template" \
  || bad "installed ai-catapult-init includes canonical README template"

# The repository onboarding itself must be cloneable without SSH credentials.
grep -q '^git clone https://github.com/r3dlex/skills.git$' "$REPO_ROOT/README.md" \
  && ok "repository Quick Start uses HTTPS clone" \
  || bad "repository Quick Start uses HTTPS clone"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
