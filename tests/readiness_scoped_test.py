"""RT-02 read-only readiness regressions, simulated external contexts only."""
import copy
import json
import subprocess
import shutil
from datetime import datetime, timedelta, timezone
from pathlib import Path
import sys
import tempfile
import unittest
from argparse import Namespace
from readiness_fixture import fixture, write, digest
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / '04-validate-handoff/autobahn/lib'))
import readiness_contract as c

class ScopedTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.bundle, self.context = fixture(self.root)

    def admit(self, stage='planning', context=False):
        write(self.root, 'direct.json', {'schema': 'direct-goal/1', 'bundle': self.bundle})
        self.context['authority']['subject_sha256'] = digest(self.root / 'direct.json')
        write(self.root, 'context.json', self.context)
        return c.admit(Namespace(root=str(self.root), goal=str(self.root / 'direct.json'), handoff=None,
                                goal_id=None, context=str(self.root / 'context.json') if context else None, stage=stage))

    def test_planning_missing_context_reports_all_stages_without_authorizing(self):
        report = self.admit()
        self.assertTrue(report['planning_complete'])
        self.assertFalse(report['execution_ready'])
        self.assertEqual(set(report['per_goal']['G1']), set(c.STAGES))
        self.assertEqual({g['stage'] for g in report['gaps']}, set(c.STAGES))
        for gap in report['gaps']:
            self.assertIn('recovery', gap)
            self.assertIn('responsible', gap)
            self.assertIn('freshness', gap)

    def test_planning_reports_stage_gaps_with_context(self):
        report = self.admit(context=True)
        self.assertEqual(report['per_goal']['G1']['implementation']['status'], 'ready')
        self.assertEqual(report['per_goal']['G1']['merge']['status'], 'unknown')

    def test_bare_dependency_completion_is_not_evidence(self):
        self.bundle['goals'].append(dict(copy.deepcopy(self.bundle['goals'][0]), id='G2', dependencies=['G1']))
        self.context['completed_goals'] = ['G1']
        self.context['authority']['goals'] = ['G2']
        gaps = c.policy_admit(self.root, self.bundle, ['G2'], self.context, 'implementation', self.context['authority']['subject_sha256'])
        self.assertTrue(gaps)

    def install_gate(self, kind, binding, scope=None):
        gate = {'id': 'typed', 'kind': kind, 'stage': 'implementation',
                'scope': scope or {'goals': ['G1']}, 'binding': binding}
        policy = json.loads((self.root / c.POLICY).read_text())
        policy['gates'].append(gate)
        for dimension in c.gate_dimensions(gate):
            policy['not_applicable'].pop(dimension, None)
        write(self.root, c.POLICY, policy)
        self.context['policy']['sha256'] = digest(self.root / c.POLICY)
        self.receipt(gate, binding)
        return gate

    def receipt(self, gate, value):
        now = datetime.now(timezone.utc)
        receipt = {'gate': gate['id'], 'stage': gate['stage'], 'scope': gate['scope'], 'status': 'pass',
                   'subject_sha256': c.gate_subject(self.bundle, gate, self.context['sources'], self.context['policy']), 'issuer': 'simulated-reviewer',
                   'evidence': ['local:observed'], 'observed_at': (now-timedelta(minutes=1)).isoformat(),
                   'expires_at': (now+timedelta(hours=1)).isoformat(), 'value': value}
        self.context['results'] = [receipt]
        return receipt

    def gaps(self, selected=None):
        selected = selected or ['G1']
        self.context['authority']['goals'] = selected
        return c.policy_admit(self.root, self.bundle, selected, self.context, 'implementation',
                              self.context['authority']['subject_sha256'])

    def test_ownership_requires_names_not_placeholders_or_boolean(self):
        gate = self.install_gate('ownership', {'roles': ['owner', 'reviewer']})
        for value in ({'owner': 'Ada', 'reviewer': 'TBD'}, True, {'owner': 'Ada'}):
            self.receipt(gate, value)
            self.assertTrue(self.gaps())
        self.receipt(gate, {'owner': 'Ada', 'reviewer': 'Grace'})
        self.assertEqual(self.gaps(), [])

    def test_fixture_checks_executable_isolation_tool_and_never_executes(self):
        script = self.root / 'tests/check.sh'
        script.write_text('#!/bin/bash\ntouch '+str(self.root/'SHOULD_NOT_RUN')+'\n')
        script.chmod(0o755)
        binding = {'file': {'path': 'tests/check.sh', 'sha256': digest(script)}, 'command': 'bash tests/check.sh',
                   'isolation': 'temporary-directory', 'tool': 'bash'}
        self.install_gate('fixture', binding)
        self.assertEqual(self.gaps(), [])
        self.assertFalse((self.root / 'SHOULD_NOT_RUN').exists())
        script.chmod(0o644)
        self.assertIn('fixture_not_executable', str(self.gaps()))
        script.chmod(0o755)
        binding['tool'] = 'nonexistent-readiness-tool-123'
        self.install_gate_replacing('fixture', binding)
        self.assertIn('tool_unavailable', str(self.gaps()))

    def install_gate_replacing(self, kind, binding, scope=None):
        policy = json.loads((self.root / c.POLICY).read_text())
        policy['gates'] = [g for g in policy['gates'] if g['id'] != 'typed']
        write(self.root, c.POLICY, policy)
        return self.install_gate(kind, binding, scope)

    def test_receipts_preserve_unrelated_goals_reject_changed_approval_and_expiry(self):
        self.bundle['goals'].append(dict(copy.deepcopy(self.bundle['goals'][0]), id='G2'))
        gate = self.install_gate('protected_approval', {'subject': {'mode': 'goal-scope', 'goal': 'G1',
                                                                 'goal_sha256': c.goal_revision(self.bundle, 'G1')}})
        self.assertEqual(self.gaps(), [])
        self.bundle['goals'][1]['acceptance_criteria'] = ['Unrelated change']
        self.assertEqual(self.gaps(), [])
        self.context['results'][0]['expires_at'] = '2000-01-01T00:00:00Z'
        self.assertIn('expired', str(self.gaps()))
        self.receipt(gate, gate['binding'])
        self.bundle['goals'][0]['scope'].append('other.py')
        self.assertIn('approval_goal_subject_mismatch', str(self.gaps()))

    def test_full_file_approval_remains_full_file(self):
        self.install_gate('protected_approval', {'subject': {'mode': 'full-file', 'file': {'path': 'evidence.txt', 'sha256': digest(self.root / 'evidence.txt')}}})
        self.assertEqual(self.gaps(), [])
        (self.root / 'evidence.txt').write_text('other goal changed same file')
        self.assertIn('stale_file', str(self.gaps()))

    def test_trust_mismatch_diagnostics_independent_and_read_only(self):
        write(self.root, 'lock.json', {'commit': 'b'*40})
        write(self.root, 'anchor.json', {'commit': 'a'*40})
        anchor = {'path': 'anchor.json', 'sha256': digest(self.root / 'anchor.json')}
        policy = json.loads((self.root / c.POLICY).read_text())
        policy['sources'].append(anchor)
        write(self.root, c.POLICY, policy)
        self.context['sources'] = policy['sources']
        self.install_gate('harness_trust', {'lock': {'path': 'lock.json', 'sha256': digest(self.root / 'lock.json')}, 'anchor': anchor}, {'repository': True})
        before = {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()}
        gaps = self.gaps()
        self.assertIn('expected='+'a'*40, str(gaps))
        self.assertIn('actual='+'b'*40, str(gaps))
        self.assertIn('independent_source=anchor.json', str(gaps))
        self.assertEqual(before, {str(p): digest(p) for p in self.root.rglob('*') if p.is_file()})

    def test_three_goal_scoping_and_revision_bound_dependencies(self):
        self.bundle['goals'] += [dict(copy.deepcopy(self.bundle['goals'][0]), id='G2'),
                                dict(copy.deepcopy(self.bundle['goals'][0]), id='G3', dependencies=['G1'])]
        self.install_gate('tooling', {'tool': 'no-such-fixture-tool'}, {'repository': True})
        self.assertEqual(self.gaps(['G1','G2','G3'])[-1]['blocked_goals'], ['G1','G2','G3'])
        self.install_gate_replacing('tooling', {'tool': 'no-such-fixture-tool'})
        self.assertEqual(self.gaps(['G2']), [])
        self.assertTrue(self.gaps(['G3']))
        now = datetime.now(timezone.utc)
        self.context['completed_goals'] = [{'goal': 'G1', 'goal_sha256': c.goal_revision(self.bundle,'G1'),
            'status': 'complete', 'issuer': 'simulated', 'evidence': ['local:test-result'],
            'observed_at': (now-timedelta(minutes=1)).isoformat(), 'expires_at': (now+timedelta(hours=1)).isoformat()}]
        self.assertTrue(self.gaps(['G3']), 'Current failed dependency gate must override old completion')
        self.install_gate_replacing('tooling', {'tool': 'bash'})
        self.assertEqual(self.gaps(['G3']), [])
        self.bundle['goals'][0]['acceptance_criteria'] = ['New revision']
        self.assertIn('dependency_incomplete', str(self.gaps(['G3'])))

    def test_receipt_borrowing_source_drift_and_unknown_fields_fail_closed(self):
        gate = self.install_gate('branch_target', {'target': 'main', 'branch': 'fix/G1'})
        self.assertEqual(self.gaps(), [])
        self.context['results'][0]['scope'] = {'goals': ['G2']}
        self.assertIn('subject_mismatch', str(self.gaps()))
        self.receipt(gate, gate['binding'])
        self.context['results'][0]['approved'] = True
        self.assertIn('typed_evidence_fields', str(self.gaps()))
        self.receipt(gate, gate['binding'])
        (self.root/'AGENTS.md').write_text('changed independently governed policy')
        self.assertIn('stale_file', str(self.gaps()))

    def test_missing_and_self_trust_anchor_stay_unready(self):
        write(self.root, 'lock.json', {'commit': 'a'*40})
        lock = {'path': 'lock.json', 'sha256': digest(self.root/'lock.json')}
        self.install_gate('harness_trust', {'lock': lock, 'anchor': lock})
        self.assertIn('trust_anchor_not_independent', str(self.gaps()))
        self.install_gate_replacing('harness_trust', {'lock': lock, 'anchor': {'path':'missing.json','sha256':'a'*64}})
        self.assertIn('trust_source_unavailable', str(self.gaps()))

    def test_planning_with_malformed_context_retains_consolidated_unknowns(self):
        self.context['results'] = True
        report = self.admit(context=True)
        self.assertTrue(report['planning_complete'])
        self.assertEqual({gap['stage'] for gap in report['gaps']}, set(c.STAGES))
        self.assertFalse(report['execution_ready'])

    def test_bad_fixture_command_is_never_executed(self):
        script=self.root/'tests/check.sh'
        script.chmod(0o755)
        binding={'file':{'path':'tests/check.sh','sha256':digest(script)},'command':'bash tests/check.sh; touch SHOULD_NOT_RUN','isolation':'temporary-directory','tool':'bash'}
        self.install_gate('fixture',binding)
        self.assertTrue(self.gaps())
        self.assertFalse((self.root/'SHOULD_NOT_RUN').exists())

    def test_policy_change_invalidates_approval_receipt(self):
        gate = self.install_gate('protected_approval', {'subject': {'mode': 'goal-scope', 'goal': 'G1', 'goal_sha256': c.goal_revision(self.bundle,'G1')}})
        self.assertEqual(self.gaps(), [])
        policy=json.loads((self.root/c.POLICY).read_text())
        policy['not_applicable']['tooling']='Revised approved rationale'
        write(self.root,c.POLICY,policy)
        self.context['policy']['sha256']=digest(self.root/c.POLICY)
        self.assertIn('subject_mismatch',str(self.gaps()))

    def test_revoked_malformed_and_expired_receipt_report_actual_metadata(self):
        gate=self.install_gate('ownership',{'roles':['owner']})
        receipt=self.receipt(gate,{'owner':'Ada'})
        receipt['status']='revoked'
        self.assertTrue(self.gaps())
        receipt=self.receipt(gate,{'owner':'Ada'})
        receipt['observed_at']=True
        self.assertIn('freshness_required',str(self.gaps()))
        receipt=self.receipt(gate,{'owner':'Ada'})
        receipt['expires_at']='2000-01-01T00:00:00Z'
        report=self.admit('implementation',True)
        failed=next(f for f in report['gaps'] if f['code']=='gate_failed')
        self.assertEqual(failed['freshness']['expires_at'],receipt['expires_at'])
        self.assertEqual(failed['evidence_refs'],receipt['evidence'])
        self.assertIn('owner',failed['recovery'])
        self.assertEqual(report['remaining_blockers'],report['gaps'])

    def test_resolved_receipts_and_unknown_status_are_explicit(self):
        gate=self.install_gate('ownership',{'roles':['owner']})
        receipt=self.receipt(gate,{'owner':'Ada'})
        report=self.admit(context=True)
        resolved=next(r for r in report['resolved'] if r['gate']=='typed')
        self.assertEqual(resolved['status'],'ready')
        self.assertEqual(resolved['evidence_refs'],receipt['evidence'])
        self.assertTrue(any(r['status']=='not_applicable' for r in report['resolved']))
        report=self.admit()
        self.assertEqual(report['per_goal']['G1']['implementation']['status'],'unknown')

    def test_hardlinked_trust_anchor_is_not_independent(self):
        import os
        write(self.root,'lock.json',{'commit':'a'*40})
        os.link(self.root/'lock.json',self.root/'anchor.json')
        self.install_gate('harness_trust',{'lock':{'path':'lock.json','sha256':digest(self.root/'lock.json')},'anchor':{'path':'anchor.json','sha256':digest(self.root/'anchor.json')}})
        self.assertIn('trust_anchor_not_independent',str(self.gaps()))

    def test_unavailable_tool_unknown_unsupported_never_resolved_ready(self):
        self.install_gate('tooling', {'tool':'no-such-readiness-tool'})
        report=self.admit('implementation',True)
        self.assertEqual(report['per_goal']['G1']['implementation']['status'],'unknown')
        policy=json.loads((self.root/c.POLICY).read_text())
        policy['gates'][-1]={'dimension':'tooling','id':'unsupported','kind':'unknown-kind','stage':'implementation','scope':{'repository':True}}
        write(self.root,c.POLICY,policy)
        self.context['policy']['sha256']=digest(self.root/c.POLICY)
        report=self.admit('implementation',True)
        self.assertFalse(any(r['gate']=='unsupported' for r in report['resolved']))

    def test_redact_all_external_metadata(self):
        secret='https://user:TOPSECRET@example.invalid/path?token=TOPSECRET'
        gate=self.install_gate('ownership', {'roles':['owner']})
        receipt=self.receipt(gate,{'owner':'Ada'})
        receipt.update(issuer=secret, observed_at=secret, expires_at=secret, evidence=[secret])
        report=self.admit('implementation',True)
        self.assertNotIn('TOPSECRET',json.dumps(report))

    def test_planning_keeps_known_local_gaps_without_context(self):
        self.bundle['goals'][0]['readiness']['implementation']='blocked'
        report=self.admit()
        self.assertTrue(any(g['code']=='goal_not_ready' for g in report['gaps']))
        self.assertTrue(any(g['code']=='policy_context_invalid' for g in report['gaps']))

    def test_nonexistent_approval_goal_is_structured_failure(self):
        self.install_gate('protected_approval', {'subject':{'mode':'goal-scope','goal':'NONEXISTENT','goal_sha256':'a'*64}}, {'repository':True})
        self.assertIn('approval_goal_subject_mismatch',str(self.gaps()))

    def test_transitive_completion_revision_and_deep_dag(self):
        self.bundle['goals'] += [dict(copy.deepcopy(self.bundle['goals'][0]),id='G2',dependencies=['G1']),dict(copy.deepcopy(self.bundle['goals'][0]),id='G3',dependencies=['G2'])]
        old=c.goal_revision(self.bundle,'G2')
        self.bundle['goals'][0]['acceptance_criteria']=['Changed ancestor']
        self.assertNotEqual(old,c.goal_revision(self.bundle,'G2'))
        for i in range(4,1201):
            self.bundle['goals'].append(dict(copy.deepcopy(self.bundle['goals'][0]), id=f'G{i}', dependencies=[f'G{i-1}']))
        self.assertEqual(len(c.goal_revision(self.bundle,'G1200')),64)

    def test_completed_preparation_ancestor_does_not_need_feature_readiness(self):
        self.bundle['goals'][0]['readiness']['implementation']='unknown'
        self.bundle['goals'].append(dict(copy.deepcopy(self.bundle['goals'][0]),id='G2', dependencies=['G1'],readiness={s:'ready' for s in c.STAGES}))
        now=datetime.now(timezone.utc)
        self.context['completed_goals']=[{'goal':'G1','goal_sha256':c.goal_revision(self.bundle,'G1'),'status':'complete','issuer':'simulated','evidence':['local:passed'],'observed_at':(now-timedelta(minutes=1)).isoformat(),'expires_at':(now+timedelta(hours=1)).isoformat()}]
        self.assertEqual(self.gaps(['G2']),[])
        self.install_gate('tooling',{'tool':'no-such-tool'})
        self.assertTrue(self.gaps(['G2']), 'Actual current prerequisite gate still applies')

    def test_plan_source_anchor_extra_field_alias_and_enriched_envelope_rejected(self):
        import os
        write(self.root,'lock.json',{'commit':'a'*40})
        lock={'path':'lock.json','sha256':digest(self.root/'lock.json')}
        self.install_gate('harness_trust',{'lock':lock,'anchor':dict(self.bundle['spec'],extra='ignored')})
        self.assertIn('trust_sources_required',str(self.gaps()))
        os.link(self.root/self.bundle['spec']['path'],self.root/'spec-alias.json')
        self.install_gate_replacing('harness_trust',{'lock':lock,'anchor':{'path':'spec-alias.json','sha256':digest(self.root/'spec-alias.json')}})
        self.assertIn('trust_anchor_is_plan_source',str(self.gaps()))
        write(self.root,'enriched.json',{'schema':'direct-goal/1','bundle':self.bundle,'commit':'a'*40})
        anchor={'path':'enriched.json','sha256':digest(self.root/'enriched.json')}
        policy=json.loads((self.root/c.POLICY).read_text())
        policy['sources'].append(anchor)
        write(self.root,c.POLICY,policy)
        self.context['sources']=policy['sources']
        self.install_gate_replacing('harness_trust',{'lock':lock,'anchor':anchor})
        self.assertIn('trust_anchor_is_plan_source',str(self.gaps()))

    def test_goal_additive_requirement_preserved_with_and_without_context(self):
        self.bundle['goals'][0]['requirements']=[{'id':'added','kind':'file_digest','stage':'implementation','scope':{'goals':['G1']},'path':'missing-fixture','sha256':'a'*64}]
        report=self.admit(context=True)
        self.assertTrue(any('added:' in gap['detail'] for gap in report['gaps']))
        report=self.admit()
        self.assertTrue(report['planning_complete'])
        self.assertFalse(report['execution_ready'])
        self.assertIn('policy_context_invalid',str(report['gaps']))

    def test_missing_context_ancestor_gap_binds_selected_dependents(self):
        self.bundle['goals'] += [dict(copy.deepcopy(self.bundle['goals'][0]),id='G2',dependencies=['G1']),dict(copy.deepcopy(self.bundle['goals'][0]),id='G3',dependencies=['G2'])]
        gaps=c.policy_admit(self.root,self.bundle,['G3'],{},'implementation','a'*64)
        self.assertTrue(gaps)
        self.assertTrue(all(g['blocked_goals']==['G3'] for g in gaps))
        self.assertTrue(all(c.applies(g['scope'],'G3') for g in gaps))

    def test_public_unknown_goal_readiness_stays_unknown_and_denies_admission(self):
        self.bundle['goals'][0]['readiness']['implementation']='unknown'
        self.admit('implementation',True)
        repo=Path(__file__).resolve().parents[1]
        run=subprocess.run(['bash',str(repo/'04-validate-handoff/autobahn/prereq-check.sh'),
            '--root',str(self.root),'--goal',str(self.root/'direct.json'),
            '--context',str(self.root/'context.json')],capture_output=True,text=True)
        self.assertNotEqual(run.returncode,0,run.stdout+run.stderr)
        report=json.loads(run.stdout)
        self.assertFalse(report['execution_ready'])
        self.assertEqual(report['per_goal']['G1']['implementation']['status'],'unknown')
        gap=next(g for g in report['gaps'] if g['code']=='goal_not_ready')
        self.assertEqual(gap['status'],'unknown')

    def test_sensitive_url_is_redacted(self):
        gaps = []
        c.add(gaps, 'test', 'https://user:password@example.test/private?token=secret', 'repository', 'merge')
        self.assertNotIn('secret', str(gaps))
        self.assertNotIn('password', str(gaps))

    def test_public_canonical_flat_and_direct_handoff_equivalence(self):
        repo = Path(__file__).resolve().parents[1]
        flat = self.root / 'flat'
        for name, phase in [('autobahn','04-validate-handoff'), ('northstar','02-govern-plan')]:
            shutil.copytree(repo / phase / name, flat / name)
        publish = subprocess.run(['bash', str(flat/'northstar/handoff-write.sh'), '--root', str(self.root), '--bundle', str(self.root/'plan.json')], capture_output=True, text=True)
        self.assertEqual(publish.returncode, 0, publish.stdout+publish.stderr)
        entry = json.loads(publish.stdout)['published']
        write(self.root, 'direct.json', {'schema':'direct-goal/1','bundle':self.bundle})
        reports=[]
        for auto in (repo/'04-validate-handoff/autobahn', flat/'autobahn'):
            for selector in (['--goal',str(self.root/'direct.json')], ['--handoff',entry['id'],'--goal-id','G1']):
                self.context['authority']['subject_sha256'] = digest(self.root/'direct.json') if selector[0]=='--goal' else entry['artifacts']['bundle']['sha256']
                write(self.root,'context.json',self.context)
                run=subprocess.run(['bash',str(auto/'prereq-check.sh'),'--root',str(self.root),'--context',str(self.root/'context.json'),*selector],capture_output=True,text=True)
                self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                report=json.loads(run.stdout)
                reports.append((report['execution_ready'], report['goals'], report['per_goal']))
        self.assertTrue(all(r == reports[0] for r in reports))

if __name__ == '__main__':
    unittest.main()
