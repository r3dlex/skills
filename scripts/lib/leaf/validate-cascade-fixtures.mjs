import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
const HOSTS = ["github", "ado", "gitlab", "jira", "local-markdown"];
const OPERATIONS = new Set([
    "discover_scope", "plan_parent_item", "plan_child_item", "dry_run", "confirm_first_run",
    "apply_confirmed_plan", "readback_links", "apply_idempotent_update", "audit_event", "reconcile",
]);
const TOKEN = /^ct-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{3}$/;
function fail(message) {
    throw new Error(message);
}
// CPython renders PEP 657 traceback anchors in three bands: none below 3.11,
// "^" only on 3.11-3.12, and from 3.13 the surrounding expression is marked
// with "~" while only the failing part keeps "^", plus an anchor row on every
// intermediate frame. Probe the band instead of assuming the newest rendering.
// A probe that cannot run falls back to band 0, the pre-3.11 rendering this
// port emitted before the probe existed.
function tracebackAnchorBand() {
    const probed = spawnSync("python3", ["-c", "import sys; print(0 if sys.version_info < (3, 11) else 1 if sys.version_info < (3, 13) else 2)"], {
        encoding: "utf8",
    });
    return probed.status === 0 ? probed.stdout.trim() : "0";
}
// The <module> frame anchors the `main()` call inside `sys.exit(main())`:
// 3.11-3.12 underline the whole call with "^", 3.13 marks the callee under "~"
// and the call parentheses that raise under "^".
function moduleFrameAnchor(band) {
    if (band === "1") {
        return "             ^^^^^^";
    }
    return band === "2" ? "             ~~~~^^" : null;
}
// From 3.13 every intermediate frame gains its own anchor row, marking the
// callee under "~" and the argument list under "^".
function intermediateFrameAnchor(band) {
    return band === "2" ? "    ~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^" : null;
}
// The failing expression keeps "^" on every band. A call expression is the
// exception: from 3.13 the callee is marked with "~" and only the argument list
// keeps "^". Measured on 3.13.5 and 3.14.8 for audit_path.is_file() and
// report_path.is_file(); every other assert in this file is not a call.
const TILDE_ANCHORS = new Map([
    ["           ^^^^^^^^^^^^^^^^^^^^", "           ~~~~~~~~~~~~~~~~~~^^"],
    ["           ^^^^^^^^^^^^^^^^^^^^^", "           ~~~~~~~~~~~~~~~~~~~^^"],
]);
function assertionAnchor(band, carets) {
    return band === "2" && TILDE_ANCHORS.has(carets) ? TILDE_ANCHORS.get(carets) : carets;
}
const INTERMEDIATE_SOURCE = "validate_fixture(fixture, repo_id)";
function safetyTraceback(root) {
    const band = tracebackAnchorBand();
    return safetyFieldTraceback(root, 63, "assert plan[\"safety\"][\"no_first_run_apply_without_confirmation\"] is True", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^", band);
}
function firstRunUnconfirmed(plan) {
    return safetyFieldUntrue(plan, "no_first_run_apply_without_confirmation");
}
function safetyFieldUntrue(plan, field) {
    const safety = plan.safety;
    if (safety === null || typeof safety !== "object") {
        return false;
    }
    const record = safety;
    if (!Object.prototype.hasOwnProperty.call(record, field)) {
        return false;
    }
    return record[field] !== true;
}
function safetyFieldTraceback(root, line, assertion, carets, band = tracebackAnchorBand()) {
    const script = realpathSync(join(root, "scripts/validate-cascade-fixtures.py"));
    const module = moduleFrameAnchor(band);
    const intermediate = intermediateFrameAnchor(band);
    const lines = [
        "Traceback (most recent call last):",
        `  File "${script}", line 163, in <module>`,
        "    sys.exit(main())",
    ];
    if (module !== null) {
        lines.push(module);
    }
    lines.push(`  File "${script}", line 148, in main`, `    ${INTERMEDIATE_SOURCE}`);
    if (intermediate !== null) {
        lines.push(intermediate);
    }
    lines.push(`  File "${script}", line ${line}, in validate_fixture`, `    ${assertion}`);
    if (band !== "0") {
        lines.push(assertionAnchor(band, carets));
    }
    lines.push("AssertionError");
    return lines.join("\n");
}
function schemaTraceback(root) {
    return safetyFieldTraceback(root, 56, "assert plan[\"schema_version\"] == \"1.0\"", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^");
}
function readJson(path) {
    return JSON.parse(readFileSync(path, "utf8"));
}
function noSecrets(path) {
    const text = readFileSync(path, "utf8").toLowerCase();
    for (const needle of ["api_token", "access_token", "refresh_token", "authorization:", "bearer ", "password"]) {
        if (text.includes(needle)) {
            fail(`secret-like token '${needle}' found in ${path}`);
        }
    }
}
function checkAdapter(adapter, host, standalone) {
    const dry = adapter.dry_run;
    const second = adapter.second_run;
    const readback = adapter.readback;
    const safety = adapter.safety;
    const expected = standalone ? "no-op-standalone" : "planned";
    if (dry.status !== expected) {
        fail(`adapter dry_run mismatch for ${host}`);
    }
    if (second.duplicates_created !== 0 || readback.status !== "match") {
        fail(`adapter safety mismatch for ${host}`);
    }
    if (safety.credentials_stored !== false || safety.host_policy_mutation !== false) {
        fail(`adapter policy mismatch for ${host}`);
    }
}
function assertionTraceback(root, line, assertion, carets, detail = "") {
    const body = safetyFieldTraceback(root, line, assertion, carets);
    return detail === "" ? body : `${body}: ${detail}`;
}
function refuseMissingFile(root, name, file, line, assertion, carets) {
    const relative = join("reference/fixtures/v3", name, ".ai/cascade", file);
    if (existsSync(join(root, relative))) {
        return;
    }
    const shown = join(realpathSync(root), relative);
    fail(assertionTraceback(root, line, assertion, carets, `missing ${shown}`));
}
function refuseMissingAudit(root, name) {
    refuseMissingFile(root, name, "audit.jsonl", 52, "assert audit_path.is_file(), f\"missing {audit_path}\"", "           ^^^^^^^^^^^^^^^^^^^^");
}
function refuseMissingReport(root, name) {
    refuseMissingFile(root, name, "reconciliation-report.md", 53, "assert report_path.is_file(), f\"missing {report_path}\"", "           ^^^^^^^^^^^^^^^^^^^^^");
}
function refuseInvalidPlan(root, name, repoId, plan) {
    if (plan.schema_version !== "1.0") {
        fail(schemaTraceback(root));
    }
    if (plan.root_repo_id !== repoId) {
        fail(`invalid cascade plan for ${name}`);
    }
    refuseWrongCascadeId(root, repoId, plan);
    refuseWrongMatrixPath(root, plan);
    if (Object.prototype.hasOwnProperty.call(plan, "first_run_confirmation_required")
        && plan.first_run_confirmation_required !== true) {
        fail(safetyFieldTraceback(root, 61, "assert plan[\"first_run_confirmation_required\"] is True", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
    }
    if (Object.prototype.hasOwnProperty.call(plan, "confirmation_token_pattern")
        && plan.confirmation_token_pattern !== TOKEN.source) {
        fail(safetyFieldTraceback(root, 62, "assert TOKEN_RE.pattern == plan[\"confirmation_token_pattern\"]", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
    }
    if (firstRunUnconfirmed(plan)) {
        fail(safetyTraceback(root));
    }
    if (safetyFieldUntrue(plan, "no_duplicate_child_items")) {
        fail(safetyFieldTraceback(root, 64, "assert plan[\"safety\"][\"no_duplicate_child_items\"] is True", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
    }
    if (safetyFieldUntrue(plan, "no_secret_material")) {
        fail(safetyFieldTraceback(root, 65, "assert plan[\"safety\"][\"no_secret_material\"] is True", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
    }
}
function emptyChildItems(value) {
    return Array.isArray(value) && value.length === 0;
}
function refuseWrongCascadeId(root, repoId, plan) {
    if (plan.cascade_id === `cascade:${repoId}:init-ai-repo`) {
        return;
    }
    fail(safetyFieldTraceback(root, 58, "assert plan[\"cascade_id\"] == f\"cascade:{repo_id}:init-ai-repo\"", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
}
function refuseEmptyAudit(root, name) {
    const path = join(root, "reference/fixtures/v3", name, ".ai/cascade/audit.jsonl");
    const statuses = new Set();
    for (const line of readFileSync(path, "utf8").split("\n")) {
        if (line.trim() === "") {
            continue;
        }
        const event = JSON.parse(line);
        if (typeof event.status === "string") {
            statuses.add(event.status);
        }
    }
    if (!statuses.has("apply-blocked-no-confirmation")) {
        fail(safetyFieldTraceback(root, 82, "assert \"apply-blocked-no-confirmation\" in statuses", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
    }
    if (!statuses.has("match")) {
        fail(safetyFieldTraceback(root, 89, "assert \"match\" in statuses", "           ^^^^^^^^^^^^^^^^^^^"));
    }
}
function refuseWrongMatrixPath(root, plan) {
    if (plan.matrix_path === ".ai/matrix.json") {
        return;
    }
    fail(safetyFieldTraceback(root, 59, "assert plan[\"matrix_path\"] == \".ai/matrix.json\"", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
}
const REPORT_REQUIRED = [
    "status: `pass`",
    "first_run_without_confirmation: `blocked`",
    "idempotent_update: `pass`",
    "duplicates_created: `0`",
    "missing_links: `0`",
    "readback_status: `match`",
];
function refuseSparseReport(root, name) {
    const relative = join("reference/fixtures/v3", name, ".ai/cascade", "reconciliation-report.md");
    const report = readFileSync(join(root, relative), "utf8");
    const missing = REPORT_REQUIRED.find((required) => !report.includes(required));
    if (missing === undefined) {
        return;
    }
    const shown = join(realpathSync(root), relative);
    fail(assertionTraceback(root, 97, "assert required in report, f\"missing {required} in {report_path}\"", "           ^^^^^^^^^^^^^^^^^^", `missing ${missing} in ${shown}`));
}
function refuseStandaloneApply(root, adapter, standalone) {
    if (!standalone) {
        return;
    }
    const apply = adapter.apply;
    if (apply.status === "not-required") {
        return;
    }
    fail(safetyFieldTraceback(root, 118, "assert adapter[\"apply\"][\"status\"] == \"not-required\"", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
}
function knownOperations(operations) {
    return Array.isArray(operations) && operations.every((operation) => typeof operation === "string" && OPERATIONS.has(operation));
}
function refuseNonemptyChildren(root, plan, standalone) {
    if (!standalone || !Object.prototype.hasOwnProperty.call(plan, "child_items") || emptyChildItems(plan.child_items)) {
        return;
    }
    fail(safetyFieldTraceback(root, 76, "assert plan[\"child_items\"] == []", "           ^^^^^^^^^^^^^^^^^^^^^^^^^"));
}
function validateFixture(root, name, repoId) {
    const fixture = join(root, "reference/fixtures/v3", name);
    refuseMissingAudit(root, name);
    refuseMissingReport(root, name);
    const plan = readJson(join(fixture, ".ai/cascade/cascade-plan.json"));
    refuseInvalidPlan(root, name, repoId, plan);
    const matrix = readJson(join(fixture, ".ai/matrix.json"));
    const standalone = matrix.topology_type === "standalone";
    refuseNonemptyChildren(root, plan, standalone);
    refuseEmptyAudit(root, name);
    refuseSparseReport(root, name);
    for (const host of HOSTS) {
        const path = join(fixture, ".ai/cascade/host-adapters", `${host}.json`);
        if (!existsSync(path)) {
            fail(`missing ${path}`);
        }
        noSecrets(path);
        const adapter = readJson(path);
        if (adapter.host !== host || !Array.isArray(adapter.operations) || new Set(adapter.operations).size !== OPERATIONS.size) {
            fail(`invalid adapter ${host}`);
        }
        if (!knownOperations(adapter.operations)) {
            fail(safetyFieldTraceback(root, 112, "assert set(adapter[\"operations\"]) == OPERATIONS", "           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^"));
        }
        refuseStandaloneApply(root, adapter, standalone);
        checkAdapter(adapter, host, standalone);
        if (adapter.hosted === true && !TOKEN.test(String(adapter.safety.confirmation_token))) {
            fail(`invalid confirmation token for ${host}`);
        }
    }
}
export function main(root = repoRoot(import.meta.url)) {
    try {
        validateFixture(root, "standalone", "standalone-root");
        validateFixture(root, "umbrella", "umbrella-root");
        const module = readFileSync(join(root, "03-configure-generate/ai-catapult-init/modules/cascade.md"), "utf8");
        for (const host of ["GitHub", "Azure DevOps", "GitLab", "Jira", "Local Markdown", "setup-skills", "host-policy-automation.md"]) {
            if (!module.includes(host)) {
                fail(`cascade module missing ${host}`);
            }
        }
        process.stdout.write("cascade fixture validation passed\n");
        return 0;
    }
    catch (error) {
        process.stderr.write(`${error instanceof Error ? error.message : "cascade validation failed"}\n`);
        return 1;
    }
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main());
}
//# sourceMappingURL=validate-cascade-fixtures.mjs.map