#!/usr/bin/env bash
# Lock the provider-independent secret scan before retiring the GitGuardian label.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
workflow = root / '.github/workflows/security.yml'
assert workflow.is_file(), 'provider-independent security workflow is missing'
text = workflow.read_text()
assert 'name: Repository Secret Scan' in text, 'native check must be named accurately'
assert 'GitGuardian' not in text, 'native scanner must not impersonate GitGuardian'
assert not (root / '.github/workflows/gitguardian.yml').exists(), 'retired provider workflow remains'
assert 'permissions:\n  contents: read' in text, 'scanner permissions must remain read-only'
assert 'run: python3 scripts/scan-secret-material.py' in text, 'real secret scanner must still execute'
scanner = root / 'scripts/scan-secret-material.py'
with tempfile.TemporaryDirectory() as tmp:
    cwd = pathlib.Path(tmp)
    clean = subprocess.run([sys.executable, str(scanner)], cwd=cwd, capture_output=True, text=True)
    assert clean.returncode == 0, clean.stderr
    (cwd / 'secret.txt').write_text('-----BEGIN ' + 'PRIVATE KEY-----\nfixture\n')
    bad = subprocess.run([sys.executable, str(scanner)], cwd=cwd, capture_output=True, text=True)
    assert bad.returncode == 1 and 'secret.txt' in bad.stdout, 'native scanner must reject secret fixtures'
print('Results: 8 passed, 0 failed')
PY
