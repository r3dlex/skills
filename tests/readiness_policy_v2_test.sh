#!/bin/bash
# Pins the skills readiness-policy/2 after the post-S-06 policy amendment ACH-AM-01 (plan
# ach-skills-agent-mode, D-ACCEPT variant a): the live bytes equal the amendment generation's
# policy candidate bound by policy_sha256, the field values are exact (approval.accept now
# includes agent-self and approval.default_mode is agent; every other byte unchanged), every
# gate is repository-scoped, there are no extensions, and no plan or goal id from either
# readiness registry appears in the policy. Regression only: it never approves anything.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
python3 -I -B - "$REPO_ROOT" <<'PYTEST'
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / '04-validate-handoff/autobahn/lib'))
import readiness_contract_v2 as v2  # noqa: E402

POLICY = ROOT / '.ai/policies/readiness-policy.json'
REGISTRY_V2 = ROOT / '.ai/workflows/northstar-readiness-v2.json'
REGISTRY_V1 = ROOT / '.ai/workflows/northstar-readiness-v1.json'
PLAN = 'ach-skills-agent-mode'
POLICY_SHA256 = '58bcd9e7ba044479e2f9f64bedd147926e8ea706f9d9c51378294dada52b354a'
AMENDS_SHA256 = '2ee17f06817e424dffdb30047f83b8e69805fe92d4771c21d1c4662092cb2176'
failures, passes = [], 0


def check(name, condition):
    global passes
    if condition:
        passes += 1
        print('  PASS: ' + name)
    else:
        failures.append(name)
        print('  FAIL: ' + name)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


data = POLICY.read_bytes()
policy = json.loads(data)
registry = json.loads(REGISTRY_V2.read_text())
entry = next((p for p in registry['plans'] if p.get('plan_id') == PLAN), {})
candidate = ROOT / entry.get('artifacts', {}).get('policy_candidate', {}).get('path', 'missing')

check('live policy is readiness-policy/2', policy.get('schema') == 'readiness-policy/2')
check('live bytes equal the amendment generation candidate', candidate.is_file() and data == candidate.read_bytes())
check('live bytes are bound by the registered policy_sha256',
      sha(POLICY) == POLICY_SHA256 == entry.get('policy_sha256') == entry['artifacts']['policy_candidate'].get('sha256'))
check('the amendment entry records amends_policy_sha256 for the pre-amendment policy',
      entry.get('amends_policy_sha256') == AMENDS_SHA256)
try:
    v2.validate_policy(json.loads(data))
    valid = True
except v2.Invalid as error:
    print('    ' + str(error))
    valid = False
check('the pinned validator accepts the policy', valid)
check('repository.id is skills', policy.get('repository') == {'id': 'skills'})
check('identity_model single is an explicit opt-in', policy.get('identity_model') == 'single')
check('required_checks are exactly the three hosted checks',
      policy.get('required_checks') == ['Pre-commit Hooks', 'Test Suite', 'Repository Secret Scan'])
check('approval.accept is exactly agent-self, ssh-tag and in-session',
      policy.get('approval', {}).get('accept') == ['agent-self', 'ssh-tag', 'in-session'])
check('approval.default_mode is agent (K3)', policy.get('approval', {}).get('default_mode') == 'agent')
check('branch_pattern is the live pattern (M4)',
      policy.get('branch_pattern') == '^(feat|fix|chore)/<plan_id>-<goal_id>$')
check('tools are exactly bash, python3, git, prek, ssh-keygen and gh',
      policy.get('tools') == ['bash', 'python3', 'git', 'prek', 'ssh-keygen', 'gh'])
check('every gate is repository-scoped', bool(policy.get('gates'))
      and all(g.get('scope') == {'repository': True} for g in policy['gates']))
check('no extensions', 'extensions' not in policy)
check('no skippable checks', policy.get('skippable_checks') == [])

ids = set()
for path in (REGISTRY_V1, REGISTRY_V2):
    for plan in json.loads(path.read_text()).get('plans', []):
        ids.add(plan['plan_id'])
        bundle = json.loads((ROOT / plan['artifacts']['bundle']['path']).read_text())
        ids.update(goal['id'] for goal in bundle['goals'])
check('both registries were read', {PLAN, 'xskp-p5-skill-producers', 'ACH-S-01', 'ACH-S-02', 'XSKP-P5-01'} <= ids)
text = data.decode().lower()
leaked = sorted(i for i in ids if i.lower() in text)
check('no plan or goal id from either registry appears in the policy (%s)' % ', '.join(leaked) if leaked else
      'no plan or goal id from either registry appears in the policy', not leaked)

print('Results: PASS=%d FAIL=%d' % (passes, len(failures)))
raise SystemExit(1 if failures else 0)
PYTEST
