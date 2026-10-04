#!/bin/bash
# Pins the XSKP-P5 readiness-policy rollover, displaced by the ACH-S-01 rollover
# (R4) and retained byte-for-byte: exact digest, live source digests, per-goal
# branch/approval scopes bound to the registered generation's goal revisions,
# explicit tool observations, the B5 gate, and contract acceptance of the retained
# bytes. Preparation regression only: it never creates context, receipts or approval.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
python3 -I -B - "$REPO_ROOT/04-validate-handoff/autobahn/lib" <<'PYTEST'
import copy
from pathlib import Path
import sys
sys.path.insert(0, sys.argv[1])
import readiness_contract as rc  # noqa: E402

ROOT = Path.cwd()
POLICY_SHA256 = '1ef4f92900133f582cac5638384f67a10266e910e883ec44493f0555690f2444'
SUPERSEDES = 'bdca65ade44ed6ab2c6d2e9bd7c54773c884998eb9a21a56a7edbcf38643f5e5'
RETAINED = '.ai/handoff/xskp-p5-readiness-policy.retained.json'
# The ACH-S-01 v1 rollover that displaced P5, retained byte-for-byte after ACH-S-02 made the
# live policy readiness-policy/2.
S01_RETAINED = '.ai/handoff/ach-skills-contract-v2/s01-readiness-policy-v1.retained.json'
S01_SHA256 = '4b022b867bef6700fa53727c7c4aeba893a28d8127fbce17c063751198d3d91f'
REGISTRATION = 'northstar-plan-xskp-p5-skill-producers'
GENERATION = '4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c'
BUNDLE_SHA256 = '8089c7c77e5aadb62c1a003fb7b30c78465ceb65541fc5b7927b3e2a0bd58cff'
RESPONSIBLE = 'Andres Silva Burgstahler'
GOALS = {
    'XSKP-P5-01': ('feat/knowledge-contract-copy-XSKP-P5-01', '059499be88c7d2fa3deda7db242b33e3e6b423adba10d76f8f52c2d99e8a4808'),
    'XSKP-P5-02': ('feat/knowledge-producers-planning-XSKP-P5-02', '76fea8df567b84a0d10875f284b6bcf479093a3079abd23951630458db9a1963'),
    'XSKP-P5-03': ('feat/knowledge-producers-review-XSKP-P5-03', '0e5a0f90c86239b07f11c86f1dde18b90cd42f5fe95583033e0a7e17ee615ab9'),
    'XSKP-P5-04': ('feat/knowledge-init-templates-XSKP-P5-04', 'd846d45fe622157871578e818ca4fbf952f32842721f3b72541af41ff94a20ed'),
}
TOOLS = ('bash', 'python3', 'git', 'prek')
REPO = {'repository': True}
failures, passes = [], 0


def check(name, condition):
    global passes
    if condition:
        passes += 1
        print('  PASS: ' + name)
    else:
        failures.append(name)
        print('  FAIL: ' + name)


policy_path = ROOT / RETAINED
policy = rc.read(policy_path)
gates = {g['id']: g for g in policy['gates']}
check('retained policy bytes keep the pinned approval subject digest', rc.digest(policy_path) == POLICY_SHA256)
displacing = rc.read(ROOT / S01_RETAINED)
check('the retained S-01 rollover displaces P5 and names the retained bytes',
      rc.digest(ROOT / S01_RETAINED) == S01_SHA256 != POLICY_SHA256
      and displacing.get('extensions', {}).get('supersedes_policy_sha256') == POLICY_SHA256
      and displacing.get('extensions', {}).get('superseded_policy_retained_at') == RETAINED)
check('the live policy is neither P5 bytes nor a v1 policy',
      rc.digest(ROOT / rc.POLICY) not in (POLICY_SHA256, S01_SHA256)
      and rc.read(ROOT / rc.POLICY).get('schema') == 'readiness-policy/2')

manifest = rc.read(ROOT / '.ai/workflows/northstar-readiness-v1.json')
entry = next((p for p in manifest['plans'] if p['id'] == REGISTRATION), None)
check('registration is active at the pinned generation',
      entry is not None and entry['status'] == 'active' and entry['generation'] == GENERATION
      and entry['artifacts']['bundle']['sha256'] == BUNDLE_SHA256)
bundle_path = ROOT / entry['artifacts']['bundle']['path']
bundle = rc.read(bundle_path)
check('bundle bytes match the registered digest', rc.digest(bundle_path) == BUNDLE_SHA256)
check('policy repository equals the bundle repository', policy['repository'] == bundle['repository'])

ext = policy.get('extensions', {})
check('extensions name the active P5 plan, generation and superseded policy',
      ext.get('active_plan') == 'xskp-p5-skill-producers' and ext.get('registration') == REGISTRATION
      and ext.get('generation') == GENERATION and ext.get('bundle_sha256') == BUNDLE_SHA256
      and ext.get('supersedes_policy_sha256') == SUPERSEDES)
check('approval is pending, never claimed', ext.get('approval_status') == 'pending-independent-approval')

required = {'AGENTS.md', '.rules.ts'} | {p.relative_to(ROOT).as_posix() for p in (ROOT / '.ai/rules').rglob('*') if p.is_file()}
check('sources cover exactly the governing instruction set', {s['path'] for s in policy['sources']} == required)
check('every source digest is current', all(rc.digest(ROOT / s['path']) == s['sha256'] for s in policy['sources']))

check('own-execution owner gate preserved',
      gates.get('own-execution', {}).get('binding') == {'roles': ['owner']}
      and gates['own-execution']['stage'] == 'implementation' and gates['own-execution']['scope'] == REPO)
check('own-review reviewer gate preserved',
      gates.get('own-review', {}).get('binding') == {'roles': ['reviewer']}
      and gates['own-review']['stage'] == 'merge' and gates['own-review']['scope'] == REPO)

goal_ids = {g['id'] for g in bundle['goals']}
check('bundle goals are exactly XSKP-P5-01..04', goal_ids == set(GOALS))
for gid, (branch, revision) in GOALS.items():
    suffix = gid.lower()
    b = gates.get('branch-' + suffix, {})
    check(gid + ' exact branch gate targets main',
          b.get('kind') == 'branch_target' and b.get('stage') == 'implementation'
          and b.get('scope') == {'goals': [gid]} and b.get('binding') == {'branch': branch, 'target': 'main'})
    a = gates.get('approval-' + suffix, {})
    check(gid + ' protected approval bound to the live goal revision',
          a.get('kind') == 'protected_approval' and a.get('stage') == 'implementation'
          and a.get('scope') == {'goals': [gid]}
          and a.get('binding') == {'subject': {'mode': 'goal-scope', 'goal': gid, 'goal_sha256': revision}}
          and rc.goal_revision(bundle, gid) == revision)
    check(gid + ' owner stays unassigned in the frozen bundle',
          next(g for g in bundle['goals'] if g['id'] == gid)['owner'] == 'unassigned')

for tool in TOOLS:
    t = gates.get('tool-' + tool, {})
    check('tool observation gate: ' + tool,
          t.get('kind') == 'tooling' and t.get('binding') == {'tool': tool}
          and t.get('stage') == 'implementation' and t.get('scope') == REPO)
cv = gates.get('tool-catalog-validator', {})
check('catalog validator presence gate',
      cv.get('kind') == 'executable_presence' and cv.get('path') == 'scripts/validate-skill-catalog.py'
      and cv.get('stage') == 'implementation' and cv.get('scope') == REPO)
b5 = gates.get('planning-inputs-on-main', {})
check('B5 planning-inputs-on-main independent result gate',
      b5.get('kind') == 'independent_result' and b5.get('stage') == 'implementation' and b5.get('scope') == REPO)
check('legacy repository-wide tool-present gate removed', 'tool-present' not in gates)
check('every gate names the retained responsible party', all(g.get('responsible') == RESPONSIBLE for g in policy['gates']))
check('no gate scope leaves the admitted bundle',
      all(g['scope'] == REPO or set(g['scope'].get('goals', [])) <= goal_ids for g in policy['gates']))

exclusions = set(policy['not_applicable'])
covered = set().union(*(rc.gate_dimensions(g) for g in policy['gates']))
check('only fixtures and harness_trust are exempt', exclusions == {'fixtures', 'harness_trust'})
check('policy dimensions complete without contradiction',
      rc.DIMENSIONS <= exclusions | covered and not (exclusions & covered))

# Contract acceptance of the retained bytes in this checkout. The frozen bundle
# pins the canonical checkout root, so only repository() root equality is relaxed
# and the fixed policy path is pointed at the retained bytes; every other check
# runs unchanged. The context is simulated, ephemeral and carries no results, so
# every gate must stay unproven.
original, original_policy = rc.repository, rc.POLICY
rc.repository = lambda value, root: rc.require(isinstance(value, dict) and rc.ID.fullmatch(value.get('id', '')), 'repository_id_required')
rc.POLICY = RETAINED
try:
    sim = {'schema': 'readiness-context/1', 'repository': bundle['repository'],
           'policy': {'sha256': rc.digest(policy_path), 'revision': 'simulated', 'issuer': 'simulated'},
           'sources': copy.deepcopy(policy['sources']), 'authority': {}, 'results': [], 'completed_goals': []}
    gaps = rc.policy_admit(ROOT, bundle, sorted(GOALS), sim, 'implementation', 'simulated')
    codes = {g['code'] for g in gaps}
    check('contract accepts the policy shape (no policy_context_invalid)', 'policy_context_invalid' not in codes)
    failed = {g['source']['gate'] for g in gaps if g['code'] == 'gate_failed'}
    expected = {gid for gid, g in gates.items() if g['stage'] == 'implementation'} - {'tool-catalog-validator'}
    check('every evidence-bound implementation gate stays unproven without receipts', expected <= failed)
    check('authority and dependency blockers remain', {'authority_unavailable', 'dependency_incomplete', 'goal_not_ready'} <= codes)
finally:
    rc.repository, rc.POLICY = original, original_policy

print('Results: PASS=%d FAIL=%d' % (passes, len(failures)))
raise SystemExit(1 if failures else 0)
PYTEST
