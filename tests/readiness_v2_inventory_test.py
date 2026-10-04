"""v1 inventory (O10, ACH-S-02): contract-run.sh inventory-v1 decides every v1 registry
entry's fate by hosted merged-PR head-branch tokens and merge-commit ancestry, never
by commit-message or title text. The recorded aitool-root data below is replayed
through the in-process adapter; disposable repositories only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import hashlib
import json
import tempfile
import unittest
from unittest import mock

from readiness_v2_core_test import POLICY, REGISTRY, Fixture, codes, git, sample_bundle, v2, observer, write_json

REPO = Path(__file__).resolve().parents[1]
V1_REGISTRY = '.ai/workflows/northstar-readiness-v1.json'

# Recorded 2026-10-04 from r3dlex/ai-tool-workspace (aitool-root) at origin/main 6162d0f:
#   gh pr list --state merged --limit 200 --json number,headRefName,mergeCommit,title
#   gh pr list --state open --limit 200 --json number,headRefName,headRefOid
#   git ls-remote origin 'refs/heads/*' plus git merge-base --is-ancestor <tip> origin/main
# Every recorded merge commit was an ancestor of origin/main at recording time.
ROOT_MAIN = '6162d0fdd918505cc9e0709fb40e9b46d5902395'
MERGED = [
    (3, 'fix/release-skip-without-package', '5770d02cd00551ea2fec9bffb1606a3ac28fcbbe'),
    (5, 'codex/ai-sdlc-init-v3-rollout', 'f3ff28089cee88a9a44cc945b741f158979c0fea'),
    (6, 'codex/update-kontor-cli-remote', '1d6877de088fbd6cbb92ec1e04a7fc725310195a'),
    (7, 'codex/use-ssh-kontor-cli-remote', 'cea109749c6da005c8c29d6be33a6cd3ae1cb8ac'),
    (8, 'chore/self-hosted-wrapper', '70bac507d7d4f46b7b8d989d8b82ab96f4432949'),
    (9, 'codex/ai-sdlc-init-v3-rollout', '51c8b0165b519490c0f34613c1fe6977e4896375'),
    (10, 'fix/release-self-hosted', '4278618d0962ae4bc6ac90927a93f80ec1ccd312'),
    (11, 'codex/update-managed-remotes', '61b6315f5da63128e18ca16af4e6f609ac148961'),
    (12, 'codex/reverso-model-selector-instructions', 'f0bf69aeba999afb1c03fb351b7dba1d903d080c'),
    (13, 'chore/init-ai-repo-v3-upgrade', '89657cc35ea4c450d1d3c58091a7fe7a8098b6bb'),
    (14, 'chore/untrack-and-reconcile-matrix', '7c283c28635c4c9e61760a0b12bd4786afb0fc5e'),
    (15, 'chore/northstar-planning-artifacts', '05aceb2992a43ce6e955d8e3ae0b3f9875db8f83'),
    (16, 'feat/slice-0b-registration', 'e408e8dced602eca28d41d7db713601fc09ab3c7'),
    (17, 'autobahn/headroom-managed-repo', '747373b53beafa9817b559e8695511516e1682ee'),
    (18, 'chore/ai-catapult-build-status', '78ce5fec84c09dc86514bc29e18b40f073142559'),
    (19, 'chore/ai-catapult-published', '43643320cb50df7266c17dc1f1f68dd96efdadec'),
    (20, 'chore/graph-hooks-planning', '71669d4a16db9ae217df12a3391d1a58d6fb78c3'),
    (21, 'feat/graph-hooks-slice-1-wrapper', 'bda92cc63d4f3bdb5173aa727a63865fef183320'),
    (22, 'feat/graph-hooks-slice-2-setup', 'd31fdaac27a177fc9e70c7d5dc4d4142adca2796'),
    (23, 'feat/graph-hooks-slice-3-harness', 'fb69342d177be4af2ac034044031e59ab105e1f4'),
    (24, 'feat/graph-hooks-slice-6-drift-guard', '22c8432cb6c139cb4a55fac39b077c8aea680af3'),
    (25, 'chore/graph-hooks-close', '12bdc24566d37b0236f654eb514e5a5fd145adb4'),
    (26, 'fix/claude-stop-hook-schema', '141675c20c488d3f8b8fb0e45ba796db2415cd4b'),
    (27, 'codex/fix-graphify-pretooluse-schema', 'ba5cdaa8dd4dfd196c22a72709e50ecfd0007535'),
    (29, 'feat/dpua-goal-0-eligibility', 'd43fd0ab181372078a8e6718aba862362027f9fd'),
    (30, 'feat/dpua-goal-3-root-migration', 'c743c14742bfcfcdd3cd381e8d554ec81528d646'),
    (31, 'feat/dpua-goal-5-checkout-reconciler', '1dceefdf75b7807b64928ba34a4d31a5730734c7'),
    (32, 'feat/dpua-goal-4-root-moon', 'b43698e589d57b649bac9ed6162da04cc6fc2d0c'),
    (33, 'feat/dpua-goal-6-github-selector', 'ee129224178bab923fcd8d05961ff21402528082'),
    (34, 'feat/dpua-goal-11-cas-pull', '390c88cc580a7d2b1d04185962814c612d220c8f'),
    (35, 'feat/dpua-goal-12-cas-protected-push', '9aa4a34e644d724e4bfeb2a6e1c9745925313bef'),
    (36, 'feat/dpua-goal-13-context-ledgers', '9261e76c8972a6273d088adf591543c6029713a9'),
    (37, 'feat/dpua-goal-9-ado-selector', 'ccb5fd99555d62f351cd6996bd40418eac01db4f'),
    (38, 'feat/dpua-goal-10-gitlab-selector', '715a63915dd7cc460aa3d362dfae2b25fae550c1'),
    (39, 'chore/ai-catapult-init-refresh', '311886b3aee0594da50662e47d6b0e78948aa021'),
    (40, 'docs/canonical-readme-onboarding', 'bc1e69b33820ae4d23611df52fa1f6b012ec50a0'),
    (41, 'docs/spec-northstar-autobahn-hardening', '84646d824ab554e756594313077879581f0ddbaa'),
    (42, 'chore/port-slice8-provenance', '92b9605ff5539076894a1af91f19b356b4428a1b'),
    (43, 'docs/hardening-progress', '543308a21f2050edb474c9f0c8e4c1d2f3cdc3ab'),
    (44, 'docs/hardening-followups', '17562740ea9be6ae503a05c5440fab1707ccfe29'),
    (45, 'docs/state-vocabulary', 'd5aed52b936305cdf4f768fb22f63d0f7fa3022f'),
    (46, 'docs/tick-acceptance-criteria', '19c41b512222139d189e57d37d817f5db16000a2'),
    (47, 'docs/close-codex-criterion', 'd05eb925709f8358cacf9512640d9fda1cd92498'),
    (48, 'docs/northstar-umbrella-command-surface', '49cc94311272dd6dd067b0b2306c9e26f527432b'),
    (49, 'fix/command-surface-parity', '25f42ab7659adf0d6adb404061ad1ec7a331c17c'),
    (50, 'docs/evidence-contract', 'b866fdadf2a843d4a467da6e9f96f6c4bf5b570b'),
    (51, 'ci/command-surface-drift-guard', '2e8edc98483672630e3ee7c6d1f9b8a1d732f93f'),
    (52, 'docs/document-the-spine', '610954f9f41fc446c30d2af02b8cd3c72541222e'),
    (53, 'docs/close-command-surface-sync', '575528b7bee4e6562d6f6e00e9dcc471ac2df1d9'),
    (54, 'docs/reference-only-children', '571a1bfc3b39fffb10716352685adcc4ed7ca628'),
    (55, 'chore/deprecate-three-repos', '82b82752ae7264f3f82038a76c214146847a0ea4'),
    (56, 'test/guard-noop-mutations', '675020658b55f13a3df370a928a3bcec3f177fa3'),
    (57, 'docs/adr-0012-checkouts-removed', '839121fc4f630ae48cb6df541c6af2225a76f40a'),
    (58, 'fix/restore-graph-refresh-ssot', '29fa1e40ff6500dfb877e32b3b86c400972e4316'),
    (59, 'feat/opencode-command-surface', 'e1aec7d0863e88973b18058e575d4a70ebaac72e'),
    (60, 'chore/cascade-close-opencode-omo', '189eb1f511ff8d705ae8c42db34b0bc3c754d9d1'),
    (61, 'root-local-ci-manifest', 'b798714aafecd1ee9e656994cbb8253d9b83f503'),
    (62, 'af-02-umbrella-registration', '5c827b93af610299b4687473fad60a30e8e537b3'),
    (63, 'af-07-merge-posture-signoff', '143f6d49e1273ec0df4eada2110c7a2abfae4930'),
    (64, 'af-recon-counts-and-superseded-gate', '26d51e9b4cc5e266a1ef855abcd4d1bafcae1a9d'),
    (65, 'feat/model-frontier-root-drift-guard', 'b4fe726267e05b30a3cc5f93228de5d2bec246a5'),
    (66, 'fix/graph-refresh-import-shadow', '644c21c758095716f34394f31c391708bd52b6ef'),
    (67, 'fix/readiness-transfer-RT-04', '55e9ce9de6ee2f580eaa060dafccb015fc046617'),
    (68, 'chore/readiness-transfer-completion', 'fb6fdab47afce7808cb703f615efc45b273f60da'),
    (69, 'feat/spec-amendment-G-01', '986466a06ba1a39719b68f384bce055821a050d7'),
    (70, 'feat/omo-fixture-enforcement-G-02', '756203b06976bcafcddcf0d56a4b1f778af3b1f0'),
    (71, 'feat/skills-catalog-edit-article-G-03', '8bd8dcbbec55e21ef4a23d3417881c6da90587e7'),
    (72, 'chore/cascade-close-G-03', 'af9f171fa6d8673308e9865a688092595d6e05a6'),
    (73, 'chore/cascade-close-G-04', '147d7fd2ed44aac9a6c14a641240d837d573ff0a'),
    (74, 'docs/close-G-05-freshness-lane', '3d0097f191cf02f4006221cbb71c622fa714fba5'),
    (75, 'chore/xskp-p1-admission-preparation', 'e917604c3cb27daeb723cf54a6b67952481c0309'),
    (76, 'docs/xskp-planning-publication', '243885f8ff6b368276a71cdbbeb94fdd8cfb4b26'),
    (77, 'chore/xskp-p1-green-repair', '0f4667fc7a54f37972b73e8a023ddde832ab9621'),
    (78, 'feat/knowledge-registry-XSKP-P1-01', '49a57366852e7c8828d3de65e63df7213780f53d'),
    (79, 'prep/xskp-p2-readiness-recovery-20261002', '0b314b1ade6632564a0a10f8cc00a6853870ba1b'),
    (80, 'chore/commit-dangling-planning-refs', 'ebeec15126d8a71dbd451d88cd0a2d90f46eb341'),
    (81, 'feat/knowledge-registry-XSKP-P1-01', '317ee0d0c8677c7fcdb0d7a6173a0564b7fd8c4b'),
    (84, 'feat/knowledge-descriptors-XSKP-P1-02', '7d99b9a4b2f7978ca8e4a365416bb197772ebde4'),
    (85, 'feat/knowledge-federation-XSKP-P1-03', 'd53d44d451016bd237fb45ae800485964092e236'),
    (86, 'feat/knowledge-readback-XSKP-P1-04', 'fd004fe403d1f002d9dedbafef91bd60bdaf8370'),
    (87, 'feat/xskp-p2-01-classification', 'd80068590c5375434a3cad2161ff28df8d126bfa'),
    (88, 'feat/xskp-p2-02-publication', '87f0aae770980f3dc6658ed5cf834d252837c142'),
    (89, 'feat/knowledge-drift-XSKP-P3-01-current', '2a94c914ed4b26e1bb6013f85db9e0daad809305'),
    (90, 'feat/xskp-p2-03-drift-check', '75378de46473a703748e848b7cfc3d5d1a26b761'),
    (91, 'feat/knowledge-inventory-XSKP-P3-02-75378de', 'f2532c826568eac477b5714932c03fb3848977c3'),
    (92, 'feat/knowledge-adoption-XSKP-P3-03-f2532c8', 'c06473a6f6577642b28a190ac1be1feb609204c2'),
    (93, 'feat/knowledge-derivation-XSKP-P3-04-c06473a', '22985a9a7efc9dd743830d71957ec70d93310ff2'),
    (94, 'docs/ach-planning-publication', '6162d0fdd918505cc9e0709fb40e9b46d5902395'),
]
# Titles and commit text are recorded only to prove they are never signals.
TITLES = {
    75: 'chore(xskp): prepare frozen P1 inputs for XSKP-P1-02, XSKP-P1-03 and XSKP-P1-04',
    81: 'fix(knowledge): corrective P1-01 reader and exact merge admission',
    88: 'feat(knowledge): publish canonical copies with provenance',
    90: 'feat(knowledge): lifecycle locks and recovery',
}
OPEN = [(83, 'fix/xskp-p3-policy-current-20261002', '1ecc4c1f8c7c4ac717d2672b2d16f9094d2f267f')]
BRANCHES = [
    ('refs/heads/af-07-merge-posture-signoff', '028d04e0398572e807d69b7026ca4750ded1d034', True),
    ('refs/heads/af-recon-counts-and-superseded-gate', 'c3dc9cec989b7b9a8d822cf216cf8f1727255910', True),
    ('refs/heads/chore/commit-dangling-planning-refs', 'cfffbdcb10b8b0273da50ce761142e83bd5476af', False),
    ('refs/heads/chore/readiness-transfer-completion', '84b035195bee2bda36b633ba8e701ffcc11f52bf', False),
    ('refs/heads/chore/xskp-p1-admission-preparation', '3b180953a92e678fc4be67c272f3734c006d1ea1', False),
    ('refs/heads/chore/xskp-p1-green-repair', '947f0c5d703056b4e0ec97cc432de6d0252ebc55', False),
    ('refs/heads/docs/ach-planning-publication', '4f865239050f4d7cfe8083de1491bc8354349411', False),
    ('refs/heads/docs/xskp-planning-publication', '869644330b6f280164701b500c6df1f1e741109b', False),
    ('refs/heads/feat/knowledge-adoption-XSKP-P3-03-f2532c8', '3beb0dd98a877e39f1b1da95b4d0c1719daff1d0', True),
    ('refs/heads/feat/knowledge-derivation-XSKP-P3-04-c06473a', '285bc0710cb69b6c961d4c5d376ee01c96eedf54', True),
    ('refs/heads/feat/knowledge-descriptors-XSKP-P1-02', '9a1d89f57db3e5944c13f2824aa1041cb74477c5', False),
    ('refs/heads/feat/knowledge-drift-XSKP-P3-01-current', 'dfba3e5bf5303b54d7d3f1b2f97c47177eea8052', True),
    ('refs/heads/feat/knowledge-federation-XSKP-P1-03', 'ca59870e58d5684b2beea43be6e2271b9a3e36f2', False),
    ('refs/heads/feat/knowledge-inventory-XSKP-P3-02-75378de', '12838e4f77a40c1ff5fa12e896ce9fd0e5aab108', True),
    ('refs/heads/feat/knowledge-readback-XSKP-P1-04', '32f726bae34adc9ab7a4acb36ae0194e5f88d85b', False),
    ('refs/heads/feat/knowledge-registry-XSKP-P1-01', 'c1f96e494f35ae92985081ccebe78f0cbd8febff', False),
    ('refs/heads/feat/model-frontier-root-drift-guard', '7b8df70caf1aae5c5f80c2e6163d5e4cab889286', False),
    ('refs/heads/feat/skills-catalog-edit-article-G-03', 'cb8f804b66cf78692a0748a97b744333a371a8b1', False),
    ('refs/heads/feat/xskp-p2-01-classification', '691a5c5c301f17d89528a7762e6d47d06c3baefa', False),
    ('refs/heads/feat/xskp-p2-02-publication', 'fc0f56fabaceed5b1b3631b65b9678c4f4987c37', False),
    ('refs/heads/feat/xskp-p2-03-drift-check', 'dde9a9abad6227c651ce8156fb40f4ba7103d491', False),
    ('refs/heads/fix/readiness-transfer-RT-04', '6da3818127f752e9b50b25326987a659bc2617a0', False),
    ('refs/heads/fix/xskp-p3-policy-current-20261002', '1ecc4c1f8c7c4ac717d2672b2d16f9094d2f267f', False),
    ('refs/heads/main', '6162d0fdd918505cc9e0709fb40e9b46d5902395', True),
    ('refs/heads/prep/xskp-p2-readiness-recovery-20261002', 'ccb336d8f991ddb2937edd1ba3dc63adc86f2791', False),
]
ROOT_PLANS = {
    'opencode-omo-gap-fill-r2': ['G-01', 'G-02', 'G-03', 'G-04', 'G-05'],
    'northstar-small-work-profiles': ['SWP-ROOT-01'],
    'xskp-p1-registry-core': ['XSKP-P1-01', 'XSKP-P1-02', 'XSKP-P1-03', 'XSKP-P1-04'],
    'xskp-p2-publication': ['XSKP-P2-01', 'XSKP-P2-02', 'XSKP-P2-03'],
    'xskp-p3-root-adoption': ['XSKP-P3-01', 'XSKP-P3-02', 'XSKP-P3-03', 'XSKP-P3-04', 'XSKP-P3-05'],
}
ANCESTORS = {commit for _, _, commit in MERGED} | {sha for _, sha, reached in BRANCHES if reached}
KNOWN = ANCESTORS | {sha for _, sha, _ in BRANCHES} | {sha for _, _, sha in OPEN}

# The skills v1 registry and generation bytes this goal must leave unchanged.
V1_REGISTRY_SHA256 = 'c2afea32223acdcdb2412bf0114b231dc83b4c5f16d5215e454532a67013d461'
V1_GENERATIONS_DIGEST = '737d0c6dc3efc932e1d3c198a8b123b85262acd413a710df7fc97f6f0f6acf84'
S01_RETIRE = {'id': 'northstar-plan-ach-skills-contract-v2', 'plan_id': 'ach-skills-contract-v2',
              'generation': 'ba4a7996ca50979aa4cf21cd50892ac7dc8eb71c161547ccf8ae3d1f448a31b0',
              'registry': V1_REGISTRY, 'fate': 'completed',
              'merged': [{'goal': 'ACH-S-01', 'pr': 97, 'merge_commit': 'f6be8346c1254fa2fc12ad853b2bacd0e6c1056e'}]}


def v1_repository(base, plans):
    """A disposable repository whose origin/main carries a v1 registry of content-only bundles."""
    origin, work = base / 'origin.git', base / 'work'
    git(base, 'init', '-q', '--bare', str(origin))
    git(base, 'clone', '-q', str(origin), str(work))
    registry = {'schema': 'readiness-contract/1', 'plans': []}
    for plan_id, goals in plans.items():
        generation = hashlib.sha256(plan_id.encode()).hexdigest()
        path = '.ai/handoff/readiness-v1/%s/%s/goals.json' % (plan_id, generation)
        write_json(work / path, {'schema': 'handoff-goals/1', 'id': plan_id, 'goals': [{'id': g} for g in goals]})
        registry['plans'].append({'schema': 'readiness-contract/1', 'id': 'northstar-plan-' + plan_id, 'plan_id': plan_id,
                                  'generation': generation, 'status': 'active',
                                  'artifacts': {'bundle': {'path': path}}})
    write_json(work / V1_REGISTRY, registry)
    git(work, 'add', '-A')
    git(work, 'commit', '-q', '-m', 'v1 registry')
    git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
    git(work, 'fetch', '-q', 'origin')
    return work


def host(merged=MERGED, open_prs=OPEN, branches=BRANCHES):
    return {'merged_prs': [{'number': n, 'headRefName': ref, 'headRefOid': None, 'mergeCommit': {'oid': commit},
                            'title': TITLES.get(n, '')} for n, ref, commit in merged],
            'open_prs': [{'number': n, 'headRefName': ref, 'headRefOid': sha} for n, ref, sha in open_prs],
            'branches': [{'ref': ref, 'sha': sha} for ref, sha, _ in branches]}


def recorded_ancestry(root, commit, ref):
    """The recorded aitool-root ancestry facts: True, False, or None for an unknown object."""
    if commit in ANCESTORS:
        return True
    return False if commit in KNOWN else None


class RecordedRootInventoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()
        self.work = v1_repository(self.base, ROOT_PLANS)

    def inventory(self, state, ancestry=recorded_ancestry):
        with mock.patch.object(observer, 'ancestry', ancestry):
            return observer.run(['inventory-v1', '--root', str(self.work)], adapter=observer.FixtureAdapter(state))

    def entries(self, result):
        return {entry['plan_id']: entry for entry in result['entries']}

    def test_recorded_root_data_reproduces_the_real_fates(self):
        exit_code, result = self.inventory(host())
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['schema'], 'v1-inventory/1')
        self.assertEqual(result['adapter'], 'fixture')
        entries = self.entries(result)
        self.assertEqual({plan: entry['fate'] for plan, entry in entries.items()}, {
            'opencode-omo-gap-fill-r2': 'completed', 'northstar-small-work-profiles': 'unstarted',
            'xskp-p1-registry-core': 'completed', 'xskp-p2-publication': 'completed',
            'xskp-p3-root-adoption': 'partly-merged'})
        merged = lambda plan: sorted((m['goal'], m['pr']) for m in entries[plan]['merged'])
        # P1-01 merged by #81 although its title omits the id (and by #78); #75 names P1-02..04 only in text.
        self.assertIn(('XSKP-P1-01', 81), merged('xskp-p1-registry-core'))
        self.assertIn(('XSKP-P1-01', 78), merged('xskp-p1-registry-core'))
        self.assertNotIn(75, {pr for _, pr in merged('xskp-p1-registry-core')})
        self.assertEqual({goal for goal, pr in merged('xskp-p1-registry-core') if pr in (84, 85, 86)},
                         {'XSKP-P1-02', 'XSKP-P1-03', 'XSKP-P1-04'})
        # P2-02/P2-03 merged by #88/#90, whose titles and main commit messages omit the ids.
        self.assertIn(('XSKP-P2-02', 88), merged('xskp-p2-publication'))
        self.assertIn(('XSKP-P2-03', 90), merged('xskp-p2-publication'))
        # G-03 maps to both #71 and #72.
        self.assertEqual([pr for goal, pr in merged('opencode-omo-gap-fill-r2') if goal == 'G-03'], [71, 72])
        for entry in entries.values():
            for item in entry['merged']:
                self.assertEqual(set(item), {'goal', 'pr', 'merge_commit'})
        p3 = entries['xskp-p3-root-adoption']
        self.assertEqual(merged('xskp-p3-root-adoption'),
                         [('XSKP-P3-01', 89), ('XSKP-P3-02', 91), ('XSKP-P3-03', 92), ('XSKP-P3-04', 93)])
        self.assertEqual(p3['unmerged'], ['XSKP-P3-05'])
        self.assertEqual(p3['action'], 'migrate-unmerged')
        self.assertEqual(p3['in_flight'], [])
        self.assertNotIn('fix/xskp-p3-policy-current-20261002', json.dumps(p3))
        self.assertEqual(entries['northstar-small-work-profiles']['action'], 'migrate')
        self.assertEqual(entries['xskp-p2-publication']['action'], 'retire')
        self.assertEqual(entries['xskp-p2-publication']['retire_record']['merged'], entries['xskp-p2-publication']['merged'])
        self.assertNotIn('refusals', result)

    def test_titles_and_commit_text_are_never_signals(self):
        renamed = [(n, 'chore/renamed-%d' % n if n in (81, 78) else ref, commit) for n, ref, commit in MERGED]
        # Without the P1-01 head branches (and their leftover origin branch) only text names P1-01.
        state = host(merged=renamed, open_prs=[], branches=[])
        for pull in state['merged_prs']:
            pull['title'] = 'XSKP-P1-01 ' + pull['title']
        entries = self.entries(self.inventory(state)[1])
        self.assertEqual(entries['xskp-p1-registry-core']['fate'], 'partly-merged')
        self.assertEqual(entries['xskp-p1-registry-core']['unmerged'], ['XSKP-P1-01'])

    def test_partly_merged_plan_with_an_open_pr_for_an_unmerged_goal_is_in_flight(self):
        open_prs = OPEN + [(95, 'feat/knowledge-closeout-xskp-p3-05', '9' * 40)]
        exit_code, result = self.inventory(host(open_prs=open_prs))
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        p3 = self.entries(result)['xskp-p3-root-adoption']
        self.assertEqual((p3['fate'], p3['action']), ('in-flight', 'wait'))
        self.assertEqual(p3['in_flight'], [{'goal': 'XSKP-P3-05', 'pr': 95, 'ref': 'feat/knowledge-closeout-xskp-p3-05'}])
        self.assertIn('v1_inventory_in_flight', codes(result))

    def test_unmerged_origin_branch_carrying_the_token_is_in_flight(self):
        branches = BRANCHES + [('refs/heads/wip/XSKP-P3-05', '8' * 40, False)]
        with mock.patch.dict(globals(), {'KNOWN': KNOWN | {'8' * 40}}):
            exit_code, result = self.inventory(host(branches=branches))
        self.assertEqual(exit_code, 1)
        self.assertEqual(self.entries(result)['xskp-p3-root-adoption']['fate'], 'in-flight')
        # A branch already reachable from origin/<target> is merged history, not in flight.
        merged_branch = BRANCHES + [('refs/heads/wip/XSKP-P3-05', ROOT_MAIN, True)]
        self.assertEqual(self.entries(self.inventory(host(branches=merged_branch))[1])['xskp-p3-root-adoption']['fate'],
                         'partly-merged')

    def test_unreachable_api_unattributable_and_truncated_lists_are_in_flight(self):
        class Unreachable(observer.FixtureAdapter):
            def merged_prs(self, limit=observer.AUDIT_LIMIT):
                raise v2.Invalid('hosted_api_unavailable:pr list')
        with mock.patch.object(observer, 'ancestry', recorded_ancestry):
            exit_code, result = observer.run(['inventory-v1', '--root', str(self.work)], adapter=Unreachable(host()))
        self.assertEqual(exit_code, 1, json.dumps(result, indent=1))
        self.assertEqual({e['fate'] for e in result['entries']}, {'in-flight'})
        self.assertTrue(all(e['ambiguous'] for e in result['entries']))
        # A token match whose merge commit cannot be observed cannot be attributed: ambiguous.
        unknown = MERGED + [(96, 'feat/close-SWP-ROOT-01', '7' * 40)]
        swp = self.entries(self.inventory(host(merged=unknown))[1])['northstar-small-work-profiles']
        self.assertEqual(swp['fate'], 'in-flight')
        self.assertEqual(swp['ambiguous'][0]['goal'], 'SWP-ROOT-01')
        many = [(n, 'chore/n-%d' % n, ROOT_MAIN) for n in range(1000)]
        exit_code, result = self.inventory(host(merged=many))
        self.assertEqual(exit_code, 1)
        self.assertEqual({e['fate'] for e in result['entries']}, {'in-flight'})


class AncestryInventoryTests(unittest.TestCase):
    """Real git ancestry: a PR merged on a branch that never reached origin/<target> is refused."""

    def test_pr_merged_off_target_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            work = v1_repository(base, {'plan-x': ['PX-01', 'PX-02']})
            on_main = git(work, 'rev-parse', 'HEAD')
            git(work, 'checkout', '-q', '-b', 'release/side')
            (work / 'side.txt').write_text('merged into a side branch\n')
            git(work, 'add', '-A')
            git(work, 'commit', '-q', '-m', 'merge of PX-02 into release/side')
            off_main = git(work, 'rev-parse', 'HEAD')
            git(work, 'checkout', '-q', 'main')
            state = host(merged=[(1, 'feat/plan-x-PX-01', on_main), (2, 'feat/plan-x-PX-02', off_main)],
                         open_prs=[], branches=[])
            exit_code, result = observer.run(['inventory-v1', '--root', str(work)], adapter=observer.FixtureAdapter(state))
            self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
            entry = result['entries'][0]
            self.assertEqual(entry['merged'], [{'goal': 'PX-01', 'pr': 1, 'merge_commit': on_main}])
            self.assertEqual(entry['refused'], [{'goal': 'PX-02', 'pr': 2, 'merge_commit': off_main,
                                                 'reason': 'merge_commit_not_on_target'}])
            self.assertEqual((entry['fate'], entry['unmerged']), ('partly-merged', ['PX-02']))

    def test_goal_token_is_case_insensitive_and_bounded_by_non_alphanumerics(self):
        token = v2.goal_token('XSKP-P1-01')
        for ref in ('feat/knowledge-registry-XSKP-P1-01', 'feat/xskp-p1-01', 'XSKP-P1-01', 'fix/x_xskp-p1-01.y'):
            self.assertTrue(token.search(ref), ref)
        for ref in ('feat/xskp-p1-010', 'feat/axskp-p1-01', 'feat/xskp-p1-0', 'chore/xskp-p1-admission-preparation'):
            self.assertFalse(token.search(ref), ref)


class SkillsInventoryTests(unittest.TestCase):
    """The skills fates: ach-skills-contract-v2's v1 generation retires; xskp-p5 is unstarted."""

    def test_skills_fates_and_the_registry_retire_record(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            work = v1_repository(base, {'ach-skills-contract-v2': ['ACH-S-01'],
                                        'xskp-p5-skill-producers': ['XSKP-P5-01', 'XSKP-P5-02', 'XSKP-P5-03', 'XSKP-P5-04']})
            main = git(work, 'rev-parse', 'HEAD')
            state = host(merged=[(97, 'feat/ach-skills-contract-v2-ACH-S-01', main),
                                 (95, 'chore/ach-s01-bootstrap-preparation', main),
                                 (93, 'chore/xskp-p5-admission-preparation', main)],
                         open_prs=[(100, 'prep/xskp-p5-readiness-v2-20261004', '1' * 40)],
                         branches=[('refs/heads/chore/xskp-p5-admission-preparation', main, True),
                                   ('refs/heads/docs/xskp-p5-planning-publication', '1' * 40, False),
                                   ('refs/heads/prep/xskp-p5-readiness-v2-20261004', '1' * 40, False)])
            exit_code, result = observer.run(['inventory-v1', '--root', str(work)], adapter=observer.FixtureAdapter(state))
            self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
            entries = {e['plan_id']: e for e in result['entries']}
            self.assertEqual((entries['ach-skills-contract-v2']['fate'], entries['ach-skills-contract-v2']['action']),
                             ('completed', 'retire'))
            self.assertEqual((entries['xskp-p5-skill-producers']['fate'], entries['xskp-p5-skill-producers']['action']),
                             ('unstarted', 'migrate'))
            record = entries['ach-skills-contract-v2']['retire_record']
            self.assertEqual(set(record), set(S01_RETIRE))
            self.assertEqual(record['merged'], [{'goal': 'ACH-S-01', 'pr': 97, 'merge_commit': main}])

    def test_live_v2_registry_retires_s01_and_v1_bytes_are_unchanged(self):
        registry = json.loads((REPO / REGISTRY).read_text())
        self.assertEqual(registry['retired_v1'], [S01_RETIRE])
        self.assertNotIn('northstar-plan-ach-skills-contract-v2', [p['id'] for p in registry['plans'] if p.get('generation') ==
                                                                    S01_RETIRE['generation']])
        self.assertEqual((REPO / REGISTRY).read_bytes(),
                         (json.dumps(registry, indent=2, sort_keys=True) + '\n').encode())
        self.assertEqual(hashlib.sha256((REPO / V1_REGISTRY).read_bytes()).hexdigest(), V1_REGISTRY_SHA256)
        digest = hashlib.sha256()
        for path in sorted(p for p in (REPO / '.ai/handoff/readiness-v1').rglob('*') if p.is_file()):
            digest.update(path.relative_to(REPO).as_posix().encode() + b'\0' +
                          hashlib.sha256(path.read_bytes()).hexdigest().encode() + b'\n')
        self.assertEqual(digest.hexdigest(), V1_GENERATIONS_DIGEST)


class InventoryAdmissionTests(unittest.TestCase):
    """An in-flight v1 entry refuses the policy goal's admission with a named gap."""

    def test_policy_goal_admission_refuses_while_a_v1_entry_is_in_flight(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            policy_goal = {'id': 'P', 'scope': [POLICY], 'acceptance_criteria': ['policy lands'], 'dependencies': [],
                           'verification': ['bash tests/check.sh']}
            fixture = Fixture(base, bundle=sample_bundle([policy_goal]), candidate=True, live_policy=False)
            write_json(fixture.work / V1_REGISTRY, {'schema': 'readiness-contract/1', 'plans': [
                {'id': 'northstar-plan-old', 'plan_id': 'old', 'generation': 'a' * 64, 'status': 'active',
                 'artifacts': {'bundle': {'path': '.ai/handoff/readiness-v1/old/%s/goals.json' % ('a' * 64)}}}]})
            write_json(fixture.work / '.ai/handoff/readiness-v1/old' / ('a' * 64) / 'goals.json',
                       {'schema': 'handoff-goals/1', 'id': 'old', 'goals': [{'id': 'OLD-01'}]})
            fixture.commit_push('a v1 registry with one entry')
            fixture.approve('in-session')
            busy = observer.FixtureAdapter({'merged_prs': [], 'branches': [],
                                            'open_prs': [{'number': 5, 'headRefName': 'feat/old-OLD-01', 'headRefOid': '5' * 40}]})
            exit_code, context = fixture.admit(goal='P', adapter=busy)
            self.assertNotEqual(exit_code, 0)
            self.assertIn('v1_inventory_in_flight', codes(context), json.dumps(context['gaps'], indent=1))
            idle = observer.FixtureAdapter({'merged_prs': [], 'branches': [], 'open_prs': []})
            exit_code, context = fixture.admit(goal='P', adapter=idle)
            self.assertEqual(exit_code, 0, json.dumps(context['gaps'], indent=1))


if __name__ == '__main__':
    unittest.main()
