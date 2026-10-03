"""readiness-contract/2: the pure validator.

It decides only from the data it is handed. It runs no command, reads no file and
writes nothing; the pinned observer (observer.py) gathers every fact and this
module compares them. Supplied contexts, observations, verdicts and certificate
claims are only ever compared against a rebuilt decision, never trusted.

v1 helpers are imported read-only (V1_HELPERS); v1 bytes and behavior are frozen.
"""
import hashlib
import json
import re
from datetime import datetime, timedelta, timezone

from readiness_contract import Invalid, canonical, require, string, ID, SHA, REVISION

V1_HELPERS = {'Invalid', 'canonical', 'require', 'string', 'ID', 'SHA', 'REVISION'}
VERSION = 'readiness-contract/2'
POLICY_SCHEMA = 'readiness-policy/2'
BUNDLE_SCHEMA = 'handoff-goals/2'
SIDECAR_SCHEMA = 'readiness-sidecar/1'
APPROVAL_SCHEMA = 'plan-approval/1'
CERTIFICATE_SCHEMA = 'merge-certificate/1'
REVIEW_SCHEMA = 'review-lane/1'
CONTEXT_SCHEMA = 'readiness-context/2'
OBSERVATION_SCHEMA = 'observation/1'
POLICY = '.ai/policies/readiness-policy.json'
REGISTRY = '.ai/workflows/northstar-readiness-v2.json'
GEN = '.ai/handoff/readiness-v2'
STAGES = ('preparation', 'implementation', 'merge')
APPROVED_STAGES = ['implementation', 'merge']
GATE_KINDS = ('ownership', 'review', 'branch_target', 'tooling', 'file_digest', 'git_ancestor',
              'hosted_checks', 'plan_approval', 'fixture', 'harness_trust')
NOT_APPLICABLE = {'fixture': 'no-fixture-dependency', 'harness_trust': 'no-pinned-harness'}
BINDINGS = {'ownership': {'roles'}, 'file_digest': {'path', 'sha256'}, 'git_ancestor': {'commits'},
            'fixture': {'path'}, 'harness_trust': {'commit'}}
FORMS = ('ssh-tag', 'in-session')
ASSURANCE = ('user-presence', 'key-held', 'in-session')
NS_APPROVAL = 'ai-catapult-plan-approval'
NS_REVIEW = 'ai-catapult-review'
NS_CERTIFICATE = 'ai-catapult-certificate'
MAX_AGE_DAYS = 14
POLICY_FIELDS = {'schema', 'repository', 'identity_model', 'sources', 'required_checks', 'skippable_checks',
                 'branch_pattern', 'target', 'tools', 'reviewer_requirements', 'approval', 'gates'}
GATE_FIELDS = {'id', 'kind', 'stage', 'scope', 'binding', 'not_applicable', 'responsible'}
BUNDLE_FIELDS = {'schema', 'id', 'repository', 'spec', 'goals', 'issue_ref', 'attachments'}
GOAL_FIELDS = {'id', 'scope', 'acceptance_criteria', 'dependencies', 'verification', 'issue_ref'}
MUTABLE_GOAL_FIELDS = {'readiness', 'readiness_notes', 'coverage_status', 'coverage_percent', 'legacy_safe_tdd',
                       'legacy_risk_reason', 'owner'}
SIDECAR_GOAL_FIELDS = {'readiness', 'coverage_status', 'coverage_percent', 'legacy_safe_tdd', 'legacy_risk_reason'}
APPROVAL_FIELDS = {'schema', 'plan_id', 'generation', 'bundle_sha256', 'spec_sha256', 'policy_sha256', 'sidecar_sha256',
                   'goals', 'stages', 'owner', 'reviewer_lane', 'issued_at', 'expires_at', 'anchor_sha256', 'assurance'}
CERTIFICATE_FIELDS = {'schema', 'repository', 'plan_id', 'generation', 'goal_id', 'approval_digest', 'assurance', 'pr',
                      'head', 'base', 'base_ref', 'merge_admission_digest', 'local_gates', 'required_checks',
                      'unresolved_threads', 'review_lane', 'lane_independence', 'admin', 'adapter', 'certifier',
                      'issued_at'}
TOOL = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._+-]*$')
STAMP = re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$')
NO_AUTHORITY = 'none: no verified plan approval; this report carries no authority'
NOTICES = {
    'user-presence': 'assurance: user-presence (hardware security key with touch)',
    'key-held': 'assurance: key-held (an approver key signed; no hardware touch is proven)',
    'in-session': 'ASSURANCE: IN-SESSION - an agent-writable digest-echo record, not a signature and no hardware touch',
}
RECOVERY = {
    'approval': 'Obtain one plan approval for this exact generation: contract-run.sh approval-request, then the printed ssh-keygen and git tag commands',
    'anchor': 'A human creates or repairs ~/.config/ai-catapult/allowed_signers outside every worktree; agents never write it',
    'sidecar': 'Tighten only; loosening a sidecar value needs a new plan approval binding the new sidecar',
    'hosted': 'Wait for or fix the hosted check, thread or review at this exact head, then rerun',
    'policy': 'Fix readiness-policy/2 through a reviewed policy goal; a bundle can never relax it',
}


def refuse(code_text, detail=''):
    raise Invalid(code_text + (':' + str(detail) if detail != '' else ''))


def check(condition, code_text, detail=''):
    if not condition:
        refuse(code_text, detail)


def code(error):
    """The stable refusal code of an Invalid (text before the first colon)."""
    return str(error).split(':', 1)[0]


def utc(text):
    check(isinstance(text, str) and STAMP.fullmatch(text), 'timestamp_invalid', text)
    return datetime.strptime(text, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=timezone.utc)


def stamp(moment):
    return moment.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def safe_path(name):
    return (isinstance(name, str) and bool(name) and not name.startswith('/') and '\\' not in name
            and not any(char in name for char in '*?[]') and all(p not in ('', '.', '..') for p in name.split('/')))


def fill(pattern, plan_id, goal_id):
    return pattern.replace('<plan_id>', re.escape(plan_id)).replace('<goal_id>', re.escape(goal_id))


def unique_strings(value, pattern=None, allow_empty=True):
    return (isinstance(value, list) and (allow_empty or bool(value)) and all(string(x) for x in value)
            and len(set(value)) == len(value) and (pattern is None or all(pattern.fullmatch(x) for x in value)))


# --- policy (readiness-policy/2) --------------------------------------------

def validate_gate(gate):
    check(isinstance(gate, dict), 'policy_gate_invalid', 'gate must be an object')
    check(gate.get('kind') in GATE_KINDS, 'policy_gate_unknown_kind', gate.get('kind'))
    unknown = sorted(set(gate) - GATE_FIELDS)
    check(not unknown, 'policy_gate_unknown_field', ','.join(unknown))
    check(string(gate.get('id')) and ID.fullmatch(gate['id']), 'policy_gate_invalid', 'id')
    check(gate.get('stage') in STAGES, 'policy_gate_invalid', gate['id'] + ' stage')
    scope = gate.get('scope')
    goal_scoped = isinstance(scope, dict) and 'goals' in scope
    check(not goal_scoped, 'policy_gate_goal_scoped', gate['id'])
    check(scope == {'repository': True}, 'policy_gate_invalid', gate['id'] + ' scope')
    check('responsible' not in gate or string(gate['responsible']), 'policy_gate_invalid', gate['id'] + ' responsible')
    kind = gate['kind']
    if 'not_applicable' in gate:
        check(kind in NOT_APPLICABLE, 'policy_not_applicable_refused', kind)
        exemption = gate['not_applicable']
        check(isinstance(exemption, dict) and set(exemption) == {'reason'} and exemption['reason'] == NOT_APPLICABLE[kind],
              'policy_not_applicable_reason', gate['id'])
        check('binding' not in gate, 'policy_gate_invalid', gate['id'] + ' binding with not_applicable')
        return
    binding = gate.get('binding', {})
    check(isinstance(binding, dict) and set(binding) <= BINDINGS.get(kind, set()), 'policy_gate_invalid', gate['id'] + ' binding')
    if kind == 'ownership':
        roles = binding.get('roles')
        check(unique_strings(roles, allow_empty=False) and set(roles) <= {'owner', 'reviewer'}, 'policy_gate_invalid', gate['id'] + ' roles')
    elif kind == 'file_digest':
        check(safe_path(binding.get('path')) and isinstance(binding.get('sha256'), str) and SHA.fullmatch(binding['sha256']),
              'policy_gate_invalid', gate['id'] + ' file')
    elif kind == 'git_ancestor':
        commits = binding.get('commits', [])
        check(isinstance(commits, list) and all(isinstance(c, str) and REVISION.fullmatch(c) for c in commits),
              'policy_gate_invalid', gate['id'] + ' commits')
    elif kind == 'fixture':
        check(safe_path(binding.get('path')), 'policy_gate_invalid', gate['id'] + ' fixture path or not_applicable')
    elif kind == 'harness_trust':
        check(isinstance(binding.get('commit'), str) and REVISION.fullmatch(binding['commit']),
              'policy_gate_invalid', gate['id'] + ' harness commit or not_applicable')


def validate_policy(policy):
    """Structural validation of the one fixed, plan-agnostic policy file."""
    check(isinstance(policy, dict) and policy.get('schema') == POLICY_SCHEMA, 'policy_schema_unsupported',
          policy.get('schema') if isinstance(policy, dict) else type(policy).__name__)
    extensions = policy.get('extensions')
    check(not (isinstance(extensions, dict) and 'active_plan' in extensions), 'policy_active_plan_refused')
    unknown = sorted(set(policy) - POLICY_FIELDS)
    check(not unknown, 'policy_unknown_field', ','.join(unknown))
    missing = sorted(POLICY_FIELDS - set(policy))
    check(not missing, 'policy_field_invalid', 'missing ' + ','.join(missing))
    repository = policy['repository']
    check(isinstance(repository, dict) and set(repository) == {'id'} and string(repository['id'])
          and ID.fullmatch(repository['id']), 'policy_field_invalid', 'repository')
    check(policy['identity_model'] in ('multi', 'single'), 'policy_identity_model_invalid', policy['identity_model'])
    check(policy['reviewer_requirements'] == {'independent_lane': True}, 'policy_reviewer_lane_required')
    check(unique_strings(policy['sources'], allow_empty=False) and all(safe_path(s) for s in policy['sources']),
          'policy_field_invalid', 'sources')
    for field in ('required_checks', 'skippable_checks'):
        check(unique_strings(policy[field]), 'policy_field_invalid', field)
    check(unique_strings(policy['tools'], TOOL), 'policy_field_invalid', 'tools')
    pattern = policy['branch_pattern']
    check(string(pattern) and pattern.startswith('^') and pattern.endswith('$') and '<plan_id>' in pattern
          and '<goal_id>' in pattern, 'policy_field_invalid', 'branch_pattern')
    try:
        re.compile(fill(pattern, 'plan', 'goal'))
    except re.error:
        refuse('policy_field_invalid', 'branch_pattern')
    target = policy['target']
    check(string(target) and re.fullmatch(r'[A-Za-z0-9._/-]+', target) and not target.startswith('refs/'),
          'policy_field_invalid', 'target')
    approval = policy['approval']
    check(isinstance(approval, dict) and set(approval) == {'anchor_sha256', 'max_age_days', 'accept'},
          'policy_approval_invalid', 'fields')
    check(approval['anchor_sha256'] is None or (isinstance(approval['anchor_sha256'], str) and SHA.fullmatch(approval['anchor_sha256'])),
          'policy_approval_invalid', 'anchor_sha256')
    check(type(approval['max_age_days']) is int and approval['max_age_days'] == MAX_AGE_DAYS, 'policy_approval_invalid', 'max_age_days')
    check(unique_strings(approval['accept'], allow_empty=False) and set(approval['accept']) <= set(FORMS),
          'policy_approval_invalid', 'accept')
    gates = policy['gates']
    check(isinstance(gates, list), 'policy_field_invalid', 'gates')
    seen = set()
    for gate in gates:
        validate_gate(gate)
        check(gate['id'] not in seen, 'policy_gate_duplicate_id', gate['id'])
        seen.add(gate['id'])
    return policy


def policy_gaps(policy):
    """Fail-closed placeholders of a baseline policy, each a named admission gap."""
    gaps = []
    if policy['approval']['anchor_sha256'] is None:
        gaps.append('anchor_unset')
    if not policy['required_checks']:
        gaps.append('required_checks_unset')
    return gaps


# --- content-only bundle, revisions and generation ---------------------------

def validate_bundle(bundle):
    check(isinstance(bundle, dict) and bundle.get('schema') == BUNDLE_SCHEMA, 'bundle_schema_unsupported',
          bundle.get('schema') if isinstance(bundle, dict) else '')
    check(not ({'gates', 'policy', 'requirements'} & set(bundle)), 'bundle_gate_refused', 'bundle')
    unknown = sorted(set(bundle) - BUNDLE_FIELDS)
    check(not unknown, 'bundle_unknown_field', ','.join(unknown))
    check(string(bundle.get('id')) and ID.fullmatch(bundle['id']), 'bundle_field_invalid', 'id')
    repository = bundle.get('repository')
    check(isinstance(repository, dict) and set(repository) == {'id'} and string(repository['id'])
          and ID.fullmatch(repository['id']), 'bundle_field_invalid', 'repository')
    spec = bundle.get('spec')
    check(isinstance(spec, dict) and set(spec) == {'path'} and safe_path(spec['path']), 'bundle_field_invalid', 'spec')
    goals = bundle.get('goals')
    check(isinstance(goals, list) and goals, 'bundle_field_invalid', 'goals')
    ids = []
    for goal in goals:
        check(isinstance(goal, dict), 'bundle_field_invalid', 'goal')
        gid = goal.get('id')
        check(not ({'requirements', 'gates'} & set(goal)), 'bundle_gate_refused', gid)
        mutable = sorted(MUTABLE_GOAL_FIELDS & set(goal))
        check(not mutable, 'bundle_mutable_field', '%s:%s' % (gid, ','.join(mutable)))
        unknown = sorted(set(goal) - GOAL_FIELDS)
        check(not unknown, 'bundle_unknown_field', '%s:%s' % (gid, ','.join(unknown)))
        check(string(gid) and ID.fullmatch(gid), 'bundle_field_invalid', 'goal id')
        check(unique_strings(goal.get('scope'), allow_empty=False), 'bundle_field_invalid', gid + ' scope')
        check(all(safe_path(s) for s in goal['scope']), 'bundle_scope_unsafe', gid)
        check(unique_strings(goal.get('acceptance_criteria'), allow_empty=False), 'bundle_field_invalid', gid + ' acceptance_criteria')
        dependencies = goal.get('dependencies')
        check(unique_strings(dependencies, ID) and gid not in dependencies, 'bundle_field_invalid', gid + ' dependencies')
        verification = goal.get('verification')
        check(isinstance(verification, list) and verification and all(
            string(v) or (isinstance(v, dict) and set(v) == {'cwd', 'command'}) for v in verification),
            'bundle_field_invalid', gid + ' verification')
        ids.append(gid)
    check(len(set(ids)) == len(ids), 'bundle_duplicate_goal')
    for goal in goals:
        for dependency in goal['dependencies']:
            check(dependency in ids, 'bundle_dependency_unknown', '%s->%s' % (goal['id'], dependency))
    for gid in ids:
        check(gid not in ancestors(bundle, gid), 'bundle_dependency_cycle', gid)
    return bundle


def ancestors(bundle, gid):
    edges = {g['id']: g['dependencies'] for g in bundle['goals']}
    pending, seen = list(edges.get(gid, [])), set()
    while pending:
        dependency = pending.pop()
        if dependency not in seen:
            seen.add(dependency)
            pending.extend(edges.get(dependency, []))
    return seen


def goal_revision_v2(bundle, gid):
    """Content only: id, scope, acceptance criteria, dependencies by id, verification, repository.id."""
    goal = next((g for g in bundle['goals'] if g['id'] == gid), None)
    check(goal is not None, 'requested_goal_missing', gid)
    return canonical({'schema': 'goal-revision/2', 'repository': bundle['repository']['id'], 'id': goal['id'],
                      'scope': goal['scope'], 'acceptance_criteria': goal['acceptance_criteria'],
                      'dependencies': sorted(goal['dependencies']), 'verification': goal['verification']})


def bundle_sha256(bundle):
    return canonical(bundle)


def generation_v2(bundle_sha256, spec_sha256, policy_sha256, anchor_sha256):
    """What one approval signs: content, spec, policy and anchor. Never the sidecar."""
    return canonical({'schema': 'generation/2', 'bundle_sha256': bundle_sha256, 'spec_sha256': spec_sha256,
                      'policy_sha256': policy_sha256, 'anchor_sha256': anchor_sha256})


# --- sidecar: holds-only, tighten-only ---------------------------------------

def validate_sidecar(sidecar, bundle):
    check(isinstance(sidecar, dict) and set(sidecar) == {'schema', 'plan_id', 'goals'}
          and sidecar['schema'] == SIDECAR_SCHEMA, 'sidecar_invalid', 'fields')
    check(sidecar['plan_id'] == bundle['id'], 'sidecar_invalid', 'plan_id')
    goals = sidecar['goals']
    check(isinstance(goals, dict) and set(goals) == {g['id'] for g in bundle['goals']}, 'sidecar_goals_mismatch')
    for gid, entry in sorted(goals.items()):
        check(isinstance(entry, dict), 'sidecar_invalid', gid)
        unknown = sorted(set(entry) - SIDECAR_GOAL_FIELDS)
        check(not unknown, 'sidecar_unknown_field', '%s:%s' % (gid, ','.join(unknown)))
        readiness = entry.get('readiness')
        check(isinstance(readiness, dict) and set(readiness) == set(STAGES)
              and all(v in ('unknown', 'blocked') for v in readiness.values()), 'sidecar_hold_invalid', gid)
        status, percent = entry.get('coverage_status'), entry.get('coverage_percent')
        measured = (status == 'measured' and isinstance(percent, (int, float)) and not isinstance(percent, bool)
                    and 0 <= percent <= 100)
        check(measured or (status == 'unknown' and 'coverage_percent' not in entry), 'sidecar_coverage_invalid', gid)
        check(isinstance(entry.get('legacy_safe_tdd'), bool), 'sidecar_invalid', gid + ' legacy_safe_tdd')
        check(string(entry.get('legacy_risk_reason')), 'sidecar_invalid', gid + ' legacy_risk_reason')
    return sidecar


def sidecar_leq(v0, current):
    """Product order: readiness unknown<blocked, legacy_safe_tdd false<true,
    legacy_risk_reason by prefix extension, coverage unknown<measured(p) with p final."""
    check(v0['plan_id'] == current['plan_id'] and set(v0['goals']) == set(current['goals']), 'sidecar_loosened', 'goal set')
    for gid in sorted(v0['goals']):
        before, after = v0['goals'][gid], current['goals'][gid]
        for stage in STAGES:
            check(not (before['readiness'][stage] == 'blocked' and after['readiness'][stage] != 'blocked'),
                  'sidecar_loosened', '%s/readiness/%s' % (gid, stage))
        check(not (before['legacy_safe_tdd'] and not after['legacy_safe_tdd']), 'sidecar_loosened', gid + '/legacy_safe_tdd')
        check(after['legacy_risk_reason'].startswith(before['legacy_risk_reason']), 'sidecar_loosened', gid + '/legacy_risk_reason')
        if before['coverage_status'] == 'measured':
            check(after['coverage_status'] == 'measured' and after.get('coverage_percent') == before.get('coverage_percent'),
                  'sidecar_loosened', gid + '/coverage')


# --- policy bootstrap (O9) ------------------------------------------------------

def policy_goals(bundle):
    return [g['id'] for g in bundle['goals'] if POLICY in g['scope']]


def validate_bootstrap(bundle, live_policy2, candidate_is_live=False):
    """One policy goal scopes the fixed path; every sibling depends on it."""
    check(not live_policy2 or candidate_is_live, 'bootstrap_policy_live')
    found = policy_goals(bundle)
    check(len(found) <= 1, 'bootstrap_multiple_policy_goals', ','.join(found))
    check(found, 'bootstrap_policy_goal_missing')
    for goal in bundle['goals']:
        if goal['id'] != found[0]:
            check(found[0] in ancestors(bundle, goal['id']), 'bootstrap_sibling_not_dependent', goal['id'])
    return found[0]


def validate_live_scope(bundle):
    found = policy_goals(bundle)
    check(not found, 'policy_goal_requires_bootstrap', ','.join(found))


def bootstrap_certificate_gaps(policy_goal, goal_id, head_policy_sha256, policy_sha256):
    if policy_goal is not None and goal_id == policy_goal and head_policy_sha256 != policy_sha256:
        return ['bootstrap_head_policy_mismatch']
    return []


# --- plan approval (plan-approval/1) ------------------------------------------

def approval_record(**fields):
    record = dict(fields, schema=APPROVAL_SCHEMA, stages=list(APPROVED_STAGES))
    check(set(record) == APPROVAL_FIELDS, 'approval_record_invalid', ','.join(sorted(set(record) ^ APPROVAL_FIELDS)))
    return record


def assurance_for(form, key_type=None, options=()):
    """K1: user-presence only for an sk- key whose anchor line lacks no-touch-required."""
    if form == 'in-session':
        return 'in-session'
    if isinstance(key_type, str) and key_type.startswith('sk-') and 'no-touch-required' not in options:
        return 'user-presence'
    return 'key-held'


def render_assurance(assurance):
    check(assurance in NOTICES, 'assurance_invalid', assurance)
    return NOTICES[assurance]


def check_approval(record, expected, policy, now):
    check(isinstance(record, dict) and set(record) == APPROVAL_FIELDS and record.get('schema') == APPROVAL_SCHEMA,
          'approval_record_invalid', 'fields')
    check(record['stages'] == APPROVED_STAGES, 'approval_record_invalid', 'stages')
    check(string(record['owner']) and string(record['reviewer_lane']), 'approval_record_invalid', 'owner or reviewer_lane')
    check(record['assurance'] in ASSURANCE, 'approval_record_invalid', 'assurance')
    check(record['plan_id'] == expected['plan_id'], 'approval_plan_mismatch')
    for name, code_text in (('bundle_sha256', 'approval_bundle_mismatch'), ('spec_sha256', 'approval_spec_mismatch'),
                            ('policy_sha256', 'approval_policy_mismatch'), ('anchor_sha256', 'approval_anchor_mismatch')):
        check(record[name] == expected[name], code_text)
    check(record['generation'] == expected['generation'], 'approval_generation_mismatch')
    check(isinstance(record['goals'], list) and len(set(record['goals'])) == len(record['goals'])
          and sorted(record['goals']) == sorted(expected['goals']), 'approval_goals_mismatch')
    try:
        issued, expires = utc(record['issued_at']), utc(record['expires_at'])
    except Invalid:
        refuse('approval_record_invalid', 'timestamps')
    max_age = timedelta(days=policy['approval']['max_age_days'])
    check(issued <= now, 'approval_not_yet_valid')
    check(now < expires, 'approval_expired', record['expires_at'])
    check(now - issued <= max_age, 'approval_too_old', record['issued_at'])
    check(expires - issued <= max_age, 'approval_window_exceeds_max_age')


def check_sidecar_binding(record, sidecar, sidecar_v0):
    if canonical(sidecar) == record['sidecar_sha256']:
        return
    check(sidecar_v0 is not None and canonical(sidecar_v0) == record['sidecar_sha256'], 'approval_sidecar_mismatch')
    sidecar_leq(sidecar_v0, sidecar)


def decide_approval(carrier, policy, expected, now, sidecar, sidecar_v0):
    """Verify one approval carrier (observed tag facts) against observed digests."""
    anchor = policy['approval']['anchor_sha256']
    check(anchor is not None, 'anchor_unset')
    carrier = carrier or {}
    facts = carrier.get('anchor') or {}
    check(not facts.get('symlink'), 'anchor_symlink')
    check(facts.get('present'), 'anchor_missing')
    check(not facts.get('inside_worktree'), 'anchor_inside_worktree')
    check(facts.get('sha256') == anchor, 'anchor_digest_mismatch')
    check(not facts.get('ambiguous'), 'anchor_principal_ambiguous', ','.join(facts.get('ambiguous') or []))
    check(carrier.get('tag'), 'approval_tag_missing', 'approval/%s/%s' % (expected['plan_id'], expected['generation'][:12]))
    check(carrier.get('annotated'), 'approval_tag_not_annotated', carrier['tag'])
    check(carrier.get('on_origin'), 'approval_tag_not_on_origin', carrier['tag'])
    check(carrier.get('target_contains_generation'), 'approval_tag_target_invalid', carrier['tag'])
    form = carrier.get('form')
    check(form in FORMS, 'approval_carrier_invalid', 'form')
    check(form in policy['approval']['accept'], 'approval_form_not_accepted', form)
    record = carrier.get('record')
    check(isinstance(record, dict) and carrier.get('record_canonical') is True, 'approval_carrier_invalid', 'record')
    principal = None
    if form == 'ssh-tag':
        signature = carrier.get('signature') or {}
        principal = signature.get('principal')
        check(principal, 'approval_signature_invalid', 'no anchor principal for this signature')
        namespaces = set(signature.get('namespaces') or [])
        check(NS_APPROVAL in namespaces and not ({NS_REVIEW, NS_CERTIFICATE} & namespaces),
              'approval_signer_not_approver', principal)
        check(signature.get('verified') is True, 'approval_signature_invalid', principal)
        assurance = assurance_for(form, signature.get('key_type'), signature.get('options') or [])
    else:
        check(carrier.get('digest_echo') == canonical(record), 'approval_digest_echo_mismatch')
        assurance = 'in-session'
    check_approval(record, expected, policy, now)
    check(record['assurance'] == assurance, 'approval_assurance_mismatch', '%s claimed, %s observed' % (record['assurance'], assurance))
    check_sidecar_binding(record, sidecar, sidecar_v0)
    return {'digest': canonical(record), 'form': form, 'assurance': assurance, 'principal': principal,
            'tag': carrier['tag'], 'owner': record['owner'], 'reviewer_lane': record['reviewer_lane'],
            'issued_at': record['issued_at'], 'expires_at': record['expires_at']}


# --- hosted facts ----------------------------------------------------------------

def decide_checks(policy, runs):
    """Dedupe by name across push and pull_request runs; every run at head must be
    SUCCESS, SKIPPED only for skippable_checks; every required check must exist."""
    groups = {}
    for run in runs:
        groups.setdefault(run.get('name'), []).append(run)
    gaps = ['check_missing:' + name for name in policy['required_checks'] if name not in groups]
    for name in sorted(groups, key=str):
        group = groups[name]
        if any(r.get('status') != 'completed' or r.get('conclusion') is None for r in group):
            gaps.append('check_pending:%s' % name)
            continue
        conclusions = {str(r['conclusion']).lower() for r in group}
        if conclusions - {'success', 'skipped'}:
            gaps.append('check_failed:%s' % name)
        elif 'skipped' in conclusions and name not in policy['skippable_checks']:
            gaps.append('check_skipped_unlisted:%s' % name)
    return gaps


def protection_gaps(protection, runs):
    """Branch protection adds requirements only when observable; unavailable is never satisfied."""
    if not isinstance(protection, dict) or protection.get('status') != 'available':
        return []
    passed = {r.get('name') for r in runs if r.get('status') == 'completed' and str(r.get('conclusion')).lower() == 'success'}
    return ['protection_check_unsatisfied:' + name for name in protection.get('contexts', []) if name not in passed]


def required_check_summary(policy, runs):
    summary = []
    for name in policy['required_checks']:
        group = [r for r in runs if r.get('name') == name]
        conclusions = {str(r.get('conclusion')).lower() for r in group}
        conclusion = 'unsatisfied'
        if group and conclusions == {'success'}:
            conclusion = 'success'
        elif group and conclusions <= {'success', 'skipped'} and name in policy['skippable_checks']:
            conclusion = 'skipped'
        summary.append({'name': name, 'conclusion': conclusion,
                        'completed_at': max((r.get('completed_at') or '') for r in group) if group else None})
    return summary


# --- admission (readiness-context/2) -------------------------------------------

def gap_entry(code_text, detail='', goal=None, gate=None, source='observer', recovery=None):
    return {'code': code_text, 'detail': str(detail), 'goal': goal, 'gate': gate, 'source': source,
            'recovery': recovery or RECOVERY['policy']}


def evaluate_gate(gate, policy, bundle, goals, facts, approval):
    kind = gate['kind']
    if 'not_applicable' in gate:
        return 'not_applicable', []
    value = lambda name: (facts.get(name) or {}).get('value')
    binding = gate.get('binding', {})
    codes = []
    if kind == 'ownership':
        if approval is None:
            codes.append('ownership_unresolved')
        else:
            roles = {'owner': approval['owner'], 'reviewer': approval['reviewer_lane']}
            codes += ['ownership_unresolved:' + role for role in binding['roles'] if not string(roles[role])]
    elif kind == 'plan_approval':
        if approval is None:
            codes.append('plan_approval_missing')
    elif kind == 'tooling':
        codes += ['tool_missing:' + tool for tool in policy['tools'] if not value('tool:' + tool)]
    elif kind == 'git_ancestor':
        inputs = value('planning_inputs') or {}
        if not inputs.get('on_target'):
            codes.append('planning_input_not_on_target')
        if not inputs.get('in_head'):
            codes.append('planning_input_not_in_head')
        codes += ['git_ancestor_missing:' + c for c in binding.get('commits', []) if value('ancestor:' + c) is not True]
    elif kind == 'branch_target':
        pull = value('pr')
        repository = value('repository') or {}
        branch = pull['head_ref'] if pull else str(repository.get('branch') or '').replace('refs/heads/', '', 1)
        for gid in goals:
            if not re.fullmatch(fill(policy['branch_pattern'], bundle['id'], gid), branch):
                codes.append('branch_target_mismatch:%s' % branch)
        if pull and pull['base_ref'] != policy['target']:
            codes.append('branch_target_mismatch:base ' + pull['base_ref'])
    elif kind == 'hosted_checks':
        if value('pr') is None or value('checks') is None:
            codes.append('pr_required')
        else:
            codes += decide_checks(policy, value('checks')) + protection_gaps(value('protection'), value('checks'))
    elif kind == 'review':
        lane, threads = value('review_lane'), value('threads')
        if not lane:
            codes.append('review_lane_missing')
        elif lane.get('code'):
            codes.append(lane['code'])
        if threads is None:
            codes.append('threads_unobserved')
        elif threads.get('unresolved', 1) != 0:
            codes.append('unresolved_threads')
    elif kind == 'file_digest':
        if value('file:' + binding['path']) != binding['sha256']:
            codes.append('file_digest_mismatch:' + binding['path'])
    elif kind == 'fixture':
        if value('fixture:' + binding['path']) is not True:
            codes.append('fixture_unavailable:' + binding['path'])
    elif kind == 'harness_trust':
        if value('ancestor:' + binding['commit']) is not True:
            codes.append('harness_untrusted:' + binding['commit'])
    return ('blocked' if codes else 'pass'), codes


def admission(inputs):
    """Rebuild the readiness context from observation plus the verified approval."""
    stage, goals, now = inputs['stage'], list(inputs['goals']), inputs['now']
    gaps = [gap_entry(e['code'], e.get('detail', ''), source='observer') for e in inputs.get('errors', [])]
    observation = inputs.get('observation') or {'schema': OBSERVATION_SCHEMA, 'adapter': 'none', 'facts': {}}
    facts = observation.get('facts', {})
    registered = inputs.get('registered') or {}
    policy, bundle = inputs.get('policy'), inputs.get('bundle')
    digests = inputs.get('digests') or {}
    approval, gates, revisions = None, [], {}
    if policy is not None and bundle is not None and not gaps:
        for name in policy_gaps(policy):
            gaps.append(gap_entry(name, source='policy', recovery=RECOVERY['policy']))
        for source in policy['sources']:
            if 'source:' + source in facts and facts['source:' + source]['value'] is None:
                gaps.append(gap_entry('policy_source_missing', source, source='observation/1'))
        if generation_v2(**digests) != registered.get('generation'):
            gaps.append(gap_entry('generation_mismatch', 'observed inputs no longer match the registered generation'))
        try:
            if inputs.get('policy_mode') == 'bootstrap':
                validate_bootstrap(bundle, inputs.get('live_policy2', False), inputs.get('candidate_is_live', False))
            else:
                validate_live_scope(bundle)
        except Invalid as error:
            gaps.append(gap_entry(code(error), str(error), source='policy'))
        expected = dict(digests, plan_id=bundle['id'], generation=registered.get('generation'),
                        goals=[g['id'] for g in bundle['goals']])
        try:
            approval = decide_approval(inputs.get('carrier'), policy, expected, now, inputs['sidecar'], inputs.get('sidecar_v0'))
        except Invalid as error:
            family = 'anchor' if code(error).startswith('anchor') else ('sidecar' if 'sidecar' in code(error) else 'approval')
            gaps.append(gap_entry(code(error), str(error), source='plan-approval/1', recovery=RECOVERY[family]))
        for gid in goals:
            revisions[gid] = goal_revision_v2(bundle, gid)
            holds = inputs['sidecar']['goals'][gid]['readiness']
            for held in (STAGES if stage == 'planning' else (stage,)):
                if holds[held] == 'blocked':
                    gaps.append(gap_entry('readiness_hold', held, goal=gid, source='sidecar', recovery=RECOVERY['sidecar']))
            for dependency in sorted(ancestors(bundle, gid)):
                completed = (facts.get('dependency:' + dependency) or {}).get('value') or {}
                if completed.get('ancestor') is not True:
                    gaps.append(gap_entry('dependency_incomplete', dependency, goal=gid, source='hosted+git',
                                          recovery='Merge the dependency goal first; its PR merge commit must reach the target'))
        for gate in policy['gates']:
            if stage != 'planning' and gate['stage'] != stage:
                continue
            status, codes = evaluate_gate(gate, policy, bundle, goals, facts, approval)
            gates.append({'id': gate['id'], 'kind': gate['kind'], 'stage': gate['stage'], 'status': status})
            for item in codes:
                family = 'hosted' if gate['kind'] in ('hosted_checks', 'review') else 'policy'
                gaps.append(gap_entry(item.split(':', 1)[0], item.split(':', 1)[1] if ':' in item else '',
                                      gate=gate['id'], source='observation/1', recovery=RECOVERY[family]))
    gaps.sort(key=lambda g: (g['code'], str(g['goal']), str(g['gate']), g['detail']))
    admitted = stage in STAGES and not gaps and approval is not None
    context = {'schema': CONTEXT_SCHEMA, 'stage': stage, 'goals': goals, 'plan_id': bundle['id'] if bundle else None,
               'generation': registered.get('generation'), 'registration': registered.get('id'),
               'goal_revisions': revisions,
               'policy': {'sha256': digests.get('policy_sha256'), 'mode': inputs.get('policy_mode')},
               'repository': (facts.get('repository') or {}).get('value'),
               'approval': approval, 'assurance': approval['assurance'] if approval else None,
               'authority': 'plan-approval/1' if approval else NO_AUTHORITY,
               'observation': observation, 'gates': gates, 'gaps': gaps, 'admitted': admitted}
    if approval:
        context['assurance_notice'] = render_assurance(approval['assurance'])
    return context


def projection(value, volatile=('observed_at', 'root')):
    """A value without observation timestamps and informational absolute paths."""
    if isinstance(value, dict):
        return {k: projection(v, volatile) for k, v in value.items() if k not in volatile}
    if isinstance(value, list):
        return [projection(v, volatile) for v in value]
    return value


def verdict_of(context):
    return {'admitted': context['admitted'], 'gaps': sorted({g['code'] for g in context['gaps']})}


def compare_supplied(kind, supplied, rebuilt):
    """A supplied artifact is only ever compared with the rebuilt one, never used."""
    check(projection(supplied) == projection(rebuilt), 'supplied_%s_mismatch' % kind,
          'differs from the rebuilt %s; supplied artifacts never carry authority' % kind)


# --- merge certificate (merge-certificate/1) -------------------------------------

def certificate_refusals(facts):
    """Every merge condition at one exact head; returns refusal codes (empty = issue)."""
    refusals = []
    if not facts['clean_before'] or not facts['clean_after']:
        refusals.append('tree_not_clean')
    if facts['head_before'] != facts['head_after']:
        refusals.append('head_changed_during_gates')
    if facts['pr_head'] != facts['head_before']:
        refusals.append('pr_head_mismatch')
    refusals += ['local_gate_failed:' + g['name'] for g in facts['local_gates'] if g['exit'] != 0]
    issued = facts['now']
    for run in facts['runs']:
        if run.get('name') in facts['required_checks']:
            completed = run.get('completed_at')
            if completed is None or utc(completed) >= issued:
                refusals.append('check_completed_after_issue:' + run['name'])
    if facts['unresolved_threads'] != 0:
        refusals.append('unresolved_threads')
    lane = facts['review_lane']
    if not lane:
        refusals.append('review_lane_missing')
    elif lane['principal'] == facts['certifier']:
        refusals.append('review_lane_not_independent')
    refusals += bootstrap_certificate_gaps(facts['policy_goal'], facts['goal_id'], facts['head_policy_sha256'],
                                           facts['policy_sha256'])
    return sorted(set(refusals))


def certificate_body(**fields):
    body = dict(fields, schema=CERTIFICATE_SCHEMA, lane_independence='declared')
    check(set(body) == CERTIFICATE_FIELDS, 'certificate_invalid', ','.join(sorted(set(body) ^ CERTIFICATE_FIELDS)))
    check(body['assurance'] in ASSURANCE, 'certificate_invalid', 'assurance')
    return body


def certificate_differences(stored, rederived):
    """Fields whose stored claim differs from re-observation (issue time excepted)."""
    if not isinstance(stored, dict) or set(stored) != CERTIFICATE_FIELDS:
        return ['fields']
    return sorted(k for k in CERTIFICATE_FIELDS - {'issued_at'} if stored[k] != rederived[k])


def canonical_bytes(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()
