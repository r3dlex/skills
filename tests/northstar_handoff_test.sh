#!/bin/bash
# Offline public CLI regression using disposable, simulated v1 policy inputs.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHONPATH="$REPO_ROOT/tests:$REPO_ROOT/scripts${PYTHONPATH:+:$PYTHONPATH}" python3 - <<'PYTEST'
import json
from pathlib import Path
import subprocess
import tempfile
from readiness_fixture import fixture, write, digest

REPO = Path.cwd()
WRITER = REPO / '02-govern-plan/northstar/handoff-write.sh'
AUTO = REPO / '04-validate-handoff/autobahn'

def run(script, root, *args):
    return subprocess.run(['bash', str(script), '--root', str(root), *args],
                          capture_output=True, text=True, timeout=10)

def passed(result):
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads(result.stdout)

def blocked(result, reason):
    assert result.returncode != 0, result.stdout
    assert reason in result.stdout + result.stderr, result.stdout + result.stderr

from traceability_schema import validate_graph

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bundle, context = fixture(root)
    # Preserve the initialized repository's complete workflow contract, including
    # required branches and phase status paths, not just a minimal manifest.
    import shutil
    source = REPO / 'reference/fixtures/v3/standalone'
    manifest = json.loads((source / '.ai/workflows/repo-workflow.json').read_text())
    write(root, '.ai/workflows/repo-workflow.json', manifest)
    for phase in manifest['phases']:
        destination = root / phase['status_path']
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / phase['status_path'], destination)
    legacy_before = (root / '.ai/workflows/repo-workflow.json').read_bytes()
    registry_path = root / '.ai/workflows/northstar-readiness-v1.json'
    registry_before = json.loads(registry_path.read_text())
    graph_before = json.loads((root / '.ai/traceability/graph.json').read_text())
    args = ('--bundle', str(root / 'plan.json'))
    entry = passed(run(WRITER, root, *args))['published']
    handoff = root / entry['handoff_path']
    assert handoff.is_file()
    assert 'G1' in handoff.read_text()
    stored_bundle = json.loads((root / entry['artifacts']['bundle']['path']).read_text())
    assert stored_bundle['spec'] == bundle['spec']
    assert stored_bundle['goals'] == bundle['goals']
    updated = json.loads((root / '.ai/workflows/repo-workflow.json').read_text())
    assert (root / '.ai/workflows/repo-workflow.json').read_bytes() == legacy_before
    assert json.loads(registry_path.read_text()) == {**registry_before, 'plans': [entry]}
    assert all((root / phase['status_path']).is_file() for phase in updated['phases'])
    assert updated['schema_version'] == '1.0'
    assert updated['workflow_id'] == 'init-ai-repo'
    assert updated['handoff'] == '.ai/handoff/init-ai-repo-handoff.md'
    print('PASS: immutable handoff, durable spec/goals and existing workflow preserved')

    graph = json.loads((root / entry['artifacts']['graph']['path']).read_text())
    validate_graph(graph)
    ids = {node['id'] for node in graph['nodes']}
    generation = entry['generation']
    assert {f'handoff:fixture:chosen:{generation}', f'plan:fixture:chosen:G1:{generation}'} <= ids
    live_graph = json.loads((root / '.ai/traceability/graph.json').read_text())
    validate_graph(live_graph)
    live_nodes = {node['id']: node for node in live_graph['nodes']}
    for previous in graph_before['nodes']:
        current = live_nodes[previous['id']]
        assert {k: v for k, v in previous.items() if k != 'backlinks'} == {
            k: v for k, v in current.items() if k != 'backlinks'}
        assert set(previous.get('backlinks', [])) <= set(current.get('backlinks', []))
    assert all(edge in live_graph['edges'] for edge in graph_before['edges'])
    assert ids <= live_nodes.keys()
    print('PASS: generation and additive live graphs validate with prior evidence preserved')

    before = {str(p): p.read_bytes() for p in root.rglob('*') if p.is_file()}
    assert passed(run(WRITER, root, *args))['published'] == entry
    assert before == {str(p): p.read_bytes() for p in root.rglob('*') if p.is_file()}
    print('PASS: identical publication is byte-idempotent without duplicate records')

    # A generation published before registry completion is safe to retry.
    write(root, '.ai/workflows/northstar-readiness-v1.json', registry_before)
    assert passed(run(WRITER, root, *args))['published'] == entry
    assert json.loads(registry_path.read_text()) == {**registry_before, 'plans': [entry]}
    assert (root / '.ai/workflows/repo-workflow.json').read_bytes() == legacy_before
    print('PASS: interrupted registry publication converges on retry')

    # Corrupt immutable generations must NOT be silently repaired or accepted.
    handoff.unlink()
    registry_bytes = registry_path.read_bytes()
    result = run(WRITER, root, *args)
    assert result.returncode != 0, result.stdout
    assert registry_path.read_bytes() == registry_bytes
    assert not handoff.exists()
    print('PASS: damaged generation fails closed without registry mutation')
PYTEST
