#!/usr/bin/env bash
# Same pinned helper as the consumer, in canonical source or sibling-flat install.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$HERE/../autobahn/readiness-dependency.json" ]]; then
  AUTOBAHN="$HERE/../autobahn"
else
  AUTOBAHN="$HERE/../../04-validate-handoff/autobahn"
fi
python3 -B - "$HERE/readiness-dependency.json" "$AUTOBAHN/readiness-dependency.json" <<'PY'
import json, sys
try:
    if json.load(open(sys.argv[1])) != json.load(open(sys.argv[2])):
        raise ValueError('producer/consumer fingerprint mismatch')
except (OSError, ValueError) as error:
    print('dependency_failed:' + str(error), file=sys.stderr)
    sys.exit(1)
PY
# A handoff-goals/2 bundle is a readiness-contract/2 publication: planning-stage admission against
# the simulated post-merge target (origin/<target> plus this publication) before anything is written.
# Every other bundle, and any bundle that does not parse, takes the unchanged v1 path below.
bundle=""
previous=""
for arg in "$@"; do
  case "$previous" in --bundle) bundle="$arg" ;; esac
  case "$arg" in --bundle=*) bundle="${arg#--bundle=}" ;; esac
  previous="$arg"
done
if [[ -n "$bundle" && -f "$bundle" ]] && python3 -I -B -c 'import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("schema") == "handoff-goals/2" else 1)' "$bundle" 2>/dev/null; then
  exec bash "$AUTOBAHN/contract-run.sh" publish-v2 --admit-planning "$@" </dev/null
fi
exec bash "$AUTOBAHN/contract-run.sh" publish "$@"
