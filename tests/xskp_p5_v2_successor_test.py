"""P5 v2 preparation regression; no approval or live policy writes.

Uses the full Git history, as the repository Test Suite CI does (fetch-depth: 0).
"""
import copy
import hashlib
import json
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '04-validate-handoff/autobahn/lib'))
import readiness_contract_v2 as v2

V1_GEN = '4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c'
V1_DIR = ROOT / '.ai/handoff/readiness-v1/xskp-p5-skill-producers' / V1_GEN
BASE = '48f90f11f5ce443451c2bfaeda3e2e4657791828'
PLANNING_COMMIT = '277cc698e8403131f87549b0d8ac64a7906a7c3e'
HANDOFF = 'northstar-plan-xskp-p5-skill-producers-v2'
PACK = 'docs/specifications/ACTIVE/cross-surface-knowledge-publication.contract'
LOCK_SHA = '9f5d7edfc17554c383b06aa4726dfffe564ecc8d657b16baa89ce72098d5e102'
SPEC = 'docs/specifications/ACTIVE/cross-surface-knowledge-publication-xskp-p5-skill-producers.md'
SPEC_SHA = 'f2c315e2843033cde9d4e609b2ab2b3c841ac1321f1a461f21c09c1b29120fa4'


def read(path):
    return json.loads(Path(path).read_text())


def at_base(path):
    return subprocess.check_output(['git', 'show', BASE + ':' + path], cwd=ROOT)


class SuccessorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        registry = read(ROOT / v2.REGISTRY)
        cls.entry = next(p for p in registry['plans'] if p['id'] == HANDOFF)
        cls.bundle = read(ROOT / cls.entry['artifacts']['bundle']['path'])
        cls.sidecar = read(ROOT / cls.entry['artifacts']['sidecar']['path'])
        cls.policy_path = ROOT / cls.entry['artifacts']['policy_candidate']['path']
        cls.policy = read(cls.policy_path)
        cls.original = read(V1_DIR / 'goals.json')

    def test_schema_and_bootstrap(self):
        v2.validate_bundle(self.bundle)
        v2.validate_sidecar(self.sidecar, self.bundle)
        v2.validate_policy(self.policy)
        v2.validate_bootstrap(self.bundle, live_policy2=False)
        self.assertEqual(v2.policy_goals(self.bundle), ['XSKP-P5-00'])
        self.assertEqual(self.bundle['goals'][0]['scope'], [v2.POLICY])
        for goal in self.original['goals']:
            self.assertIn('XSKP-P5-00', v2.ancestors(self.bundle, goal['id']))

    def test_original_feature_content_and_order_preserved(self):
        new = {g['id']: g for g in self.bundle['goals']}
        self.assertEqual(set(new), {'XSKP-P5-00'} | {g['id'] for g in self.original['goals']})
        for old in self.original['goals']:
            goal = new[old['id']]
            self.assertEqual(set(goal), {'id', 'scope', 'acceptance_criteria', 'dependencies', 'verification'})
            for field in ('scope', 'acceptance_criteria', 'verification'):
                self.assertEqual(goal[field], old[field])
            expected = old['dependencies'] or ['XSKP-P5-00']
            self.assertEqual(goal['dependencies'], expected)

    def test_historical_artifacts_and_live_policy_unchanged(self):
        paths = ['.ai/workflows/northstar-readiness-v1.json',
                 '.ai/handoff/xskp-p5-readiness-policy.retained.json',
                 '.ai/handoff/xskp-p5-policy-approval.md']
        paths += subprocess.check_output(
            ['git', 'ls-tree', '-r', '--name-only', BASE, '--', '.ai/handoff/readiness-v1'],
            cwd=ROOT, text=True).splitlines()
        self.assertEqual(set(paths[3:]), {str(p.relative_to(ROOT)) for p in
                         (ROOT / '.ai/handoff/readiness-v1').rglob('*') if p.is_file()})
        for path in paths:
            self.assertEqual((ROOT / path).read_bytes(), at_base(path), path)
        self.assertEqual(hashlib.sha256((V1_DIR / 'goals.json').read_bytes()).hexdigest(),
                         '8089c7c77e5aadb62c1a003fb7b30c78465ceb65541fc5b7927b3e2a0bd58cff')
        retained = ROOT / '.ai/handoff/ach-s01-readiness-policy.retained.json'
        self.assertEqual(retained.read_bytes(), at_base(v2.POLICY))
        live = ROOT / v2.POLICY
        if read(live)['schema'] == 'readiness-policy/2':
            # ACH-S-02 (merged PR #102) made readiness-policy/2 live before this publication.
            # A live policy/2 is either this generation's candidate once XSKP-P5-00 is admitted,
            # or the merged policy/2 left byte-untouched at the merge target.
            target = subprocess.check_output(['git', 'show', 'HEAD~1:' + v2.POLICY], cwd=ROOT)
            self.assertIn(live.read_bytes(), (self.policy_path.read_bytes(), target))
        else:
            self.assertEqual(live.read_bytes(), at_base(v2.POLICY))

    def test_b5_transition_is_backed_by_target_bytes(self):
        subprocess.run(['git', 'merge-base', '--is-ancestor', PLANNING_COMMIT, BASE], cwd=ROOT, check=True)
        for path, digest in ((SPEC, SPEC_SHA), (PACK + '/contract.lock.json', LOCK_SHA)):
            self.assertEqual(hashlib.sha256(at_base(path)).hexdigest(), digest)
            self.assertEqual((ROOT / path).read_bytes(), at_base(path))
        lock = read(ROOT / PACK / 'contract.lock.json')
        for name, digest in lock['files'].items():
            path = PACK + '/' + name
            self.assertEqual(hashlib.sha256(at_base(path)).hexdigest(), digest, path)
            self.assertEqual((ROOT / path).read_bytes(), at_base(path), path)
        gate = next(g for g in self.policy['gates'] if g['id'] == 'planning-inputs-on-target')
        self.assertEqual(gate['binding']['commits'], [PLANNING_COMMIT])

    def test_sidecar_preserves_legacy_posture_without_claiming_readiness(self):
        for old in self.original['goals']:
            entry = self.sidecar['goals'][old['id']]
            self.assertEqual(old['readiness']['preparation'], 'blocked')
            self.assertEqual(entry['readiness'], dict.fromkeys(v2.STAGES, 'unknown'))
            for field in ('coverage_status', 'legacy_safe_tdd', 'legacy_risk_reason'):
                self.assertEqual(entry[field], old[field])
        self.assertNotIn('owner', self.bundle)
        self.assertEqual(self.policy['approval']['accept'], ['ssh-tag'])
        self.assertEqual(self.policy['identity_model'], 'multi')
        self.assertEqual(set(self.policy['required_checks']),
                         {'Test Suite', 'Pre-commit Hooks', 'Repository Secret Scan'})
        self.assertEqual(self.policy['skippable_checks'], [])

    def test_publication_digests_are_bound(self):
        for name in ('bundle', 'graph', 'handoff', 'policy_candidate'):
            artifact = self.entry['artifacts'][name]
            self.assertEqual(hashlib.sha256((ROOT / artifact['path']).read_bytes()).hexdigest(), artifact['sha256'])
        digests = {'bundle_sha256': v2.bundle_sha256(self.bundle),
                   'spec_sha256': hashlib.sha256((ROOT / self.bundle['spec']['path']).read_bytes()).hexdigest(),
                   'policy_sha256': hashlib.sha256(self.policy_path.read_bytes()).hexdigest(),
                   'anchor_sha256': self.policy['approval']['anchor_sha256']}
        self.assertEqual(self.entry['generation'], v2.generation_v2(**digests))
        self.assertEqual(self.entry['mode'], 'bootstrap')
        self.assertEqual(self.entry['spec']['sha256'], digests['spec_sha256'])

    def test_historical_policy_regressions_survive_approved_bootstrap(self):
        # Only a disposable repository gets the policy/2 bytes, never this checkout.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / 'repo'
            subprocess.run(['git', 'clone', '--quiet', '--shared', str(ROOT), str(root)], check=True)
            files = ['tests/ach_s01_readiness_policy_test.sh', 'tests/xskp_p5_readiness_policy_test.sh',
                     '.ai/handoff/ach-s01-readiness-policy.retained.json']
            for name in files:
                destination = root / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(ROOT / name, destination)
            (root / v2.POLICY).write_bytes(self.policy_path.read_bytes())
            for name in files[:2]:
                process = subprocess.run(['bash', str(root / name)], cwd=root, capture_output=True, text=True)
                self.assertEqual(process.returncode, 0, process.stdout + process.stderr)

    def test_original_blocked_sidecar_cannot_publish(self):
        held = copy.deepcopy(self.sidecar)
        held['goals']['XSKP-P5-01']['readiness']['preparation'] = 'blocked'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, value in (('bundle.json', self.bundle), ('sidecar.json', held)):
                (root / name).write_text(json.dumps(value))
            process = subprocess.run(['bash', str(ROOT / '04-validate-handoff/autobahn/contract-run.sh'),
                                      'publish-v2', '--root', str(root), '--bundle', str(root / 'bundle.json'),
                                      '--sidecar', str(root / 'sidecar.json'), '--policy-candidate', str(self.policy_path)],
                                     cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(process.returncode, 0)
            self.assertIn('publication_hold_refused', process.stdout)
            self.assertFalse((root / v2.REGISTRY).exists())
            self.assertFalse((root / '.ai/handoff/readiness-v2').exists())


if __name__ == '__main__':
    unittest.main()
