#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Assert explicitly rather than relying on `set -e` to abort on a bare `[[ ]]`.
# bash 3.2 (the macOS system shell, and what contributors run locally) does NOT
# treat a failing conditional command as an errexit trigger, so a bare
# `[[ a -eq b ]]` line silently continues and the suite exits 0 with the
# assertion inert. Verified on 3.2.57: a false `[[ ]]` under `set -euo pipefail`
# still reaches the next line. `die` makes these fail closed on every shell.
die() { echo "FAIL: $1" >&2; exit 1; }

python3 scripts/catalog-query.py --host codex > /tmp/catalog.default
actual="$(wc -l < /tmp/catalog.default | tr -d ' ')"
[[ "$actual" -eq 36 ]] || die "default catalog count is $actual, expected 36"
# The catalog is host-independent: every host sees the same skills. Assert that
# against the *extended* query, not the default one — the two stopped being
# identical when lifecycle gating landed, which is the whole point of a
# lifecycle. Comparing default-vs-extended here would assert that no skill is
# ever deprecated, which is a claim about the catalog's contents rather than
# about host parity.
# Host selection is supported_hosts membership, not host-independence: a skill
# may legitimately be exclusive to one host (edit-article is opencode-only per
# the 2026-10-01 SSCM amendment). Assert each host's extended view against
# catalog.json membership directly; no cross-file /tmp state.
python3 - <<'PY'
import json, subprocess, sys
query = [sys.executable, 'scripts/catalog-query.py']
def run(*args):
    return subprocess.run(query + list(args), capture_output=True, text=True, check=True).stdout
codex_extended = run('--host', 'codex',
                     '--include-lifecycle', 'experimental',
                     '--include-lifecycle', 'deprecated').splitlines()
assert codex_extended, 'extended codex view must not be empty'
assert any(line.startswith('resolving-merge-conflicts\t') for line in codex_extended), \
    'deprecated resolving-merge-conflicts missing from the extended query'
for host in ('codex', 'claude-code', 'gemini', 'copilot', 'auggie', 'opencode'):
    names = {line.split('\t', 1)[0] for line in run('--host', host).splitlines() if line}
    expected = {
        s['name'] for s in json.load(open('catalog.json'))['skills']
        if s.get('lifecycle', 'stable') in {'stable', 'compatibility'}
        and host in s.get('supported_hosts', [])
    }
    assert names == expected, f'--host {host} default view mismatch: off by {sorted(names ^ expected)}'
PY

if grep -q '^resolving-merge-conflicts	' /tmp/catalog.default; then
  die "deprecated resolving-merge-conflicts must not appear in a default install"
fi
out=$(mktemp); python3 scripts/catalog-query.py --host codex --projection "$out" >/dev/null
python3 - "$out" <<'PY'
import json,sys
p=sys.argv[1]; data=json.load(open(p)); names=[x['name'] for x in data['skills']]
assert names==sorted(names); assert open(p,'rb').read().endswith(b'\n')
PY
set +e
python3 scripts/catalog-query.py --host codex --include-lifecycle unknown >/dev/null 2>&1; rc=$?
set -e
[[ $rc -eq 2 ]] || die "unknown lifecycle should exit 2, got $rc"
python3 scripts/generate-skill-docs.py --check
