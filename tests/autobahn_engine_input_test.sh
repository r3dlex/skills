#!/bin/bash
# Exercise the public engine selector CLI; bound regressions that used to hang.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
python3 - <<'PY'
import subprocess
import tempfile
from pathlib import Path
import unittest

SCRIPT = "04-validate-handoff/autobahn/engine-pick.sh"


class EngineInputTest(unittest.TestCase):
    def assert_rejected(self, *args):
        result = subprocess.run(
            ["bash", SCRIPT, *args], capture_output=True, text=True, timeout=2
        )
        self.assertEqual(result.returncode, 2, result)
        self.assertEqual(result.stdout, "", result)
        self.assertTrue(result.stderr.strip(), result)

    def test_missing_option_values(self):
        for option in (
            "--goal", "--engine", "--qa-heavy", "--parallelizable",
            "--needs-persistence", "--kind",
        ):
            for tail in ([], [""], ["--engine", "team"]):
                with self.subTest(option=option, tail=tail):
                    self.assert_rejected(option, *tail)

    def test_invalid_goal_cannot_select_an_engine(self):
        with tempfile.TemporaryDirectory() as directory:
            goal = Path(directory) / "goal.json"
            for content in (b"[]", b"null", b"true", b"42", b'"qa"', b"{", b"\\xff"):
                goal.write_bytes(content)
                for override in ([], ["--engine", "team"]):
                    with self.subTest(content=content, override=override):
                        self.assert_rejected("--goal", str(goal), *override)
            goal.unlink()
            for path in (goal, Path(directory)):
                for override in ([], ["--engine", "team"]):
                    with self.subTest(path=str(path), override=override):
                        self.assert_rejected("--goal", str(path), *override)


unittest.main(verbosity=2)
PY
