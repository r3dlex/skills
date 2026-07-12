#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 scripts/check-markdown-links.py

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/phase-a/alpha" "$tmp/phase-b/beta"
cat > "$tmp/catalog.json" <<'JSON'
{
  "schema_version": "1.0",
  "phases": ["phase-a", "phase-b"],
  "skills": [
    {"name":"alpha","source_path":"phase-a/alpha","owner_phase":"phase-a","applies_to_phases":["phase-a"],"lifecycle":"stable","supported_hosts":["codex"]},
    {"name":"beta","source_path":"phase-b/beta","owner_phase":"phase-b","applies_to_phases":["phase-b"],"lifecycle":"stable","supported_hosts":["codex"]}
  ]
}
JSON
cat > "$tmp/phase-a/alpha/SKILL.md" <<'MD'
---
name: alpha
description: alpha fixture
---
[flat beta reference](../beta/detail.md)
MD
cat > "$tmp/phase-b/beta/SKILL.md" <<'MD'
---
name: beta
description: beta fixture
---
MD
printf 'detail\n' > "$tmp/phase-b/beta/detail.md"
PYTHONPATH=scripts python3 scripts/check-markdown-links.py --root "$tmp"
rm "$tmp/phase-b/beta/detail.md"
if PYTHONPATH=scripts python3 scripts/check-markdown-links.py --root "$tmp" >/dev/null 2>&1; then
  echo "link guard accepted a broken catalog-mapped flat skill link" >&2
  exit 1
fi
