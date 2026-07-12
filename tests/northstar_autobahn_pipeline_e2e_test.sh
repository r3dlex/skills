#!/bin/bash
#
# northstar_autobahn_pipeline_e2e_test.sh
#
# END-TO-END handshake test for the northstar -> autobahn intake->ship pipeline.
# Where northstar_handoff_test.sh proves northstar's WRITE side and the autobahn
# *_test.sh files prove autobahn's helpers in isolation, this test proves the two
# skills actually COMPOSE: artifacts northstar writes are exactly what autobahn's
# discovery gate consumes, against a throwaway init-ai-repo (a temp copy of the
# standalone fixture). It is the deterministic, offline form of the "E2E pipeline
# dry-run" — no GitHub PRs, no model, no network.
#
# Pipeline exercised, in order:
#   1. 02-govern-plan/northstar/prereq-check.sh   -> init-ai-repo present                (exit 0)
#   2. 02-govern-plan/northstar/handoff-write.sh  -> writes the A->B handoff             (exit 0)
#   3. 04-validate-handoff/autobahn/prereq-check.sh    -> DISCOVERS northstar's handoff       (exit 0)
#      + the slug autobahn discovers == the slug northstar wrote (handshake)
#   4. NEGATIVE control: a fresh init-ai-repo with NO northstar run ->
#      04-validate-handoff/autobahn/prereq-check.sh fails closed                             (exit 1)
#   5. 04-validate-handoff/autobahn/engine-pick.sh     -> selects a ship engine per goal signal
#   6. 04-validate-handoff/autobahn/merge-authority.sh -> merge decision on an approved verdict(exit 0)
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FIXTURE="$REPO_ROOT/reference/fixtures/v3/standalone"
N_PREREQ="$REPO_ROOT/02-govern-plan/northstar/prereq-check.sh"
N_HANDOFF="$REPO_ROOT/02-govern-plan/northstar/handoff-write.sh"
A_PREREQ="$REPO_ROOT/04-validate-handoff/autobahn/prereq-check.sh"
A_ENGINE="$REPO_ROOT/04-validate-handoff/autobahn/engine-pick.sh"
A_MERGE="$REPO_ROOT/04-validate-handoff/autobahn/merge-authority.sh"
VERDICT="$REPO_ROOT/reference/fixtures/v3/standalone/.ai/host-policy/verdict-approved.json"

PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

command -v python3 >/dev/null 2>&1 || { echo "python3 is required (fail-closed prerequisite)." >&2; exit 2; }
for s in "$N_PREREQ" "$N_HANDOFF" "$A_PREREQ" "$A_ENGINE" "$A_MERGE"; do
  [[ -f "$s" ]] || { bad "pipeline helper exists: $s"; echo ""; echo "Results: PASS=$PASS FAIL=$FAIL"; exit 1; }
done

tmp="$(mktemp -d)"
tmp2=""
trap 'rm -rf "$tmp" "${tmp2:-}"' EXIT
cp -R "$FIXTURE/." "$tmp/"

SLUG="rate-limit-public-api"
rc_of() { "$@" >/dev/null 2>&1; echo $?; }

# --- 1. northstar prereq gate passes on an initialized repo -------------------
rc="$(rc_of bash "$N_PREREQ" --root "$tmp")"
if [[ "$rc" -eq 0 ]]; then
  ok "1. northstar prereq-check passes on the init-ai-repo (exit 0)"
else
  bad "1. northstar prereq-check should pass on init-ai-repo (got $rc)"
fi

# --- 2. northstar writes the A->B handoff ------------------------------------
rc="$(rc_of bash "$N_HANDOFF" --root "$tmp" \
  --spec "docs/specifications/ACTIVE/intake-and-ship-skills.md" \
  --slug "$SLUG" --issue "local:work-intake/$SLUG")"
if [[ "$rc" -eq 0 ]]; then
  ok "2. northstar handoff-write produces the A->B handoff (exit 0)"
else
  bad "2. northstar handoff-write should write the handoff (got $rc)"
fi
if [[ -f "$tmp/.ai/handoff/northstar-$SLUG.md" ]]; then
  ok "2. handoff file present at .ai/handoff/northstar-$SLUG.md"
else
  bad "2. handoff file missing"
fi

# --- 3. autobahn DISCOVERS northstar's handoff (the handshake) ----------------
out="$(bash "$A_PREREQ" --root "$tmp" 2>&1)"; rc=$?
if [[ "$rc" -eq 0 ]]; then
  ok "3. autobahn prereq-check discovers the handoff northstar wrote (exit 0)"
else
  bad "3. autobahn prereq-check should discover northstar's handoff (got $rc: $out)"
fi
# The slug autobahn reports must be exactly the one northstar wrote -> the two
# skills agree on the same handoff identity (no silent mismatch).
if printf '%s' "$out" | grep -q "'$SLUG'"; then
  ok "3. autobahn discovered the SAME slug northstar wrote ('$SLUG')"
else
  bad "3. autobahn must discover northstar's slug '$SLUG' (saw: $out)"
fi

# --- 4. NEGATIVE control: init-ai-repo without a northstar run fails closed ---
tmp2="$(mktemp -d)"
cp -R "$FIXTURE/." "$tmp2/"
# Remove any pre-seeded northstar handoff so the only handoffs are ones we write.
rm -f "$tmp2/.ai/handoff/"northstar-*.md 2>/dev/null
python3 - "$tmp2/.ai/workflows/repo-workflow.json" <<'PY'
import json, sys
p = sys.argv[1]
m = json.load(open(p))
m["optional_branches"] = [b for b in m.get("optional_branches", [])
                          if not str(b.get("id", "")).startswith("northstar-handoff-")]
json.dump(m, open(p, "w"), indent=2)
PY
rc="$(rc_of bash "$A_PREREQ" --root "$tmp2")"
rm -rf "$tmp2"
if [[ "$rc" -eq 1 ]]; then
  ok "4. autobahn fails closed when no northstar handoff exists (exit 1) — discovery is real, not vacuous"
else
  bad "4. autobahn should fail closed without a handoff (got $rc)"
fi

# --- 5. autobahn picks a ship engine per goal signal -------------------------
eng_qa="$(bash "$A_ENGINE" --qa-heavy true 2>/dev/null | tail -1)"
eng_def="$(bash "$A_ENGINE" 2>/dev/null | tail -1)"
if [[ "$eng_qa" == "ultraqa" && "$eng_def" == "team" ]]; then
  ok "5. autobahn engine-pick selects per goal (qa-heavy=ultraqa, default=team)"
else
  bad "5. autobahn engine-pick mismatch (qa=$eng_qa default=$eng_def)"
fi

# --- 6. autobahn merge-authority decides on an approved verdict ---------------
rc="$(rc_of bash "$A_MERGE" --verdict "$VERDICT")"
if [[ "$rc" -eq 0 ]]; then
  ok "6. autobahn merge-authority authorizes merge on the approved verdict (exit 0)"
else
  bad "6. autobahn merge-authority should authorize merge (got $rc)"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
