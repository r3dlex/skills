import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { repoRoot } from "./repo-root.mjs";
import { validateGraph } from "./traceability.mjs";

assertNodeVersion();

const TEXT_SUFFIXES = new Set([
  ".md", ".txt", ".toml", ".json", ".jsonl", ".yml", ".yaml", ".sh", ".py",
  ".ts", ".js", ".template", ".gitignore", ".lock", ".xml", ".csproj", ".sln",
]);
const EXCLUDED = new Set([".git", ".omx", ".omc", ".claude", "graphify-out", "node_modules", "__pycache__"]);
const SECRET_PATTERNS = [
  /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/,
  /\bsk-[A-Za-z0-9_-]{20,}\b/,
  /\bghp_[A-Za-z0-9]{20,}\b/,
  /\bgithub_pat_[A-Za-z0-9_]{20,}\b/,
  /\bxox[baprs]-[A-Za-z0-9-]{20,}\b/,
  /\bAKIA[0-9A-Z]{16}\b/,
];

function fail(message: string): never {
  throw new Error(message);
}

function readJson(path: string): Record<string, unknown> {
  return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
}

function assertFile(root: string, path: string): string {
  const full = join(root, path);
  if (!existsSync(full)) {
    fail(`missing required file: ${path}`);
  }
  return full;
}

function checkCiWiring(root: string): void {
  const runTests = readFileSync(assertFile(root, "tests/run-tests.sh"), "utf8");
  const testScripts = readFileSync(assertFile(root, "tests/test-scripts.sh"), "utf8");
  const ci = readFileSync(assertFile(root, ".github/workflows/ci.yml"), "utf8");
  const prek = readFileSync(assertFile(root, ".github/workflows/ci-prek.yml"), "utf8");
  if (!runTests.includes("test-scripts.sh") || !runTests.includes("test-skills.sh")) {
    fail("tests/run-tests.sh must include shell and skill suites");
  }
  if (!testScripts.includes("*_test.sh")) {
    fail("tests/test-scripts.sh must discover *_test.sh suites");
  }
  assertFile(root, "tests/skill-catalog_test.sh");
  assertFile(root, "tests/cascade-fixtures_test.sh");
  if (!ci.includes("tests/run-tests.sh")) {
    fail(".github/workflows/ci.yml must run tests/run-tests.sh");
  }
  if (!ci.includes('"codex/**"')) {
    fail(".github/workflows/ci.yml must run on codex/** stack branch pushes");
  }
  if (!prek.includes("--all-files")) {
    fail(".github/workflows/ci-prek.yml must run prek over all files");
  }
  if (!prek.includes('"codex/**"')) {
    fail(".github/workflows/ci-prek.yml must run on codex/** stack branch pushes");
  }
}

function checkRequired(root: string): void {
  for (const path of [
    "tests/final-validation-gate_test.sh",
    "tests/init-ai-repo_docs_test.sh",
    "tests/workflow-fixtures_test.sh",
    "tests/traceability-fixtures_test.sh",
    "tests/cascade-fixtures_test.sh",
    "tests/skill-catalog_test.sh",
    "tests/test-skills-validator_test.sh",
    "scripts/validate-final-package.py",
    "scripts/validate-cascade-fixtures.py",
    "scripts/validate-skill-catalog.py",
    "scripts/verify-golden-dir.sh",
    "scripts/archgate.sh",
  ]) {
    assertFile(root, path);
  }
}

function checkOptionalBranches(fixture: string, workflow: Record<string, unknown>): void {
  const branches = workflow.optional_branches;
  if (!Array.isArray(branches)) {
    return;
  }
  for (const branch of branches) {
    const record = branch as Record<string, unknown>;
    const id = record.id;
    if ((id === "multi-repo-cascade" || id === "skill-modernization") && record.status !== "available") {
      fail(`optional branch ${String(id)} must be available in ${fixture}`);
    }
  }
}

function checkGraph(root: string, fixture: string): void {
  for (const name of ["graph.json", "graph-1.1.json"]) {
    const graphPath = join(fixture, ".ai/traceability", name);
    if (!existsSync(graphPath)) {
      continue;
    }
    try {
      validateGraph(readJson(graphPath));
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      fail(`invalid traceability graph ${relative(root, graphPath)}: ${message}`);
    }
  }
}

function checkFixture(root: string, fixture: string): void {
  for (const path of [
    ".ai/matrix.json", ".ai/workflows/repo-workflow.json", ".ai/traceability/graph.json",
    ".ai/cascade/cascade-plan.json", ".ai/skills/catalog-audit.json",
    ".ai/skills/description-exceptions.json", ".ai/skills/body-line-exceptions.json",
  ]) {
    const full = join(fixture, path);
    if (!existsSync(full)) {
      fail(`missing fixture output: ${relative(root, fixture)}/${path}`);
    }
    readJson(full);
  }
  const workflow = readJson(join(fixture, ".ai/workflows/repo-workflow.json"));
  if (workflow.workflow_id !== "init-ai-repo") {
    fail(`invalid workflow id in ${fixture}`);
  }
  checkOptionalBranches(fixture, workflow);
  checkGraph(root, fixture);
  const catalog = readJson(join(fixture, ".ai/skills/catalog-audit.json"));
  if (catalog.status !== "pass" || catalog.skill_count !== 21) {
    fail(`catalog audit must pass with 21 skills in ${fixture}`);
  }
}

function checkRootCatalog(root: string): void {
  const catalog = readJson(assertFile(root, ".ai/skills/catalog-audit.json"));
  const exceptions = readJson(assertFile(root, ".ai/skills/description-exceptions.json"));
  const body = readJson(assertFile(root, ".ai/skills/body-line-exceptions.json"));
  const policy = catalog.policy as Record<string, unknown> | undefined;
  checkBudgets(catalog, policy, exceptions, body);
}

function checkBudgets(
  catalog: Record<string, unknown>,
  policy: Record<string, unknown> | undefined,
  exceptions: Record<string, unknown>,
  body: Record<string, unknown>,
): void {
  if (catalog.status !== "pass") {
    fail("root catalog audit must pass");
  }
  if (policy?.target_description_chars !== 160) {
    fail("catalog target description budget must be 160");
  }
  if (policy.max_description_chars !== 180) {
    fail("catalog maximum description budget must be 180");
  }
  if (policy.target_body_lines !== 100) {
    fail("catalog target body budget must be 100");
  }
  if (policy.max_body_lines_with_exception !== 180) {
    fail("catalog maximum body budget must be 180");
  }
  if (JSON.stringify(exceptions.exceptions) !== "[]") {
    fail("description exceptions must be empty unless explicitly reviewed");
  }
  if (JSON.stringify(body.exceptions) !== "[]") {
    fail("body-line exceptions must be empty unless explicitly reviewed");
  }
}

function suffixOf(name: string): string {
  const dot = name.lastIndexOf(".");
  return dot <= 0 ? "" : name.slice(dot);
}

function walk(root: string, dir: string, files: string[]): void {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!EXCLUDED.has(entry.name)) {
        walk(root, path, files);
      }
    } else if (TEXT_SUFFIXES.has(suffixOf(entry.name)) || ["AGENTS.md", "CLAUDE.md", "README.md", ".gitignore"].includes(entry.name)) {
      files.push(path);
    }
  }
}

function checkSecrets(root: string): void {
  const files: string[] = [];
  walk(root, root, files);
  const offenders: string[] = [];
  for (const path of files) {
    const text = readFileSync(path, "utf8");
    for (const pattern of SECRET_PATTERNS) {
      if (pattern.test(text)) {
        offenders.push(`${relative(root, path)} matches ${pattern.source}`);
      }
    }
  }
  if (offenders.length > 0) {
    fail(`potential secrets found:\n${offenders.join("\n")}`);
  }
}

export function main(root = repoRoot(import.meta.url)): number {
  try {
    checkCiWiring(root);
    checkRequired(root);
    checkFixture(root, join(root, "reference/fixtures/v3/standalone"));
    checkFixture(root, join(root, "reference/fixtures/v3/umbrella"));
    checkRootCatalog(root);
    checkSecrets(root);
    process.stdout.write("final validation package checks passed\n");
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`FAIL: ${message}\n`);
    return 1;
  }
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main());
}
