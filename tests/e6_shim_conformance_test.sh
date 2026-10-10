#!/usr/bin/env bash
set -uo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:${PATH}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT" || exit 1
PASS=0
FAIL=0
ok() {
	echo "  PASS: $1"
	PASS=$((PASS + 1))
}
bad() {
	echo "  FAIL: $1"
	FAIL=$((FAIL + 1))
}

rendered="$(node scripts/lib/shim-render.mjs bash lib/check-legacy-freeze.mjs)"
if [[ "$rendered" == "$(cat scripts/check-legacy-freeze.sh)" ]]; then
	ok "check-legacy-freeze.sh matches the bash template"
else
	bad "check-legacy-freeze.sh matches the bash template"
fi
if [[ -x scripts/check-legacy-freeze.sh ]]; then
	ok "shim is executable"
else
	bad "shim is executable"
fi
if node scripts/lib/shim-render.mjs bash lib/sample.mjs NODE_OPTIONS >/tmp/e6-node-allow.out 2>/tmp/e6-node-allow.err; then
	bad "NODE_* allowlist is refused"
else
	ok "NODE_* allowlist is refused"
fi
python_shim="$(mktemp)"
node scripts/lib/shim-render.mjs python3 lib/sample.mjs >"$python_shim"
chmod +x "$python_shim"
head -1 "$python_shim" | grep -q 'python3 -I -B' && ok "python3 shim carries -I -B" || bad "python3 shim carries -I -B"
rm -f "$python_shim"

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
