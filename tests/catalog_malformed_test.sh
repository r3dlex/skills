#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."; src=tests/fixtures/catalog-malformed; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -R "$src/skill" "$tmp/skill"
for fixture in "$src"/*.json; do
 cp "$fixture" "$tmp/catalog.json"; set +e
 output=$(python3 scripts/catalog-query.py --root "$tmp" --host codex 2>&1); rc=$?
 set -e
 [[ $rc -eq 2 ]]; [[ "$output" != *Traceback* ]]; [[ -n "$output" ]]
done
