#!/usr/bin/env bash
# Differential proof for e6-sk-01-py-leaf. Fails until each TS port matches the
# legacy implementation materialized from the publication commit.
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

ANCHOR="6255da27afeee8c2e9f3582793e74fbc5ff68bf3"
candidates=(
	scripts/lib/leaf/catalog-query.mjs
	scripts/lib/leaf/check-markdown-links.mjs
	scripts/lib/leaf/check-root-discovery.mjs
	scripts/lib/leaf/generate-skill-docs.mjs
	scripts/lib/leaf/scan-secret-material.mjs
	scripts/lib/leaf/validate-cascade-fixtures.mjs
	scripts/lib/leaf/validate-final-package.mjs
	scripts/lib/leaf/validate-skill-catalog.mjs
	scripts/lib/leaf/catalog-install.mjs
	scripts/lib/leaf/check-codex-parity.mjs
	scripts/lib/leaf/check-opencode-parity.mjs
	scripts/lib/leaf/check-sync-staleness.mjs
	scripts/lib/leaf/install-auggie.mjs
	scripts/lib/leaf/install-claude-code.mjs
	scripts/lib/leaf/install-codex.mjs
	scripts/lib/leaf/install-copilot.mjs
	scripts/lib/leaf/install-gemini.mjs
	scripts/lib/leaf/readme-generate.mjs
	scripts/lib/leaf/regen-host-golden.mjs
	scripts/lib/leaf/verify-golden-dir.mjs
	04-validate-handoff/eval-a-skill/lib/scaffold-eval.mjs
	03-configure-generate/ai-catapult-init/scripts/lib/readme-generate.mjs
)

for candidate in "${candidates[@]}"; do
	if [[ -f "$candidate" ]]; then
		ok "candidate present: $candidate"
	else
		bad "candidate present: $candidate"
	fi
done

if [[ -f scripts/lib/leaf-parity.mjs ]]; then
	if node scripts/lib/leaf-parity.mjs "$ANCHOR"; then
		ok "legacy and TS outputs match"
	else
		bad "legacy and TS outputs match"
	fi
else
	bad "legacy and TS outputs match"
fi

echo ""
echo "Results: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
