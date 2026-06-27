#!/usr/bin/env python3
"""Final init-ai-repo validation package checks for PR 6F."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {
    '.md', '.txt', '.toml', '.json', '.jsonl', '.yml', '.yaml', '.sh', '.py',
    '.ts', '.js', '.template', '.gitignore', '.lock', '.xml', '.csproj', '.sln',
}
EXCLUDED_PARTS = {'.git', '.omx', '.omc', '.claude', 'graphify-out', 'node_modules', '__pycache__'}
SECRET_PATTERNS = [
    re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'),
    re.compile(r'\bsk-[A-Za-z0-9_-]{20,}\b'),
    re.compile(r'\bghp_[A-Za-z0-9]{20,}\b'),
    re.compile(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b'),
    re.compile(r'\bxox[baprs]-[A-Za-z0-9-]{20,}\b'),
    re.compile(r'\bAKIA[0-9A-Z]{16}\b'),
]


def fail(message: str) -> None:
    raise AssertionError(message)


def read_json(path: Path) -> dict:
    with path.open() as handle:
        return json.load(handle)


def assert_file(path: str) -> Path:
    p = ROOT / path
    if not p.is_file():
        fail(f'missing required file: {path}')
    return p


def check_ci_wiring() -> None:
    run_tests = assert_file('tests/run-tests.sh').read_text()
    test_scripts = assert_file('tests/test-scripts.sh').read_text()
    ci = assert_file('.github/workflows/ci.yml').read_text()
    prek = assert_file('.github/workflows/ci-prek.yml').read_text()
    if 'test-scripts.sh' not in run_tests or 'test-skills.sh' not in run_tests:
        fail('tests/run-tests.sh must include shell and skill suites')
    for expected in ['*_test.sh', 'tests/skill-catalog_test.sh', 'tests/cascade-fixtures_test.sh']:
        # The concrete tests are discovered by suffix; keep a sentinel for the discovery rule and key files.
        if expected == '*_test.sh':
            if '*_test.sh' not in test_scripts:
                fail('tests/test-scripts.sh must discover *_test.sh suites')
        else:
            assert_file(expected)
    if 'tests/run-tests.sh' not in ci:
        fail('.github/workflows/ci.yml must run tests/run-tests.sh')
    if '"codex/**"' not in ci:
        fail('.github/workflows/ci.yml must run on codex/** stack branch pushes')
    if '--all-files' not in prek:
        fail('.github/workflows/ci-prek.yml must run prek over all files')
    if '"codex/**"' not in prek:
        fail('.github/workflows/ci-prek.yml must run on codex/** stack branch pushes')


def check_required_validators() -> None:
    for path in [
        'tests/final-validation-gate_test.sh',
        'tests/init-ai-repo_docs_test.sh',
        'tests/workflow-fixtures_test.sh',
        'tests/traceability-fixtures_test.sh',
        'tests/cascade-fixtures_test.sh',
        'tests/skill-catalog_test.sh',
        'tests/test-skills-validator_test.sh',
        'scripts/validate-final-package.py',
        'scripts/validate-cascade-fixtures.py',
        'scripts/validate-skill-catalog.py',
        'scripts/verify-golden-dir.sh',
        'scripts/archgate.sh',
    ]:
        assert_file(path)


def check_v3_fixtures() -> None:
    fixture_roots = [ROOT / 'reference/fixtures/v3/standalone', ROOT / 'reference/fixtures/v3/umbrella']
    for fixture in fixture_roots:
        for path in [
            '.ai/matrix.json',
            '.ai/workflows/repo-workflow.json',
            '.ai/traceability/graph.json',
            '.ai/cascade/cascade-plan.json',
            '.ai/skills/catalog-audit.json',
            '.ai/skills/description-exceptions.json',
        ]:
            if not (fixture / path).is_file():
                fail(f'missing fixture output: {fixture.relative_to(ROOT) / path}')
            read_json(fixture / path)
        workflow = read_json(fixture / '.ai/workflows/repo-workflow.json')
        if workflow.get('workflow_id') != 'init-ai-repo':
            fail(f'invalid workflow id in {fixture}')
        for branch in workflow.get('optional_branches', []):
            if branch.get('id') in {'multi-repo-cascade', 'skill-modernization'} and branch.get('status') != 'available':
                fail(f'optional branch {branch.get("id")} must be available in {fixture}')
        graph = read_json(fixture / '.ai/traceability/graph.json')
        node_ids = {node['id'] for node in graph.get('nodes', [])}
        for edge in graph.get('edges', []):
            if edge.get('source') not in node_ids or edge.get('target') not in node_ids:
                fail(f'dangling traceability edge in {fixture}: {edge}')
        catalog = read_json(fixture / '.ai/skills/catalog-audit.json')
        if catalog.get('status') != 'pass' or catalog.get('skill_count') != 21:
            fail(f'catalog audit must pass with 21 skills in {fixture}')


def check_root_catalog() -> None:
    catalog = read_json(assert_file('.ai/skills/catalog-audit.json'))
    exceptions = read_json(assert_file('.ai/skills/description-exceptions.json'))
    if catalog.get('status') != 'pass':
        fail('root catalog audit must pass')
    if catalog.get('policy', {}).get('target_description_chars') != 180:
        fail('catalog target description budget must be 180')
    if catalog.get('policy', {}).get('hard_fail_description_chars') != 280:
        fail('catalog hard-fail description budget must be 280')
    if exceptions.get('exceptions') != []:
        fail('description exceptions must be empty unless explicitly reviewed')


def iter_text_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob('*'):
        if not path.is_file():
            continue
        if any(part in EXCLUDED_PARTS for part in path.relative_to(ROOT).parts):
            continue
        if path.suffix in TEXT_SUFFIXES or path.name in {'AGENTS.md', 'CLAUDE.md', 'README.md', '.gitignore'}:
            files.append(path)
    return files


def check_no_secrets() -> None:
    offenders: list[str] = []
    for path in iter_text_files():
        try:
            text = path.read_text(errors='ignore')
        except UnicodeDecodeError:
            continue
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                offenders.append(f'{path.relative_to(ROOT)} matches {pattern.pattern}')
    if offenders:
        fail('potential secrets found:\n' + '\n'.join(offenders))


def main() -> int:
    check_ci_wiring()
    check_required_validators()
    check_v3_fixtures()
    check_root_catalog()
    check_no_secrets()
    print('final validation package checks passed')
    return 0


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except AssertionError as exc:
        print(f'FAIL: {exc}', file=sys.stderr)
        raise SystemExit(1)
