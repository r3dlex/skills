#!/bin/bash
#
# regen-host-golden.sh — rewrite tests/fixtures/host-default-golden.json from a
# real default install.
#
# tests/host_default_golden_test.sh pins the flattened-host output byte-for-byte,
# and until now the fixture had to be reproduced by hand every time a skill
# changed. Hand-deriving a file of SHA-256s is a footgun: the obvious failure is
# a wrong hash, but the quiet one is editing the hashes a test computes so the
# test agrees with itself while the projection is wrong.
#
# This script and the test must compute the same thing. Keep the install
# invocations and the exclusion set below in step with
# tests/host_default_golden_test.sh.
#
# Usage: bash scripts/regen-host-golden.sh
#        git diff tests/fixtures/host-default-golden.json   # review before committing

set -euo pipefail
cd "$(dirname "$0")/.."

home=$(mktemp -d)
target=$(mktemp -d)/repo
trap 'rm -rf "$home" "${target%/repo}"' EXIT
mkdir -p "$target"

HOME="$home" bash scripts/install-gemini.sh --link >/dev/null
HOME="$home" bash scripts/install-auggie.sh --all >/dev/null
HOME="$home" bash scripts/install-copilot.sh --repo "$target" >/dev/null

python3 - "$home" "$target" <<'PY'
import hashlib, json, sys
from pathlib import Path

home, target = map(Path, sys.argv[1:])
roots = {
    'gemini': home / '.gemini/skills',
    'auggie': home / '.auggie/rules',
    'copilot': target / '.github',
}
golden = {
    host: {
        str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(root.rglob('*'))
        if p.is_file() and p.name not in {'catalog.json', 'skills-catalog.json'}
    }
    for host, root in roots.items()
}
Path('tests/fixtures/host-default-golden.json').write_text(json.dumps(golden, indent=2) + '\n')
print('regenerated: ' + ', '.join(f'{h}={len(v)} files' for h, v in golden.items()))
PY
