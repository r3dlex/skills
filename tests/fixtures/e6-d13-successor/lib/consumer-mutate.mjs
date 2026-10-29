// Adversarial changes to disposable synthetic consumers only.
import { cpSync, readFileSync, renameSync, rmSync, symlinkSync } from "node:fs";
import { join } from "node:path";
import { commit, git, RUN_DIRECTORY, RECEIPT_DIRECTORY, write } from "./consumer.mjs";
import { GENERATION, PLAN, POLICY_PATH, REGISTRY_PATH, TOOL_PATH, compact, pretty, sha256 } from "./world.mjs";

function editJson(root, path, change) {
  const value = JSON.parse(readFileSync(join(root, path), "utf8"));
  change(value);
  write(join(root, path), pretty(value));
}

function alterRegistry(repo, change) {
  editJson(repo.root, REGISTRY_PATH, (value) => change(value.plans[0]));
  const head = commit(repo.root, "synthetic adversarial registration");
  git(repo.root, ["update-ref", "refs/remotes/origin/main", head]);
}

function nativeDigest(value) {
  return sha256(compact(value).trimEnd().replace(/[\u007f-\uffff]/g, (c) => `\\u${c.charCodeAt(0).toString(16).padStart(4, "0")}`));
}

function anotherValidGeneration(repo, contract) {
  const bundle = JSON.parse(readFileSync(join(repo.root, repo.bundleDir, "goals.json"), "utf8"));
  bundle.attachments = bundle.attachments ?? {};
  bundle.attachments.synthetic_alternative = "another internally valid registration, not this contract";
  const generation = nativeDigest({ schema: "generation/2", bundle_sha256: nativeDigest(bundle), spec_sha256: repo.specSha, policy_sha256: repo.entry.policy_sha256, anchor_sha256: repo.entry.anchor_sha256 });
  if (generation === GENERATION) throw new Error("alternative generation did not change");
  const prefix = `.ai/handoff/readiness-v2/${PLAN}/${generation}`;
  cpSync(join(repo.root, repo.bundleDir), join(repo.root, prefix), { recursive: true });
  write(join(repo.root, prefix, "goals.json"), pretty(bundle));
  const graphPath = join(repo.root, prefix, "graph.json");
  write(graphPath, readFileSync(graphPath, "utf8").replaceAll(GENERATION, generation));
  const handoffPath = join(repo.root, prefix, "handoff.md");
  write(handoffPath, readFileSync(handoffPath, "utf8").replaceAll(GENERATION, generation).replaceAll(GENERATION.slice(0, 12), generation.slice(0, 12)));
  alterRegistry(repo, (entry) => {
    entry.generation = generation;
    entry.handoff_path = `${prefix}/handoff.md`;
    for (const artifact of Object.values(entry.artifacts)) {
      artifact.path = artifact.path.replace(repo.bundleDir, prefix);
      if (artifact.sha256) artifact.sha256 = sha256(readFileSync(join(repo.root, artifact.path)));
    }
  });
  contract.generation = generation;
  contract.completion_record.generation = generation;
}

export function mutateConsumer(repo, contract, options, outDir) {
  const mutations = {
    headBeforePublication: () => git(repo.root, ["checkout", "-q", "--detach", repo.baseCommit]),
    headToolDrift: () => { write(join(repo.root, TOOL_PATH), "// synthetic changed committed checker\n"); commit(repo.root, "synthetic head checker drift"); },
    captureMismatch: () => { contract.capture_commit = repo.merge; },
    driverDrift: () => { write(join(repo.root, "04-validate-handoff/autobahn/contract-run.sh"), "# synthetic product drift\n"); commit(repo.root, "synthetic driver drift"); },
    corruptGraph: () => { write(join(repo.root, repo.bundleDir, "graph.json"), "{}\n"); const head = commit(repo.root, "synthetic corrupt graph"); git(repo.root, ["update-ref", "refs/remotes/origin/main", head]); },
    counterfeitSpec: () => { write(join(repo.root, repo.entry.spec.path), "counterfeit comparison spec\n"); contract.spec_sha256 = sha256("counterfeit comparison spec\n"); alterRegistry(repo, (entry) => { entry.spec.sha256 = contract.spec_sha256; }); },
    arbitraryGeneration: () => { contract.generation = "a".repeat(64); contract.completion_record.generation = contract.generation; alterRegistry(repo, (entry) => { entry.generation = contract.generation; }); },
    wrongRegistryId: () => alterRegistry(repo, (entry) => { entry.id = "wrong-registry-id"; }),
    wrongPolicy: () => alterRegistry(repo, (entry) => { entry.policy_sha256 = "0".repeat(64); }),
    missingArtifacts: () => alterRegistry(repo, (entry) => { entry.artifacts.graph.path += ".absent"; entry.artifacts.handoff.path += ".absent"; }),
    missingReceipts: () => { delete contract.receipts; },
    missingCompletionFields: () => { for (const key of ["repository", "host_locator", "source_locator", "collected_by", "observed_at", "branch", "pr_number", "base_target"]) delete contract.completion_record[key]; },
    wrongCompletion: () => { Object.assign(contract.completion_record, { repository: "other", branch: "feat/other", base_target: "other", pr_number: 999 }); },
    captureAsPrHead: () => { contract.completion_record.pr_head = repo.capture; },
    wrongPlan: () => { contract.plan_id = "other-plan"; contract.completion_record.plan_id = "other-plan"; },
    symlinkRun: () => {
      const outside = join(outDir, "outside-run"); cpSync(join(repo.root, RUN_DIRECTORY), outside, { recursive: true });
      rmSync(join(repo.root, "tests/fixtures/e6-v1-port-v2/d13"), { recursive: true });
      symlinkSync(outDir, join(repo.root, "tests/fixtures/e6-v1-port-v2/d13"));
      renameSync(outside, join(outDir, "synthetic-run-0001"));
    },
    outsideScopeRun: () => { cpSync(join(repo.root, RUN_DIRECTORY), join(repo.root, "escape/run"), { recursive: true }); contract.run_directory = "escape/run"; },
    oldRunPrefix: () => { contract.run_directory = "tests/fixtures/e6-v1-port/d13/synthetic-run-0001"; },
    symlinkReceipt: () => {
      const receipt = contract.receipts.custody.path; const outside = join(outDir, "outside-custody.json");
      renameSync(join(repo.root, receipt), outside); symlinkSync(outside, join(repo.root, receipt));
    },
    receiptDrift: () => write(join(repo.root, RECEIPT_DIRECTORY, "custody.json"), "changed receipt\n"),
    headRegistrationDrift: () => { editJson(repo.root, REGISTRY_PATH, (registry) => { registry.plans[0].generation = "b".repeat(64); }); commit(repo.root, "synthetic current HEAD registry drift"); },
    otherValidGeneration: () => anotherValidGeneration(repo, contract),
    missingSidecar: () => { rmSync(join(repo.root, repo.bundleDir, "sidecar.json")); const head = commit(repo.root, "synthetic missing sidecar"); git(repo.root, ["update-ref", "refs/remotes/origin/main", head]); },
    prePublicationCollection: () => { contract.completion_record.observed_at = "2026-01-01T00:00:00Z"; },
    wrongToolBlob: () => { contract.tool_blob = "f".repeat(40); contract.completion_record.tool.blob = contract.tool_blob; },
    missingToolBlob: () => { delete contract.tool_blob; },
    missingReceiptFile: () => { rmSync(join(repo.root, contract.receipts.custody.path)); },
  };
  for (const [name, mutate] of Object.entries(mutations)) if (options[name]) mutate();
}
