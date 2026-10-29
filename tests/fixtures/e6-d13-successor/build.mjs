// Materializes synthetic test inputs; never real capture/host/custody evidence.
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, readFileSync, renameSync, rmSync } from "node:fs";
import { join, resolve } from "node:path";
import { buildConsumer, commit, git, EVIDENCE_PATH, retainReceipts, RUN_DIRECTORY, write } from "./lib/consumer.mjs";
import { mutateConsumer } from "./lib/consumer-mutate.mjs";
import { CASE_TABLE, findCase } from "./lib/cases.mjs";
import { applyMutations, renormalize } from "./lib/mutate.mjs";
import { GENERATION, GOAL, PLAN, POLICY_PATH, REGISTRY_PATH, buildRunModel, buildWorld, compact, materializeRun, pretty, recordObservation, reuseWorld, sha256 } from "./lib/world.mjs";

const MISSING_COMMIT = "0123456789abcdef0123456789abcdef01234567";
function option(argv, name) { return argv[argv.indexOf(name) + 1]; }

function runTool(cwd, toolPath, args) {
  const result = spawnSync(process.execPath, [toolPath, ...args], { cwd, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  if (!result.stdout) throw new Error(`checker produced no report: ${result.stderr}`);
  return { exit: result.status, stdout: result.stdout };
}

function buildEvidence(repo, options, report, reportText, toolSha) {
  const completion = {
    base_target: "main", branch: repo.branch, collected_by: options.noIndependentReceipts ? "fixture-author" : "synthetic-independent-source",
    generation: options.wrongGeneration ? "a".repeat(64) : GENERATION, goal_id: GOAL, host_locator: "synthetic://local", merge_commit: repo.merge, observed_at: "2026-10-19T13:05:00Z",
    plan_id: PLAN, pr_head: repo.prHead, pr_number: 1, publication_commit: repo.publication, repository: "skills", source_locator: "synthetic://source",
    tool: { blob: repo.toolBlob, path: "scripts/lib/d13-compare-successor.mjs", sha256: options.wrongToolSha ? sha256("wrong tool") : toolSha },
  };
  const contract = {
    capture_commit: options.oldCaptureHead ? repo.baseCommit : repo.capture, completion_record: completion,
    goal_id: GOAL, generation: options.wrongGeneration ? "a".repeat(64) : GENERATION,
    merge_commit: options.unrelatedMerge ? repo.baseCommit : options.unavailableHistory ? MISSING_COMMIT : repo.merge,
    plan_id: PLAN, publication_commit: repo.publication, report, report_sha256: sha256(reportText),
    run_directory: RUN_DIRECTORY, run_sha256: repo.runSha, spec_sha256: options.wrongSpecDigest ? sha256("wrong spec") : repo.specSha,
    target_ref: "refs/remotes/origin/main", tool_path: "scripts/lib/d13-compare-successor.mjs", tool_sha256: options.wrongToolSha ? sha256("wrong tool") : toolSha,
    tool_blob: repo.toolBlob, repository: "skills", host_locator: "synthetic://local", branch: repo.branch, base_target: "main", pr_number: 1, pr_head: repo.prHead,
  };
  return { d13_contract: contract, schema: "e6-evidence/2" };
}

function prepareConsumer(outDir, repoRoot, toolPath, options) {
  const world = buildWorld(join(outDir, "world"), {});
  const repo = buildConsumer(join(outDir, "consumer"), repoRoot, world, options);
  const model = buildRunModel(world, {});
  model.registries.skills = readFileSync(join(repo.root, REGISTRY_PATH));
  model.policies.skills = readFileSync(join(repo.root, POLICY_PATH));
  model.observation = recordObservation(model, {});
  applyMutations(model, options.redRun ? ["M01"] : options.forgedReport ? ["O03"] : []);
  renormalize(model);
  materializeRun(model, join(repo.root, RUN_DIRECTORY));
  repo.runSha = sha256(readFileSync(join(repo.root, RUN_DIRECTORY, "raw-manifest.json")));
  const observed = runTool(repo.root, toolPath, [RUN_DIRECTORY, "--observe"]);
  const report = JSON.parse(observed.stdout);
  if (options.forgedReport) { report.counts.red = 0; report.observed.git = true; report.verdict = "pass"; }
  const evidence = buildEvidence(repo, options, report, options.forgedReport ? compact(report) : observed.stdout, sha256(readFileSync(toolPath)));
  return { repo, evidence, world };
}

function consumerVariants(spec, result, repo, evidence, outDir) {
  const checks = [];
  const variants = spec.id === "C07" ? ["assertion", "site", "classification", "count", "omitted-assertion"] : spec.id === "C08" ? ["stdout-changed", "stdout-missing", "stdout-extra", "meta-changed", "meta-missing", "meta-extra", "snapshot-changed", "snapshot-missing", "snapshot-extra"] : [];
  for (const variant of variants) {
    const cwd = join(outDir, `variant-${variant}`);
    cpSync(repo.root, cwd, { recursive: true });
    const value = JSON.parse(JSON.stringify(evidence));
    if (spec.id === "C07") tamperReport(value.d13_contract.report, variant);
    else tamperRaw(cwd, variant);
    write(join(cwd, EVIDENCE_PATH), pretty(value));
    const expected = spec.id === "C07" ? spec.expect : { consumer: { failed_all: ["raw-inputs-bound"] }, exit: variant.endsWith("changed") ? 1 : 2 };
    checks.push({ label: variant, cwd, evidence: EVIDENCE_PATH, expect: expected });
  }
  result.checks = checks;
}

function tamperReport(report, variant) {
  if (variant === "assertion") report.assertions[0].ok = !report.assertions[0].ok;
  if (variant === "site") report.sites[0].id = "forged-site";
  if (variant === "classification") report.sites[0].classification = "red";
  if (variant === "count") report.counts.sites = 1;
  if (variant === "omitted-assertion") report.assertions.shift();
}

function tamperRaw(cwd, variant) {
  const [kind, change] = variant.split("-");
  const base = join(cwd, RUN_DIRECTORY, "captures/reference/skills", PLAN, "export-evidence");
  const file = kind === "stdout" ? join(base, "stdout") : kind === "meta" ? join(base, "meta.json") : join(base, "written-after/evidence/log.mdl");
  if (change === "changed") write(file, Buffer.concat([readFileSync(file), Buffer.from("raw drift\n")]));
  if (change === "missing") rmSync(file);
  if (change === "extra") write(`${file}.extra`, "extra raw input\n");
}

function finalizeConsumer(spec, outDir, repoRoot, toolPath, result) {
  const options = spec.consumer ?? {};
  const { repo, evidence, world } = prepareConsumer(outDir, repoRoot, toolPath, options);
  const contract = evidence.d13_contract;
  contract.receipts = retainReceipts(repo, contract.completion_record);
  mutateConsumer(repo, contract, options, outDir);
  // Mutations to declared completion identities have independently retained,
  // digest-bound bytes as well; mismatch tests must reach identity comparisons.
  if (!options.missingReceipts && !options.receiptDrift && !options.symlinkReceipt && !options.missingReceiptFile) contract.receipts = retainReceipts(repo, contract.completion_record);
  const value = options.dropContract ? { schema: "e6-evidence/2" } : evidence;
  if (options.presentFails) { contract.report.verdict = "red"; contract.report.counts.red = 1; }
  const evidencePath = options.oldEvidencePath ? ".ai/evidence/e6-sk-02-v1-port.json" : EVIDENCE_PATH;
  if (!options.missingEvidence) write(join(repo.root, evidencePath), pretty(value));
  if (!options.headBeforePublication && !options.symlinkRun) commit(repo.root, "synthetic evidence-only commit");
  result.checks = [{ label: "evidence", cwd: repo.root, evidence: evidencePath, expect: spec.expect }];
  if (spec.id === "C07" || spec.id === "C08") consumerVariants(spec, result, repo, evidence, outDir);
  if (options.relocate) {
    const relocated = join(outDir, "relocated"); cpSync(repo.root, relocated, { recursive: true });
    renameSync(world.world, `${world.world}.unavailable`); renameSync(repo.root, `${repo.root}.unavailable`);
    result.checks[0].cwd = relocated;
  }
  if (options.presentFails) {
    result.suite_checks = { present: repo.root, absent: join(outDir, "absent") };
    cpSync(repo.root, result.suite_checks.absent, { recursive: true });
    git(result.suite_checks.absent, ["checkout", "-q", "--detach", repo.merge]);
    result.checks.push({ label: "absent-cli", cwd: result.suite_checks.absent, evidence: EVIDENCE_PATH, expect: { exit: 2, consumer: { failed_all: ["input-shape"], consumer_readiness: "unready" } } });
  }
  if (options.headMoves || options.targetMoves) {
    const target = options.targetMoves;
    result.checks[0].env = movementEnvironment(outDir, repoRoot, repo.root, target ? "refs/remotes/origin/main" : "HEAD", repo.publication, target ? ["rev-parse", "--verify", "refs/remotes/origin/main^{commit}"] : ["rev-parse", "HEAD"]);
  }
  result.kind = "consumer";
}

function movementEnvironment(outDir, repoRoot, root, ref, to, trigger) {
  const bin = join(outDir, "git-wrapper"); mkdirSync(bin, { recursive: true });
  cpSync(join(repoRoot, "tests/fixtures/e6-d13-successor/git-move.cjs"), join(bin, "git")); chmodSync(join(bin, "git"), 0o755);
  const gitPath = spawnSync("which", ["git"], { encoding: "utf8" }).stdout.trim();
  return { PATH: `${bin}:${process.env.PATH}`, D13_SYNTHETIC_GIT_MOVE: JSON.stringify({ git: gitPath, root, ref, to, trigger, state: join(outDir, "movement.json") }) };
}

function main() {
  const argv = process.argv.slice(2);
  if (argv[0] === "--list") { process.stdout.write(CASE_TABLE.map((c) => c.id).join(" ")); return; }
  const [caseId, outDir] = argv;
  if (!caseId || !outDir) throw new Error("case and output directory required");
  mkdirSync(outDir, { recursive: true });
  if (caseId === "--init-world") { process.stdout.write(compact(buildWorld(outDir, {}))); return; }
  const repoRoot = option(argv, "--repo"); const toolPath = resolve(option(argv, "--tool")); const sharedWorld = option(argv, "--world");
  const spec = findCase(caseId); const result = { case: caseId, expect: spec.expect, kind: spec.kind };
  if (spec.kind === "consumer") finalizeConsumer(spec, outDir, repoRoot, toolPath, result);
  else {
    const world = !spec.world && sharedWorld && existsSync(join(sharedWorld, "targets/skills")) ? reuseWorld(sharedWorld) : buildWorld(join(outDir, "world"), spec.world ?? {});
    const model = buildRunModel(world, spec.run ?? {});
    model.observation = recordObservation(model, spec.observation ?? {});
    applyMutations(model, spec.mutations ?? []);
    if (caseId === "R10" || caseId === "R27") model.observation = recordObservation(model, {});
    if (caseId !== "R11") renormalize(model);
    result.run = materializeRun(model, join(outDir, "run"));
    if (caseId === "R21") result.env = movementEnvironment(outDir, repoRoot, world.targets.skills.root, world.targets.skills.ref, world.targets.skills.older, ["rev-parse", "--verify", `${world.targets.skills.ref}^{commit}`]);
  }
  process.stdout.write(compact(result));
}
main();
