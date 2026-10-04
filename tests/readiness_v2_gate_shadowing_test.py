"""ACH-S-03 (G3, AC-2, P8): the embedded Python of the five local gate scripts starts isolated.

Every python3 the gates start runs as `python3 -I -B`, and local-ci.sh runs
lib/local_ci_contract.py through `python3 -I -B -c` with the pinned lib directory inserted into
sys.path and the module run by runpy. A PR checkout that carries shadowing stdlib modules in its
root (the gates' working directory) and on PYTHONPATH, plus a sitecustomize there and a
usercustomize in its user site-packages, never supplies a module to a gate, and each gate's
outcome equals the outcome of the same checkout without them. Disposable checkouts only."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))  # python3 -I drops the script directory
import hashlib
import json
import os
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]
AUTO = REPO / '04-validate-handoff/autobahn'
SCRIPTS = ('tdd-evidence.sh', 'tdd-mode.sh', 'lint-gate.sh', 'ci-gate.sh', 'local-ci.sh')
SHADOWED = ('json', 'pathlib', 'hashlib', 'subprocess', 're', 'shlex', 'runpy', 'verification')
# lib/local_ci_contract.py is run, never edited: its bytes at skills origin/main d72d7cb.
LOCAL_CI_CONTRACT_SHA256 = '1e57533c11c5921f13e51a74aee4f87012f4c5d53ed0752f104b170fd60be9ea'
WORKFLOW = 'jobs:\n  test:\n    runs-on: ubuntu-latest\n    steps:\n      - run: bash tests/check.sh\n'


def write(root, name, text, mode=0o644):
    path = Path(root, name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    path.chmod(mode)
    return path


def clean_env():
    """The caller's environment without any PYTHON* variable (bytecode stays off)."""
    env = {k: v for k, v in os.environ.items() if not k.startswith('PYTHON')}
    env['PYTHONDONTWRITEBYTECODE'] = '1'
    return env


def user_site(userbase):
    """The user site-packages directory python3 derives from PYTHONUSERBASE."""
    probe = subprocess.run(['python3', '-c', 'import site; print(site.getusersitepackages())'], cwd=str(userbase),
                           env=dict(clean_env(), PYTHONUSERBASE=str(userbase)), capture_output=True, text=True, check=True)
    return Path(probe.stdout.strip())


class Checkout:
    """A disposable PR checkout; shadowed=True adds the shadowing modules and their environment."""

    def __init__(self, base, name, shadowed):
        self.root = Path(base) / name
        self.root.mkdir()
        self.sentinel = Path(base) / (name + '-imported.log')
        self.env = clean_env()
        if shadowed:
            pythonpath, userbase = Path(base) / (name + '-pythonpath'), Path(base) / (name + '-userbase')
            pythonpath.mkdir()
            userbase.mkdir()
            for where, directory in (('root', self.root), ('pythonpath', pythonpath)):
                for module in SHADOWED:
                    self.shadow(directory / (module + '.py'), '%s:%s' % (where, module), exit_code=97)
            self.shadow(pythonpath / 'sitecustomize.py', 'pythonpath:sitecustomize')
            site = user_site(userbase)
            site.mkdir(parents=True, exist_ok=True)
            self.shadow(site / 'usercustomize.py', 'usersite:usercustomize')
            self.env.update(PYTHONPATH=str(pythonpath), PYTHONUSERBASE=str(userbase))

    def shadow(self, path, label, exit_code=None):
        text = 'with open(%r, "a") as handle:\n    handle.write(%r + "\\n")\n' % (str(self.sentinel), label)
        if exit_code is not None:
            text += 'raise SystemExit(%d)\n' % exit_code
        write(path.parent, path.name, text)

    def imported(self):
        return self.sentinel.read_text().split() if self.sentinel.exists() else []

    def run(self, script, *args):
        result = subprocess.run(['bash', str(AUTO / script), *map(str, args)], cwd=str(self.root), env=self.env,
                                capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=120)
        normalize = lambda text: text.replace(str(self.root), '<ROOT>')
        return [result.returncode, normalize(result.stdout), normalize(result.stderr)]


def tdd_evidence(c):
    write(c.root, 'tests/flip.sh', '#!/bin/sh\ntest -f src/done.txt\n', 0o755)
    steps = [c.run('tdd-evidence.sh', '--record-red', '--goal', 'G1', '--root', c.root, '--command', 'sh tests/flip.sh')]
    write(c.root, 'src/done.txt', 'done\n')
    steps.append(c.run('tdd-evidence.sh', '--record-green', '--goal', 'G1', '--root', c.root, '--command', 'sh tests/flip.sh'))
    steps.append(c.run('tdd-evidence.sh', '--verify', '--goal', 'G1', '--root', c.root))
    evidence = c.root / '.ai/evidence/G1.json'
    return steps + [evidence.read_text() if evidence.exists() else None]


def tdd_mode(c):
    write(c.root, 'goal.json', json.dumps({'coverage_status': 'unknown', 'legacy_risk_reason': 'Unmeasured legacy seam'}))
    write(c.root, 'measured.json', json.dumps({'coverage_status': 'measured', 'coverage_percent': 80}))
    return [c.run('tdd-mode.sh', '--goal', 'goal.json'), c.run('tdd-mode.sh', '--goal', 'measured.json'),
            c.run('tdd-mode.sh', '--goal', 'goal.json', '--legacy-risk', 'maybe')]


def lint_gate(c):
    write(c.root, 'package.json', '{"scripts": ')  # unreadable: only a correct read blocks it
    return [c.run('lint-gate.sh', '--root', c.root)]


def ci_checkout(c, contract=False):
    write(c.root, '.github/workflows/ci.yml', WORKFLOW)
    check = write(c.root, 'tests/check.sh', '#!/bin/sh\nexit 0\n', 0o755)
    write(c.root, 'record.json', json.dumps({'id': 'G1', 'verification': ['bash tests/check.sh']}))
    if contract:
        digest = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
        write(c.root, '.ai/ci/local-ci.json', json.dumps({
            'schema': 'local-ci/1', 'workflows': {'.github/workflows/ci.yml': digest(c.root / '.github/workflows/ci.yml')},
            'sources': {'tests/check.sh': digest(check)}, 'verification': ['bash tests/check.sh']}))


def ci_gate(c):
    ci_checkout(c)
    return [c.run('ci-gate.sh', '--derive-json', '--root', c.root),
            c.run('ci-gate.sh', '--verify', '--root', c.root, '--goal-record', c.root / 'record.json')]


def local_ci(c):
    ci_checkout(c)
    return [c.run('local-ci.sh', '--root', c.root)]


def local_ci_contract(c):
    ci_checkout(c, contract=True)
    return [c.run('local-ci.sh', '--root', c.root)]


class GateShadowingTests(unittest.TestCase):
    """One negative case per gate script, plus local_ci_contract.py run from a PR checkout."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name).resolve()

    def outcome(self, case):
        clean = Checkout(self.base, 'clean', shadowed=False)
        shadowed = Checkout(self.base, 'shadowed', shadowed=True)
        expected, actual = case(clean), case(shadowed)
        self.assertEqual(shadowed.imported(), [], 'a PR checkout supplied a module to a gate')
        self.assertEqual(actual, expected, 'the shadowing checkout changed the gate outcome')
        return expected

    def test_tdd_evidence_records_and_verifies_without_pr_modules(self):
        steps = self.outcome(tdd_evidence)
        self.assertEqual([step[0] for step in steps[:3]], [0, 0, 0], steps)
        self.assertEqual(json.loads(steps[3])['green']['exit_code'], 0)

    def test_tdd_mode_selects_without_pr_modules(self):
        steps = self.outcome(tdd_mode)
        self.assertEqual([(step[0], step[1].strip()) for step in steps[:2]], [(0, 'legacy-safe'), (0, 'standard')])
        self.assertEqual(steps[2][0], 2)

    def test_lint_gate_reads_package_json_without_pr_modules(self):
        steps = self.outcome(lint_gate)
        self.assertEqual(steps[0][0], 1)
        self.assertIn('package.json is malformed', steps[0][2])

    def test_ci_gate_derives_and_verifies_without_pr_modules(self):
        steps = self.outcome(ci_gate)
        self.assertEqual(steps[0][:2], [0, '["bash tests/check.sh"]\n'])
        self.assertEqual(steps[1][0], 0, steps[1])

    def test_local_ci_runs_the_safe_subset_without_pr_modules(self):
        steps = self.outcome(local_ci)
        self.assertEqual(steps[0][0], 0, steps[0])
        self.assertIn('safe local command subset', steps[0][1])

    def test_local_ci_contract_runs_from_a_pr_checkout_without_pr_modules(self):
        steps = self.outcome(local_ci_contract)
        self.assertEqual(steps[0][0], 0, steps[0])
        self.assertIn('explicit supporting local CI contract', steps[0][1])


class IsolatedInvocationTests(unittest.TestCase):
    """Every embedded python3 of the five gates is isolated; local_ci_contract.py is run, not edited."""

    def test_every_embedded_python3_starts_isolated(self):
        for name in SCRIPTS:
            lines = [line for line in (AUTO / name).read_text().splitlines()
                     if re.search(r'\bpython3\b', line) and not line.lstrip().startswith('#')
                     and 'command -v python3' not in line]
            self.assertTrue(lines, name)
            for line in lines:
                self.assertRegex(line, r'\bpython3 -I -B (-|-c)( |$)', '%s: %s' % (name, line))

    def test_local_ci_contract_runs_through_runpy_from_the_pinned_lib(self):
        text = (AUTO / 'local-ci.sh').read_text()
        self.assertTrue('runpy.run_path' in text and '"$HERE/lib"' in text,
                        'local-ci.sh must run local_ci_contract.py through runpy from the pinned lib directory')
        self.assertEqual(hashlib.sha256((AUTO / 'lib/local_ci_contract.py').read_bytes()).hexdigest(),
                         LOCAL_CI_CONTRACT_SHA256)
        with tempfile.TemporaryDirectory() as tmp:
            # Why runpy: python3 -I drops the script directory, so the module's sibling import fails.
            plain = subprocess.run(['python3', '-I', '-B', str(AUTO / 'lib/local_ci_contract.py'), tmp],
                                   capture_output=True, text=True, cwd=tmp)
            self.assertNotEqual(plain.returncode, 0)
            self.assertIn("No module named 'verification'", plain.stderr)


if __name__ == '__main__':
    unittest.main()
