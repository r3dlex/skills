#!/usr/bin/env bash
# Pinned local dependency only. Never search PATH or the network for a helper.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 -B - "$HERE" "$@" <<'PY'
import hashlib, json, pathlib, sys
root = pathlib.Path(sys.argv[1])
try:
    manifest = json.loads((root / 'readiness-dependency.json').read_text())
    peer = root.parent / 'northstar'
    if not peer.is_dir():
        peer = root.parent.parent / '02-govern-plan/northstar'
    if json.loads((peer / 'readiness-dependency.json').read_text()) != manifest:
        raise ValueError('producer/consumer fingerprint mismatch')
    if manifest['schema'] != 'readiness-contract/1':
        raise ValueError('unsupported helper release')
    for name, expected in manifest['files'].items():
        if name not in ('lib/readiness_contract.py', 'lib/verification.py', 'schemas/readiness-contract.json'):
            raise ValueError('unsupported helper dependency')
        if hashlib.sha256((root / name).read_bytes()).hexdigest() != expected:
            raise ValueError('helper fingerprint mismatch')
    if set(manifest['files']) != {'lib/readiness_contract.py', 'lib/verification.py', 'schemas/readiness-contract.json'}:
        raise ValueError('incomplete helper dependency')
except (OSError, KeyError, ValueError) as error:
    print(json.dumps({'error': 'dependency_failed:' + str(error), 'dispatch_authorized': False, 'execution_ready': False, 'authority_verification': 'external-required'}))
    sys.exit(1)
sys.path.insert(0, str(root / 'lib'))
import readiness_contract
sys.argv = [str(root / 'lib/readiness_contract.py'), *sys.argv[2:]]
sys.exit(readiness_contract.main())
PY
