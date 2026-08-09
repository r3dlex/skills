#!/bin/bash
#
# interview_decomposition_test.sh  (northstar-autobahn-hardening, Slice 1)
#
# Pins the interview family's decomposition: `grilling` is the primitive that
# owns the interview loop, `grill-me` and `grill-with-docs` are thin wrappers
# over it, and `domain-modeling` is the sole owner of the format docs.
#
# The decomposition is what makes the loop editable in one place. Two skills
# that each carry their own copy of the loop drift apart silently — which is
# exactly what had happened: grill-with-docs held 86 lines of interview and
# format prose duplicating domain-modeling byte-for-byte.
#
#   1. `grilling` is cataloged and carries the interview loop itself.
#   2. `grill-me` and `grill-with-docs` are wrappers: short, and each names
#      `grilling` rather than restating the loop.
#   3. The format docs live only under domain-modeling — no second copy.
#   4. No skill links at the retired grill-with-docs format-doc paths.
#   5. `wayfinder` points at `grilling`, not `grill-me`.
#   6. `ubiquitous-language` is `deprecated` (domain-modeling supersedes it).
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

# A wrapper exists to delegate. Upstream's are 7 lines; allow headroom for the
# local frontmatter convention and a reference line, but not for a second loop.
WRAPPER_MAX=25

body_lines() {
  # Lines after the closing frontmatter delimiter.
  awk 'BEGIN{d=0} /^---[[:space:]]*$/{d++; next} d>=2{print}' "$1" | wc -l | tr -d ' '
}

# --- 1. grilling is the cataloged primitive ---------------------------------
GRILLING_PATH="$(python3 - <<'PY'
import json
skills = json.load(open('catalog.json', encoding='utf-8'))['skills']
match = [s for s in skills if s['name'] == 'grilling']
print(match[0]['source_path'] if len(match) == 1 else '')
PY
)"

if [[ -z "$GRILLING_PATH" ]]; then
  bad "catalog.json has exactly one grilling entry"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi
ok "catalog.json has exactly one grilling entry"

GRILLING="$GRILLING_PATH/SKILL.md"
if [[ -f "$GRILLING" ]]; then
  ok "grilling SKILL.md exists at $GRILLING_PATH"
else
  bad "grilling SKILL.md exists at $GRILLING_PATH"
  echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1
fi

# The primitive must carry the loop, not point elsewhere for it.
if grep -q "frontier" "$GRILLING"; then
  ok "grilling carries the interview loop (frontier rounds)"
else
  bad "grilling carries the interview loop (frontier rounds)"
fi

# --- 2. grill-me and grill-with-docs are wrappers over grilling -------------
for wrapper in 02-govern-plan/grill-me 02-govern-plan/grill-with-docs; do
  name="$(basename "$wrapper")"
  skill="$wrapper/SKILL.md"

  if [[ ! -f "$skill" ]]; then
    bad "$name SKILL.md exists"
    continue
  fi

  lines="$(body_lines "$skill")"
  if [[ "$lines" -le "$WRAPPER_MAX" ]]; then
    ok "$name is a wrapper ($lines body lines <= $WRAPPER_MAX)"
  else
    bad "$name is a wrapper ($lines body lines > $WRAPPER_MAX — the loop belongs in grilling)"
  fi

  if grep -q "grilling" "$skill"; then
    ok "$name delegates to grilling"
  else
    bad "$name delegates to grilling"
  fi
done

# grill-with-docs is the doc-grounded variant: it must reach domain-modeling.
if grep -q "domain-modeling" 02-govern-plan/grill-with-docs/SKILL.md; then
  ok "grill-with-docs delegates to domain-modeling"
else
  bad "grill-with-docs delegates to domain-modeling"
fi

# --- 3/4. the format docs have exactly one owner ----------------------------
for doc in ADR-FORMAT.md CONTEXT-FORMAT.md; do
  if [[ -f "01-discover-decide/domain-modeling/$doc" ]]; then
    ok "domain-modeling owns $doc"
  else
    bad "domain-modeling owns $doc"
  fi

  if [[ -e "02-govern-plan/grill-with-docs/$doc" ]]; then
    bad "grill-with-docs no longer carries a duplicate $doc"
  else
    ok "grill-with-docs no longer carries a duplicate $doc"
  fi

  # A link surviving at the retired path would resolve to nothing. Search the
  # skill tree rather than the whole repo so specs quoting history stay legal.
  stale="$(grep -rl "grill-with-docs/$doc" \
    01-discover-decide 02-govern-plan 03-configure-generate 04-validate-handoff 2>/dev/null)"
  if [[ -z "$stale" ]]; then
    ok "no skill links at the retired grill-with-docs/$doc"
  else
    bad "no skill links at the retired grill-with-docs/$doc (found: $stale)"
  fi
done

# --- 5. wayfinder points at the primitive -----------------------------------
if grep -rq "grill-me" 02-govern-plan/wayfinder; then
  bad "wayfinder points at grilling, not grill-me"
else
  ok "wayfinder points at grilling, not grill-me"
fi

# --- 6. ubiquitous-language is deprecated -----------------------------------
LIFECYCLE="$(python3 - <<'PY'
import json
skills = json.load(open('catalog.json', encoding='utf-8'))['skills']
match = [s for s in skills if s['name'] == 'ubiquitous-language']
print(match[0]['lifecycle'] if len(match) == 1 else '')
PY
)"

if [[ "$LIFECYCLE" == "deprecated" ]]; then
  ok "ubiquitous-language is deprecated (superseded by domain-modeling)"
else
  bad "ubiquitous-language is deprecated (got '${LIFECYCLE:-<missing>}')"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
