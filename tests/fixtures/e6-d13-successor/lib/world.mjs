// Synthetic fixture builder for the D13 comparison contract checker.
// Every artifact produced here is synthetic test data. Nothing in this module
// authenticates a real capture, custody receipt, hosted completion or remote.
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { CASE_TABLE, findCase } from "./cases.mjs";

const PLAN = "e6-d13-supplier-v2";
const GOAL = "e6-d13-su-02";
const GENERATION = "e7f526fbf9424f93f2a28cbf1a6e958c9d488b10327ea0b814cbfb36b2764d8c";
const SPEC_SHA256 = "2457a7105943ed92e8293b6c6c35dccc6a09cae169fefb640ce8b689a2a4fe1b";
const POLICY_PATH = ".ai/policies/readiness-policy.json";
const REGISTRY_PATH = ".ai/workflows/northstar-readiness-v2.json";
const TOOL_PATH = "scripts/lib/d13-compare-successor.mjs";
const PLANS = [PLAN, "e6-skills-ts-02"];
const REPOS = ["skills", "aitool-root", "ai-catapult", "ai-factory"];
const OPERATIONS = ["audit-merges", "export-evidence"];
const LANES = ["reference", "candidate"];
const REFUSAL_CODES = { "ai-catapult": "evidence_conflict", "ai-factory": "evidence_incomplete" };
const LOG_SHA = "b1c2d3e4f5a60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90";
const T0 = Date.UTC(2026, 9, 19, 12, 0, 0);
const GIT_ENV = {
  ...process.env,
  GIT_AUTHOR_DATE: "2026-10-19T12:00:00Z",
  GIT_AUTHOR_EMAIL: "fixture@example.com",
  GIT_AUTHOR_NAME: "fixture",
  GIT_COMMITTER_DATE: "2026-10-19T12:00:00Z",
  GIT_COMMITTER_EMAIL: "fixture@example.com",
  GIT_COMMITTER_NAME: "fixture",
};

export function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function sortKeys(value) {
  if (Array.isArray(value)) {
    return value.map(sortKeys);
  }
  if (value !== null && typeof value === "object") {
    const out = {};
    for (const key of Object.keys(value).sort()) {
      out[key] = sortKeys(value[key]);
    }
    return out;
  }
  return value;
}

export function compact(value) {
  return `${JSON.stringify(sortKeys(value))}\n`;
}

export function pretty(value) {
  return `${JSON.stringify(sortKeys(value), null, 2)}\n`;
}

function write(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}

function git(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "buffer", env: GIT_ENV });
  return {
    status: result.status ?? 1,
    stdout: Buffer.isBuffer(result.stdout) ? result.stdout : Buffer.alloc(0),
    stderr: Buffer.isBuffer(result.stderr) ? result.stderr : Buffer.alloc(0),
  };
}

function gitOk(cwd, args) {
  const result = git(cwd, args);
  if (result.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed: ${result.stderr.toString()}`);
  }
  return result.stdout.toString("utf8").trim();
}

export function registryBytesWithPlans(repository, planCount) {
  const plans = [...PLANS];
  while (plans.length < planCount) {
    plans.push(`synthetic-extra-plan-${plans.length}`);
  }
  return Buffer.from(
    pretty({
      plans: plans.slice(0, planCount).map((plan) => ({
        generation: plan === PLAN ? GENERATION : "b287e55570671799d43ddf09a2af8c2247a5b7a5e8e6c859e91ed3f0431ed015",
        id: `northstar-plan-${plan}`,
        mode: "live",
        plan_id: plan,
        policy_sha256: "d48f7f6709af2dce406433d0f2611d97b56c85b5c5db7eaf2fbc9f7502e75962",
        repository,
        schema: "readiness-contract/2",
        status: "active",
      })),
      schema: "readiness/registry/1",
    }),
    "utf8",
  );
}

function policyBytes(repository) {
  return Buffer.from(pretty({ repository: { id: repository }, schema: "readiness-policy/2" }), "utf8");
}

function commitTree(root) {
  git(root, ["add", "-A"]);
  gitOk(root, ["commit", "-q", "-m", "fixture"]);
}

// Builds one target repository: an older commit holding fewer registry plans
// followed by the resolved main commit holding the full registry.
function buildTarget(root, repository, planCount, policyRepository) {
  mkdirSync(root, { recursive: true });
  gitOk(root, ["init", "-q", "-b", "main", "."]);
  write(join(root, POLICY_PATH), policyBytes(policyRepository ?? repository));
  write(join(root, REGISTRY_PATH), registryBytesWithPlans(repository, Math.max(1, planCount - 1)));
  commitTree(root);
  write(join(root, REGISTRY_PATH), registryBytesWithPlans(repository, planCount));
  commitTree(root);
  return gitOk(root, ["rev-parse", "HEAD"]);
}

// The checker never contacts a remote, so the synthetic world only needs the
// local remote-tracking ref and a remote name. Creating the bare origin with
// `git init --bare` and setting the ref directly avoids any object copying.
function addOriginRemote(root) {
  const origin = `${root}.origin.git`;
  gitOk(root, ["init", "-q", "--bare", origin]);
  gitOk(root, ["remote", "add", "origin", origin]);
  gitOk(root, ["update-ref", "refs/remotes/origin/main", gitOk(root, ["rev-parse", "HEAD"])]);
  gitOk(root, ["config", "branch.main.remote", "origin"]);
  gitOk(root, ["config", "branch.main.merge", "refs/heads/main"]);
  return origin;
}

function commonDir(root) {
  return gitOk(root, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
}

export function buildWorld(world, options = {}) {
  mkdirSync(world, { recursive: true });
  const targets = {};
  const repos = options.repos ?? REPOS;
  for (const repository of repos) {
    const root = join(world, "targets", repository);
    buildTarget(root, repository, options.repoPlans ?? PLANS.length, options.policyRepository === repository ? options.wrongPolicyRepository : undefined);
    addOriginRemote(root);
    targets[repository] = {
      common_dir: commonDir(root),
      ref: "refs/remotes/origin/main",
      repository,
      revision: gitOk(root, ["rev-parse", "refs/remotes/origin/main"]),
      older: gitOk(root, ["rev-parse", "HEAD~1"]),
      root,
      target: "main",
    };
  }
  const reference = targets.skills.root;
  const candidate = join(world, "drivers", "candidate");
  if (options.linkedCandidate) {
    gitOk(targets.skills.root, ["worktree", "add", "-q", "-b", "candidate", candidate, "main"]);
  } else {
    gitOk(world, ["clone", "-q", "--no-local", targets.skills.root, candidate]);
  }
  write(join(candidate, "port/synthetic-lane-note.md"), "synthetic candidate lane commit\n");
  commitTree(candidate);
  const laneInfo = {
    candidate: { driver_root: candidate, common_dir: commonDir(candidate), driver_commit: gitOk(candidate, ["rev-parse", "HEAD"]) },
    reference: { driver_root: reference, common_dir: commonDir(reference), driver_commit: gitOk(reference, ["rev-parse", "HEAD"]) },
  };
  return { targets, lanes: laneInfo, world };
}

export function reuseWorld(world) {
  const targets = {};
  for (const repository of REPOS) {
    const root = join(world, "targets", repository);
    targets[repository] = {
      common_dir: commonDir(root),
      ref: "refs/remotes/origin/main",
      repository,
      revision: gitOk(root, ["rev-parse", "refs/remotes/origin/main"]),
      older: gitOk(root, ["rev-parse", "HEAD~1"]),
      root,
      target: "main",
    };
  }
  const reference = targets.skills.root;
  const candidate = join(world, "drivers", "candidate");
  return {
    targets,
    lanes: {
      candidate: { driver_root: candidate, common_dir: commonDir(candidate), driver_commit: gitOk(candidate, ["rev-parse", "HEAD"]) },
      reference: { driver_root: reference, common_dir: commonDir(reference), driver_commit: gitOk(reference, ["rev-parse", "HEAD"]) },
    },
    world,
  };
}

export function expectedProvenance(world, repository, lane) {
  const target = world.targets[repository];
  return target !== undefined && target.common_dir === world.lanes[lane].common_dir ? "base-copy" : "source-lane";
}

function siteOrder() {
  const sites = [];
  for (const operation of OPERATIONS) {
    for (const repository of REPOS) {
      for (const plan of PLANS) {
        for (const lane of LANES) {
          sites.push({ lane, repository, plan, operation });
        }
      }
    }
  }
  return sites;
}

function isRefusalExport(site) {
  return site.operation === "export-evidence" && REFUSAL_CODES[site.repository] !== undefined;
}

export function envelopeFor(world, site, overrides = {}) {
  const provenance = expectedProvenance(world, site.repository, site.lane);
  if (isRefusalExport(site)) {
    return {
      code: REFUSAL_CODES[site.repository],
      detail: `synthetic ${REFUSAL_CODES[site.repository]} refusal for ${site.repository}`,
      schema: "readiness-contract/2",
      ...overrides,
    };
  }
  if (site.operation === "audit-merges") {
    return {
      findings: [],
      merged_at: "2026-10-19T12:00:05Z",
      plan_id: site.plan,
      provenance,
      schema: "merge-audit/1",
      target_revision: overrides.target_revision ?? world.targets[site.repository].revision,
      ...overrides,
    };
  }
  return {
    exported_at: "2026-10-19T12:00:10Z",
    log_sha256: LOG_SHA,
    plan_id: site.plan,
    provenance,
    schema: "evidence-export/1",
    ...overrides,
  };
}

function argvFor(world, site) {
  const target = world.targets[site.repository];
  return [
    "bash",
    "04-validate-handoff/autobahn/contract-run.sh",
    site.operation,
    "--root",
    target.root,
    "--target",
    target.target,
    "--plan",
    site.plan,
  ];
}

function writtenFiles(site) {
  if (site.operation === "audit-merges") return { before: {}, after: {} };
  const before = {
    "evidence/log.mdl": Buffer.from(`synthetic log before ${site.plan} ${site.operation}\n`, "utf8"),
  };
  const after = { ...before };
  if (!isRefusalExport(site)) {
    after["evidence/exports/plan.json"] = Buffer.from(`synthetic export for ${site.plan}\n`, "utf8");
  }
  return { before, after };
}

function mapOf(files) {
  const map = {};
  for (const path of Object.keys(files).sort()) {
    map[path] = sha256(files[path]);
  }
  return map;
}

function dropped(options, site) {
  if (options.dropSite === siteKey(site)) {
    return true;
  }
  if (options.dropRepository === undefined || options.dropRepository !== site.repository) {
    return false;
  }
  return asList(options.dropSites).includes(site.operation);
}

function asList(value) {
  return Array.isArray(value) ? value : [];
}

export function buildRunModel(world, options = {}) {
  const sites = siteOrder().filter((site) => !dropped(options, site));
  const model = {
    world,
    sites: [],
    lanes: {
      candidate: { ...world.lanes.candidate },
      reference: { ...world.lanes.reference },
      schema: "d13-lanes/1",
      targets: REPOS.map((repository) => ({
        common_dir: world.targets[repository].common_dir,
        ref: world.targets[repository].ref,
        repository,
        revision: options.olderRevision && options.olderRevision === repository ? world.targets[repository].older : world.targets[repository].revision,
        root: world.targets[repository].root,
        target: world.targets[repository].target,
      })),
    },
    normalizations: [],
    registries: {},
    policies: {},
    observation: null,
  };
  for (const repository of REPOS) {
    model.registries[repository] = registryBytesWithPlans(repository, options.registryPlans ?? PLANS.length);
    const target = model.lanes.targets.find((t) => t.repository === repository);
    model.policies[repository] = committedBytes(target.root, target.revision, POLICY_PATH);
    if (options.olderRevision === repository) model.registries[repository] = committedBytes(target.root, target.revision, REGISTRY_PATH);
  }
  model.sites = sites.filter((site) => registeredSite(model, site)).map((site, index) => captureFor(world, site, index + 1, model.lanes.targets.find((t) => t.repository === site.repository).revision));
  return model;
}

function committedBytes(root, revision, path) {
  const result = git(root, ["cat-file", "blob", `${revision}:${path}`]);
  if (result.status !== 0) throw new Error(`synthetic committed input unavailable: ${revision}:${path}`);
  return result.stdout;
}

function registeredSite(model, site) {
  return JSON.parse(model.registries[site.repository]).plans.some((plan) => plan.plan_id === site.plan);
}

function captureFor(world, site, sequence, revision) {
  const started = T0 + (sequence - 1) * 60000;
  const exportSite = site.operation === "export-evidence";
  const files = writtenFiles(site);
  const exit = isRefusalExport(site) ? 2 : 0;
  return {
      ...site,
      exit,
      meta: {
        argv: argvFor(world, site),
        cwd: world.lanes[site.lane].driver_root,
        driver_commit: world.lanes[site.lane].driver_commit,
        exit,
        finished_at: new Date(started + 5000).toISOString().replace(".000", ""),
        log_after: exportSite ? { lines: 3, sha256: LOG_SHA } : null,
        log_before: exportSite ? { lines: 3, sha256: LOG_SHA } : null,
        schema: "d13-capture/1",
        sequence,
        started_at: new Date(started).toISOString().replace(".000", ""),
        written: exportSite ? mapOf(files.after) : null,
        written_before: exportSite ? mapOf(files.before) : null,
      },
      files,
      stdout: Buffer.from(pretty(envelopeFor(world, site, site.operation === "audit-merges" ? { target_revision: revision } : {})), "utf8"),
      stderr: Buffer.from(`synthetic ${site.operation} for ${site.repository}\n`, "utf8"),
  };
}

export function siteKey(site) {
  return `${site.lane}/${site.repository}/${site.plan}/${site.operation}`;
}

function observationCommand(cwd, args, subject, phase) {
  const result = git(cwd, args);
  return {
    argv: ["git", ...args],
    cwd,
    exit: result.status,
    phase,
    stderr: result.stderr.toString("base64"),
    stdout: result.stdout.toString("base64"),
    subject,
  };
}

const IDENTITY_READS = [
  ["rev-parse", "--show-toplevel"],
  ["rev-parse", "--path-format=absolute", "--git-common-dir"],
];

export function recordObservation(model, options = {}) {
  const commands = [];
  for (const target of model.lanes.targets) {
    for (const phase of ["start", "finish"]) {
      if (phase === "finish" && options.finishRevision && target.repository === "skills") {
        gitOk(target.root, ["update-ref", target.ref, model.world.targets.skills.older]);
      }
      for (const args of IDENTITY_READS) {
        commands.push(observationCommand(target.root, args, `target:${target.repository}`, phase));
      }
      commands.push(observationCommand(target.root, ["rev-parse", "--verify", `${target.ref}^{commit}`], `target:${target.repository}`, phase));
    }
    if (options.finishRevision && target.repository === "skills") gitOk(target.root, ["update-ref", target.ref, model.world.targets.skills.revision]);
    commands.push(observationCommand(target.root, ["cat-file", "-e", `${target.revision}^{commit}`], `target:${target.repository}`, "start"));
    for (const path of [POLICY_PATH, REGISTRY_PATH]) {
      commands.push(observationCommand(target.root, ["rev-parse", `${target.revision}:${path}`], `target:${target.repository}`, "start"));
      const blob = gitOk(target.root, ["rev-parse", `${target.revision}:${path}`]);
      commands.push(observationCommand(target.root, ["cat-file", "blob", blob], `target:${target.repository}`, "start"));
    }
  }
  for (const lane of LANES) {
    for (const phase of ["start", "finish"]) {
      commands.push(observationCommand(model.lanes[lane].driver_root, ["rev-parse", "--show-toplevel"], `lane:${lane}`, phase));
      commands.push(observationCommand(model.lanes[lane].driver_root, ["rev-parse", "--path-format=absolute", "--git-common-dir"], `lane:${lane}`, phase));
      commands.push(observationCommand(model.lanes[lane].driver_root, ["rev-parse", "HEAD"], `lane:${lane}`, phase));
    }
  }
  return { commands, lanes_sha256: sha256(compact(model.lanes)), schema: "d13-local-observation/1" };
}

function walk(dir, base, out) {
  for (const entry of readdirSync(dir).sort()) {
    const full = join(dir, entry);
    const info = statSync(full);
    const rel = base === "" ? entry : `${base}/${entry}`;
    if (info.isDirectory()) {
      walk(full, rel, out);
    } else if (info.isFile()) {
      out.set(rel, readFileSync(full));
    }
  }
  return out;
}

export function manifestBytes(dir) {
  const files = new Map();
  walk(dir, "", files);
  files.delete("raw-manifest.json");
  const rows = [...files.entries()]
    .map(([path, bytes]) => ({ bytes: bytes.length, path, sha256: sha256(bytes) }))
    .sort((left, right) => (left.path < right.path ? -1 : 1));
  return Buffer.from(pretty({ files: rows, schema: "d13-raw-manifest/1" }), "utf8");
}

export function materializeRun(model, dir) {
  mkdirSync(dir, { recursive: true });
  write(join(dir, "lanes.json"), compact(model.lanes));
  write(join(dir, "normalizations.json"), compact(model.normalizations));
  write(join(dir, "observation.json"), compact(model.observation));
  for (const repository of Object.keys(model.registries)) {
    if (model.omitInput !== `registries/${repository}.json`) write(join(dir, "registries", `${repository}.json`), model.registries[repository]);
    if (model.omitInput !== `policies/${repository}.json`) write(join(dir, "policies", `${repository}.json`), model.policies[repository]);
  }
  for (const site of model.sites) {
    const base = join(dir, "captures", site.lane, site.repository, site.plan, site.operation);
    write(join(base, "stdout"), site.stdout);
    write(join(base, "stderr"), site.stderr);
    write(join(base, "meta.json"), compact(site.meta));
    for (const phase of ["before", "after"]) {
      const files = phase === "before" ? site.files.before : site.files.after;
      for (const path of Object.keys(files).sort()) {
        write(join(base, `written-${phase}`, path), files[path]);
      }
    }
  }
  if (model.extraMetadata) write(join(dir, "extra-meta.json"), "{}\n");
  write(join(dir, "raw-manifest.json"), manifestBytes(dir));
  return dir;
}

export function findSite(model, key) {
  const site = model.sites.find((entry) => siteKey(entry) === key);
  if (site === undefined) {
    throw new Error(`unknown fixture site ${key}`);
  }
  return site;
}

export { GOAL, GENERATION, PLAN, PLANS, POLICY_PATH, REFUSAL_CODES, REGISTRY_PATH, REPOS, SPEC_SHA256, TOOL_PATH };
