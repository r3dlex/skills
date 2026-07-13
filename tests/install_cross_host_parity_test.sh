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
HOME="$tmp_copilot" bash scripts/install-copilot.sh --repo "$tmp_copilot/repo" >/dev/null

codex_root="$tmp_codex/.codex/skills"
claude_root="$tmp_claude/.claude/skills/omc-learned"
auggie_root="$tmp_auggie/.auggie/rules"
gemini_root="$tmp_gemini/.gemini/skills"
copilot_root="$tmp_copilot/repo/.github"

python3 - "$REPO_ROOT" "$codex_root" "$claude_root" "$auggie_root" "$gemini_root" "$copilot_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

repo, codex, claude, auggie, gemini, copilot = map(Path, sys.argv[1:])
catalog = json.loads((repo / 'catalog.json').read_text())
entries = sorted(catalog['skills'], key=lambda item: item['name'])
skills = [entry['name'] for entry in entries]
assert skills, 'catalog must not be empty'

for entry in entries:
    name = entry['name']
    source = repo / entry['source_path'] / 'SKILL.md'
    codex_copy = codex / name / 'SKILL.md'
    claude_copy = claude / name / 'SKILL.md'
    assert codex_copy.is_file(), f'Codex missing {name}'
    assert claude_copy.is_file(), f'Claude Code missing {name}'
    hashes = {hashlib.sha256(p.read_bytes()).hexdigest() for p in (source, codex_copy, claude_copy)}
    assert len(hashes) == 1, f'host copies differ for {name}'

assert sorted(p.name for p in codex.iterdir() if p.is_dir()) == skills
assert sorted(p.name for p in claude.iterdir() if p.is_dir()) == skills

# Codex and Claude receive recursive skill directories. Other hosts receive
# host-specific flattened or synthesized projections rather than false copies.
sample = entries[0]['name']
assert (auggie / f'{sample}.md').is_file()
assert not (auggie / sample).exists()
assert (gemini / f'{sample}.md').is_file()
assert not (gemini / sample).exists()
assert (copilot / 'copilot-instructions.md').is_file()
assert not (copilot / 'copilot-instructions').exists()
assert not (copilot / sample / 'SKILL.md').exists()

readme = (repo / 'README.md').read_text()
normalized_readme = ' '.join(readme.split())
assert 'Codex and Claude Code recursively install each selected skill directory' in normalized_readme
assert 'Auggie, Gemini, and GitHub Copilot receive host-specific flattened or synthesized projections' in normalized_readme
assert 'The installers copy the complete skill directory' not in readme
assert 'matching `SKILL.md` content across supported destinations' not in readme
print(f'cross-host projection contract passed ({len(skills)} skills)')
PY
