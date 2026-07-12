#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from pathlib import Path
needles = ('$SKILLS_DIR"/*/', "glob('*/SKILL.md", 'glob("*/SKILL.md', 'for body in */SKILL.md', 'for skill_dir in */SKILL.md')
fail=[]
for base in (Path('scripts'),Path('tests')):
 for path in base.rglob('*'):
  if not path.is_file() or path.name=='root_discovery_guard_test.sh' or '__pycache__' in path.parts: continue
  try: text=path.read_text()
  except UnicodeDecodeError: continue
  for n in needles:
   if n in text: fail.append(f'{path}: unsupported root discovery {n}')
if fail: raise SystemExit('\n'.join(fail))
PY
[[ -s docs/migration/root-path-assumptions.md ]]
