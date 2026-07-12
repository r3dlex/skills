#!/bin/bash
#
# command_surface_schema_test.sh  (PR-1, N5a/N5b; C2)
#
# Validates the command-surface schema designed once in
# 02-govern-plan/northstar/modules/command-surface.md and the generated northstar entries:
#   - .ai/commands/omx/northstar.json and .ai/commands/omc/northstar.json
#     (in the standalone fixture root) parse as JSON
#   - both carry the required fields: name, surface, skill, invocation, args,
#     description, delegates_to
#   - surface matches the directory (omx | omc)
#   - the omx invocation uses the $<name> form; the omc invocation uses the
#     /oh-my-claudecode:<name> form; both point at the same skill
#   - the schema is documented in the module and cross-referenced from
#     03-configure-generate/ai-catapult-init/modules/phases/README.md
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

FIXTURE="reference/fixtures/v3/standalone"
PASS=0
FAIL=0
ok()  { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

omx="$FIXTURE/.ai/commands/omx/northstar.json"
omc="$FIXTURE/.ai/commands/omc/northstar.json"

for f in "$omx" "$omc"; do
  if [[ -f "$f" ]] && python3 -m json.tool "$f" >/dev/null 2>&1; then
    ok "command surface parses: $f"
  else
    bad "command surface parses: $f"
  fi
done

python3 - "$omx" "$omc" <<'PY'
import json, sys
omx_path, omc_path = sys.argv[1], sys.argv[2]
required = {"name","surface","skill","invocation","args","description","delegates_to"}
errs = []
def load(p):
    try:
        return json.load(open(p))
    except Exception as e:
        errs.append(f"load {p}: {e}"); return {}
omx = load(omx_path); omc = load(omc_path)
for label, doc, surface in (("omx", omx, "omx"), ("omc", omc, "omc")):
    missing = required - set(doc)
    if missing:
        errs.append(f"{label} missing fields: {sorted(missing)}")
    if doc.get("surface") != surface:
        errs.append(f"{label} surface != {surface}: {doc.get('surface')}")
    if doc.get("name") != "northstar":
        errs.append(f"{label} name != northstar")
    if doc.get("skill") != "northstar":
        errs.append(f"{label} skill != northstar")
# invocation form difference
if omx.get("invocation") != "$northstar":
    errs.append(f"omx invocation must be $northstar, got {omx.get('invocation')!r}")
if omc.get("invocation") != "/oh-my-claudecode:northstar":
    errs.append(f"omc invocation must be /oh-my-claudecode:northstar, got {omc.get('invocation')!r}")
if omx.get("skill") != omc.get("skill"):
    errs.append("omx and omc must point at the same skill")
if errs:
    print("\n".join(errs), file=sys.stderr); sys.exit(1)
print("schema-ok")
PY
if [[ $? -eq 0 ]]; then
  ok "northstar omx/omc entries carry required fields; invocation forms differ"
else
  bad "northstar omx/omc schema validation"
fi

# schema documented + cross-referenced
MODULE="02-govern-plan/northstar/modules/command-surface.md"
for needle in "name" "surface" "invocation" "delegates_to" '$northstar' "/oh-my-claudecode:northstar"; do
  if grep -qF -- "$needle" "$MODULE" 2>/dev/null; then
    ok "command-surface module documents '$needle'"
  else
    bad "command-surface module documents '$needle'"
  fi
done

if grep -q "command-surface" 03-configure-generate/ai-catapult-init/modules/phases/README.md 2>/dev/null; then
  ok "init-ai-repo phases README cross-references the command-surface schema"
else
  bad "init-ai-repo phases README cross-references the command-surface schema"
fi

# --- autobahn entries reuse the same shared schema (PR-2, A5) -----------------
a_omx="$FIXTURE/.ai/commands/omx/autobahn.json"
a_omc="$FIXTURE/.ai/commands/omc/autobahn.json"

for f in "$a_omx" "$a_omc"; do
  if [[ -f "$f" ]] && python3 -m json.tool "$f" >/dev/null 2>&1; then
    ok "command surface parses: $f"
  else
    bad "command surface parses: $f"
  fi
done

python3 - "$a_omx" "$a_omc" <<'PY'
import json, sys
omx_path, omc_path = sys.argv[1], sys.argv[2]
required = {"name","surface","skill","invocation","args","description","delegates_to"}
errs = []
def load(p):
    try:
        return json.load(open(p))
    except Exception as e:
        errs.append(f"load {p}: {e}"); return {}
omx = load(omx_path); omc = load(omc_path)
for label, doc, surface in (("omx", omx, "omx"), ("omc", omc, "omc")):
    missing = required - set(doc)
    if missing:
        errs.append(f"{label} missing fields: {sorted(missing)}")
    if doc.get("surface") != surface:
        errs.append(f"{label} surface != {surface}: {doc.get('surface')}")
    if doc.get("name") != "autobahn":
        errs.append(f"{label} name != autobahn")
    if doc.get("skill") != "autobahn":
        errs.append(f"{label} skill != autobahn")
if omx.get("invocation") != "$autobahn":
    errs.append(f"omx invocation must be $autobahn, got {omx.get('invocation')!r}")
if omc.get("invocation") != "/oh-my-claudecode:autobahn":
    errs.append(f"omc invocation must be /oh-my-claudecode:autobahn, got {omc.get('invocation')!r}")
if omx.get("skill") != omc.get("skill"):
    errs.append("omx and omc must point at the same skill")
if errs:
    print("\n".join(errs), file=sys.stderr); sys.exit(1)
print("schema-ok")
PY
if [[ $? -eq 0 ]]; then
  ok "autobahn omx/omc entries carry required fields; invocation forms differ"
else
  bad "autobahn omx/omc schema validation"
fi

A_MODULE="04-validate-handoff/autobahn/modules/command-surface.md"
for needle in '$autobahn' "/oh-my-claudecode:autobahn"; do
  if grep -qF -- "$needle" "$A_MODULE" 2>/dev/null; then
    ok "autobahn command-surface module documents '$needle'"
  else
    bad "autobahn command-surface module documents '$needle'"
  fi
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
