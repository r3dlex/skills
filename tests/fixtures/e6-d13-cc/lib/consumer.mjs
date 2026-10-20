// All objects are synthetic. The publication objects are exact copies of the
// reviewed immutable inputs; no copied approval or hosted completion is asserted.
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { GENERATION, GOAL, PLAN, POLICY_PATH, REGISTRY_PATH, TOOL_PATH, pretty, sha256 } from "./world.mjs";

export const DRIVER_DIRS = ["04-validate-handoff/autobahn", "02-govern-plan/northstar", "scripts/lib"];
export const EVIDENCE_PATH = ".ai/evidence/e6-sk-02-v1-port.json";
export const RUN_DIRECTORY = "tests/fixtures/e6-v1-port/d13/synthetic-run-0001";
export const RECEIPT_DIRECTORY = "tests/fixtures/e6-v1-port/d13-receipts/synthetic-run-0001";
const ENV = { ...process.env, GIT_AUTHOR_DATE: "2026-10-19T13:00:00Z", GIT_AUTHOR_EMAIL: "fixture@example.com", GIT_AUTHOR_NAME: "fixture", GIT_COMMITTER_DATE: "2026-10-19T13:00:00Z", GIT_COMMITTER_EMAIL: "fixture@example.com", GIT_COMMITTER_NAME: "fixture" };

export function write(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}

export function git(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "buffer", env: ENV });
  if (result.status !== 0) throw new Error(`synthetic git ${args.join(" ")} failed: ${String(result.stderr)}`);
  return result.stdout.toString("utf8").trim();
}

export function commit(root, message) {
  git(root, ["add", "-A"]);
  git(root, ["commit", "-q", "--allow-empty", "-m", message]);
  return git(root, ["rev-parse", "HEAD"]);
}

function publishInputs(root, source, options) {
  const registry = JSON.parse(readFileSync(join(source, REGISTRY_PATH), "utf8"));
  const entry = registry.plans.find((p) => p.plan_id === PLAN);
  if (options.wrongSpecDigest) entry.spec.sha256 = sha256("wrong spec");
  const bundleDir = `.ai/handoff/readiness-v2/${PLAN}/${GENERATION}`;
  cpSync(join(source, bundleDir), join(root, bundleDir), { recursive: true });
  cpSync(join(source, POLICY_PATH), join(root, POLICY_PATH));
  write(join(root, entry.spec.path), readFileSync(join(source, entry.spec.path)));
  // Keep the two-site-plan run inventory while retaining the *exact* comparison
  // registration; other targets still use the ordinary observation fixtures.
  write(join(root, REGISTRY_PATH), pretty({ schema: "readiness-contract/2", plans: [entry, { plan_id: "e6-skills-ts-02", generation: "b287e55570671799d43ddf09a2af8c2247a5b7a5e8e6c859e91ed3f0431ed015", status: "active" }] }));
  return { entry, bundleDir };
}

function supplierMerge(root, source, branch, options) {
  git(root, ["checkout", "-q", "-b", branch]);
  for (const path of DRIVER_DIRS) cpSync(join(source, path), join(root, path), { recursive: true });
  for (const path of ["tests/e6_d13_comparison_test.sh", "tests/fixtures/e6-d13-cc"]) cpSync(join(source, path), join(root, path), { recursive: true });
  const prHead = commit(root, "synthetic supplier PR head (not capture)");
  git(root, ["checkout", "-q", "main"]);
  write(join(root, "MAIN-NOTE.md"), "synthetic main-side merge parent\n");
  commit(root, "synthetic main-side change");
  // A real two-parent merge whose *message* repeats its second parent: message
  // text is not Git ancestry, so the recorded merge stays exactly this merge.
  const text = options.parentLineInMergeMessage ? `synthetic supplier goal merge\n\nparent ${prHead}\n` : "synthetic supplier goal merge";
  git(root, ["merge", "-q", "--no-ff", branch, "-m", text]);
  const merge = git(root, ["rev-parse", "HEAD"]);
  // An ordinary one-parent commit whose message claims the supplier PR head as
  // a second parent: only actual parentage may satisfy a merge binding.
  if (!options.forgedMessageParent) return { prHead, merge };
  return { prHead, merge: commit(root, `synthetic non-merge\n\nparent ${prHead}\n`), realMerge: merge };
}

// One connected history: exact publication -> distinct supplier PR/merge ->
// candidate capture -> later evidence-only consumer HEAD. Reference and candidate
// really are separate clones, and capture is the candidate's actual Git HEAD.
export function buildConsumer(root, source, world, options = {}) {
  const reference = world.targets.skills.root;
  const baseCommit = git(reference, ["rev-parse", "HEAD"]);
  const published = publishInputs(reference, source, options);
  const publication = commit(reference, "synthetic exact contract publication");
  const branch = `feat/${PLAN}-${GOAL}`;
  const merged = supplierMerge(reference, source, branch, options);
  git(reference, ["update-ref", "refs/remotes/origin/main", merged.merge]);
  // Local upload-pack transport avoids racing loose-object copies on ARM64.
  git(source, ["clone", "-q", "--no-local", reference, root]);
  git(root, ["update-ref", "refs/remotes/origin/main", merged.merge]);
  write(join(root, "CAPTURE-NOTE.md"), "synthetic candidate capture\n");
  const capture = commit(root, "synthetic candidate capture head");
  world.targets.skills.revision = merged.merge;
  world.targets.skills.older = publication;
  world.lanes.reference.driver_commit = merged.merge;
  world.lanes.candidate = { driver_root: root, common_dir: git(root, ["rev-parse", "--path-format=absolute", "--git-common-dir"]), driver_commit: capture };
  return { ...published, ...merged, baseCommit, branch, capture, root, publication, specSha: sha256(readFileSync(join(source, published.entry.spec.path))), toolBlob: git(root, ["rev-parse", `${merged.merge}:${TOOL_PATH}`]) };
}

export function retainReceipts(repo, completion) {
  const receipts = {};
  for (const name of ["collection", "custody", "completion"]) {
    const path = `${RECEIPT_DIRECTORY}/${name}.json`;
    const bytes = Buffer.from(pretty(name === "completion" ? completion : { schema: "d13-receipt/1", kind: name, collected_by: "synthetic fixture only" }));
    write(join(repo.root, path), bytes);
    receipts[name] = { path, sha256: sha256(bytes) };
  }
  return receipts;
}
