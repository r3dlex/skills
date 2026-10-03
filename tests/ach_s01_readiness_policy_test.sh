#!/bin/bash
# Pins the ACH-S-01 readiness-policy rollover (R4, the last v1 rollover): exact
# digest, live source digests, the #92 worktree binding, the full-ref branch gate,
# the goal-revision protected approval bound to the registered one-goal
# generation, explicit tool observations, the B5 gate and contract acceptance.
# Preparation regression only: it never creates context, receipts or approval.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/04-validate-handoff/autobahn/lib${PYTHONPATH:+:$PYTHONPATH}" python3 -B - <<'PYTEST'
import copy
from pathlib import Path
import readiness_contract as rc

ROOT = Path.cwd()
POLICY_SHA256 = '29ae6feeb3a408496095601cf4e0d58798f2445d844245c33ebcdef9a32fd9e3'
SUPERSEDES = '1ef4f92900133f582cac5638384f67a10266e910e883ec44493f0555690f2444'
RETAINED = '.ai/handoff/xskp-p5-readiness-policy.retained.json'
REGISTRATION = 'northstar-plan-ach-skills-contract-v2'
GENERATION = 'ba4a7996ca50979aa4cf21cd50892ac7dc8eb71c161547ccf8ae3d1f448a31b0'
BUNDLE_SHA256 = '1c7b4837af54742374b140ed06fda2561ec62a1cc86ed847afe1029bce9a8dcd'
GOAL = 'ACH-S-01'
GOAL_REVISION = 'd3f083e87a52b06691a7e3c22432e7d466642b32ef132b5a22151ef700802212'
SPEC = 'docs/specifications/ACTIVE/admission-complete-handoffs-ach-skills-contract-v2.md'
UMBRELLA_SPEC_SHA256 = 'fded0858d0c3aa2ba06cdc9b6d716053cb92dd82a3afa22e6a13774e30f6ddd5'
WORKTREE = {
    'schema': 'git-worktree/1',
    'root': '/private/tmp/claude-502/-Users-andresilvaburgstahler-Ws-Personal-AiTool/94f42008-9018-42b5-b61e-b0edc80d9a34/scratchpad/wt-ps1',
    'base_commit': '92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3',
    'target_ref': 'refs/remotes/origin/main',
}
BRANCH = {'branch': 'refs/heads/feat/ach-skills-contract-v2-ACH-S-01', 'target': 'refs/remotes/origin/main'}
RESPONSIBLE = 'Andres Silva Burgstahler'
TOOLS = ('bash', 'python3', 'git', 'prek', 'ssh-keygen')
REPO = {'repository': True}
SCOPED = {'goals': [GOAL]}
failures, passes = [], 0


def check(name, condition):
    global passes
    if condition:
        passes += 1
        print('  PASS: ' + name)
    else:
        failures.append(name)
        print('  FAIL: ' + name)


def raised(call):
    try:
        call()
    except (rc.Invalid, KeyError, TypeError, AttributeError) as error:
        return type(error).__name__ + ':' + str(error) if not isinstance(error, rc.Invalid) else str(error)
    return None


policy_path = ROOT / rc.POLICY
policy = rc.read(policy_path)
gates = {g.get('id'): g for g in policy.get('gates', [])}
check('policy digest is the pinned approval subject', rc.digest(policy_path) == POLICY_SHA256)
check('policy is readiness-policy/1 with only supported worktree-mode fields',
      policy.get('schema') == 'readiness-policy/1'
      and set(policy) == {'schema', 'repository', 'sources', 'worktree', 'gates', 'not_applicable', 'extensions'})
check('worktree binding names the exact linked worktree, base and full target ref', policy.get('worktree') == WORKTREE)

manifest = rc.read(ROOT / rc.REGISTRY)
entry = next((p for p in manifest['plans'] if p.get('id') == REGISTRATION), None)
check('registration is active at the pinned generation',
      entry is not None and entry['status'] == 'active' and entry['generation'] == GENERATION
      and entry['artifacts']['bundle']['sha256'] == BUNDLE_SHA256)
bundle_path = ROOT / '.ai/handoff/readiness-v1/ach-skills-contract-v2' / GENERATION / 'goals.json'
bundle = rc.read(bundle_path)
check('bundle bytes match the registered digest', rc.digest(bundle_path) == BUNDLE_SHA256)
check('generation is the canonical bundle digest', rc.canonical(bundle) == GENERATION)
check('policy repository equals the bundle repository', policy.get('repository') == bundle['repository'])
check('bundle names the plan-scoped spec copy at its current digest',
      bundle['spec'] == {'path': SPEC, 'sha256': rc.digest(ROOT / SPEC)})
check('spec copy pins the umbrella spec digest', UMBRELLA_SPEC_SHA256 in (ROOT / SPEC).read_text())

goal = next((g for g in bundle['goals'] if g['id'] == GOAL), {})
check('generation is exactly one goal, ACH-S-01', [g['id'] for g in bundle['goals']] == [GOAL])
check('all three stages ready as published',
      goal.get('readiness') == {'preparation': 'ready', 'implementation': 'ready', 'merge': 'ready'})
check('owner stays unassigned in the frozen bundle', goal.get('owner') == 'unassigned')
check('no goal dependencies (S-01 completion is a B5 input, not a dependency)', goal.get('dependencies') == [])
check('verification commands are exact',
      goal.get('verification') == ['bash tests/run-tests.sh', 'git diff --check'])
check('goal revision is the pinned approval subject', rc.goal_revision(bundle, GOAL) == GOAL_REVISION)

ext = policy.get('extensions', {})
check('extensions name the active plan, generation and superseded P5 policy',
      ext.get('active_plan') == 'ach-skills-contract-v2' and ext.get('registration') == REGISTRATION
      and ext.get('generation') == GENERATION and ext.get('bundle_sha256') == BUNDLE_SHA256
      and ext.get('supersedes_policy_sha256') == SUPERSEDES)
check('superseded P5 policy bytes are retained',
      ext.get('superseded_policy_retained_at') == RETAINED and rc.digest(ROOT / RETAINED) == SUPERSEDES)
check('approval is pending, never claimed', ext.get('approval_status') == 'pending-independent-approval')

required = {'AGENTS.md', '.rules.ts'} | {p.relative_to(ROOT).as_posix() for p in (ROOT / '.ai/rules').rglob('*') if p.is_file()}
required |= rc.instruction_paths(bundle, ROOT)
check('sources cover exactly the worktree-mode instruction set',
      {s['path'] for s in policy.get('sources', [])} == required)
check('every source digest is current', all(rc.digest(ROOT / s['path']) == s['sha256'] for s in policy.get('sources', [])))

expected_ids = {'own-execution', 'own-review', 'branch-ach-s-01', 'approval-ach-s-01',
                'planning-inputs-on-main'} | {'tool-' + t for t in TOOLS}
check('gate set is exact (none added or removed)', set(gates) == expected_ids and len(policy.get('gates', [])) == len(expected_ids))
check('own-execution owner gate',
      gates.get('own-execution', {}).get('binding') == {'roles': ['owner']}
      and gates['own-execution'].get('stage') == 'implementation' and gates['own-execution'].get('scope') == REPO)
check('own-review reviewer gate',
      gates.get('own-review', {}).get('binding') == {'roles': ['reviewer']}
      and gates['own-review'].get('stage') == 'merge' and gates['own-review'].get('scope') == REPO)
b = gates.get('branch-ach-s-01', {})
check('branch gate binds the exact full refs',
      b.get('kind') == 'branch_target' and b.get('stage') == 'implementation'
      and b.get('scope') == SCOPED and b.get('binding') == BRANCH)
check('branch gate target equals the worktree target ref', b.get('binding', {}).get('target') == WORKTREE['target_ref'])
a = gates.get('approval-ach-s-01', {})
check('protected approval bound to the published goal revision',
      a.get('kind') == 'protected_approval' and a.get('stage') == 'implementation' and a.get('scope') == SCOPED
      and a.get('binding') == {'subject': {'mode': 'goal-scope', 'goal': GOAL, 'goal_sha256': GOAL_REVISION}})
for tool in TOOLS:
    t = gates.get('tool-' + tool, {})
    check('tool observation gate: ' + tool,
          t.get('kind') == 'tooling' and t.get('binding') == {'tool': tool}
          and t.get('stage') == 'implementation' and t.get('scope') == REPO)
b5 = gates.get('planning-inputs-on-main', {})
check('B5 planning-inputs-on-main independent result gate',
      b5.get('kind') == 'independent_result' and b5.get('stage') == 'implementation' and b5.get('scope') == REPO)
check('every gate names the retained responsible party', all(g.get('responsible') == RESPONSIBLE for g in policy.get('gates', [])))
check('no gate scope leaves the admitted bundle',
      all(g.get('scope') == REPO or set(g.get('scope', {}).get('goals', [])) <= {GOAL} for g in policy.get('gates', [])))

exclusions = policy.get('not_applicable', {})
covered = set().union(*(rc.gate_dimensions(g) for g in policy.get('gates', [])))
check('only fixtures and harness_trust are exempt', set(exclusions) == {'fixtures', 'harness_trust'})
check('all 7 v1 dimensions covered without contradiction',
      rc.DIMENSIONS <= set(exclusions) | covered and not (set(exclusions) & covered)
      and covered == rc.DIMENSIONS - {'fixtures', 'harness_trust'})
check('harness_trust reason is the honest S-01-is-the-harness disclosure',
      'ACH-S-01 is the harness' in exclusions.get('harness_trust', ''))

request = ROOT / '.ai/handoff/ach-s01-policy-approval.md'
text = request.read_text() if request.is_file() else ''
check('unsigned approval request names this policy digest and goal revision',
      POLICY_SHA256 in text and GOAL_REVISION in text and 'unsigned' in text.lower())

# Contract acceptance in this checkout against a simulated worktree observation.
# The frozen bundle pins the canonical checkout root, so only repository() root
# equality is relaxed here; every other check runs unchanged. The observation and
# context are simulated, ephemeral and carry no results, so every gate must stay
# unproven.
observed = dict(WORKTREE, common_dir='simulated', head='simulated', branch=BRANCH['branch'],
                target_revision='simulated', state_sha256='simulated')
original = rc.repository
rc.repository = lambda value, root: rc.require(isinstance(value, dict) and rc.ID.fullmatch(value.get('id', '')), 'repository_id_required')
try:
    sim = {'schema': 'readiness-context/1', 'repository': bundle['repository'],
           'policy': {'sha256': rc.digest(policy_path), 'revision': 'simulated', 'issuer': 'simulated'},
           'sources': copy.deepcopy(policy.get('sources')), 'authority': {}, 'results': [], 'completed_goals': [],
           'worktree': observed}
    for stage in ('implementation', 'merge'):
        gaps = rc.policy_admit(ROOT, bundle, [GOAL], sim, stage, 'simulated', worktree=observed)
        codes = {g['code'] for g in gaps}
        check(stage + ': contract accepts the policy shape (no policy_context_invalid)', 'policy_context_invalid' not in codes)
        failed = {g['source']['gate'] for g in gaps if g['code'] == 'gate_failed'}
        stage_gates = {gid for gid, g in gates.items() if g.get('stage') == stage}
        check(stage + ': every gate stays unproven without receipts', bool(stage_gates) and stage_gates == failed)
        check(stage + ': authority blocker remains and the goal itself is ready',
              'authority_unavailable' in codes and 'goal_not_ready' not in codes)
    branch_gate = gates.get('branch-ach-s-01', {})
    check('full-ref binding matches the observed branch (fails only for missing evidence)',
          bool(branch_gate) and raised(lambda: rc.typed_gate(ROOT, bundle, branch_gate, sim, worktree=observed)) == 'typed_evidence_missing_or_ambiguous')
    short = dict(branch_gate, binding={'branch': 'feat/ach-skills-contract-v2-ACH-S-01', 'target': 'main'})
    check('a short-name binding is refused as worktree_branch_target_mismatch',
          raised(lambda: rc.typed_gate(ROOT, bundle, short, sim, worktree=observed)) == 'worktree_branch_target_mismatch')
finally:
    rc.repository = original

print('Results: PASS=%d FAIL=%d' % (passes, len(failures)))
raise SystemExit(1 if failures else 0)
PYTEST
