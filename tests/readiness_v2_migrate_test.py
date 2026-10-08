"""readiness-contract/2 migration (R1, O10, ACH-S-05).

`migrate-handoff.sh --to readiness-contract/2 --legacy <v1 goals.json> --inventory <report.json>`
emits a reviewable v2 candidate of one v1 generation's unmerged goals: content preserved
(`goal_revision_v2` deterministic), an empty-hold sidecar, the legacy bundle and its sha256
retained under `extensions`, no write to `.ai/handoff/readiness-v1/**`, and no authority.
The merged goals come from the recorded inventory-v1 `{goal, pr, merge_commit}` map, never
from commit text. Without `--to` the v1 output stays byte-identical (AC-3). The P5
generation is published through the admission-complete publisher and its planning admission
reports only the approval gap (AC-7). Disposable fixtures and recorded repository state only;
nothing here approves, publishes into this checkout, or writes into `.ai/handoff/readiness-v1`.
"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from datetime import timedelta
from unittest import mock

from readiness_v2_core_test import (AUTO, NOW, POLICY, REGISTRY, REPO, Fixture, Keys, codes, gh_shim, git, sha, stamp,
                                    v2, observer, write_json)
from readiness_v2_inventory_test import V1_GENERATIONS_DIGEST, V1_REGISTRY_SHA256
from readiness_fixture import fixture as v1_fixture, write as v1_write

P5 = '.ai/handoff/readiness-v1/xskp-p5-skill-producers/4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c/goals.json'
P5_SHA256 = '8089c7c77e5aadb62c1a003fb7b30c78465ceb65541fc5b7927b3e2a0bd58cff'
P5_BUNDLE_SHA256 = '8cecc2369ffbed09ad860c7708d0662cf109cc219b386fac31666bfc40c5ed5a'
P5_SIDECAR_SHA256 = '60b1f70bd4788f8334a8befd2c8587c86e8c06137824c6b361c8d6e7a91e702a'
P5_REVISIONS = {
    'XSKP-P5-01': '4c48da95733c37f2d645f0d4b1bbf6ddc31b3cf1595b8f78a5d5d8315e665dba',
    'XSKP-P5-02': '74c6274b3b678b0048f462bcfaf1b22a820ea691e90d4b7d74cfab62ec8b4dc0',
    'XSKP-P5-03': '365cad2ceeb3f0b4d7d98e5f781297dab5ca63c76877edde176a76292963c303',
    'XSKP-P5-04': 'b638957040c8a39c8acb3f22663ce0096afb09d673d90d425007e5db8b014bac',
}
P5_SPEC = 'docs/specifications/ACTIVE/cross-surface-knowledge-publication-xskp-p5-skill-producers.md'
V1_REGISTRY = '.ai/workflows/northstar-readiness-v1.json'
GOAL_IDS = ['XSKP-P5-01', 'XSKP-P5-02', 'XSKP-P5-03', 'XSKP-P5-04']


def repo_p5_legacy():
    path = REPO / P5
    return json.loads(path.read_text()), path.read_bytes()


def recorded_p5_inventory():
    """The recorded inventory-v1 report for the REPO v1 registry: P5 unstarted, nothing merged."""
    return {'schema': 'v1-inventory/1', 'registry': V1_REGISTRY, 'target': 'refs/remotes/origin/main',
            'entries': [{'id': 'northstar-plan-xskp-p5-skill-producers', 'plan_id': 'xskp-p5-skill-producers',
                         'generation': '4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c',
                         'goals': list(GOAL_IDS), 'fate': 'unstarted', 'action': 'migrate', 'merged': [],
                         'unmerged': list(GOAL_IDS), 'in_flight': [], 'ambiguous': [], 'refused': []}]}


def repo_candidate():
    """The candidate the pinned transform builds from the REPO's recorded inputs (B-S05-3)."""
    legacy, legacy_bytes = repo_p5_legacy()
    return v2.migrate_main(legacy, sha(legacy_bytes),
                           json.loads((REPO / V1_REGISTRY).read_text()),
                           recorded_p5_inventory(), sha(REPO / P5_SPEC))


def synthetic_legacy(plan_id, goals, spec_sha256):
    """A content-only v1 bundle with every mutable and legacy field a v1 goal may carry."""
    return {'schema': 'handoff-goals/1', 'id': plan_id, 'repository': {'id': 'fixture', 'root': '/fixture'},
            'spec': {'path': 'spec.md', 'sha256': spec_sha256}, 'issue_ref': 'issue:fixture:' + plan_id,
            'planning_complete': True, 'status': 'active', 'attachments': {'note': 'kept verbatim'},
            'goals': [{'id': gid, 'repository': {'id': 'fixture', 'root': '/fixture'},
                       'scope': ['src/%s.txt' % gid], 'acceptance_criteria': [gid + ' works'],
                       'dependencies': list(dependencies), 'verification': ['bash tests/check.sh'],
                       'issue_ref': 'issue:fixture:' + plan_id, 'owner': 'unassigned',
                       'coverage_status': 'unknown', 'legacy_safe_tdd': True,
                       'legacy_risk_reason': 'Unmeasured fixture coverage',
                       'readiness': {'preparation': 'blocked', 'implementation': 'unknown', 'merge': 'unknown'},
                       'readiness_notes': {'preparation': 'planning inputs must land first'}}
                      for gid, dependencies in goals]}


def synthetic_registry(plan_id, legacy_sha256):
    return {'schema': 'readiness-contract/1', 'plans': [
        {'schema': 'readiness-contract/1', 'id': 'northstar-plan-' + plan_id, 'plan_id': plan_id,
         'generation': 'd' * 64, 'status': 'active', 'planning_complete': True,
         'handoff_path': '.ai/handoff/readiness-v1/%s/%s/handoff.md' % (plan_id, 'd' * 64),
         'artifacts': {'bundle': {'path': '.ai/handoff/readiness-v1/%s/%s/goals.json' % (plan_id, 'd' * 64),
                                  'sha256': legacy_sha256}}}]}


def synthetic_inventory(plan_id, fate, merged=(), unmerged=(), goals=()):
    return {'schema': 'v1-inventory/1', 'registry': V1_REGISTRY, 'entries': [
        {'id': 'northstar-plan-' + plan_id, 'plan_id': plan_id, 'generation': 'd' * 64,
         'goals': list(goals) or [item['goal'] for item in merged] + list(unmerged),
         'fate': fate, 'action': 'migrate-unmerged' if fate == 'partly-merged' else 'migrate',
         'merged': [dict(item) for item in merged], 'unmerged': list(unmerged),
         'in_flight': [], 'ambiguous': [], 'refused': []}]}


def migration_refusal(legacy, registry, inventory, spec_sha256):
    """The refusal code migrate_main raises for these inputs, or None when it succeeds."""
    try:
        v2.migrate_main(legacy, sha(json.dumps(legacy, sort_keys=True).encode()), registry, inventory, spec_sha256)
    except v2.Invalid as error:
        return v2.code(error)
    return None


class MigrateCandidateTests(unittest.TestCase):
    """AC1 pure transform: content preservation, B5 inputs, refusals, determinism, no v1 leakage."""

    def test_unstarted_p5_preserves_content(self):
        candidate = repo_candidate()
        self.assertEqual(candidate['schema'], 'handoff-migration/2')
        self.assertEqual(candidate['authority'], v2.NO_AUTHORITY)
        self.assertEqual(candidate['from']['contract'], 'readiness-contract/1')
        self.assertEqual(candidate['from']['registration'], 'northstar-plan-xskp-p5-skill-producers')
        self.assertEqual(candidate['from']['generation'], '4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c')
        self.assertEqual(candidate['from']['fate'], 'unstarted')
        bundle = candidate['bundle']
        self.assertEqual(bundle['id'], 'xskp-p5-skill-producers')  # P7: the plan id stays as is
        self.assertEqual(bundle['repository'], {'id': 'skills'})
        self.assertEqual(bundle['spec'], {'path': P5_SPEC})
        self.assertEqual([goal['id'] for goal in bundle['goals']], GOAL_IDS)
        legacy = json.loads((REPO / P5).read_text())
        for goal in bundle['goals']:
            source = next(g for g in legacy['goals'] if g['id'] == goal['id'])
            self.assertEqual(goal['scope'], source['scope'])
            self.assertEqual(goal['acceptance_criteria'], source['acceptance_criteria'])
            self.assertEqual(goal['dependencies'], source['dependencies'])
            self.assertEqual(goal['verification'], source['verification'])
        self.assertEqual(v2.bundle_sha256(bundle), P5_BUNDLE_SHA256)
        self.assertEqual(v2.canonical(candidate['sidecar']), P5_SIDECAR_SHA256)
        self.assertEqual(candidate['goal_revisions'], P5_REVISIONS)
        self.assertEqual(candidate['dropped_dependencies'], [])
        self.assertEqual(candidate['extensions']['legacy_sha256'], P5_SHA256)
        self.assertEqual(candidate['extensions']['legacy_original'], legacy)
        self.assertEqual(candidate['extensions']['b5_inputs'], [])
        self.assertEqual(bundle['attachments'], legacy['attachments'])  # D3: kept verbatim

    def test_partly_merged_moves_merged_goals_to_b5(self):
        spec_sha256 = 'f' * 64
        legacy = synthetic_legacy('plan-part', [('G1', ()), ('G2', ('G1',)), ('G3', ('G2',))], spec_sha256)
        merged = [{'goal': 'G1', 'pr': 7, 'merge_commit': 'a' * 40}]
        candidate = v2.migrate_main(legacy, sha(json.dumps(legacy, sort_keys=True).encode()),
                                    synthetic_registry('plan-part', sha(json.dumps(legacy, sort_keys=True).encode())),
                                    synthetic_inventory('plan-part', 'partly-merged', merged, ['G2', 'G3']),
                                    spec_sha256)
        self.assertEqual([goal['id'] for goal in candidate['bundle']['goals']], ['G2', 'G3'])
        self.assertEqual(candidate['bundle']['goals'][0]['dependencies'], [])
        self.assertEqual(candidate['dropped_dependencies'], [{'goal': 'G2', 'dependency': 'G1'}])
        self.assertEqual(candidate['extensions']['b5_inputs'], merged)
        self.assertEqual(set(candidate['sidecar']['goals']), {'G2', 'G3'})

    def test_refusals(self):
        spec_sha256 = 'f' * 64
        legacy = synthetic_legacy('plan-part', [('G1', ())], spec_sha256)
        legacy_sha256 = sha(json.dumps(legacy, sort_keys=True).encode())
        registry = synthetic_registry('plan-part', legacy_sha256)
        for fate in ('completed', 'in-flight'):
            self.assertEqual(migration_refusal(legacy, registry, synthetic_inventory('plan-part', fate, goals=['G1']),
                                               spec_sha256), 'migration_fate_refused')
        older = json.loads((REPO / '.ai/handoff/readiness-v1/xskp-p5-skill-producers/182c7739e1d5954e100efacf68ec7300f282bac1f5166b37673c1ebdf62d6159/goals.json').read_text())
        p5_registry = json.loads((REPO / V1_REGISTRY).read_text())
        self.assertEqual(migration_refusal(older, p5_registry, recorded_p5_inventory(), spec_sha256),
                         'migration_legacy_unregistered')
        self.assertEqual(migration_refusal(legacy, registry, synthetic_inventory('plan-part', 'unstarted', unmerged=['G1']),
                                           'e' * 64), 'migration_spec_drifted')
        self.assertEqual(migration_refusal(dict(legacy, schema='handoff-goals/9'), registry,
                                           synthetic_inventory('plan-part', 'unstarted', unmerged=['G1']), spec_sha256),
                         'migration_legacy_unsupported')
        malformed = synthetic_inventory('plan-part', 'partly-merged',
                                        [{'goal': 'G1', 'pr': 7, 'merge_commit': 'a' * 40, 'extra': True}], ['G2'])
        self.assertEqual(migration_refusal(legacy, registry, malformed, spec_sha256), 'migration_b5_invalid')

    def test_deterministic_and_v1_fields_never_leak(self):
        spec_sha256 = 'f' * 64
        legacy = synthetic_legacy('plan-part', [('G1', ()), ('G2', ('G1',))], spec_sha256)
        registry = synthetic_registry('plan-part', sha(json.dumps(legacy, sort_keys=True).encode()))
        inventory = synthetic_inventory('plan-part', 'unstarted', unmerged=['G1', 'G2'])
        first = v2.migrate_main(legacy, sha(json.dumps(legacy, sort_keys=True).encode()), registry, inventory, spec_sha256)
        second = v2.migrate_main(json.loads(json.dumps(legacy)), sha(json.dumps(legacy, sort_keys=True).encode()),
                                 registry, inventory, spec_sha256)
        self.assertEqual(v2.canonical(first), v2.canonical(second))
        for goal in first['bundle']['goals']:
            for key in ('readiness', 'readiness_notes', 'owner', 'coverage_status', 'coverage_percent',
                        'legacy_safe_tdd', 'legacy_risk_reason', 'repository'):
                self.assertNotIn(key, goal, key)
        self.assertNotIn('planning_complete', first['bundle'])
        self.assertNotIn('status', first['bundle'])
        self.assertNotIn('root', first['bundle']['repository'])
        self.assertNotIn('sha256', first['bundle']['spec'])
        v2.validate_bundle(first['bundle'])
        v2.validate_sidecar(first['sidecar'], first['bundle'])


def disposable_v1_repo(base, plan_id='plan-m', goals=('M1',)):
    """A bare origin plus clone holding one v1 registry entry, its generation and its spec."""
    origin, work = base / 'origin.git', base / 'work'
    git(base, 'init', '-q', '--bare', str(origin))
    git(base, 'clone', '-q', str(origin), str(work))
    spec_text = plan_id + ' specification\n'
    legacy = synthetic_legacy(plan_id, [(gid, goals[:index]) for index, gid in enumerate(goals)],
                              sha(spec_text.encode()))
    legacy_path = '.ai/handoff/readiness-v1/%s/%s/goals.json' % (plan_id, 'd' * 64)
    write_json(work / legacy_path, legacy)
    write_json(work / V1_REGISTRY,
               synthetic_registry(plan_id, sha((json.dumps(legacy, indent=2, sort_keys=True) + '\n').encode())))
    (work / 'spec.md').write_text(spec_text)
    git(work, 'add', '-A')
    git(work, 'commit', '-q', '-m', 'fixture: v1 generation')
    git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
    git(work, 'fetch', '-q', 'origin')
    head = git(work, 'rev-parse', 'HEAD')
    return origin, work, head, legacy_path


class MigrateEntryTests(unittest.TestCase):
    """AC1 CLI: the candidate goes to stdout, nothing is written, usage errors exit 2."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def run_cli(self, *args, cwd=None, env=None):
        return subprocess.run(['bash', str(AUTO / 'migrate-handoff.sh'), *args], capture_output=True, text=True,
                              cwd=cwd or self.base, stdin=subprocess.DEVNULL, env=env, timeout=300)

    def test_cli_emits_candidate_and_writes_nothing(self):
        origin, work, head, legacy_path = disposable_v1_repo(self.base)
        report = write_json(self.base / 'inventory.json', synthetic_inventory('plan-m', 'unstarted', unmerged=['M1']))
        before = {p.relative_to(work).as_posix(): p.read_bytes() for p in sorted(work.rglob('*'))
                  if p.is_file() and '.git' not in p.relative_to(work).parts}
        result = self.run_cli('--to', 'readiness-contract/2', '--legacy', str(work / legacy_path),
                              '--inventory', str(report), '--root', str(work), cwd=work)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        candidate = json.loads(result.stdout)
        self.assertEqual(candidate['schema'], 'handoff-migration/2')
        self.assertEqual(candidate['authority'], v2.NO_AUTHORITY)
        self.assertEqual([goal['id'] for goal in candidate['bundle']['goals']], ['M1'])
        self.assertEqual(candidate['provenance'], 'source-lane')
        self.assertEqual(candidate['target_revision'], head)
        expected = v2.migrate_main(json.loads((work / legacy_path).read_text()), sha(work / legacy_path),
                                   json.loads((work / V1_REGISTRY).read_text()), json.loads(report.read_text()),
                                   sha(work / 'spec.md'))
        self.assertEqual({key: value for key, value in candidate.items()
                          if key not in ('provenance', 'target_revision')}, expected)
        after = {p.relative_to(work).as_posix(): p.read_bytes() for p in sorted(work.rglob('*'))
                 if p.is_file() and '.git' not in p.relative_to(work).parts}
        self.assertEqual(before, after, 'the candidate is printed, never written')
        self.assertFalse((work / '.git/ai-catapult/observer/driver-log.jsonl').exists(),
                         'a no-authority transform must not write a driver-log entry')

    def test_usage_and_proceed_exit_2(self):
        cases = [('--to', 'readiness-contract/3', '--legacy', 'x', '--inventory', 'y'),
                 ('--to', 'readiness-contract/2', '--legacy', 'x'),
                 ('--to', 'readiness-contract/2', '--inventory', 'y'),
                 ('--to', 'readiness-contract/2', '--legacy', 'x', '--inventory', 'y', 'proceed'),
                 ('--to', 'readiness-contract/2', '--legacy', 'x', '--inventory', 'y', '-h'),
                 ('--to', 'readiness-contract/2', '--legacy', 'x', '--inventory', 'y', '--help')]
        for args in cases:
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(json.loads(result.stdout)['schema'], 'readiness-contract/2')
                self.assertEqual(json.loads(result.stdout)['refusals'], [{'code': 'usage', 'detail': 'unknown or missing argument'}])

    def test_merged_by_branch_token_not_commit_text(self):
        """Characterization through migrate: the inventory-v1 map decides merges from head-branch
        tokens only. PR 7's (unobservable) title and squash message name G1 but its head is
        docs/notes; PR 8's head carries the token. Only PR 8 merges G1."""
        origin, work, head, legacy_path = disposable_v1_repo(self.base, plan_id='plan-tok', goals=('G1', 'G2'))
        state = self.base / 'gh-state.json'
        write_json(state, {'merged_prs': [
            {'number': 7, 'headRefName': 'docs/notes', 'headRefOid': head, 'baseRefName': 'main',
             'mergeCommit': {'oid': head}, 'mergedAt': '2026-10-01T00:00:00Z'},
            {'number': 8, 'headRefName': 'feat/x-plan-tok-G1', 'headRefOid': head, 'baseRefName': 'main',
             'mergeCommit': {'oid': head}, 'mergedAt': '2026-10-01T00:00:00Z'}],
            'open_prs': []})
        shim = gh_shim(self.base / 'bin', state, self.base / 'gh-log.jsonl')
        env = dict(os.environ, PATH=str(shim.parent) + os.pathsep + os.environ['PATH'])
        run = subprocess.run(['bash', str(AUTO / 'contract-run.sh'), 'inventory-v1', '--root', str(work)],
                             capture_output=True, text=True, stdin=subprocess.DEVNULL, env=env, timeout=300)
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        report = json.loads(run.stdout)
        entry = next(e for e in report['entries'] if e['id'] == 'northstar-plan-plan-tok')
        self.assertEqual(entry['fate'], 'partly-merged')
        self.assertEqual([item['goal'] for item in entry['merged']], ['G1'])
        self.assertEqual([item['pr'] for item in entry['merged']], [8])
        report_path = write_json(self.base / 'inventory.json', report)
        migrated = self.run_cli('--to', 'readiness-contract/2', '--legacy', str(work / legacy_path),
                                '--inventory', str(report_path), '--root', str(work), cwd=work)
        self.assertEqual(migrated.returncode, 0, migrated.stdout + migrated.stderr)
        candidate = json.loads(migrated.stdout)
        self.assertEqual([goal['id'] for goal in candidate['bundle']['goals']], ['G2'])
        self.assertEqual(candidate['dropped_dependencies'], [{'goal': 'G2', 'dependency': 'G1'}])
        self.assertEqual(candidate['extensions']['b5_inputs'], [{'goal': 'G1', 'pr': 8, 'merge_commit': head}])


class MigrateV1PathTests(unittest.TestCase):
    """AC2 characterization: without --to the v1 legacy-migration output stays byte-identical."""

    def test_without_to_v1_output_unchanged(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            root = base / 'fixture'
            root.mkdir()
            v1_fixture(root)
            v1_write(root, 'legacy.json', {'id': 'legacy-chosen', 'implementation_ready': True,
                                           'root_causes': ['kept']})

            def run(script, *extra):
                return subprocess.run(['bash', str(script), *extra, '--root', str(root), '--legacy',
                                       str(root / 'legacy.json'), '--bundle', str(root / 'plan.json')],
                                      capture_output=True, text=True, cwd=root, stdin=subprocess.DEVNULL,
                                      timeout=300)
            via_entry = run(AUTO / 'migrate-handoff.sh')
            via_contract = run(AUTO / 'contract-run.sh', 'migrate')
            self.assertEqual(via_entry.returncode, 0, via_entry.stdout + via_entry.stderr)
            self.assertEqual(json.loads(via_entry.stdout)['schema'], 'readiness-contract/1')
            self.assertEqual(via_entry.stdout, via_contract.stdout)
            self.assertEqual(via_entry.returncode, via_contract.returncode)


class MigrationAdmissionTests(unittest.TestCase):
    """AC1 admission: the migrated generation refuses until one new plan approval binds it; the
    previous plan's approval never counts."""

    def test_admission_refuses_until_a_new_approval_binds_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            fixture = Fixture(base)
            fixture.approve('in-session')
            legacy = synthetic_legacy('plan-m', [('M1', ())], sha(fixture.work / 'spec.md'))
            legacy_sha256 = sha(json.dumps(legacy, sort_keys=True).encode())
            candidate = v2.migrate_main(legacy, legacy_sha256, synthetic_registry('plan-m', legacy_sha256),
                                        synthetic_inventory('plan-m', 'unstarted', unmerged=['M1']),
                                        sha(fixture.work / 'spec.md'))
            inputs = Path(tempfile.mkdtemp(prefix='plan-m-', dir=base))
            patches = fixture.hooks()
            for patch in patches:
                patch.start()
            try:
                exit_code, result = observer.run(['publish-v2', '--root', str(fixture.work),
                                                 '--bundle', str(write_json(inputs / 'bundle.json', candidate['bundle'])),
                                                 '--sidecar', str(write_json(inputs / 'sidecar.json', candidate['sidecar']))],
                                                now=NOW)
            finally:
                for patch in reversed(patches):
                    patch.stop()
            self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
            entry = result['published']
            self.assertEqual(entry['plan_id'], 'plan-m')
            fixture.commit_push('publish the migrated plan-m generation')
            # The migrated generation is refused: no approval binds it, and plan-a's never counts.
            exit_code, context = fixture.run(['admit-v2', '--root', str(fixture.work), '--handoff',
                                              'northstar-plan-plan-m', '--goal-id', 'M1', '--stage', 'implementation'])
            self.assertNotEqual(exit_code, 0)
            self.assertIn('approval_tag_missing', codes(context))
            self.assertEqual(fixture.admit()[0], 0, "the previous plan's approval still admits its own plan")
            # One new in-session approval binding the new generation admits it.
            record = v2.approval_record(plan_id='plan-m', generation=entry['generation'],
                                        bundle_sha256=v2.bundle_sha256(candidate['bundle']),
                                        spec_sha256=sha(fixture.work / 'spec.md'),
                                        policy_sha256=sha(fixture.work / POLICY),
                                        sidecar_sha256=v2.canonical(candidate['sidecar']), goals=['M1'],
                                        owner='Fixture Owner', reviewer_lane='independent review lane',
                                        issued_at=stamp(NOW - timedelta(hours=1)), expires_at=stamp(NOW + timedelta(days=6)),
                                        anchor_sha256=fixture.anchor_sha256, assurance='in-session')
            line = json.dumps(record, sort_keys=True, separators=(',', ':'))
            message = line + '\ndigest-echo: ' + sha(line.encode()) + '\n'
            message_path = base / 'plan-m-approval.msg'
            message_path.write_text(message)
            tag = 'approval/plan-m/' + entry['generation'][:12]
            git(fixture.work, 'tag', '-f', '-a', '--cleanup=verbatim', '-F', str(message_path), tag,
                git(fixture.work, 'rev-parse', 'HEAD'))
            git(fixture.work, 'push', '-q', '-f', 'origin', 'refs/tags/' + tag)
            git(fixture.work, 'fetch', '-q', 'origin')
            exit_code, context = fixture.run(['admit-v2', '--root', str(fixture.work), '--handoff',
                                              'northstar-plan-plan-m', '--goal-id', 'M1', '--stage', 'implementation'])
            self.assertEqual(exit_code, 0, json.dumps(context, indent=1))
            self.assertEqual(context['assurance'], 'in-session')


class PublishedP5Tests(unittest.TestCase):
    """AC3 repository state: the committed P5 v2 generation is exactly the migration of its v1
    generation, an offline publish-v2 replay reproduces it byte for byte, and the v1 bytes are
    unchanged."""

    def p5_entry(self):
        registry = json.loads((REPO / REGISTRY).read_text())
        entries = [entry for entry in registry['plans'] if entry.get('plan_id') == 'xskp-p5-skill-producers']
        return entries, registry

    def test_p5_generation_is_the_migration_of_its_v1_generation(self):
        entries, _ = self.p5_entry()
        self.assertEqual(len(entries), 1)
        entry = entries[0]
        self.assertEqual(entry['id'], 'northstar-plan-xskp-p5-skill-producers')
        self.assertEqual(entry['plan_id'], 'xskp-p5-skill-producers')  # P7
        self.assertEqual(entry['mode'], 'live')
        self.assertEqual(entry['status'], 'active')
        candidate = repo_candidate()
        prefix = '.ai/handoff/readiness-v2/xskp-p5-skill-producers/' + entry['generation']
        for name, value in (('goals.json', candidate['bundle']), ('sidecar.json', candidate['sidecar'])):
            self.assertEqual((REPO / prefix / name).read_bytes(),
                             json.dumps(value, indent=2, sort_keys=True).encode() + b'\n', name)
        # The generation derives from the entry's own digests, so a later policy-only republish stays green.
        self.assertEqual(entry['generation'], v2.generation_v2(v2.bundle_sha256(candidate['bundle']),
                                                               entry['spec']['sha256'], entry['policy_sha256'],
                                                               entry['anchor_sha256']))

    def test_offline_replay_is_byte_equal(self):
        entries, _ = self.p5_entry()
        entry = entries[0]
        prefix = '.ai/handoff/readiness-v2/xskp-p5-skill-producers/' + entry['generation']
        base = Path(tempfile.mkdtemp()).resolve()
        # P5 was republished against the amended live policy (the republish ACH-AM-01 mandated),
        # so the committed generation binds the live bytes and its byte-for-byte H1 replay runs
        # under them. A later policy change moves the live digest again and would force another
        # republish plus the same collateral re-pin ACH-AM-01 made here.
        published_policy = REPO / POLICY
        self.assertEqual(sha(published_policy), entry['policy_sha256'])
        for relative in (REGISTRY, entry['spec']['path'], 'tests/run-tests.sh'):
            source, target = REPO / relative, base / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
        target = base / POLICY
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(published_policy.read_bytes())
        registry = json.loads((REPO / REGISTRY).read_text())
        write_json(base / REGISTRY, dict(registry, plans=[p for p in registry['plans']
                                                          if p.get('plan_id') != 'xskp-p5-skill-producers']))
        for path in sorted((REPO / '.ai/handoff/readiness-v2').rglob('*')):
            if path.is_file() and 'xskp-p5-skill-producers' not in path.relative_to(REPO).parts:
                target = base / path.relative_to(REPO)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(path.read_bytes())
        # The H1 replay: the unflagged publish-v2 over the base's reserved paths and the head's
        # goals.json/sidecar.json, run offline and compared tree entry for tree entry.
        exit_code, result = observer.run(['publish-v2', '--root', str(base), '--bundle', str(REPO / prefix / 'goals.json'),
                                          '--sidecar', str(REPO / prefix / 'sidecar.json')], now=NOW)
        self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
        self.assertEqual(result['published'], entry)
        self.assertEqual(result['generation'], entry['generation'])
        for path in sorted(base.rglob('*')):
            if not path.is_file():
                continue
            relative = path.relative_to(base)
            if relative.as_posix() == POLICY:
                # The replay lane compares the reserved entries, never the policy file (S-05 §3.4):
                # the base carries the policy this generation was published with.
                self.assertEqual(path.read_bytes(), published_policy.read_bytes(), relative.as_posix())
                continue
            if relative.as_posix() == REGISTRY:
                # The plans list is compared order-insensitively: the publisher appends entries,
                # so a second plan published after P5 changes the append order, while every entry
                # stays byte-identical (H1 holds per generation; the cross-plan order is history).
                produced = json.loads(path.read_bytes())
                expected = json.loads((REPO / relative).read_bytes())
                self.assertEqual({k: v for k, v in produced.items() if k != 'plans'},
                                 {k: v for k, v in expected.items() if k != 'plans'}, relative.as_posix())
                self.assertEqual(sorted(json.dumps(p, sort_keys=True) for p in produced['plans']),
                                 sorted(json.dumps(p, sort_keys=True) for p in expected['plans']),
                                 relative.as_posix())
                continue
            self.assertEqual(path.read_bytes(), (REPO / relative).read_bytes(), relative.as_posix())

    def test_v1_bytes_unchanged(self):
        self.assertEqual(sha(REPO / V1_REGISTRY), V1_REGISTRY_SHA256)
        digest = hashlib.sha256()
        for path in sorted(p for p in (REPO / '.ai/handoff/readiness-v1').rglob('*') if p.is_file()):
            digest.update(path.relative_to(REPO).as_posix().encode() + b'\0' +
                          hashlib.sha256(path.read_bytes()).hexdigest().encode() + b'\n')
        self.assertEqual(digest.hexdigest(), V1_GENERATIONS_DIGEST)


class PlanningGapTests(unittest.TestCase):
    """AC4 characterization: the migrated P5 generation's planning admission reports only the
    approval gap as ACH-S-04 defines it, and its approval is P5's own."""

    def test_migrated_p5_reports_only_the_approval_gap(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp).resolve()
            keys = Keys(base)
            origin, work = base / 'origin.git', base / 'work'
            git(base, 'init', '-q', '--bare', str(origin))
            git(base, 'clone', '-q', str(origin), str(work))
            spec = REPO / P5_SPEC
            target = work / P5_SPEC
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(spec.read_bytes())
            (work / 'scripts').mkdir(parents=True)
            (work / 'scripts/validate-skill-catalog.py').write_text('#!/bin/sh\nexit 0\n')
            (work / 'scripts/validate-skill-catalog.py').chmod(0o755)
            for name in ('AGENTS.md', 'CLAUDE.md', 'GEMINI.md'):
                (work / name).write_text('Fixture instructions\n')
            (work / '.rules.ts').write_text('export const rules = {};\n')
            (work / '.ai/rules').mkdir(parents=True)
            (work / '.ai/rules/security.md').write_text('Fixture security rules\n')
            (work / '.ai/rules/technical-bounds.md').write_text('Fixture technical bounds\n')
            (work / 'tests').mkdir()
            (work / 'tests/run-tests.sh').write_text('#!/bin/sh\nexit 0\n')
            (work / 'tests/run-tests.sh').chmod(0o755)
            git(work, 'add', '-A')
            git(work, 'commit', '-q', '-m', 'fixture: skills-shaped repository')
            initial = git(work, 'rev-parse', 'HEAD')
            policy = json.loads((REPO / POLICY).read_text())
            policy['approval']['anchor_sha256'] = sha(keys.anchor)
            for gate in policy['gates']:
                if gate['kind'] == 'harness_trust':
                    gate['binding'] = {'commit': initial}
            write_json(work / POLICY, policy)
            git(work, 'add', '-A')
            git(work, 'commit', '-q', '-m', 'fixture: live policy with the fixture anchor and harness')
            git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
            git(work, 'fetch', '-q', 'origin')
            entry = self.p5_entry()[0][0]
            repo_prefix = '.ai/handoff/readiness-v2/xskp-p5-skill-producers/' + entry['generation']
            patches = [mock.patch.object(observer, 'anchor_locator', lambda: Path(keys.anchor)),
                       mock.patch.object(observer, 'signing_key_locator', lambda: keys.paths['certifier'])]
            path_extra = []
            for tool in ('prek', 'gh'):
                if shutil.which(tool) is None:
                    stub = base / 'bin'
                    stub.mkdir(exist_ok=True)
                    (stub / tool).write_text('#!/bin/sh\nexit 0\n')
                    (stub / tool).chmod(0o755)
                    path_extra.append(str(stub))
            if path_extra:
                patches.append(mock.patch.dict(os.environ, PATH=os.pathsep.join(path_extra + [os.environ['PATH']])))
            for patch in patches:
                patch.start()
            try:
                exit_code, result = observer.run(['publish-v2', '--root', str(work), '--bundle',
                                                  str(REPO / repo_prefix / 'goals.json'), '--sidecar',
                                                  str(REPO / repo_prefix / 'sidecar.json'), '--admit-planning'], now=NOW)
            finally:
                for patch in reversed(patches):
                    patch.stop()
            self.assertEqual(exit_code, 0, json.dumps(result, indent=1))
            self.assertTrue(result['planning_complete'])
            planning = result['planning']
            self.assertEqual(planning['blocking'], [])
            self.assertLessEqual({'approval_tag_missing', 'plan_approval_missing', 'ownership_unresolved'},
                                 {gap['code'] for gap in planning['approval']})
            self.assertLessEqual({'branch_target_mismatch', 'pr_required', 'review_lane_missing',
                                  'threads_unobserved', 'dependency_incomplete'},
                                 {gap['code'] for gap in planning['deferred']})
            deferred_gates = {gap['gate'] for gap in planning['deferred'] if gap['gate']}
            self.assertTrue(deferred_gates)
            for gate in result['gates']:
                if gate['id'] in deferred_gates:
                    self.assertEqual(gate['status'], 'deferred', gate)
            generation = result['generation']
            prefix = '.ai/handoff/readiness-v2/xskp-p5-skill-producers/' + generation
            self.assertEqual((work / prefix / 'goals.json').read_bytes(),
                             (REPO / repo_prefix / 'goals.json').read_bytes())
            # P5's approval is its own: a foreign plan's record under P5's tag refuses.
            record = v2.approval_record(plan_id='ach-skills-contract-v2', generation=generation,
                                        bundle_sha256=v2.bundle_sha256(json.loads((REPO / repo_prefix / 'goals.json').read_text())),
                                        spec_sha256=sha(work / P5_SPEC), policy_sha256=sha(work / POLICY),
                                        sidecar_sha256=v2.canonical(json.loads((REPO / repo_prefix / 'sidecar.json').read_text())),
                                        goals=list(GOAL_IDS), owner='Fixture Owner',
                                        reviewer_lane='independent review lane',
                                        issued_at=stamp(NOW - timedelta(hours=1)),
                                        expires_at=stamp(NOW + timedelta(days=6)),
                                        anchor_sha256=sha(keys.anchor), assurance='in-session')
            line = json.dumps(record, sort_keys=True, separators=(',', ':'))
            message = line + '\ndigest-echo: ' + sha(line.encode()) + '\n'
            message_path = base / 'foreign-approval.msg'
            message_path.write_text(message)
            git(work, 'add', '-A')
            git(work, 'commit', '-q', '-m', 'publish the migrated P5 generation')
            git(work, 'push', '-q', 'origin', 'HEAD:refs/heads/main')
            git(work, 'fetch', '-q', 'origin')
            publication_commit = git(work, 'rev-parse', 'HEAD')
            tag = 'approval/xskp-p5-skill-producers/' + generation[:12]
            git(work, 'tag', '-f', '-a', '--cleanup=verbatim', '-F', str(message_path), tag, publication_commit)
            git(work, 'push', '-q', '-f', 'origin', 'refs/tags/' + tag)
            git(work, 'fetch', '-q', 'origin')
            state = base / 'gh-state.json'
            write_json(state, {'merged_prs': [], 'open_prs': [], 'branches': [],
                               'pulls': {}, 'checks': {}, 'threads': {}, 'protection': None})
            patches = [mock.patch.object(observer, 'anchor_locator', lambda: Path(keys.anchor)),
                       mock.patch.object(observer, 'signing_key_locator', lambda: keys.paths['certifier'])]
            for patch in patches:
                patch.start()
            try:
                exit_code, context = observer.run(['admit-v2', '--root', str(work), '--handoff',
                                                   'northstar-plan-xskp-p5-skill-producers', '--goal-id', 'XSKP-P5-01',
                                                   '--stage', 'planning'],
                                                  now=NOW, adapter=observer.FixtureAdapter(state))
            finally:
                for patch in reversed(patches):
                    patch.stop()
            self.assertNotEqual(exit_code, 0)
            self.assertIn('approval_plan_mismatch', codes(context))

    def p5_entry(self):
        registry = json.loads((REPO / REGISTRY).read_text())
        entries = [entry for entry in registry['plans'] if entry.get('plan_id') == 'xskp-p5-skill-producers']
        return entries, registry


class OwnershipP5Tests(unittest.TestCase):
    """AC5 ownership: ACH-S-05 is this plan's only v2 path for XSKP P5, the published
    generation touches only its own directory, and no P5 approval is requested before the
    post-S-06 default_mode amendment. #100 is hosted and untouched; that stays procedural."""

    def p5_entry(self):
        registry = json.loads((REPO / REGISTRY).read_text())
        entries = [entry for entry in registry['plans'] if entry.get('plan_id') == 'xskp-p5-skill-producers']
        return entries, registry

    def test_p5_is_the_only_v2_path_and_confined_to_its_directory(self):
        entries, _ = self.p5_entry()
        self.assertEqual(len(entries), 1)
        entry = entries[0]
        self.assertEqual(entry['plan_id'], 'xskp-p5-skill-producers')  # P7: never a -v2 variant
        prefix = '.ai/handoff/readiness-v2/xskp-p5-skill-producers/' + entry['generation']
        for artifact in entry['artifacts'].values():
            self.assertTrue(str(artifact['path']).startswith(prefix + '/'), artifact)
        self.assertEqual(entry['handoff_path'], prefix + '/handoff.md')

    def test_no_p5_approval_request_before_the_amendment(self):
        for name in ('xskp-p5-skill-producers-plan-approval-request.json',
                     'xskp-p5-skill-producers-plan-approval.md'):
            self.assertFalse((REPO / '.ai/handoff' / name).exists(), name)


class ReleaseSurfaceTests(unittest.TestCase):
    """AC6 hygiene: re-pinned manifests and local CI contract, the documented migration surface,
    and no SKILL.md growth."""

    def test_migration_surface_and_pins(self):
        import local_ci_contract
        local_ci_contract.read_contract(REPO)  # a stale pin raises ValueError
        manifest = json.loads((AUTO / 'readiness-dependency-v2.json').read_text())
        self.assertEqual((AUTO / 'readiness-dependency-v2.json').read_bytes(),
                         (REPO / '02-govern-plan/northstar/readiness-dependency-v2.json').read_bytes())
        for name in ('migrate-handoff.sh', 'contract-run-v2.sh', 'lib/readiness_contract_v2.py'):
            self.assertEqual(manifest['files'][name], sha(AUTO / name), name)
        contract = json.loads((REPO / '.ai/ci/local-ci.json').read_text())
        for name in ('tests/readiness_v2_migrate_test.py', 'tests/readiness_v2_migrate_test.sh',
                     '04-validate-handoff/autobahn/contract-run-v2.sh',
                     '04-validate-handoff/autobahn/lib/readiness_contract_v2.py',
                     '04-validate-handoff/autobahn/readiness-dependency-v2.json',
                     '02-govern-plan/northstar/readiness-dependency-v2.json'):
            self.assertEqual(contract['sources'].get(name), sha(REPO / name), name)
        text = (AUTO / 'modules/readiness-v2.md').read_text()
        for phrase in ('migrate-handoff.sh --to readiness-contract/2', 'handoff-migration/2',
                       'migration_legacy_unsupported', 'migration_legacy_unregistered',
                       'migration_fate_refused', 'migration_spec_drifted', 'migration_b5_invalid',
                       'extensions.b5_inputs', 'carries no authority', '--root "$(pwd -P)"',
                       'northstar/handoff-write.sh'):
            self.assertIn(phrase, text, phrase)
        # Pin advanced by XSKP-P5-02 (plan xskp-p5-skill-producers): the registered
        # knowledge-publication pointer change deliberately edits five producer SKILL.md
        # files. The pin is a content digest over every tracked */SKILL.md (path, index
        # mode and working-tree bytes), the same file set `git diff <commit> -- '*/SKILL.md'`
        # compared: a commit pin breaks once a squash merge drops the branch-only commit
        # (git exit 128), a digest holds in any clone. Per-goal re-pin, like
        # tests/fixtures/host-default-golden.json: the next goal that edits a SKILL.md
        # advances it (maintenance precedent: ACH goals #104..#114).
        listed = subprocess.run(['git', '-C', str(REPO), 'ls-files', '-s', '-z', '--', '*/SKILL.md'],
                                capture_output=True, check=True).stdout.split(b'\0')
        files = []
        for record in (item for item in listed if item):
            meta, path = record.split(b'\t', 1)
            files.append((path, meta.split(b' ', 1)[0],
                          hashlib.sha256((REPO / os.fsdecode(path)).read_bytes()).hexdigest()))
        digest = hashlib.sha256()
        for path, mode, file_sha in sorted(files):
            digest.update(path + b'\0' + mode + b'\0' + bytes.fromhex(file_sha))
        current = '\n'.join(f'{mode.decode()} {file_sha} {os.fsdecode(path)}' for path, mode, file_sha in sorted(files))
        self.assertEqual(digest.hexdigest(), 'ca420e6e708b8babe3f60092be3501b7c594a0c3e92b61725fbc04df78133cba',
                         'a tracked */SKILL.md changed; re-pin only for a deliberate, reviewed edit. '
                         'Current mode, sha256 and path per file:\n' + current)


if __name__ == '__main__':
    unittest.main()
