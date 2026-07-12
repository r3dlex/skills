#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

python3 scripts/check-markdown-links.py

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
printf '[missing](does-not-exist.md)\n' > "$tmp/broken.md"
if python3 scripts/check-markdown-links.py "$tmp/broken.md" >/dev/null 2>&1; then
  echo "link guard accepted a broken local link" >&2
  exit 1
fi
