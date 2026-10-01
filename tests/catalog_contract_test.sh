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
python3 scripts/catalog-query.py --host codex \
  --include-lifecycle experimental --include-lifecycle deprecated > /tmp/catalog.extended
# Host selection is supported_hosts membership, not host-independence: a skill
# may legitimately be exclusive to one host (edit-article is opencode-only per
# the 2026-10-01 SSCM amendment), so each host's view must equal the shared
# set minus entries that do not name that host — checked directly in
# catalog.json below rather than by diffing whole views.
python3 - <<'PY'
import json
cat = json.load(open('catalog.json'))
lifecycles = {'stable', 'compatibility', 'experimental', 'deprecated'}
supported = {
    s['name'] for s in cat.get('skills', [])
    if s.get('lifecycle', 'stable') in lifecycles or not s.get('lifecycle')
}
for host in ('codex', 'claude-code', 'gemini', 'copilot', 'auggie', 'opencode'):
    names = {
        line.split('\t', 1)[0]
        for line in open(f'/tmp/catalog.{host}').read().splitlines() if line
    }
    expected = {
        s['name'] for s in cat.get('skills', [])
        if (s.get('lifecycle', 'stable') in {'stable', 'compatibility', 'experimental', 'deprecated'})
        and host in s.get('supported_hosts', [])
    }
    assert names == expected, f'--host {host} view mismatch: off by {names ^ expected}'
assert supported, 'catalog has no lifecycled skills'
PY

# Default installs must exclude non-default lifecycles. Without this the
# amendment above would let a deprecated skill silently ship by default.
extended_count="$(wc -l < /tmp/catalog.extended | tr -d ' ')"
[[ "$extended_count" -gt "$actual" ]] \
  || die "extended catalog ($extended_count) must exceed the default ($actual) — no non-default lifecycle is being excluded"
grep -q '^resolving-merge-conflicts	' /tmp/catalog.extended \
  || die "deprecated resolving-merge-conflicts missing from the extended query"
# `grep -q ... && die` would be wrong here: when grep finds nothing the whole
# list returns non-zero and `set -e` aborts the run as a failure. Use `if`.
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
