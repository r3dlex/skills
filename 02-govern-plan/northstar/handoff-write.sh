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
exec bash "$AUTOBAHN/contract-run.sh" publish "$@"
