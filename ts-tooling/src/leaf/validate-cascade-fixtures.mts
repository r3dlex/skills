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

function fail(message: string): never {
  throw new Error(message);
}

function pythonShowsCarets(): boolean {
  const probed = spawnSync("python3", ["-c", "import sys; print(0 if sys.version_info >= (3, 11) else 1)"], {
    encoding: "utf8",
  });
  return probed.stdout.trim() === "0";
}

function schemaTraceback(root: string): string {
  const script = realpathSync(join(root, "scripts/validate-cascade-fixtures.py"));
  const carets = pythonShowsCarets();
  const lines = [
    "Traceback (most recent call last):",
    `  File "${script}", line 163, in <module>`,
    "    sys.exit(main())",
  ];
  if (carets) {
    lines.push("             ^^^^^^");
  }
  lines.push(
    `  File "${script}", line 148, in main`,
    "    validate_fixture(fixture, repo_id)",
    `  File "${script}", line 56, in validate_fixture`,
    "    assert plan[\"schema_version\"] == \"1.0\"",
  );
  if (carets) {
    lines.push("           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^");
  }
  lines.push("AssertionError");
  return lines.join("\n");
}

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

function noSecrets(path: string): void {
  const text = readFileSync(path, "utf8").toLowerCase();
  for (const needle of ["api_token", "access_token", "refresh_token", "authorization:", "bearer ", "password"]) {
    if (text.includes(needle)) {
      fail(`secret-like token '${needle}' found in ${path}`);
    }
  }
}

function checkAdapter(adapter: Record<string, unknown>, host: string, standalone: boolean): void {
  const dry = adapter.dry_run as Record<string, unknown>;
  const second = adapter.second_run as Record<string, unknown>;
  const readback = adapter.readback as Record<string, unknown>;
  const safety = adapter.safety as Record<string, unknown>;
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

function validateFixture(root: string, name: string, repoId: string): void {
  const fixture = join(root, "reference/fixtures/v3", name);
  const plan = readJson(join(fixture, ".ai/cascade/cascade-plan.json"));
  if (plan.schema_version !== "1.0") {
    fail(schemaTraceback(root));
  }
  if (plan.root_repo_id !== repoId) {
    fail(`invalid cascade plan for ${name}`);
  }
  const matrix = readJson(join(fixture, ".ai/matrix.json"));
  const standalone = matrix.topology_type === "standalone";
  for (const host of HOSTS) {
    const path = join(fixture, ".ai/cascade/host-adapters", `${host}.json`);
    if (!existsSync(path)) {
      fail(`missing ${path}`);
    }
    noSecrets(path);
    const adapter = readJson(path);
    if (adapter.host !== host || !Array.isArray(adapter.operations) || new Set(adapter.operations as string[]).size !== OPERATIONS.size) {
      fail(`invalid adapter ${host}`);
    }
    checkAdapter(adapter, host, standalone);
    if (adapter.hosted === true && !TOKEN.test(String((adapter.safety as Record<string, unknown>).confirmation_token))) {
      fail(`invalid confirmation token for ${host}`);
    }
  }
}

export function main(root = repoRoot(import.meta.url)): number {
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
  } catch (error) {
    process.stderr.write(`${error instanceof Error ? error.message : "cascade validation failed"}\n`);
    return 1;
  }
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main());
}
