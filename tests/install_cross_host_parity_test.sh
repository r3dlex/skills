#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmp_codex="$(mktemp -d)"
tmp_claude="$(mktemp -d)"
tmp_auggie="$(mktemp -d)"
tmp_gemini="$(mktemp -d)"
tmp_copilot="$(mktemp -d)"
trap 'rm -rf "$tmp_codex" "$tmp_claude" "$tmp_auggie" "$tmp_gemini" "$tmp_copilot"' EXIT

HOME="$tmp_codex" bash scripts/install-codex.sh --all >/dev/null
HOME="$tmp_claude" bash scripts/install-claude-code.sh --user >/dev/null
HOME="$tmp_auggie" bash scripts/install-auggie.sh --all >/dev/null
HOME="$tmp_gemini" bash scripts/install-gemini.sh --all >/dev/null
HOME="$tmp_copilot" bash scripts/install-copilot.sh --all "$tmp_copilot/repo" >/dev/null

codex_root="$tmp_codex/.codex/skills"
claude_root="$tmp_claude/.claude/skills/omc-learned"
auggie_root="$tmp_auggie/.auggie/rules"
gemini_root="$tmp_gemini/.gemini/skills"
copilot_root="$tmp_copilot/repo/.github"

python3 - "$REPO_ROOT" "$codex_root" "$claude_root" "$auggie_root" "$gemini_root" "$copilot_root" <<'PY'
import hashlib, json, re, sys
from pathlib import Path

repo, codex, claude, auggie, gemini, copilot = map(Path, sys.argv[1:])
catalog = json.loads((repo / 'catalog.json').read_text())

# The installers above run with default lifecycles, so only default-lifecycle
# skills land on disk. Filtering here fixes a latent bug rather than bending a
# gate: the test's original premise — every catalog entry installs on every host
# — is simply false once a lifecycle gates installation, and it held only
# because the catalog had no non-default entry until ubiquitous-language was
# deprecated. Keep this set in step with DEFAULT_LIFECYCLES in scripts/catalog.py.
# supported_hosts is filtered the same way: an entry with no hosts is
# documentation-only and installs nowhere.
DEFAULT_LIFECYCLES = {'stable', 'compatibility'}
entries = sorted(
    (item for item in catalog['skills']
     if item.get('lifecycle') in DEFAULT_LIFECYCLES and item.get('supported_hosts')),
    key=lambda item: item['name'],
)
assert entries, 'catalog must not be empty'
# Recursive-copy parity is host-scoped: each recursive host installs exactly the
# entries that name it in supported_hosts (scripts/catalog.py resolution).
codex_skills = [e['name'] for e in entries if 'codex' in e['supported_hosts']]
claude_skills = [e['name'] for e in entries if 'claude-code' in e['supported_hosts']]
auggie_skills = [e['name'] for e in entries if 'auggie' in e['supported_hosts']]
gemini_skills = [e['name'] for e in entries if 'gemini' in e['supported_hosts']]
copilot_skills = [e['name'] for e in entries if 'copilot' in e['supported_hosts']]
assert codex_skills and claude_skills, 'recursive hosts must install a nonempty set'

for host_root, host_skills, host_name in ((codex, codex_skills, 'Codex'), (claude, claude_skills, 'Claude Code')):
    for name in host_skills:
        entry = next(e for e in entries if e['name'] == name)
        source = repo / entry['source_path'] / 'SKILL.md'
        copy = host_root / name / 'SKILL.md'
        assert copy.is_file(), f'{host_name} missing {name}'
        hashes = {hashlib.sha256(p.read_bytes()).hexdigest() for p in (source, copy)}
        assert len(hashes) == 1, f'{host_name} copy differs for {name}'

assert sorted(p.name for p in codex.iterdir() if p.is_dir()) == sorted(codex_skills)
assert sorted(p.name for p in claude.iterdir() if p.is_dir()) == sorted(claude_skills)

# Codex and Claude receive recursive skill directories. Other hosts receive
# host-specific flattened or synthesized projections rather than false copies.
# Projections are host-scoped like the recursive hosts: sample/projection sets
# exclude entries that do not name that host in supported_hosts.
sample = next(e['name'] for e in entries if 'auggie' in e['supported_hosts'])
assert (auggie / f'{sample}.md').is_file()
assert not (auggie / sample).exists()
assert (gemini / f'{sample}.md').is_file()
assert not (gemini / sample).exists()
assert (copilot / 'copilot-instructions.md').is_file()
assert (copilot / 'copilot-instructions' / f'{sample}.md').is_file()
assert not (copilot / 'copilot-instructions' / sample / 'SKILL.md').exists()

# Flattened projections have no bundled skill directory. Every projected skill
# must retain its semantic headings while dropping all references to sidecar
# paths that do not exist on the target host.
projection_for = {
    'Auggie': lambda name: auggie / f'{name}.md',
    'Gemini': lambda name: gemini / f'{name}.md',
    'GitHub Copilot': lambda name: copilot / 'copilot-instructions' / f'{name}.md',
}
unavailable_paths = set()
for catalog_entry in entries:
    catalog_source = repo / catalog_entry['source_path']
    for sidecar in catalog_source.rglob('*'):
        if sidecar.is_file() and sidecar.name != 'SKILL.md':
            relative = sidecar.relative_to(catalog_source).as_posix()
            unavailable_paths.add(f"{catalog_entry['name']}/{relative}")
for prefix in ('reference', 'tests'):
    unavailable_paths.update(
        path.relative_to(repo).as_posix()
        for path in (repo / prefix).rglob('*')
        if path.is_file()
    )
flat_hosts = {
    'Auggie': auggie_skills,
    'Gemini': gemini_skills,
    'GitHub Copilot': copilot_skills,
}
for entry in entries:
    if not any(entry['name'] in names for names in flat_hosts.values()):
        continue
    name = entry['name']
    source_dir = repo / entry['source_path']
    source_text = (source_dir / 'SKILL.md').read_text()
    title = next(
        (line[2:].strip() for line in source_text.splitlines() if line.startswith('# ')),
        name,
    )
    description = next(
        line.split(':', 1)[1].strip().strip('"\'')
        for line in source_text.splitlines()
        if line.startswith('description:')
    )
    own_sidecar_paths = set()
    for sidecar in source_dir.rglob('*'):
        if not sidecar.is_file() or sidecar.name == 'SKILL.md':
            continue
        relative = sidecar.relative_to(source_dir).as_posix()
        own_sidecar_paths.add(relative)

    for host, locate in projection_for.items():
        if name not in flat_hosts[host]:
            continue
        projection = locate(name)
        assert projection.is_file(), f'{host} missing flattened {name}'
        content = projection.read_text()
        assert title in content, f'{host} {name} lost its semantic title: {title}'
        assert description in content, f'{host} {name} lost its catalog description'
        dangling = sorted(path for path in unavailable_paths | own_sidecar_paths if path in content)
        assert not dangling, f'{host} {name} retains unavailable sidecar paths: {dangling}'
        headings = list(re.finditer(r'^(#{2,6})\s+.+$', content, re.M))
        for index, heading in enumerate(headings):
            level = len(heading.group(1))
            end = len(content)
            for later in headings[index + 1:]:
                if len(later.group(1)) <= level:
                    end = later.start()
                    break
            section = re.sub(r'^#{2,6}\s+.+$', '', content[heading.end():end], flags=re.M)
            assert section.strip(), f'{host} {name} has empty section: {heading.group(0)}'

for forbidden in (
    'northstar/prereq-check.sh',
    'autobahn/prereq-check.sh',
    'eval-a-skill/scaffold-eval.py',
):
    for host, names in flat_hosts.items():
        locate = projection_for[host]
        for name in names:
            content = locate(name).read_text()
            assert forbidden not in content, f'{host} retains executable reference: {forbidden}'

readme = (repo / 'README.md').read_text()
normalized_readme = ' '.join(readme.split())
assert 'Codex and Claude Code recursively install each selected skill directory' in normalized_readme
assert 'Auggie, Gemini, and GitHub Copilot receive host-specific flattened or synthesized projections' in normalized_readme
assert 'The canonical README generator is available only in the recursive Claude Code and Codex installations.' in normalized_readme
assert 'The installers copy the complete skill directory' not in readme
assert 'matching `SKILL.md` content across supported destinations' not in readme
print(f'cross-host projection contract passed ({len(entries)} supported, {len(codex_skills)} recursive, {len(auggie_skills)}/{len(gemini_skills)}/{len(copilot_skills)} flat)')
PY
