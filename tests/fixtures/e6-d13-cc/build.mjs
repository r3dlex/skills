// Materializes one synthetic fixture case for the D13 comparison contract
// checker and prints its invocation plan as JSON on stdout.
//
//   node tests/fixtures/e6-d13-cc/build.mjs <case-id> <out-dir> --repo <root> --tool <checker>
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { buildConsumer } from "./lib/consumer.mjs";
import { findCase } from "./lib/cases.mjs";
import { applyMutations, renormalize } from "./lib/mutate.mjs";
import {
  GENERATION,
  GOAL,
  PLAN,
  buildRunModel,
  buildWorld,
  compact,
  materializeRun,
  pretty,
  recordObservation,
  reuseWorld,
  sha256,
} from "./lib/world.mjs";
import { existsSync } from "node:fs";

const RUN_DIRECTORY = "tests/fixtures/e6-v1-port/d13/synthetic-run-0001";
const MISSING_COMMIT = "0123456789abcdef0123456789abcdef01234567";

function option(argv, name) {
  const index = argv.indexOf(name);
  return index < 0 ? undefined : argv[index + 1];
}

function writeReceipts(root) {
  const entries = {};
  for (const name of ["collection", "custody", "completion"]) {
    const path = join(root, "receipts", `${name}.json`);
    const bytes = Buffer.from(pretty({ collected_by: "synthetic fixture", kind: name, schema: "d13-receipt/1" }), "utf8");
    mkdirSync(join(root, "receipts"), { recursive: true });
    writeFileSync(path, bytes);
    entries[name] = { path, sha256: sha256(bytes) };
  }
  return entries;
}

function runTool(cwd, toolPath, args) {
  const result = spawnSync(process.execPath, [toolPath, ...args], { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  return { exit: result.status ?? 1, stdout: result.stdout ?? "" };
}

function buildEvidence(repo, options, reportValue, reportText, toolSha) {
  const claim = {
    base_target: "main",
    branch: `feat/${PLAN}-${GOAL}`,
    collected_by: options.noIndependentReceipts === true ? "fixture-author" : "synthetic-independent-source",
    generation: options.wrongGeneration === true ? "a".repeat(64) : GENERATION,
    goal_id: GOAL,
    host_locator: "synthetic://local",
    merge_commit: options.unavailableHistory === true ? MISSING_COMMIT : repo.merge,
    observed_at: "2026-10-19T13:05:00Z",
    plan_id: PLAN,
    pr_head: repo.head,
    pr_number: 1,
    publication_commit: repo.publication,
    repository: "skills",
    source_locator: "synthetic://source",
    tool: { blob: repo.toolBlob, path: "scripts/lib/d13-compare.mjs", sha256: toolSha },
  };
  const contract = {
    capture_commit: options.oldCaptureHead === true ? repo.baseCommit : repo.head,
    completion_record: claim,
    goal_id: GOAL,
    generation: claim.generation,
    merge_commit: options.unrelatedMerge === true ? repo.baseCommit : options.unavailableHistory === true ? MISSING_COMMIT : repo.merge,
    plan_id: PLAN,
    publication_commit: repo.publication,
    receipts: writeReceipts(repo.root),
    report: reportValue,
    report_sha256: sha256(Buffer.from(reportText, "utf8")),
    run_directory: RUN_DIRECTORY,
    run_sha256: repo.runSha,
    spec_sha256: options.wrongSpecDigest === true ? sha256("synthetic wrong evidence spec digest") : repo.specSha,
    target_ref: "refs/remotes/origin/main",
    tool_path: "scripts/lib/d13-compare.mjs",
    tool_sha256: options.wrongToolSha === true ? sha256("synthetic wrong tool digest") : toolSha,
  };
  if (options.dropContract === true) {
    return { schema: "e6-evidence/2" };
  }
  return { d13_contract: contract, schema: "e6-evidence/2" };
}

function forgeReport(text) {
  const forged = JSON.parse(text);
  forged.counts.red = 0;
  forged.observed.git = true;
  forged.verdict = "pass";
  return forged;
}

function consumerCase(spec, outDir, repoRoot, rawToolPath, sharedWorld, result) {
  const toolPath = resolve(repoRoot, rawToolPath);
  const options = spec.consumer ?? {};
  const world = shared(spec, sharedWorld) ?? buildWorld(join(outDir, "world"), {});
  const model = buildRunModel(world, {});
  const mutations = [];
  if (options.redRun === true) {
    mutations.push("M01");
  }
  if (options.forgedReport === true) {
    mutations.push("O03");
  }
  model.observation = recordObservation(model, {});
  applyMutations(model, mutations);
  renormalize(model);
  const staged = materializeRun(model, join(outDir, "staged"));
  const toolBytes = readFileSync(toolPath);
  const repo = buildConsumer(join(outDir, "consumer"), {
    runBytes: readFileSync(join(staged, "raw-manifest.json")),
    runDirectory: RUN_DIRECTORY,
    runTree: join(outDir, "staged"),
    specBytes: readFileSync(join(repoRoot, "docs/specifications/ACTIVE/e6-d13-comparison-contract.md")),
    toolBytes,
    wrongSpecDigest: options.wrongSpecDigest === true,
  });
  repo.runSha = sha256(readFileSync(join(repo.root, RUN_DIRECTORY, "raw-manifest.json")));
  const observed = runTool(repo.root, toolPath, [RUN_DIRECTORY, "--observe"]);
  let reportValue = JSON.parse(observed.stdout);
  let reportText = observed.stdout;
  if (options.forgedReport === true) {
    reportValue = forgeReport(observed.stdout);
    reportText = compact(reportValue);
  }
  if (options.tamperedReport === true) {
    reportValue = JSON.parse(observed.stdout);
    reportValue.counts.sites = 1;
    reportText = observed.stdout;
  }
  const evidence = buildEvidence(repo, options, reportValue, reportText, sha256(toolBytes));
  if (options.rawDrift === true) {
    const stream = join(repo.root, RUN_DIRECTORY, "captures", "reference", "skills", PLAN, "export-evidence", "stdout");
    writeFileSync(stream, Buffer.concat([readFileSync(stream), Buffer.from("raw drift\n", "utf8")]));
  }
  const evidencePath = join(repo.root, ".ai", "evidence", "e6-sk-02-v1-port.json");
  mkdirSync(join(repo.root, ".ai", "evidence"), { recursive: true });
  writeFileSync(evidencePath, Buffer.from(pretty(evidence), "utf8"));
  if (options.presentFails === true) {
    const failing = JSON.parse(readFileSync(evidencePath, "utf8"));
    failing.d13_contract.report.counts.red = 1;
    failing.d13_contract.report.verdict = "red";
    const failingPath = join(outDir, "consumer-present-evidence.json");
    writeFileSync(failingPath, Buffer.from(pretty(failing), "utf8"));
    result.checks = [
      { cwd: repo.root, evidence: join(repo.root, ".ai", "evidence", "absent-consumer-evidence.json"), expect: { exit: 2, label: "absent" } },
      { cwd: repo.root, evidence: failingPath, expect: { exit: 1, label: "present" } },
    ];
  } else {
    result.checks = [{ cwd: repo.root, evidence: evidencePath, expect: spec.expect, label: "evidence" }];
  }
  result.repo = repo.root;
  result.kind = "consumer";
}

function shared(spec, sharedWorld) {
  if (spec.world !== undefined || sharedWorld === undefined || !existsSync(join(sharedWorld, "targets", "skills"))) {
    return undefined;
  }
  return reuseWorld(sharedWorld);
}

function main() {
  const argv = process.argv.slice(2);
  const caseId = argv[0];
  const outDir = argv[1];
  const repoRoot = option(argv, "--repo");
  const toolPath = option(argv, "--tool");
  const sharedWorld = option(argv, "--world");
  if (caseId === undefined || outDir === undefined) {
    throw new Error("usage: build.mjs <case-id> <out-dir> --repo <root> --tool <checker>");
  }
  mkdirSync(outDir, { recursive: true });
  if (caseId === "--init-world") {
    process.stdout.write(compact(buildWorld(outDir, {})));
    return;
  }
  if (repoRoot === undefined || toolPath === undefined) {
    throw new Error("usage: build.mjs <case-id> <out-dir> --repo <root> --tool <checker>");
  }
  const spec = findCase(caseId);
  const result = { case: caseId, expect: spec.expect, kind: spec.kind };
  if (spec.kind === "consumer") {
    consumerCase(spec, outDir, repoRoot, toolPath, sharedWorld, result);
  } else {
    const world = shared(spec, sharedWorld) ?? buildWorld(join(outDir, "world"), spec.world ?? {});
    const model = buildRunModel(world, spec.run ?? {});
    model.observation = recordObservation(model, spec.observation ?? {});
    applyMutations(model, spec.mutations ?? []);
    renormalize(model);
    result.argument = "run";
    result.run = materializeRun(model, join(outDir, "run"));
    result.world = outDir;
  }
  process.stdout.write(compact(result));
}

main();