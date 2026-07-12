#!/usr/bin/env python3
"""Validate first-class skill catalog metadata and optional audit artifacts."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TARGET_DESCRIPTION_CHARS = 160
MAX_DESCRIPTION_CHARS = 180
TARGET_BODY_LINES = 100
MAX_BODY_LINES = 180
EXCLUDED_DIRS = {'.git', '.omx', '.omc', '.claude', '.agents', 'reference', 'tests', 'scripts', 'docs', '.ai', '.memory'}
REQUIRED_CROSS_SKILL = {
    'ai-catapult-init': ['workflow', 'traceability', 'cascade', 'catalog'],
    'setup-skills': ['tracker'],
    'to-prd': ['PRD'],
    'to-issues': ['issue'],
    'triage': ['issue'],
    'publish-semver': ['release'],
    'write-a-skill': ['skill'],
    'write-agent-docs': ['agent-facing'],
}


def first_class_skill_paths(root: Path) -> list[Path]:
    paths: list[Path] = []
    for path in root.iterdir():
        if not path.is_dir() or path.name.startswith('.') or path.name in EXCLUDED_DIRS:
            continue
        skill = path / 'SKILL.md'
        if skill.is_file():
            paths.append(skill)
    return sorted(paths)


def frontmatter(path: Path) -> tuple[dict[str, str], list[str]]:
    lines = path.read_text().splitlines()
    if not lines or lines[0] != '---':
        raise AssertionError(f'{path}: missing opening frontmatter delimiter')
    try:
        end = lines.index('---', 1)
    except ValueError as exc:
        raise AssertionError(f'{path}: missing closing frontmatter delimiter') from exc
    data: dict[str, str] = {}
    for line in lines[1:end]:
        if ':' not in line or line.startswith(' '):
            continue
        key, value = line.split(':', 1)
        data[key.strip()] = value.strip().strip('"\'')
    return data, lines[end + 1:]


def load_exceptions(root: Path, filename: str, label: str) -> dict[str, dict]:
    path = root / '.ai/skills' / filename
    if not path.exists():
        return {'schema_version': '1.0', 'exceptions': []}
    payload = json.loads(path.read_text())
    assert payload.get('schema_version') == '1.0', f'{label} exceptions schema_version must be 1.0'
    exceptions = payload.get('exceptions')
    assert isinstance(exceptions, list), f'{label} exceptions must be a list'
    by_skill = {}
    for entry in exceptions:
        for field in ['skill', 'owner', 'reason', 'expires']:
            assert entry.get(field), f'{label} exception missing {field}'
        by_skill[entry['skill']] = entry
    return {'schema_version': '1.0', 'exceptions': exceptions, 'by_skill': by_skill}


def audit(root: Path) -> dict:
    description_exceptions = load_exceptions(root, 'description-exceptions.json', 'description').get('by_skill', {})
    body_exceptions = load_exceptions(root, 'body-line-exceptions.json', 'body-line').get('by_skill', {})
    skills = []
    failures = []
    warnings = []
    for skill_path in first_class_skill_paths(root):
        rel = skill_path.relative_to(root).as_posix()
        meta, body = frontmatter(skill_path)
        name = meta.get('name', '')
        desc = meta.get('description', '')
        if not name:
            failures.append(f'{rel}: missing name')
        if not desc:
            failures.append(f'{rel}: missing description')
        desc_len = len(desc)
        description_exception = description_exceptions.get(name)
        body_exception = body_exceptions.get(name)
        status = 'pass'
        if desc_len > MAX_DESCRIPTION_CHARS:
            status = 'fail'
            failures.append(f'{rel}: description length {desc_len} exceeds maximum {MAX_DESCRIPTION_CHARS}')
        elif desc_len > TARGET_DESCRIPTION_CHARS:
            if description_exception:
                warnings.append(f'{rel}: description length {desc_len} uses audited exception above target {TARGET_DESCRIPTION_CHARS}')
            else:
                status = 'fail'
                failures.append(f'{rel}: description length {desc_len} exceeds target {TARGET_DESCRIPTION_CHARS} without audited exception')
        body_len = len(body)
        body_status = 'target'
        if body_len > MAX_BODY_LINES:
            status = 'fail'
            body_status = 'over-maximum'
            failures.append(f'{rel}: body length {body_len} exceeds maximum {MAX_BODY_LINES}')
        elif body_len > TARGET_BODY_LINES:
            if body_exception:
                body_status = 'exception'
                warnings.append(f'{rel}: body length {body_len} uses audited exception above target {TARGET_BODY_LINES}')
            else:
                status = 'fail'
                body_status = 'over-target'
                failures.append(f'{rel}: body length {body_len} exceeds target {TARGET_BODY_LINES} without audited exception')
        lowered = '\n'.join(body).lower()
        cross_skill = 'not-required'
        for required in REQUIRED_CROSS_SKILL.get(name, []):
            if required.lower() not in lowered and required.lower() not in desc.lower():
                status = 'fail'
                failures.append(f'{rel}: missing cross-skill/workflow cue {required!r}')
            else:
                cross_skill = 'present'
        skills.append({
            'name': name,
            'path': rel,
            'description_chars': desc_len,
            'description_status': 'target' if desc_len <= TARGET_DESCRIPTION_CHARS else ('exception' if description_exception and desc_len <= MAX_DESCRIPTION_CHARS else 'over-target'),
            'body_lines': body_len,
            'body_status': body_status,
            'cross_skill_links': cross_skill,
            'ai_sdlc_compatible': True,
            'status': status,
        })
    return {
        'schema_version': '1.0',
        'policy': {
            'target_description_chars': TARGET_DESCRIPTION_CHARS,
            'max_description_chars': MAX_DESCRIPTION_CHARS,
            'target_body_lines': TARGET_BODY_LINES,
            'max_body_lines_with_exception': MAX_BODY_LINES,
            'catalog_scope': 'first-class skill directories plus ai-sdlc-init shim; excludes .agents, reference fixtures, golden outputs, hidden/runtime dirs',
        },
        'skill_count': len(skills),
        'warnings': warnings,
        'failures': failures,
        'skills': skills,
        'status': 'fail' if failures else 'pass',
    }


def compare_committed(root: Path, payload: dict) -> None:
    path = root / '.ai/skills/catalog-audit.json'
    if not path.exists():
        return
    committed = json.loads(path.read_text())
    for key in ['schema_version', 'policy', 'skill_count', 'skills', 'status']:
        assert committed.get(key) == payload.get(key), f'catalog audit artifact drift at {key}'


def write_artifacts(root: Path, payload: dict) -> None:
    out = root / '.ai/skills'
    out.mkdir(parents=True, exist_ok=True)
    for filename in ('description-exceptions.json', 'body-line-exceptions.json'):
        exc = out / filename
        if not exc.exists():
            exc.write_text(json.dumps({'schema_version': '1.0', 'exceptions': []}, indent=2) + '\n')
    (out / 'catalog-audit.json').write_text(json.dumps(payload, indent=2) + '\n')
    lines = [
        '# Skill Modernization Report',
        '',
        'status: `pass`' if payload['status'] == 'pass' else 'status: `fail`',
        f"skill_count: `{payload['skill_count']}`",
        f"target_description_chars: `{TARGET_DESCRIPTION_CHARS}`",
        f"max_description_chars: `{MAX_DESCRIPTION_CHARS}`",
        f"target_body_lines: `{TARGET_BODY_LINES}`",
        f"max_body_lines_with_exception: `{MAX_BODY_LINES}`",
        f"warnings: `{len(payload['warnings'])}`",
        f"failures: `{len(payload['failures'])}`",
        '',
        'All first-class descriptions and bodies meet their normal budgets unless explicitly excepted; 180 is absolute.',
    ]
    (out / 'modernization-report.md').write_text('\n'.join(lines) + '\n')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--root', default='.')
    parser.add_argument('--write-audit', action='store_true')
    args = parser.parse_args()
    root = Path(args.root).resolve()
    payload = audit(root)
    if args.write_audit:
        write_artifacts(root, payload)
    else:
        compare_committed(root, payload)
    if payload['warnings']:
        print('\n'.join(f'WARN: {w}' for w in payload['warnings']))
    if payload['failures']:
        print('\n'.join(f'FAIL: {f}' for f in payload['failures']), file=sys.stderr)
        return 1
    print(f"skill catalog validation passed ({payload['skill_count']} skills)")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
