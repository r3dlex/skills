#!/bin/bash
# Explicitly unmeasured coverage chooses the safer TDD technique, not invented data.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$ROOT" <<'PY'
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(sys.argv[1])
sys.path.insert(0, str(ROOT / 'tests'))
from readiness_fixture import fixture, write, digest
READY = ROOT / "04-validate-handoff/autobahn/readiness-check.sh"
TDD = ROOT / "04-validate-handoff/autobahn/tdd-mode.sh"


class UnknownCoverageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bundle, self.context = fixture(self.root)
        self.path = self.root / "goal.json"
        self.goal = self.bundle['goals'][0]

    def run_gate(self, script, goal=None):
        chosen = self.goal if goal is None else goal
        if script == READY:
            bundle = copy.deepcopy(self.bundle)
            bundle['goals'] = [chosen]
            write(self.root, 'goal.json', {'schema': 'direct-goal/1', 'bundle': bundle})
            self.context['authority']['subject_sha256'] = digest(self.path)
            write(self.root, 'context.json', self.context)
            args = ['--root', str(self.root), '--context', str(self.root / 'context.json')]
        else:
            self.path.write_text(json.dumps(chosen))
            args = []
        return subprocess.run(
            ["bash", str(script), "--goal", str(self.path), *args],
            capture_output=True, text=True, timeout=5,
        )

    def test_explicit_unknown_requires_and_selects_legacy_safe(self):
        readiness = self.run_gate(READY)
        posture = self.run_gate(TDD)
        self.assertEqual(readiness.returncode, 0, readiness.stderr)
        self.assertEqual((posture.returncode, posture.stdout.strip()), (0, "legacy-safe"))

    def test_unknown_cannot_claim_standard_tdd(self):
        self.goal["legacy_safe_tdd"] = False
        self.assertNotEqual(self.run_gate(READY).returncode, 0)
        # Technique auto-selection is conservative regardless of a false goal hint.
        self.assertEqual(self.run_gate(TDD).stdout.strip(), "legacy-safe")

    def test_unknown_requires_auditable_risk_reason(self):
        self.goal["legacy_risk_reason"] = ""
        self.assertNotEqual(self.run_gate(READY).returncode, 0)
        self.assertNotEqual(self.run_gate(TDD).returncode, 0)

    def test_unknown_cannot_waive_a_measured_coverage_requirement(self):
        self.goal["coverage_required"] = True
        self.assertNotEqual(self.run_gate(READY).returncode, 0)

    def test_unknown_numeric_or_invalid_status_is_not_accepted(self):
        for value in (0, True, "unknown"):
            with self.subTest(value=value):
                goal = copy.deepcopy(self.goal)
                goal["coverage_percent"] = value
                self.assertNotEqual(self.run_gate(READY, goal).returncode, 0)
                self.assertNotEqual(self.run_gate(TDD, goal).returncode, 0)
        for status in ("typo", "measured", None):
            with self.subTest(status=status):
                goal = copy.deepcopy(self.goal)
                goal["coverage_status"] = status
                self.assertNotEqual(self.run_gate(READY, goal).returncode, 0)
                self.assertNotEqual(self.run_gate(TDD, goal).returncode, 0)

    def test_measured_legacy_flag_requires_actual_boolean(self):
        for flag in (0.0, 1.0, 0, 1, None, "false"):
            with self.subTest(flag=flag):
                goal = copy.deepcopy(self.goal)
                goal.update(coverage_percent=80, coverage_status="measured", legacy_safe_tdd=flag)
                self.assertNotEqual(self.run_gate(READY, goal).returncode, 0)
                self.assertNotEqual(self.run_gate(TDD, goal).returncode, 0)

    def test_existing_measured_postures_are_preserved(self):
        for coverage, expected in ((12, "legacy-safe"), (72, "standard")):
            with self.subTest(coverage=coverage):
                goal = copy.deepcopy(self.goal)
                goal.update(coverage_percent=coverage, coverage_status="measured", legacy_safe_tdd=False)
                self.assertEqual(self.run_gate(READY, goal).returncode, 0)
                self.assertEqual(self.run_gate(TDD, goal).stdout.strip(), expected)


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
