#!/bin/bash
#
# delegate_contract_test.sh
#
# Delegate contract gate (northstar-autobahn-hardening, Slice 0).
#
# Three independent assertions over every command surface:
#
#   1. RESOLUTION — every name in a shipped command JSON's `delegates_to`
#      either resolves to a skill in catalog.json, or is an explicitly
#      allowlisted external plugin skill (oh-my-claudecode engines, which are
#      deliberately not cataloged here). Catches a renamed or deleted skill
#      silently breaking a delegation.
#
#   2. DOC/ARTIFACT PARITY — each skill's documented `delegates_to` in its
#      modules/command-surface.md equals the `delegates_to` actually shipped in
#      both the omc and omx command JSONs. A resolution check alone cannot see
#      an ABSENT name, which is exactly how the live `tdd` drift survived.
#
#      Comparing ONE documented array against BOTH surfaces is deliberate:
#      northstar/modules/command-surface.md promises the two files are
#      identical except `surface` and `invocation`, so a legitimate omc/omx
#      divergence in `delegates_to` SHOULD fail here and be declared first.
#
#   3. COVERAGE — every shipped command JSON has a SURFACES entry. Without
#      this, SURFACES is an allowlist rather than an enumeration and a newly
#      added command JSON is silently unchecked — the same blind spot as (2),
#      one level up.
#
# Authoritative side is the SHIPPED JSON: the doc is corrected to match it, so a
# delegation is documented only once autobahn genuinely performs it.
#
# Fail-closed throughout: a parse error anywhere is a FAIL, never a silent pass.
#
# Offline, deterministic, no model/network.
#

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1

PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); echo "  PASS: $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

FIXTURE="reference/fixtures/v3/standalone/.ai/commands"

# skill:module-path pairs. Kept explicit rather than discovered — check-root-discovery
# forbids globbing for SKILL.md, and assertion 3 below reconciles this list against
# what is actually shipped, so an added surface cannot slip past unchecked.
SURFACES=(
  "autobahn:04-validate-handoff/autobahn/modules/command-surface.md"
  "northstar:02-govern-plan/northstar/modules/command-surface.md"
)

# External plugin skills that are intentionally NOT in this repo's catalog.
# They ship with oh-my-claudecode / oh-my-codex. Listing them here converts a
# silent cross-repo dependency into a declared one.
EXTERNAL_ALLOWLIST="ultragoal team ralph ultrawork ultraqa deep-interview ralplan"

echo "delegate_contract_test: resolution + doc/artifact parity + coverage"

# --- catalog parsed ONCE, fail closed if unreadable -------------------------
# Parsing per-surface let a broken catalog.json empty the resolution result and
# take the "no unresolved names" branch, disabling assertion 1 while the suite
# stayed green. Resolve it here so that failure is loud and happens once.
CATALOG_NAMES="$(python3 - catalog.json <<'PY'
import json, sys
print(" ".join(sorted(s["name"] for s in json.load(open(sys.argv[1], encoding="utf-8"))["skills"])))
PY
)"
if [[ $? -ne 0 || -z "$CATALOG_NAMES" ]]; then
  bad "catalog.json unreadable or has no skills — resolution check cannot run"
  echo ""
  echo "Results: PASS=$PASS FAIL=$FAIL"
  exit 1
fi

for entry in "${SURFACES[@]}"; do
  skill="${entry%%:*}"
  module="${entry#*:}"

  if [[ ! -f "$module" ]]; then
    bad "$skill: module not found at $module"
    continue
  fi

  # --- documented delegates_to (from the fenced JSON example(s) in the module) ---
  # findall, not search: if a module ever documents both surfaces, every example
  # must agree, and we must not silently assert against whichever came first.
  documented="$(python3 - "$module" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
matches = re.findall(r'"delegates_to"\s*:\s*(\[[^\]]*\])', text)
values = {json.dumps(sorted(json.loads(m))) for m in matches}
print(values.pop() if len(values) == 1 else "")
PY
)"
  rc=$?

  if [[ "$rc" -ne 0 ]]; then
    bad "$skill: failed to parse delegates_to from $module"
    continue
  fi
  if [[ -z "$documented" ]]; then
    bad "$skill: no delegates_to array in $module, or documented examples disagree"
    continue
  fi

  for surface in omc omx; do
    json="$FIXTURE/$surface/$skill.json"

    if [[ ! -f "$json" ]]; then
      bad "$skill/$surface: command JSON not found at $json"
      continue
    fi

    # One parse emitting both facts: line 1 = sorted shipped array,
    # line 2 = space-separated names resolving to neither catalog nor allowlist.
    parsed="$(python3 - "$json" "$CATALOG_NAMES" "$EXTERNAL_ALLOWLIST" <<'PY'
import json, sys
shipped = json.load(open(sys.argv[1], encoding="utf-8")).get("delegates_to", [])
known = set(sys.argv[2].split()) | set(sys.argv[3].split())
print(json.dumps(sorted(shipped)))
print(" ".join(n for n in shipped if n not in known))
PY
)"
    rc=$?

    if [[ "$rc" -ne 0 ]]; then
      bad "$skill/$surface: failed to parse $json"
      continue
    fi

    shipped="$(printf '%s\n' "$parsed" | sed -n '1p')"
    unresolved="$(printf '%s\n' "$parsed" | sed -n '2p')"

    # --- assertion 1: resolution ---
    if [[ -z "$unresolved" ]]; then
      ok "$skill/$surface: every delegate resolves (catalog or allowlist)"
    else
      bad "$skill/$surface: unresolved delegate(s): $unresolved"
    fi

    # --- assertion 2: doc/artifact parity ---
    if [[ "$documented" == "$shipped" ]]; then
      ok "$skill/$surface: documented delegates_to matches shipped JSON"
    else
      bad "$skill/$surface: delegates_to drift
        documented ($module): $documented
        shipped    ($json): $shipped"
    fi

    # --- assertion 4: args + description parity ---
    # Slice 0 gated delegates_to only, and the deferred drift turned out to
    # matter: the doc advertised an `args` entry the shipped JSON did not offer,
    # for an input autobahn genuinely accepts. Under-claiming is as wrong as
    # over-claiming — a command with no way to pass a goal record cannot do
    # direct intake at all.
    #
    # Arg NAMES and `required` must match exactly. Per-arg `description` is
    # required to be present and non-empty in the shipped JSON but is not
    # compared, so the doc example may stay readable.
    drift="$(python3 - "$module" "$json" "$skill" <<'PY'
import json, re, sys
module, shipped_path, skill = sys.argv[1:]

blocks = re.findall(r'```json\n(.*?)\n```', open(module, encoding='utf-8').read(), re.S)
examples = []
for block in blocks:
    try:
        parsed = json.loads(block)
    except json.JSONDecodeError:
        print(f'unparseable JSON example in {module}')
        raise SystemExit(0)
    if isinstance(parsed, dict) and parsed.get('name') == skill:
        examples.append(parsed)
if not examples:
    print(f'no JSON example naming {skill} in {module}')
    raise SystemExit(0)

shipped = json.load(open(shipped_path, encoding='utf-8'))

def shape(args):
    if not isinstance(args, list):
        return None
    return [(a.get('name'), bool(a.get('required'))) for a in args if isinstance(a, dict)]

problems = []
for example in examples:
    if shape(example.get('args')) != shape(shipped.get('args')):
        problems.append(
            f"args shape drift: documented {shape(example.get('args'))} "
            f"vs shipped {shape(shipped.get('args'))}"
        )
    if example.get('description') != shipped.get('description'):
        problems.append(
            f"description drift: documented {example.get('description')!r} "
            f"vs shipped {shipped.get('description')!r}"
        )

for arg in shipped.get('args') or []:
    if not isinstance(arg, dict) or not (arg.get('description') or '').strip():
        problems.append(f"shipped arg {arg!r} has no description")

print('; '.join(problems))
PY
)"
    rc=$?
    if [[ "$rc" -ne 0 ]]; then
      bad "$skill/$surface: failed to compare args/description"
    elif [[ -z "$drift" ]]; then
      ok "$skill/$surface: documented args + description match shipped JSON"
    else
      bad "$skill/$surface: $drift"
    fi
  done
done

# --- assertion 3: coverage — every shipped command JSON is claimed by SURFACES ---
# Globbing *.json is safe: check-root-discovery only rejects discovery of SKILL.md.
known_skills=" ${SURFACES[*]%%:*} "
for surface in omc omx; do
  for json in "$FIXTURE/$surface"/*.json; do
    [[ -f "$json" ]] || continue
    name="$(basename "$json" .json)"
    if [[ "$known_skills" == *" $name "* ]]; then
      ok "$name/$surface: command JSON covered by a SURFACES entry"
    else
      bad "$name/$surface: command JSON has no SURFACES entry — delegates unchecked"
    fi
  done
done

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
