#!/bin/bash
#
# codex_verification_test.sh
#
# Offline, deterministic validation of the P2 Codex parity VERIFICATION layer
# (plan P2-3, ADR-0004). NO model, network, or live Codex run is used anywhere
# in this test: every assertion is pure-shell + python3 JSON parsing.
#
# Codex parity has three bars (ADR-0004): P0/P1 are the MECHANICAL bar already
# enforced offline in CI by scripts/check-codex-parity.sh. P2 is the VERIFIED
# bar: a human runs representative skills under Codex out-of-band and records
# the transcript evidence. A live Codex run cannot happen in CI or an offline
# sandbox, so P2-3 ships:
#   1. a verification PROCEDURE doc — how to run a skill under Codex via
#      scripts/install-codex.sh, what to record, and the pass criteria; and
#   2. a RECORDED transcript-evidence artifact per representative skill,
#      clearly labelled as recorded out-of-band verification, not a CI gate.
#
# This test asserts:
#   1. the procedure doc exists, names install-codex.sh, documents what to
#      record + pass criteria, and carries the not-a-live-run disclaimer;
#   2. >=1 recorded evidence artifact exists, parses as JSON, and references a
#      REAL skill (the skill directory + SKILL.md exist on disk);
#   3. each artifact records the codex command + model and an outcome;
#   4. each artifact carries the explicit "recorded out-of-band verification,
#      not a CI gate" disclaimer and states no live run happened in CI;
#   5. the procedure doc references the evidence directory.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

PROCEDURE_DOC="$REPO_ROOT/docs/learning/codex-verification.md"
EVIDENCE_DIR="$REPO_ROOT/reference/fixtures/v3/standalone/.ai/evals/codex-verification"

DISCLAIMER="recorded out-of-band verification, not a CI gate"

echo "Codex Parity P2 Out-of-Band Verification Tests"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# 1. Procedure doc exists and is well-formed.
# -----------------------------------------------------------------------------
if [ -f "$PROCEDURE_DOC" ]; then
  ok "verification procedure doc exists"
else
  bad "verification procedure doc must exist ($PROCEDURE_DOC)"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

if grep -Fq "install-codex.sh" "$PROCEDURE_DOC"; then
  ok "procedure doc explains running a skill under Codex via install-codex.sh"
else
  bad "procedure doc must reference scripts/install-codex.sh"
fi

if grep -Fiq "what to record" "$PROCEDURE_DOC"; then
  ok "procedure doc documents what to record"
else
  bad "procedure doc must document what to record"
fi

if grep -Fiq "pass criteria" "$PROCEDURE_DOC"; then
  ok "procedure doc documents the pass criteria"
else
  bad "procedure doc must document the pass criteria"
fi

if grep -Fq "$DISCLAIMER" "$PROCEDURE_DOC"; then
  ok "procedure doc carries the not-a-live-run disclaimer"
else
  bad "procedure doc must carry the '$DISCLAIMER' disclaimer"
fi

if grep -Fq "codex-verification" "$PROCEDURE_DOC"; then
  ok "procedure doc references the recorded-evidence directory"
else
  bad "procedure doc must reference the codex-verification evidence directory"
fi

# -----------------------------------------------------------------------------
# 2. At least one recorded evidence artifact exists.
# -----------------------------------------------------------------------------
if [ -d "$EVIDENCE_DIR" ]; then
  ok "recorded-evidence directory exists"
else
  bad "recorded-evidence directory must exist ($EVIDENCE_DIR)"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

# Collect the transcript artifacts (*.transcript.json).
ARTIFACTS=()
while IFS= read -r f; do
  [ -n "$f" ] && ARTIFACTS+=("$f")
done < <(find "$EVIDENCE_DIR" -name "*.transcript.json" -type f | sort)

if [ "${#ARTIFACTS[@]}" -ge 1 ]; then
  ok "at least one recorded transcript-evidence artifact exists (${#ARTIFACTS[@]} found)"
else
  bad "at least one *.transcript.json evidence artifact must exist"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

# -----------------------------------------------------------------------------
# 3-4. Per-artifact structural checks.
# -----------------------------------------------------------------------------
for ARTIFACT in "${ARTIFACTS[@]}"; do
  rel="${ARTIFACT#$REPO_ROOT/}"

  # Parses as JSON.
  if python3 -m json.tool "$ARTIFACT" >/dev/null 2>&1; then
    ok "$rel parses as JSON"
  else
    bad "$rel must parse as JSON"
    continue
  fi

  # References a REAL skill: skill_under_test resolves to a real skill dir +
  # SKILL.md on disk.
  SKILL_OK="$(python3 - "$ARTIFACT" "$REPO_ROOT" <<'PY'
import json, os, sys
artifact, repo_root = sys.argv[1:3]
d = json.load(open(artifact))
skill = d.get("skill_under_test", "")
skill_dir = os.path.join(repo_root, skill)
skill_md = os.path.join(skill_dir, "SKILL.md")
print("yes" if skill and os.path.isdir(skill_dir) and os.path.isfile(skill_md) else "no")
PY
)"
  if [ "$SKILL_OK" = "yes" ]; then
    ok "$rel references a real skill (skill dir + SKILL.md exist)"
  else
    bad "$rel must reference a real skill whose directory and SKILL.md exist"
  fi

  # Records the codex command + model and an outcome.
  CMD_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
cmd = d.get("codex_command", "")
model = d.get("codex_model", "")
outcome = d.get("outcome", "")
ok = (isinstance(cmd, str) and cmd.strip()
      and isinstance(model, str) and model.strip()
      and isinstance(outcome, str) and outcome.strip())
# the recorded command should invoke install-codex.sh and/or codex
ok = ok and ("install-codex.sh" in cmd or "codex" in cmd)
print("yes" if ok else "no")
PY
)"
  if [ "$CMD_OK" = "yes" ]; then
    ok "$rel records the codex command, model, and an outcome"
  else
    bad "$rel must record a non-empty codex_command (codex/install-codex.sh), codex_model, and outcome"
  fi

  # Carries the explicit disclaimer + states no live run happened in CI.
  if grep -Fq "$DISCLAIMER" "$ARTIFACT"; then
    ok "$rel carries the '$DISCLAIMER' disclaimer"
  else
    bad "$rel must carry the '$DISCLAIMER' disclaimer"
  fi

  CI_OK="$(python3 - "$ARTIFACT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
blob = json.dumps(d).lower()
# must state, somewhere, that no live run happened in CI / this sandbox
print("yes" if ("no live" in blob and "ci" in blob) else "no")
PY
)"
  if [ "$CI_OK" = "yes" ]; then
    ok "$rel states no live Codex run happened in CI"
  else
    bad "$rel must state that no live Codex run happened in CI"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
