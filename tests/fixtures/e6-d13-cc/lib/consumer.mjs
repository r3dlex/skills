// Synthetic consumer world for --consumer-check. A temporary Git repository
// carrying the registered generation objects, the contract spec bytes, the
// merged checker bytes and the digest-bound retained run. Everything here is
// synthetic: no real approval, publication, capture custody or hosted
// completion is represented.
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import {
  GENERATION,
  GOAL,
  PLAN,
  POLICY_PATH,
  REGISTRY_PATH,
  SPEC_SHA256,
  TOOL_PATH,
  pretty,
  sha256,
} from "./world.mjs";

const GIT_ENV = {
  ...process.env,
  GIT_AUTHOR_DATE: "2026-10-19T13:00:00Z",
  GIT_AUTHOR_EMAIL: "fixture@example.com",
  GIT_AUTHOR_NAME: "fixture",
  GIT_COMMITTER_DATE: "2026-10-19T13:00:00Z",
  GIT_COMMITTER_EMAIL: "fixture@example.com",
  GIT_COMMITTER_NAME: "fixture",
};

function write(path, bytes) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, bytes);
}

function git(cwd, args) {
  const result = spawnSync("git", args, { cwd, encoding: "buffer", env: GIT_ENV });
  if ((result.status ?? 1) !== 0) {
    throw new Error(`consumer git ${args.join(" ")} failed: ${String(result.stderr)}`);
  }
  return Buffer.isBuffer(result.stdout) ? result.stdout.toString("utf8").trim() : "";
}

function commit(root, message) {
  git(root, ["add", "-A"]);
  git(root, ["commit", "-q", "-m", message]);
  return git(root, ["rev-parse", "HEAD"]);
}

export function buildConsumer(root, options) {
  const bundleDir = `.ai/handoff/readiness-v2/${PLAN}/${GENERATION}`;
  mkdirSync(root, { recursive: true });
  git(root, ["init", "-q", "-b", "main", "."]);
  const policyBytes = Buffer.from(pretty({ repository: { id: "skills" }, schema: "readiness-policy/2" }), "utf8");
  write(join(root, POLICY_PATH), policyBytes);
  const baseCommit = commit(root, "synthetic consumer base");

  write(join(root, "docs/specifications/ACTIVE/e6-d13-comparison-contract.md"), options.specBytes);
  write(join(root, TOOL_PATH), options.toolBytes);
  const goals = Buffer.from(
    `${JSON.stringify({
      goals: [{ acceptance_criteria: [], dependencies: [], id: GOAL, scope: [], verification: [] }],
      id: PLAN,
      repository: { id: "skills" },
    })}\n`,
    "utf8",
  );
  const graph = Buffer.from(
    `${JSON.stringify({ edges: [], nodes: [{ goal: GOAL, id: GOAL }] })}\n`,
    "utf8",
  );
  const handoff = Buffer.from(`# synthetic handoff for ${PLAN}\n`, "utf8");
  write(join(root, bundleDir, "goals.json"), goals);
  write(join(root, bundleDir, "graph.json"), graph);
  write(join(root, bundleDir, "handoff.md"), handoff);
  const specSha = sha256(options.specBytes);
  const specDigest = options.wrongSpecDigest === true ? sha256("synthetic wrong registered spec digest") : SPEC_SHA256;
  const registry = Buffer.from(
    pretty({
      plans: [
        {
          artifacts: {
            bundle: { path: `${bundleDir}/goals.json`, sha256: sha256(goals) },
            graph: { path: `${bundleDir}/graph.json`, sha256: sha256(graph) },
            handoff: { path: `${bundleDir}/handoff.md`, sha256: sha256(handoff) },
          },
          generation: GENERATION,
          handoff_path: `${bundleDir}/handoff.md`,
          id: `northstar-plan-${PLAN}`,
          mode: "live",
          plan_id: PLAN,
          policy_sha256: sha256(policyBytes),
          schema: "readiness-contract/2",
          spec: { path: "docs/specifications/ACTIVE/e6-d13-comparison-contract.md", sha256: specDigest },
          status: "active",
        },
      ],
      schema: "readiness/registry/1",
    }),
    "utf8",
  );
  write(join(root, REGISTRY_PATH), registry);
  const publication = commit(root, "synthetic contract publication");
  cpSync(join(options.runTree), join(root, options.runDirectory), { recursive: true });
  const merge = commit(root, "synthetic goal merge");
  write(join(root, "CONSUMER-HEAD.md"), "# synthetic consumer head\n");
  const head = commit(root, "synthetic consumer head");
  const origin = `${root}.origin.git`;
  git(root, ["init", "-q", "--bare", origin]);
  git(root, ["remote", "add", "origin", origin]);
  git(root, ["update-ref", "refs/remotes/origin/main", head]);
  git(root, ["config", "branch.main.remote", "origin"]);
  git(root, ["config", "branch.main.merge", "refs/heads/main"]);

  return {
    baseCommit,
    bundleDir,
    head,
    merge,
    publication,
    registry,
    root,
    specSha,
    toolBlob: git(root, ["rev-parse", `${publication}:${TOOL_PATH}`]),
  };
}