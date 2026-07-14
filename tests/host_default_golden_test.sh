#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."; home=$(mktemp -d); target=$(mktemp -d)/repo; trap 'rm -rf "$home" "${target%/repo}"' EXIT; mkdir -p "$target"
HOME="$home" bash scripts/install-gemini.sh --link >/dev/null
HOME="$home" bash scripts/install-auggie.sh --all >/dev/null
HOME="$home" bash scripts/install-copilot.sh --repo "$target" >/dev/null
python3 - "$home" "$target" <<'PY'
import hashlib,json,sys
from pathlib import Path
home,target=map(Path,sys.argv[1:]); expected=json.loads(Path('tests/fixtures/host-default-golden.json').read_text()); roots={'gemini':home/'.gemini/skills','auggie':home/'.auggie/rules','copilot':target/'.github'}
for host,root in roots.items():
 actual={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.rglob('*')) if p.is_file() and p.name not in {'catalog.json','skills-catalog.json'}}
 assert actual==expected[host], f'{host} default output drift from committed golden'
PY
