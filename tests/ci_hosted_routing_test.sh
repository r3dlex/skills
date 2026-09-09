#!/usr/bin/env bash
# Regression contract: required hosted checks must be directly runnable when no
# repository self-hosted runners exist. Offline and deterministic.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

python3 - <<'PY'
import re
from pathlib import Path


def job_block(text: str, job_id: str) -> str:
    match = re.search(
        rf"(?ms)^  {re.escape(job_id)}:\n(?P<body>.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
        text,
    )
    assert match, f"missing required job id: {job_id}"
    return match.group(0)


def require_direct_hosted_job(path: str, job_id: str, check_name: str, required: list[str]) -> None:
    text = Path(path).read_text(encoding="utf-8")
    block = job_block(text, job_id)

    assert "self-hosted" not in text, f"{path} still routes through self-hosted"
    assert re.search(rf"(?m)^    name: {re.escape(check_name)}$", block), (
        f"{path}:{job_id} must preserve check name {check_name!r}"
    )
    assert re.search(r"(?m)^    runs-on: ubuntu-latest$", block), (
        f"{path}:{job_id} must run directly on ubuntu-latest"
    )
    assert not re.search(r"(?m)^    needs:", block), (
        f"{path}:{job_id} must not depend on an unavailable prerequisite"
    )
    assert not re.search(r"(?m)^\s+if:", block), (
        f"{path}:{job_id} must not conditionally skip the required check"
    )
    for fragment in required:
        assert fragment in block, f"{path}:{job_id} lost required command/action: {fragment}"


require_direct_hosted_job(
    ".github/workflows/ci.yml",
    "test",
    "Test Suite",
    [
        "uses: actions/checkout@v4",
        "fetch-depth: 0",
        "chmod +x tests/run-tests.sh",
        "chmod +x tests/test-skills.sh",
        "chmod +x tests/test-scripts.sh",
        "run: tests/run-tests.sh",
    ],
)
require_direct_hosted_job(
    ".github/workflows/ci-prek.yml",
    "prek-check",
    "Pre-commit Hooks",
    [
        "uses: actions/checkout@v4",
        "uses: j178/prek-action@v2",
        "extra-args: '--all-files'",
    ],
)

for workflow in (".github/workflows/ci.yml", ".github/workflows/ci-prek.yml"):
    text = Path(workflow).read_text(encoding="utf-8")
    assert 'branches: [main, "codex/**"]' in text, f"{workflow} push trigger changed"
    assert "pull_request:\n    branches: [main]" in text, f"{workflow} PR trigger changed"

print("hosted CI routing contract passed")
PY
