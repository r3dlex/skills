#!/usr/bin/env python3
"""Validate init-ai-repo cascade fixture contracts."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = {
    "standalone": "standalone-root",
    "umbrella": "umbrella-root",
}
HOSTS = ["github", "ado", "gitlab", "jira", "local-markdown"]
OPERATIONS = {
    "discover_scope",
    "plan_parent_item",
    "plan_child_item",
    "dry_run",
    "confirm_first_run",
    "apply_confirmed_plan",
    "readback_links",
    "apply_idempotent_update",
    "audit_event",
    "reconcile",
}
TOKEN_RE = re.compile(r"^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$")


def load_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text())
    except Exception as exc:  # pragma: no cover - shell-facing diagnostic
        raise AssertionError(f"invalid json {path}: {exc}") from exc


def assert_no_secret_text(path: Path) -> None:
    text = path.read_text().lower()
    forbidden = ["api_token", "access_token", "refresh_token", "authorization:", "bearer ", "password"]
    for needle in forbidden:
        assert needle not in text, f"secret-like token {needle!r} found in {path}"


def validate_fixture(name: str, repo_id: str) -> None:
    root = ROOT / "reference/fixtures/v3" / name
    cascade_dir = root / ".ai/cascade"
    plan_path = cascade_dir / "cascade-plan.json"
    audit_path = cascade_dir / "audit.jsonl"
    report_path = cascade_dir / "reconciliation-report.md"
    assert plan_path.is_file(), f"missing {plan_path}"
    assert audit_path.is_file(), f"missing {audit_path}"
    assert report_path.is_file(), f"missing {report_path}"

    plan = load_json(plan_path)
    assert plan["schema_version"] == "1.0"
    assert plan["root_repo_id"] == repo_id
    assert plan["cascade_id"] == f"cascade:{repo_id}:init-ai-repo"
    assert plan["matrix_path"] == ".ai/matrix.json"
    assert plan["configured_hosts"] == HOSTS
    assert plan["first_run_confirmation_required"] is True
    assert TOKEN_RE.pattern == plan["confirmation_token_pattern"]
    assert plan["safety"]["no_first_run_apply_without_confirmation"] is True
    assert plan["safety"]["no_duplicate_child_items"] is True
    assert plan["safety"]["no_secret_material"] is True

    matrix = load_json(root / ".ai/matrix.json")
    standalone_noop = matrix["topology_type"] == "standalone"
    if matrix["topology_type"] == "umbrella":
        expected_paths = [repo["path"] for repo in matrix["managed_repositories"]]
        assert plan["managed_repositories"] == expected_paths
        assert len(plan["child_items"]) == len(expected_paths)
        assert plan.get("cascade_mode") != "no-op-standalone"
    else:
        assert plan["managed_repositories"] == []
        assert plan["child_items"] == []
        assert plan.get("cascade_mode") == "no-op-standalone"
        assert plan["safety"]["standalone_noop_without_explicit_multi_repo_selection"] is True

    audit_lines = [json.loads(line) for line in audit_path.read_text().splitlines() if line.strip()]
    statuses = {event["status"] for event in audit_lines}
    assert "apply-blocked-no-confirmation" in statuses
    if matrix["topology_type"] == "umbrella":
        assert "created-or-linked" in statuses
        assert "updated-existing" in statuses
    else:
        assert "no-op-standalone" in statuses
        assert "no-op-existing" in statuses
    assert "match" in statuses
    for event in audit_lines:
        if event.get("confirmation_token"):
            assert TOKEN_RE.match(event["confirmation_token"]), event
        assert event.get("duplicates_created", 0) == 0

    report = report_path.read_text()
    for required in ["status: `pass`", "first_run_without_confirmation: `blocked`", "idempotent_update: `pass`", "duplicates_created: `0`", "missing_links: `0`", "readback_status: `match`"]:
        assert required in report, f"missing {required} in {report_path}"

    workflow = (root / ".ai/workflows/repo-workflow.md").read_text()
    handoff = (root / ".ai/handoff/init-ai-repo-handoff.md").read_text()
    for linked in [".ai/cascade/cascade-plan.json", ".ai/cascade/audit.jsonl", ".ai/cascade/reconciliation-report.md"]:
        assert linked in workflow, f"missing workflow link {linked}"
        assert linked in handoff, f"missing handoff link {linked}"

    for host in HOSTS:
        adapter_path = cascade_dir / "host-adapters" / f"{host}.json"
        assert adapter_path.is_file(), f"missing {adapter_path}"
        assert_no_secret_text(adapter_path)
        adapter = load_json(adapter_path)
        assert adapter["schema_version"] == "1.0"
        assert adapter["host"] == host
        assert set(adapter["operations"]) == OPERATIONS
        if standalone_noop:
            assert adapter["standalone_noop"] is True
            assert adapter["dry_run"]["status"] == "no-op-standalone"
            assert adapter["dry_run"]["would_create_parent"] is False
            assert adapter["dry_run"]["would_create_children"] == 0
            assert adapter["apply"]["status"] == "not-required"
            assert adapter["apply"]["parent_key"] is None
            assert adapter["apply"]["child_keys"] == []
            assert adapter["second_run"]["status"] == "no-op-existing"
            assert adapter["readback"]["parent_link_present"] is False
            assert adapter["readback"]["child_links_present"] is False
        else:
            assert adapter["dry_run"]["status"] == "planned"
            assert adapter["apply"]["status"] == "created-or-linked"
            assert adapter["second_run"]["status"] == "updated-existing"
            assert adapter["readback"]["parent_link_present"] is True
            assert adapter["readback"]["child_links_present"] is True
        assert adapter["second_run"]["duplicates_created"] == 0
        assert adapter["readback"]["status"] == "match"
        assert adapter["safety"]["credentials_stored"] is False
        assert adapter["safety"]["host_policy_mutation"] is False
        if adapter["hosted"]:
            assert adapter["safety"]["first_run_without_confirmation"] == "blocked"
            assert adapter["safety"]["confirmation_token_required"] is True
            assert TOKEN_RE.match(adapter["safety"]["confirmation_token"])
        else:
            assert adapter["safety"]["first_run_without_confirmation"] == "not-required-local-write"
            assert adapter["safety"]["confirmation_token_required"] is False

    for path in [plan_path, audit_path, report_path]:
        assert_no_secret_text(path)


def main() -> int:
    for fixture, repo_id in FIXTURES.items():
        validate_fixture(fixture, repo_id)
    module = (ROOT / "init-ai-repo/modules/cascade.md").read_text()
    for host in ["GitHub", "Azure DevOps", "GitLab", "Jira", "Local Markdown"]:
        assert host in module
    assert "setup-skills" in module
    assert "host-policy-automation.md" in module
    assert (ROOT / "setup-skills/issue-tracker-jira.md").is_file()
    setup_skill = (ROOT / "setup-skills/SKILL.md").read_text()
    for required in ["Jira", "issue-tracker-jira.md", ".jira/", "Jira issue URLs", "Explicit tracker evidence wins"]:
        assert required in setup_skill, f"setup-skills missing Jira discoverability text: {required}"
    print("cascade fixture validation passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
