#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."; python3 scripts/check-root-discovery.py; [[ -s docs/migration/root-path-assumptions.md ]]
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/python.py" <<'EOF'
from pathlib import Path
skills = list(Path('.').rglob('SKILL.md'))
EOF
cat > "$tmp/shell.sh" <<'EOF'
for body in "$SKILLS_DIR"/*/SKILL.md; do echo "$body"; done
EOF
cat > "$tmp/find.sh" <<'EOF'
find "$SKILLS_DIR" -maxdepth 2 -name SKILL.md
EOF
cat > "$tmp/iterdir.py" <<'EOF'
from pathlib import Path
for path in Path('.').iterdir():
    body = path / 'SKILL.md'
    if body.is_file():
        print(body)
EOF
for bypass in "$tmp"/*; do
 if python3 scripts/check-root-discovery.py "$bypass" >/dev/null 2>&1; then echo "guard accepted bypass: $bypass" >&2; exit 1; fi
done
