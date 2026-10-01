"""Disposable v1 input builder. Context simulates independently approved inputs."""
import hashlib
import json
from pathlib import Path


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(root, path, value):
    target = Path(root) / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(value, indent=2) + '\n')
    return target


def fixture(root):
    root = Path(root)
    write(root, '.ai/matrix.json', {})
    write(root, '.ai/workflows/repo-workflow.json', {'optional_branches': []})
    write(root, '.ai/workflows/northstar-readiness-v1.json', {'schema': 'readiness-contract/1', 'plans': []})
    write(root, '.ai/traceability/graph.json', {'schema_version': '1.1', 'root_repo_id': 'fixture', 'nodes': [
        {'id': 'prd:fixture:chosen', 'type': 'prd', 'title': 'Chosen', 'status': 'active', 'repo_id': 'fixture', 'path': 'spec.md', 'backlinks': []}
    ], 'edges': []})
    for name, text in [('AGENTS.md', 'Fixture policy only'), ('spec.md', 'Exact specification'), ('evidence.txt', 'observed fixture result')]:
        (root / name).write_text(text)
    (root / 'tests').mkdir(exist_ok=True)
    (root / 'tests/check.sh').write_text('#!/bin/sh\ntouch SHOULD_NOT_RUN\n')
    repository = {'id': 'fixture', 'root': str(root.resolve())}
    sources = [{'path': 'AGENTS.md', 'sha256': digest(root / 'AGENTS.md')}]
    policy = {
        'schema': 'readiness-policy/1', 'repository': repository, 'sources': sources,
        'gates': [{'id': 'fixture-proof', 'stage': 'implementation', 'scope': {'goals': ['G1']},
                   'dimension': 'fixtures', 'kind': 'file_digest', 'path': 'evidence.txt', 'sha256': digest(root / 'evidence.txt')}],
        'not_applicable': {'owners': 'Single-agent fixture, no named-owner requirement', 'reviewer': 'No named reviewer requirement', 'tooling': 'Checked by verification validator', 'registration_approval': 'Disposable unprotected fixture', 'branch_target': 'No hosted operation at admission', 'harness_trust': 'No ticket connector'},
    }
    write(root, '.ai/policies/readiness-policy.json', policy)
    goal = {'id': 'G1', 'repository': repository, 'issue_ref': 'local:G1', 'scope': ['tests/check.sh'],
            'acceptance_criteria': ['Exact goal only'], 'dependencies': [], 'verification': ['bash tests/check.sh'],
            'coverage_status': 'unknown', 'legacy_safe_tdd': True, 'legacy_risk_reason': 'Unmeasured fixture coverage',
            'readiness': {'preparation': 'unknown', 'implementation': 'ready', 'merge': 'unknown'}}
    bundle = {'schema': 'handoff-goals/1', 'id': 'chosen', 'repository': repository,
              'spec': {'path': 'spec.md', 'sha256': digest(root / 'spec.md')}, 'issue_ref': 'local:chosen',
              'planning_complete': True, 'status': 'active', 'goals': [goal]}
    write(root, 'plan.json', bundle)
    context = {'schema': 'readiness-context/1', 'repository': repository,
               'policy': {'sha256': digest(root / '.ai/policies/readiness-policy.json'), 'revision': 'simulated-review-1', 'issuer': 'fixture-reviewer'},
               'sources': sources, 'authority': {'status': 'pass', 'stage': 'implementation', 'goals': ['G1'], 'issuer': 'simulated-runtime', 'subject_sha256': digest(root / 'plan.json')},
               'results': [], 'completed_goals': []}
    write(root, 'context.json', context)
    return bundle, context
