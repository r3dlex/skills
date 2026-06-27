# Validation Module

Read when proving the scaffold matches the v3 baseline. v3 validation covers structural checks, depth validation, physical-copy sync semantics, host-policy safety wording, and the v3 fixture set.

## Commands

Run from `skills/` when validating this repository:

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
tests/final-validation-gate_test.sh
python3 scripts/validate-final-package.py
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

In addition, the v3 check set is exercised against `reference/fixtures/v3/`:

```sh
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
python3 -m json.tool reference/fixtures/v3/standalone/.ai/matrix.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/skills/git-ops.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/skills/workspace-sync.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/workflows/repo-workflow.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/traceability/graph.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/evals/example-output-eval/evalset.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/evals/example-output-eval/judge-config.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/evals/example-output-eval/evalset.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/evals/example-output-eval/judge-config.json >/dev/null
python3 -m json.tool reference/fixtures/v3/standalone/.ai/policies/model-routing.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/policies/model-routing.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/matrix.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/drift/last-drift.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/workflows/repo-workflow.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/traceability/graph.json >/dev/null
python3 - <<'PY'
import copy, json, pathlib

def rejects_invalid_topology(candidate):
    if candidate["topology_type"] == "standalone":
        return candidate["max_allowed_depth"] != 0 or candidate["current_depth"] != 0
    if candidate["topology_type"] == "umbrella":
        return (
            candidate["max_allowed_depth"] != 3
            or candidate["current_depth"] > candidate["max_allowed_depth"]
            or any(repo["depth"] > candidate["max_allowed_depth"] for repo in candidate.get("managed_repositories", []))
        )
    return True

m = json.load(open("reference/fixtures/v3/standalone/.ai/matrix.json"))
assert m["topology_type"] == "standalone"
assert m["max_allowed_depth"] == 0
assert m["current_depth"] == 0
invalid = copy.deepcopy(m)
invalid["max_allowed_depth"] = 1
assert rejects_invalid_topology(invalid)
invalid = copy.deepcopy(m)
invalid["current_depth"] = 1
assert rejects_invalid_topology(invalid)
for rel in [
    "reference/fixtures/v3/standalone/.ai/skills/git-ops.json",
    "reference/fixtures/v3/standalone/.ai/skills/workspace-sync.json",
]:
    data = json.loads(pathlib.Path(rel).read_text())
    assert data["sync_strategy"] == "physical-copy"
    assert data["topology"]["topology_type"] == "standalone"
    assert data["topology"]["max_allowed_depth"] == 0
    assert data["topology"]["current_depth"] == 0
    assert data["validation"]["reject_canonical_symlink"] is True
    assert data["validation"]["reject_canonical_git_submodule"] is True
PY
python3 - <<'PY'
import copy, json

def rejects_invalid_topology(candidate):
    if candidate["topology_type"] == "standalone":
        return candidate["max_allowed_depth"] != 0 or candidate["current_depth"] != 0
    if candidate["topology_type"] == "umbrella":
        return (
            candidate["max_allowed_depth"] != 3
            or candidate["current_depth"] > candidate["max_allowed_depth"]
            or any(repo["depth"] > candidate["max_allowed_depth"] for repo in candidate.get("managed_repositories", []))
        )
    return True

m = json.load(open("reference/fixtures/v3/umbrella/.ai/matrix.json"))
assert m["topology_type"] == "umbrella"
assert m["max_allowed_depth"] == 3
assert m["current_depth"] <= m["max_allowed_depth"]
for repo in m["managed_repositories"]:
    assert repo["depth"] <= m["max_allowed_depth"]
invalid = copy.deepcopy(m)
invalid["max_allowed_depth"] = 2
assert rejects_invalid_topology(invalid)
invalid = copy.deepcopy(m)
invalid["current_depth"] = 4
assert rejects_invalid_topology(invalid)
PY
python3 - <<'PY'
import json
m = json.load(open("reference/fixtures/v3/depth-violation/.ai/matrix.json"))
assert m["current_depth"] > m["max_allowed_depth"]
assert any(repo["depth"] > m["max_allowed_depth"] for repo in m["managed_repositories"])
PY
python3 - <<'PY'
import json

TIERS = {"frontier", "mid", "cheap"}
for variant in ("standalone", "umbrella"):
    p = f"reference/fixtures/v3/{variant}/.ai/policies/model-routing.json"
    data = json.load(open(p))
    assert data.get("schema_version"), f"{p}: schema_version missing"
    task_classes = data["task_classes"]
    assert task_classes, f"{p}: task_classes empty"
    # forward: every task-class maps to a known tier
    for tc, tier in task_classes.items():
        assert tier in TIERS, f"{p}: task-class {tc} -> unknown tier {tier}"
    # reverse coverage: every tier has >=1 host alias; no alias outside the set
    covered = set()
    for host, aliases in data["host_aliases"].items():
        assert aliases, f"{p}: host {host} has no aliases"
        for tier, model in aliases.items():
            assert tier in TIERS, f"{p}: host {host} aliases unknown tier {tier}"
            assert model, f"{p}: host {host} tier {tier} empty model"
            covered.add(tier)
    assert covered == TIERS, f"{p}: tiers without a host alias: {sorted(TIERS - covered)}"
PY
python3 -m json.tool reference/fixtures/v3/legacy-migration/migration-manifest.json >/dev/null
test -s reference/fixtures/v3/standalone/.ai/observability/conventions.md
test -s reference/fixtures/v3/standalone/.ai/observability/audit-checklist.md
test -s reference/fixtures/v3/umbrella/.ai/observability/conventions.md
test -s reference/fixtures/v3/umbrella/.ai/observability/audit-checklist.md
python3 -m json.tool reference/fixtures/v3/standalone/.ai/mcp/registry.json >/dev/null
python3 -m json.tool reference/fixtures/v3/umbrella/.ai/mcp/registry.json >/dev/null
test -s reference/fixtures/v3/standalone/.ai/mcp/a2a-handoff.md
test -s reference/fixtures/v3/umbrella/.ai/mcp/a2a-handoff.md
python3 - <<'PY'
import json
for variant in ("standalone", "umbrella"):
    p = f"reference/fixtures/v3/{variant}/.ai/mcp/registry.json"
    data = json.load(open(p))
    assert data.get("schema_version"), f"{p}: schema_version missing"
    assert isinstance(data.get("servers"), list), f"{p}: servers array missing"
    a2a = data.get("a2a")
    assert isinstance(a2a, dict), f"{p}: a2a block missing"
    assert a2a.get("protocol"), f"{p}: a2a.protocol missing"
    assert a2a.get("handoff_convention"), f"{p}: a2a.handoff_convention missing"
    for s in data["servers"]:
        for key in ("name", "transport", "status", "tools"):
            assert key in s, f"{p}: server entry missing key {key}"
        assert s["status"] == "stub", f"{p}: server {s.get('name')} status must be 'stub'"
        assert isinstance(s["tools"], list), f"{p}: server {s.get('name')} tools not a list"
PY
```

## Expected interpretation

- `tests/test-skills.sh` is authoritative only after its frontmatter-aware body-line parser passes focused regression fixtures.
- Corrected line-count failures identify progressive-disclosure cleanup targets; do not hide them by weakening the validator.
- Golden verification compares scaffolded files and marker presence; `upstream.lock` SHA content is intentionally structure-checked, not byte-compared.
- v3 fixtures are reference outputs. They must parse as JSON, obey the matrix schema, demonstrate the depth rule, and prove workflow/traceability links have no dangling references.

## v3 structural checks

The validator runs the following v3 checks on the v3 fixtures and any candidate v3 repo:

1. **Traceability graph** — `.ai/traceability/graph.json`, `.ai/traceability/index.md`, and `.ai/traceability/validation-report.md` exist; graph node IDs are stable, every edge endpoint resolves, and backlinks have no dangling node IDs.
2. **Workflow surfaces** — `.ai/workflows/repo-workflow.md`, `.ai/workflows/repo-workflow.json`, `.ai/phases/<phase>/status.json`, and `.ai/handoff/init-ai-repo-handoff.md` exist; generated `AGENTS.md` and `README.md` link to both workflow files. `CLAUDE.md` and `GEMINI.md` are thin pointers to `AGENTS.md` and are not workflow-linking surfaces.
3. **Cascade contract** — `.ai/cascade/cascade-plan.json`, `.ai/cascade/audit.jsonl`, `.ai/cascade/reconciliation-report.md`, and `.ai/cascade/host-adapters/<host>.json` exist when multi-repo cascade is available; configured hosts are GitHub, Azure DevOps, GitLab, Jira, and Local Markdown; first hosted apply without confirmation is blocked; confirmed apply creates links once; subsequent update is idempotent and creates no duplicate child items.
4. **Skill catalog modernization** — `.ai/skills/catalog-audit.json`, `.ai/skills/description-exceptions.json`, and `.ai/skills/modernization-report.md` exist when the target repo owns skills; target descriptions are `<=180` characters, hard-fail budget is `>280` without audited exceptions, and first-class skills preserve progressive disclosure, trigger boundaries, cross-skill workflow links, and AI-SDLC compatibility.
5. **Final validation package** — `scripts/validate-final-package.py` and `tests/final-validation-gate_test.sh` bundle workflow, traceability, cascade, catalog, golden, CI-wiring, archgate, and no-secret/static checks for the final review gate.
6. **Top-level layout** — required entry files (`AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `CONTRIBUTING.md`, `README.md`) and required directories (`.ai/`, `.memory/`, `docs/architecture/`, `docs/specifications/ACTIVE/`, `docs/specifications/ARCHIVED/`, `docs/learning/`) are present for a standalone repo.
7. **Topology matrix** — `.ai/matrix.json` exists, parses as JSON, declares `schema_version: "1.0"`, has a valid `topology_type` (`standalone` or `umbrella`), and uses `sync_strategy: "physical-copy"`.
8. **Depth rule** — for `standalone` topology, `max_allowed_depth` and `current_depth` are exactly `0`; any other values fail or block before apply. For `umbrella` topology, `max_allowed_depth` is exactly `3`, `current_depth` is `<= max_allowed_depth`, and every managed repository depth is `<= max_allowed_depth`; any other maximum or exceeded depth fails or blocks before apply.
9. **Sync-strategy rule** — `sync_strategy` is `physical-copy`. The validator rejects `symlink` and `git-submodule` as canonical.
10. **Memory layer** — `.memory/human-override/` exists and is treated as terminal priority (validator never overwrites files there). `.memory/self-learned/` declares `schema_version` on every JSON file.
11. **Host-policy safety wording** — host-policy documentation contains the dry-run / confirmation / audit / negative-test language and the non-admin auto-approval prohibition. See `modules/host-policy-automation.md`.
12. **Migration audit** — when migrating from a legacy scaffold, `.ai/drift/migration-manifest.json` exists with the action vocabulary (`migrate`, `copy`, `deprecate`, `supersede`) and a confirmation token for every `migrate` action.
13. **Marker blocks** — `<!-- ai-sdlc-init:start -->` ... `<!-- ai-sdlc-init:end -->` markers are present in the entry files when the v3 marker format is in use.
14. **Eval coverage** — for every `.ai/evals/<set>/` directory, `evalset.json`, `rubric.md`, and `judge-config.json` exist; `evalset.json` parses and declares `schema_version`, `set_id`, and a non-empty `cases` array; `judge-config.json` parses and declares `schema_version` and a `judge` block; `rubric.md` is non-empty. The eval-coverage gate (`modules/evals.md`, ADR-0002) is offline and structural only; no LM-judge or network call runs in CI. A skill changed in the PR diff that declares an `eval:` key must reference a structurally valid evalset unless an audited exception is recorded in `.ai/evals/coverage-exceptions.json`.
15. **Model-routing policy** — `.ai/policies/model-routing.json` exists, parses as JSON, and declares `schema_version` (ADR-0003, `modules/documentation-blueprint.md`). Tiers are provider-neutral: `{frontier, mid, cheap}`. **Forward:** every entry in the `task_classes` map points to a tier in that set. **Reverse coverage:** the `host_aliases` table maps each host (e.g. `claude`, `codex`) to per-tier model names; every tier in `{frontier, mid, cheap}` has at least one alias entry, and no alias points to a tier outside that set. The check is offline-structural only; it never resolves a provider model ID over the network.
16. **Observability surface** — `.ai/observability/conventions.md` and `.ai/observability/audit-checklist.md` exist and are non-empty (ADR-0005, `modules/documentation-blueprint.md`). The conventions doc covers logging and trace conventions; the checklist carries the token-cost and trajectory-audit checklist items. `modules/ci-policy.md` and `modules/validation.md` carry the token-cost and trajectory-audit checklist keywords. The check is offline-structural only: observability here is generated conventions plus a checklist; token-cost and trajectory metering execute out-of-band, never as a model or network call in CI.
17. **MCP/A2A surface** — `.ai/mcp/registry.json` and `.ai/mcp/a2a-handoff.md` exist (ADR-0005, `modules/documentation-blueprint.md`, `modules/mcp-a2a.md`). `registry.json` parses as JSON and declares `schema_version`, a `servers` array whose entries each carry `name`, `transport`, `status`, and a `tools` array, and an `a2a` block with `protocol` and a `handoff_convention` pointer. Every server `status` is `"stub"` — the registry resolves no live endpoint. `a2a-handoff.md` is non-empty and carries the handoff-envelope and `correlation_id` keywords. The check is offline-structural only: the registry is a stub and the handoff doc is a convention; generation makes no model or network call. The discoverable runner is `tests/mcp_a2a_test.sh`.

## v3 fixture set

The v3 fixture set lives under `reference/fixtures/v3/`. Each fixture documents the expected v3 output for one scenario.

### Fixture A — standalone repo

`reference/fixtures/v3/standalone/.ai/matrix.json` declares `topology_type: "standalone"`, `max_allowed_depth: 0`, `current_depth: 0`, and `sync_strategy: "physical-copy"`. No `managed_repositories` are required. The fixture is a reference for the standalone tree under `.ai/`, `.memory/`, and `docs/`.

### Fixture B — umbrella repo

`reference/fixtures/v3/umbrella/.ai/matrix.json` declares `topology_type: "umbrella"`, `max_allowed_depth: 3`, and at least one entry in `managed_repositories` with a path and depth. The fixture demonstrates physical-copy inheritance, workflow docs/manifests, per-phase status files, traceability graph/index/report files, cascade plan/audit/reconciliation artifacts, and the audit log format under `.ai/drift/`.

### Fixture C — depth violation

`reference/fixtures/v3/depth-violation/.ai/matrix.json` declares `topology_type: "umbrella"`, `max_allowed_depth: 3`, and `current_depth: 4`. The validator must detect the violation and return a non-zero exit code. The error message names the offending repo path and the offending depth.

### Fixture D — legacy migration

`reference/fixtures/v3/legacy-migration/migration-manifest.json` documents the migration of a legacy scaffold to v3, including at least one `migrate` action with a `confirmation_token` and a `backup_path` under `.ai/drift/backups/<timestamp>/`. The fixture also includes a `migration-audit.jsonl` snippet that demonstrates the audit format.

## Host-policy negative tests

The v3 regression suite asserts:

- `apply-blocked-no-confirmation` is recorded when admin credentials are present without confirmation.
- `apply-rejected-non-admin` is recorded when the actor is not an admin and the host does not support a non-admin bypass.
- `apply-rejected-dry-run-mismatch` is recorded when the readback differs from the intended shape.
- `apply-rejected-gitlab-tier-restriction` is recorded when GitLab discovery reports a Free/Core tier for an intended Premium/Ultimate-only approval-rule mutation.

These negative tests are documented in `modules/host-policy-automation.md`; the live assertions are scoped to mocked host adapters in the regression suite.

## Static safety checks

The validator also runs a static check pass on the documentation modules:

- `modules/host-policy-automation.md` contains the keywords `dry-run`, `confirmation`, `audit`, `Negative test`, and `Non-admin auto-approval is disallowed`.
- `modules/sync.md` contains the keywords `physical-copy`, `max_allowed_depth`, and `current_depth`, and never mentions `symlink` or `git-submodule` as a canonical `mode` value.
- `modules/migration.md` contains the action vocabulary (`migrate`, `copy`, `deprecate`, `supersede`) and the manifest path `migration-manifest.json`.
- `modules/memory.md` declares `.memory/human-override/` as terminal priority and never lists it as inherited or syncable.
- `modules/topology.md` defines the matrix schema and the depth rule.
- `modules/language-packs.md` covers .NET Core / EF Core and legacy .NET / EF in the pack matrix.
- `modules/ci-policy.md` and this module (`modules/validation.md`) contain the observability checklist keywords `token-cost` and `trajectory-audit`, and the generated `.ai/observability/` tree (conventions + audit checklist) is named in check #16 above. Observability metering is out-of-band; CI verifies only the generated conventions and checklist, never a live model or network call.

A missing or weakened wording fails the static check pass; the validator never re-words the safety rules to satisfy a missing match.

## Regression commands

Run these commands from the repository root that contains `tests/`, `scripts/`,
and `reference/` for the installed AI-SDLC skill package. If validating from an
umbrella workspace, first `cd <target-repo>` once, then run the commands without
embedding the repository name in each command.

```sh
tests/test-skills.sh
tests/test-scripts.sh
tests/run-tests.sh
tests/final-validation-gate_test.sh
python3 scripts/validate-final-package.py
bash scripts/archgate.sh --mode structural --rules .rules.ts --format json
./scripts/verify-golden-dir.sh . reference/golden-root
./scripts/verify-golden-dir.sh . reference/golden-skills
```

## E2E acceptance

- A clean standalone fixture can be initialized and validated.
- A clean umbrella fixture can be initialized, sync inherited assets by physical copy, and detect drift.
- A legacy fixture can migrate with backups/audit logs.
- A depth-violation fixture blocks the apply path with a clear error.
- Invalid standalone or umbrella `max_allowed_depth` values are rejected before apply.
- Host-policy dry-run shows exact intended changes and required confirmations.
- Host-policy apply without explicit confirmation is rejected, including for admin credentials.
- All skills repo tests pass.
