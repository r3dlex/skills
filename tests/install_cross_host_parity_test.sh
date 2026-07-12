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
import sys
from pathlib import Path

repo, codex, claude = map(Path, sys.argv[1:])
skills = sorted(p.parent.name for p in repo.glob('*/SKILL.md'))
assert skills, 'catalog must not be empty'

def files(root):
    return {
        path.relative_to(root).as_posix(): path.read_bytes()
        for path in root.rglob('*')
        if path.is_file()
    }

for name in skills:
    source = files(repo / name)
    codex_copy = files(codex / name)
    claude_copy = files(claude / name)
    assert codex_copy == source, f'Codex copy differs from source for {name}'
    assert claude_copy == source, f'Claude Code copy differs from source for {name}'
    assert codex_copy == claude_copy, f'host copies differ for {name}'

assert sorted(p.name for p in codex.iterdir() if p.is_dir()) == skills
assert sorted(p.name for p in claude.iterdir() if p.is_dir()) == skills
print(f'cross-host skill parity passed ({len(skills)} skills)')
PY
