#!/bin/bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

tmp_codex="$(mktemp -d)"
tmp_claude="$(mktemp -d)"
trap 'rm -rf "$tmp_codex" "$tmp_claude"' EXIT

HOME="$tmp_codex" bash scripts/install-codex.sh --all >/dev/null
HOME="$tmp_claude" bash scripts/install-claude-code.sh --user >/dev/null

codex_root="$tmp_codex/.codex/skills"
claude_root="$tmp_claude/.claude/skills/omc-learned"

python3 - "$REPO_ROOT" "$codex_root" "$claude_root" <<'PY'
import hashlib, json, sys
from pathlib import Path

repo, codex, claude = map(Path, sys.argv[1:])
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
print(f'cross-host skill parity passed ({len(skills)} skills)')
PY
