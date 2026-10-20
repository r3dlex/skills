"""Every verification.py stop site, plus allowlist and quoting boundaries."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile


def run(parity, lib):
    spec = importlib.util.spec_from_file_location('frozen_verification', lib / 'verification.py')
    frozen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(frozen)
    with tempfile.TemporaryDirectory(prefix='e6-verification-') as temporary:
        root = Path(temporary).resolve()
        (root / 'tests').mkdir()
        (root / 'tests/ok.sh').write_text('exit 0\n')
        (root / 'directory').mkdir()
        (root / 'escape').symlink_to(root.parent, target_is_directory=True)
        (root / 'tests/escape.sh').symlink_to('/dev/null')
        entries = [None, [], True, [''], [None], [{}], [{'cwd': '.', 'command': ''}], [{'cwd': '', 'command': 'git diff --check'}],
                   [{'cwd': ' .', 'command': 'git diff --check'}], ['git\tdiff --check'], ['git diff --check; true'], ['bash tests/../ok.sh'],
                   [{'cwd': '../escape', 'command': 'git diff --check'}], [{'cwd': 'missing', 'command': 'git diff --check'}],
                   [{'cwd': 'tests/ok.sh', 'command': 'git diff --check'}], [{'cwd': 'escape', 'command': 'git diff --check'}],
                   ['bash "tests/ok.sh'], ['echo no'], ['bash tests/missing.sh'], ['bash tests/escape.sh'],
                   ['git diff --check'], ['bash tests/ok.sh'], ["bash 'tests/ok.sh'"], ['npm run test:unit'], ['npm run test:publish'],
                   ['moon run repo:check'], ['moon run repo:check-upload'], ['bash tests/'], ["npm run 'test:it\"s'"], ["npm run \"test:it's\""],
                   ['\ufeffgit diff --check'], ['\x1cgit diff --check']]
        entries += [[value] for value in ['npm run test:publısh', 'npm run teſt:unit', 'npm run checK:unit', 'npm run test:foo\x85../bar', 'npm run test:foo\ufeff../bar', 'moon run repo:test:publİsh']]
        entries += [[' '.join(command)] for command in sorted(frozen.EXACT_COMMANDS)]
        for index, value in enumerate(entries):
            compare(parity, frozen, root, value, 'verification-site-%d' % index)
        old = os.environ.get('PATH')
        try:
            os.environ['PATH'] = str(root / 'absent-bin')
            compare(parity, frozen, root, ['git diff --check'], 'verification-executable-unavailable', node=parity.NODE)
        finally:
            if old is not None: os.environ['PATH'] = old


def compare(parity, frozen, root, value, name, node='node'):
    try:
        result = parity.observe(frozen.validate, root, value)
        expected = {'result': [(command, argv, str(cwd)) for command, argv, cwd in result]}
        code = 0
    except frozen.VerificationError as error:
        expected = {'error': str(error), 'type': 'VerificationError', 'code': error.code}
        parity.REFUSALS.add(str(error))
        code = 1
    base = parity.REPO / 'tests/fixtures/e6-v1-port'
    result = subprocess.run([node, str(base / 'bridge.mjs'), str(parity.REPO)], input=json.dumps({'operation': 'verification', 'args': [str(root), value]}), capture_output=True, text=True)
    # JSON transport spacing is not the validator output; compare its exact values
    # serialized identically, retaining the refusal code and process exit.
    actual = json.loads(result.stdout)
    parity.same(name, (code, (json.dumps(expected, sort_keys=True) + '\n').encode(), b''), (result.returncode, (json.dumps(actual, sort_keys=True) + '\n').encode(), result.stderr.encode()))
