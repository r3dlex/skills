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
cat > "$tmp/globfiletest.sh" <<'EOF'
for d in "$ROOT"/*/; do
  [ -f "${d}SKILL.md" ] && echo "$d"
done
EOF
cat > "$tmp/iterdir.py" <<'EOF'
from pathlib import Path
for path in Path('.').iterdir():
    body = path / 'SKILL.md'
    if body.is_file():
        print(body)
EOF
for bypass in "$tmp"/*; do
 set +e
 guard_output=$(python3 scripts/check-root-discovery.py "$bypass" 2>&1)
 guard_rc=$?
 set -e
 if [[ "$guard_rc" -eq 0 || "$guard_output" == *node_unavailable* || "$guard_output" == *node_version_unsupported* || "$guard_output" != *"unsupported root SKILL.md discovery"* ]]; then
  echo "guard refusal was not the discovery code: $bypass rc=$guard_rc $guard_output" >&2
  exit 1
 fi
done
