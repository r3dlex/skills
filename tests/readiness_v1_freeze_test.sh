#!/usr/bin/env bash
#
# readiness_v1_freeze_test.sh  (ACH-S-01, AC-3, R1)
#
# readiness-contract/2 runs beside v1; it never edits v1. This test proves that:
#   1. the v1 helper files and both readiness-dependency.json manifests keep the
#      exact bytes they had at the base commit (sha256 pins below), and
#   2. a golden corpus of v1 admit/publish/migrate JSON outputs, captured at the
#      base commit 92865142, replays byte-identically through the current public
#      entry points (prereq-check.sh, handoff-write.sh, migrate-handoff.sh and
#      therefore contract-run.sh with its v2 route prelude).
#
# Scenarios: the shared disposable skills fixture (tests/readiness_fixture.py) and
# a copy of the registered xskp-p5-skill-producers generation re-rooted into a
# disposable repository. Outputs are normalized only for values that depend on
# the disposable location: the temporary root path and digests of files under it
# (named by their relative path), so the corpus is stable across machines.
#
# Usage:
#   bash tests/readiness_v1_freeze_test.sh                      # verify (default)
#   bash tests/readiness_v1_freeze_test.sh capture <code-root>  # print a corpus
#
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-check}"
CODE_ROOT="${2:-$REPO_ROOT}"
PYTHONPATH="$REPO_ROOT/tests${PYTHONPATH:+:$PYTHONPATH}" python3 -B - "$REPO_ROOT" "$MODE" "$CODE_ROOT" <<'PYTEST'
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from readiness_fixture import fixture, write, digest

REPO, MODE, CODE = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]).resolve()

PINS = {
    '04-validate-handoff/autobahn/lib/readiness_contract.py': '30cfb9bf7436ff1f6b14c0b16542a62a6893321f5eface820c827ae4ec600166',
    '04-validate-handoff/autobahn/lib/verification.py': '572819a9c8a1039173c5483d0f7f9a33362588d197e27731bb97b5dd78d33524',
    '04-validate-handoff/autobahn/schemas/readiness-contract.json': 'f05119f6d00d2d2cf58270c81073e70016d2644042e3f8185ac0371ef88aa384',
    '04-validate-handoff/autobahn/readiness-dependency.json': 'e95f145f7fa55a16fd6a2b18daf8d4674ada61b6283693ab5116e56c5ef040ca',
    '02-govern-plan/northstar/readiness-dependency.json': 'e95f145f7fa55a16fd6a2b18daf8d4674ada61b6283693ab5116e56c5ef040ca',
}
P5 = '.ai/handoff/readiness-v1/xskp-p5-skill-producers/4a064a42f24659d6df9f48f66ee9900103a6f002672155d9f8d27b49d80cdb0c/goals.json'
P5_SHA256 = '8089c7c77e5aadb62c1a003fb7b30c78465ceb65541fc5b7927b3e2a0bd58cff'

# Captured at base 92865142328863cc0d6d5e3aa36d6a9eb3d6e7d3 with
# `bash tests/readiness_v1_freeze_test.sh capture <detached base worktree>`.
CORPUS = {
    'fixture-admit-implementation': {'exit': 0, 'sha256': '32ad626812bf6495e0d3fa1421bbf52375e05dc25677b1dc41bed3407529bb5c'},
    'fixture-admit-merge': {'exit': 1, 'sha256': 'ebe41489f0dc61dd7ff74485251e4ece53b35a8a81018134d86c3ef317964958'},
    'fixture-admit-planning': {'exit': 0, 'sha256': 'bbcd1301aba071acb7c0d4b1f44f05593ee533b5c89040c5b5333f0268a89cdd'},
    'fixture-admit-unselected': {'exit': 1, 'sha256': '0c36e25c4d8fff7dc6bf21b1910295be509d8c22e84a4183396eb3f802f36eb5'},
    'fixture-migrate': {'exit': 0, 'sha256': '446f6ad83ca994aebd826f1f8a72cc02b9e82cf8d5a1d6d8516553655e017406'},
    'fixture-publish': {'exit': 0, 'sha256': 'cc0f0475017e4ff32a284203e38fa1c89cde0e4577aaafa2a3d1e6121d39cdf7'},
    'fixture-readiness-check': {'exit': 0, 'sha256': '32ad626812bf6495e0d3fa1421bbf52375e05dc25677b1dc41bed3407529bb5c'},
    'fixture-republish': {'exit': 0, 'sha256': 'cc0f0475017e4ff32a284203e38fa1c89cde0e4577aaafa2a3d1e6121d39cdf7'},
    'p5-admit-planning': {'exit': 0, 'sha256': '51d4d8f1c8240ce05805982b285d5b49f47dc55e2e0d3f25ba427a7711d196e5'},
    'p5-migrate': {'exit': 0, 'sha256': '9f2b3847c7ec75cf91cd77036c55d15a296f03fa483677fa916ded7f44ef4a7d'},
    'p5-publish': {'exit': 0, 'sha256': 'f6d15a9e14345a08b8f431f2531e880c4368b9eebd6b712b97b43c86b5c62b7b'},
}

passes, failures = 0, []


def check(name, condition, detail=''):
    global passes
    if condition:
        passes += 1
        print('  PASS: ' + name)
    else:
        failures.append(name)
        print('  FAIL: ' + name + (('\n' + detail) if detail else ''))


def canonical(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def run(script, *args):
    result = subprocess.run(['bash', str(script), *map(str, args)], capture_output=True, text=True, timeout=120,
                            stdin=subprocess.DEVNULL)
    return result.returncode, result.stdout


def normalize(text, root, bundles):
    """Replace location-dependent values with stable names; every other byte is kept."""
    replacements = [(str(root.resolve()), '<ROOT>'), (str(root), '<ROOT>')]
    for name, bundle in bundles.items():
        replacements.append((canonical(bundle), '<canonical:%s>' % name))
    for old, new in replacements:
        text = text.replace(old, new)
    files = {}
    for path in sorted(p for p in root.rglob('*') if p.is_file()):
        relative = path.relative_to(root).as_posix()
        for old, new in replacements:
            relative = relative.replace(old, new)
        files.setdefault(digest(path), '<sha256:%s>' % relative)
    for value, name in files.items():
        text = text.replace(value, name)
    return text


def skeleton(root, spec_path, spec_bytes):
    write(root, '.ai/matrix.json', {})
    write(root, '.ai/workflows/repo-workflow.json', {'optional_branches': []})
    write(root, '.ai/workflows/northstar-readiness-v1.json', {'schema': 'readiness-contract/1', 'plans': []})
    write(root, '.ai/traceability/graph.json', {'schema_version': '1.1', 'root_repo_id': 'skills', 'nodes': [
        {'id': 'spec:skills:xskp-p5-skill-producers', 'type': 'spec', 'title': 'P5', 'status': 'active',
         'repo_id': 'skills', 'path': spec_path, 'backlinks': []}], 'edges': []})
    (root / 'AGENTS.md').write_text('Fixture policy only')
    (root / spec_path).parent.mkdir(parents=True, exist_ok=True)
    (root / spec_path).write_bytes(spec_bytes)
    (root / 'tests').mkdir(exist_ok=True)
    (root / 'tests/run-tests.sh').write_text('#!/bin/sh\ntouch SHOULD_NOT_RUN\n')


def corpus(code):
    auto, writer = code / '04-validate-handoff/autobahn', code / '02-govern-plan/northstar/handoff-write.sh'
    results = {}
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / 'fixture'
        root.mkdir()
        bundle, context = fixture(root)
        bundles = {'plan.json': bundle}

        def record(name, outcome, scenario_root=root):
            exit_code, stdout = outcome
            text = normalize(stdout, scenario_root, bundles)
            results[name] = {'exit': exit_code, 'sha256': hashlib.sha256(text.encode()).hexdigest(), 'text': text}
            return exit_code, stdout

        exit_code, stdout = record('fixture-publish', run(writer, '--root', root, '--bundle', root / 'plan.json'))
        entry = json.loads(stdout)['published']
        context['authority']['subject_sha256'] = entry['artifacts']['bundle']['sha256']
        write(root, 'context.json', context)
        select = ['--root', root, '--handoff', 'northstar-plan-chosen', '--goal-id', 'G1', '--context', root / 'context.json']
        for stage in ('implementation', 'planning', 'merge'):
            record('fixture-admit-' + stage, run(auto / 'prereq-check.sh', *select, '--stage', stage))
        record('fixture-readiness-check', run(auto / 'readiness-check.sh', *select))
        record('fixture-admit-unselected', run(auto / 'prereq-check.sh', '--root', root, '--handoff', 'wrong', '--goal-id', 'G1'))
        record('fixture-republish', run(writer, '--root', root, '--bundle', root / 'plan.json'))
        legacy = write(root, 'legacy.json', {'id': 'legacy-chosen', 'implementation_ready': True, 'root_causes': ['kept']})
        record('fixture-migrate', run(auto / 'migrate-handoff.sh', '--root', root, '--legacy', legacy, '--bundle', root / 'plan.json'))

        p5_root = Path(tmp) / 'p5'
        p5_root.mkdir()
        p5_bytes = (code / P5).read_bytes()
        p5 = json.loads(p5_bytes)
        skeleton(p5_root, p5['spec']['path'], (code / p5['spec']['path']).read_bytes())
        for item in [p5, *p5['goals']]:
            item['repository']['root'] = str(p5_root.resolve())
        write(p5_root, 'plan.json', p5)
        bundles = {'p5-plan.json': p5}
        record('p5-publish', run(writer, '--root', p5_root, '--bundle', p5_root / 'plan.json'), p5_root)
        record('p5-admit-planning', run(auto / 'prereq-check.sh', '--root', p5_root, '--handoff',
                                        'northstar-plan-xskp-p5-skill-producers', '--goal-id', 'XSKP-P5-01',
                                        '--stage', 'planning'), p5_root)
        record('p5-migrate', run(auto / 'migrate-handoff.sh', '--root', p5_root, '--legacy', p5_root / 'plan.json',
                                 '--bundle', p5_root / 'plan.json'), p5_root)
    return results, p5_bytes


if MODE == 'capture':
    results, _ = corpus(CODE)
    print(json.dumps({name: {'exit': value['exit'], 'sha256': value['sha256']} for name, value in sorted(results.items())},
                     indent=4, sort_keys=True))
    sys.exit(0)
if MODE != 'check':
    sys.exit('usage: readiness_v1_freeze_test.sh [check | capture <code-root>]')

for name, expected in PINS.items():
    check('v1 bytes frozen: ' + name, digest(REPO / name) == expected)
check('registered xskp-p5 generation bytes are the pinned copy', digest(REPO / P5) == P5_SHA256)
check('golden corpus captured at the base commit is present', len(CORPUS) == 11)
results, _ = corpus(REPO)
check('replayed scenarios equal the captured scenario set', sorted(results) == sorted(CORPUS),
      'replayed: %s\ncaptured: %s' % (sorted(results), sorted(CORPUS)))
for name, golden in sorted(CORPUS.items()):
    actual = results.get(name)
    check('byte-identical v1 output: ' + name,
          actual is not None and actual['exit'] == golden['exit'] and actual['sha256'] == golden['sha256'],
          'expected %s, got exit %s:\n%s' % (golden, actual and actual['exit'], actual and actual['text'][:4000]))

print('')
print('Results: PASS=%d FAIL=%d' % (passes, len(failures)))
sys.exit(1 if failures else 0)
PYTEST
