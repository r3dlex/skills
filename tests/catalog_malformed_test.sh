#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."; src=tests/fixtures/catalog-malformed; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

# bash 3.2 does not fire errexit on a failing bare `[[ ]]`, so assert explicitly.
die() { echo "FAIL: $1" >&2; exit 1; }

cp -R "$src/skill" "$tmp/skill"
for fixture in "$src"/*.json; do
 cp "$fixture" "$tmp/catalog.json"; set +e
 output=$(python3 scripts/catalog-query.py --root "$tmp" --host codex 2>&1); rc=$?
 set -e
 [[ $rc -eq 2 ]]            || die "$fixture: expected exit 2, got $rc"
 [[ "$output" != *Traceback* ]] || die "$fixture: leaked a Python traceback"
 [[ -n "$output" ]]         || die "$fixture: produced no diagnostic output"
done
