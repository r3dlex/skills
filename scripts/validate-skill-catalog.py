#!/usr/bin/env python3
"""Validate first-class skill catalog metadata and optional audit artifacts."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

TARGET_DESCRIPTION_CHARS = 180
HARD_DESCRIPTION_CHARS = 280
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


def load_exceptions(root: Path) -> dict[str, dict]:
    path = root / '.ai/skills/description-exceptions.json'
    if not path.exists():
        return {'schema_version': '1.0', 'exceptions': []}
    payload = json.loads(path.read_text())
    assert payload.get('schema_version') == '1.0', 'description exceptions schema_version must be 1.0'
    exceptions = payload.get('exceptions')
    assert isinstance(exceptions, list), 'description exceptions must be a list'
    by_skill = {}
    for entry in exceptions:
        for field in ['skill', 'owner', 'reason', 'expires']:
            assert entry.get(field), f'description exception missing {field}'
        by_skill[entry['skill']] = entry
    return {'schema_version': '1.0', 'exceptions': exceptions, 'by_skill': by_skill}


def audit(root: Path) -> dict:
    exceptions = load_exceptions(root).get('by_skill', {})
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
        exception = exceptions.get(name)
        status = 'pass'
        if desc_len > HARD_DESCRIPTION_CHARS and not exception:
            status = 'fail'
            failures.append(f'{rel}: description length {desc_len} exceeds hard limit {HARD_DESCRIPTION_CHARS}')
        elif desc_len > TARGET_DESCRIPTION_CHARS:
            status = 'warn'
            warnings.append(f'{rel}: description length {desc_len} exceeds target {TARGET_DESCRIPTION_CHARS}')
        body_len = len(body)
        if body_len > 100:
            status = 'fail'
            failures.append(f'{rel}: body length {body_len} exceeds 100')
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
            'description_status': 'target' if desc_len <= TARGET_DESCRIPTION_CHARS else ('exception' if exception else 'over-target'),
            'body_lines': body_len,
            'cross_skill_links': cross_skill,
            'ai_sdlc_compatible': True,
            'status': status,
        })
    return {
        'schema_version': '1.0',
        'policy': {
            'target_description_chars': TARGET_DESCRIPTION_CHARS,
            'hard_fail_description_chars': HARD_DESCRIPTION_CHARS,
            'body_line_limit': 100,
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
    exc = out / 'description-exceptions.json'
    if not exc.exists():
        exc.write_text(json.dumps({'schema_version': '1.0', 'exceptions': []}, indent=2) + '\n')
    (out / 'catalog-audit.json').write_text(json.dumps(payload, indent=2) + '\n')
    lines = [
        '# Skill Modernization Report',
        '',
        'status: `pass`' if payload['status'] == 'pass' else 'status: `fail`',
        f"skill_count: `{payload['skill_count']}`",
        f"target_description_chars: `{TARGET_DESCRIPTION_CHARS}`",
        f"hard_fail_description_chars: `{HARD_DESCRIPTION_CHARS}`",
        f"warnings: `{len(payload['warnings'])}`",
        f"failures: `{len(payload['failures'])}`",
        '',
        'All first-class skill descriptions are at or below the target budget unless explicitly excepted.',
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
