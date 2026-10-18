import { spawnSync } from "node:child_process";
import { accessSync, closeSync, constants, fsyncSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { canonical, digest, dumps, ID, Invalid, read, require, REVISION, SHA, string, VERSION, type Args } from "./json.mjs";
import { shlexSplit, validate as validateCommands } from "./verification.mjs";

const POLICY = ".ai/policies/readiness-policy.json";
const MANIFEST = ".ai/workflows/repo-workflow.json";
const GRAPH = ".ai/traceability/graph.json";
const REGISTRY = ".ai/workflows/northstar-readiness-v1.json";
const GEN = ".ai/handoff/readiness-v1";
const MAPPED = "mapped-handoff-goals/1";
const STAGES = ["preparation", "implementation", "merge"];
const DIMENSIONS = ["owners", "reviewer", "branch_target", "fixtures", "tooling", "registration_approval", "harness_trust"];
type Dict = Record<string, unknown>;

function isDict(value: unknown): value is Dict {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function dict(value: unknown, message: string): Dict {
  if (!isDict(value)) {
    throw new Invalid(message);
  }
  return value;
}

function text(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function pyPath(path: string): string {
  return realpathSync(path);
}

function exists(path: string): boolean {
  try {
    lstatSync(path);
    return true;
  } catch {
    return false;
  }
}

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function isDirectory(path: string): boolean {
  return exists(path) && statSync(path).isDirectory();
}

function keysEqual(value: Dict, keys: string[]): boolean {
  return Object.keys(value).sort().join("\n") === [...keys].sort().join("\n");
}

function inside(root: string, path: string): boolean {
  return path === root || path.startsWith(root + "/");
}

function pathHasSymlink(path: string): boolean {
  for (let current = path; ; current = resolve(current, "..")) {
    if (lstatSync(current).isSymbolicLink()) {
      return true;
    }
    if (resolve(current, "..") === current) {
      return false;
    }
  }
}

function digestFile(path: string): string {
  return digest(path);
}

function symlinkComponent(root: string, path: string): boolean {
  let current = path;
  while (current !== root && current.startsWith(root + "/")) {
    try {
      if (lstatSync(current).isSymbolicLink()) {
        return true;
      }
    } catch {
      // A missing component is not a symlink. Existence is checked separately.
    }
    const parent = resolve(current, "..");
    if (parent === current) {
      break;
    }
    current = parent;
  }
  return false;
}

export function relativePath(root: string, name: unknown, mustExist = true): string {
  require(string(name), "path_required");
  const text = name as string;
  const unsafe = isAbsolute(text) || text.includes("\\") || text.split("/").some((part) => part === "" || part === "." || part === "..");
  require(!unsafe, "unsafe_path:" + text);
  const path = resolve(root, text);
  require(!symlinkComponent(root, path), "symlink_path:" + text);
  if (mustExist) {
    try {
      return realpathSync(path);
    } catch (error) {
      throw new Invalid("outside_root:" + text, (error as NodeJS.ErrnoException).code === "ENOENT" ? "enoent" : "");
    }
  }
  return path;
}

function fileRef(root: string, value: unknown): void {
  const record = dict(value, "file_digest_required");
  require(SHA.test(text(record.sha256)), "file_digest_required");
  const path = relativePath(root, record.path);
  require(isFile(path) && digestFile(path) === record.sha256, "stale_file:" + text(record.path));
}

function repository(value: unknown, root: string): void {
  const record = dict(value, "repository_id_required");
  require(ID.test(text(record.id)), "repository_id_required");
  require(record.root === root, "repository_root_mismatch");
}

function stringList(goal: Dict, key: string): string[] {
  const list = goal[key];
  require(Array.isArray(list) && list.length > 0 && list.every((item) => string(item)), key + "_required");
  return list as string[];
}

function goalShape(goal: unknown, root: string, filesRoot = root): void {
  const record = dict(goal, "goal_id_required");
  require(ID.test(text(record.id)), "goal_id_required");
  repository(record.repository, root);
  require(string(record.issue_ref), "goal_issue_required");
  stringList(record, "scope");
  stringList(record, "acceptance_criteria");
  for (const scope of stringList(record, "scope")) {
    relativePath(filesRoot, scope, false);
  }
  const deps = record.dependencies;
  require(Array.isArray(deps) && deps.every((item) => typeof item === "string" && ID.test(item)), "invalid_dependencies");
  require(new Set(deps as string[]).size === (deps as string[]).length && !(deps as string[]).includes(text(record.id)), "invalid_dependencies");
  const readiness = dict(record.readiness, "stage_readiness_required");
  require(STAGES.every((stage) => stage in readiness), "stage_readiness_required");
  require(Object.values(readiness).every((item) => item === "ready" || item === "blocked" || item === "unknown"), "stage_readiness_required");
  require(Array.isArray(record.verification) && record.verification.length > 0, "verification_required");
}

function acyclic(goals: Dict[]): void {
  const ids = goals.map((goal) => String(goal.id));
  const edges = new Map(goals.map((goal) => [String(goal.id), goal.dependencies as string[]]));
  const degree = new Map(ids.map((id) => [id, (edges.get(id) ?? []).length]));
  const ready = ids.filter((id) => degree.get(id) === 0);
  let visited = 0;
  while (ready.length > 0) {
    const id = ready.shift() ?? "";
    visited += 1;
    for (const [gid, deps] of edges) {
      if (deps.includes(id)) {
        degree.set(gid, (degree.get(gid) ?? 0) - 1);
        if (degree.get(gid) === 0) {
          ready.push(gid);
        }
      }
    }
  }
  require(visited === ids.length, "dependency_cycle");
}

function mapped(bundle: Dict): boolean {
  return bundle.schema === MAPPED;
}

function executionRoot(bundle: Dict, root: string): string {
  return mapped(bundle) ? text(((bundle.execution as Dict).repository as Dict).root) : root;
}

function executionSources(binding: Dict, root: string): void {
  const sources = binding.sources;
  require(Array.isArray(sources) && sources.length > 0, "execution_sources_required");
  const records = (sources as unknown[]).map((source) => dict(source, "execution_sources_required"));
  require(records.every((source) => keysEqual(source, ["path", "sha256"])), "execution_sources_required");
  require(new Set(records.map((source) => source.path)).size === records.length, "duplicate_execution_sources");
  for (const source of records) {
    fileRef(root, source);
  }
}

function executionShape(bundle: Dict, root: string): string {
  const binding = dict(bundle.execution, "execution_binding_required");
  require(keysEqual(binding, ["repository", "target", "source_revision", "sources", "validation"]), "execution_binding_required");
  const repo = dict(binding.repository, "execution_repository_required");
  require(keysEqual(repo, ["id", "root"]) && string(repo.root), "execution_repository_required");
  const target = text(repo.root);
  require(isAbsolute(target) && realpathSync(target) === target && isDirectory(target), "execution_root_not_canonical");
  require(!pathHasSymlink(target), "execution_root_symlink");
  repository(repo, target);
  require(repo.id !== (bundle.repository as Dict).id && !inside(root, target) && !inside(target, root), "execution_roots_not_disjoint");
  require(string(binding.target) && !/[\s;&|`$<>]/.test(text(binding.target)), "execution_target_required");
  require(REVISION.test(text(binding.source_revision)), "execution_source_revision_required");
  require(["local", "external-only"].includes(text(binding.validation)), "execution_validation_required");
  executionSources(binding, target);
  return target;
}

function scopeDirectories(root: string, scope: string, directories: Set<string>): void {
  require(!/[*?[\]]/.test(scope), "execution_scope_must_be_literal");
  const path = relativePath(root, scope, false);
  for (let parent = resolve(path, ".."); inside(root, parent); parent = resolve(parent, "..")) {
    directories.add(parent);
    if (parent === root) {
      break;
    }
  }
  if (isDirectory(path)) {
    directories.add(path);
    collectDirectories(path, directories);
  }
}

function collectDirectories(path: string, directories: Set<string>): void {
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      const child = resolve(path, entry.name);
      directories.add(child);
      collectDirectories(child, directories);
    }
  }
}

function instructionPaths(bundle: Dict, root: string): Set<string> {
  const directories = new Set([root]);
  for (const goal of bundle.goals as Dict[]) {
    for (const scope of goal.scope as string[]) {
      scopeDirectories(root, scope, directories);
    }
  }
  const required = new Set(["AGENTS.md"]);
  for (const directory of directories) {
    for (const name of ["AGENTS.md", "CLAUDE.md", "GEMINI.md", ".rules.ts"]) {
      if (isFile(resolve(directory, name))) {
        required.add(resolve(directory, name).slice(root.length + 1));
      }
    }
    const rules = resolve(directory, ".ai/rules");
    if (isDirectory(rules)) {
      filesUnder(root, rules).forEach((name) => required.add(name));
    }
  }
  return required;
}

export function bundleShape(bundle: unknown, root: string, filesRoot = root): void {
  const record = dict(bundle, "migration_required:handoff-goals/1");
  require(record.schema === "handoff-goals/1" || record.schema === MAPPED, "migration_required:handoff-goals/1");
  require(ID.test(text(record.id)), "bundle_id_required");
  repository(record.repository, root);
  require(mapped(record) || !("execution" in record), "execution_requires_mapped_schema");
  const goalRoot = mapped(record) ? executionShape(record, root) : root;
  require(string(record.issue_ref), "bundle_issue_required");
  require(typeof record.planning_complete === "boolean", "planning_complete_required");
  require(record.status === "active" || record.status === "blocked" || record.status === "superseded", "bundle_status_required");
  fileRef(filesRoot, record.spec);
  require(Array.isArray(record.goals) && record.goals.length > 0, "goals_required");
  bundleGoals(record, filesRoot, goalRoot);
}

function bundleGoals(record: Dict, filesRoot: string, goalRoot: string): void {
  const goals = record.goals as Dict[];
  for (const goal of goals) {
    goalShape(goal, goalRoot, mapped(record) ? goalRoot : filesRoot);
    const repo = mapped(record) ? (record.execution as Dict).repository : record.repository;
    require(sameValue(dict(goal, "goal_repository_mismatch").repository, repo), "goal_repository_mismatch");
  }
  if (mapped(record)) {
    const listed = new Set(((record.execution as Dict).sources as Dict[]).map((source) => text(source.path)));
    require([...instructionPaths(record, goalRoot)].every((name) => listed.has(name)), "execution_source_set_incomplete");
  }
  const ids = goals.map((goal) => text(goal.id));
  require(new Set(ids).size === ids.length, "duplicate_goal_ids");
  require(goals.every((goal) => ((goal.dependencies as string[]) ?? []).every((dep) => ids.includes(dep))), "unknown_dependency");
  acyclic(goals);
}

function handoffText(bundle: Dict): string {
  const planning = bundle.planning_complete === true ? "true" : "false";
  const goals = (bundle.goals as Dict[]).map((goal) => String(goal.id)).join(", ");
  return `# Northstar handoff: ${String(bundle.id)}\n\nPlanning complete: ${planning}\n\nExecution readiness: independently revalidate; planning is not admission.\n\nGoals: ${goals}\n`;
}

function gitRead(root: string, ...args: string[]): string {
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith("GIT_")));
  Object.assign(env, { GIT_CONFIG_NOSYSTEM: "1", GIT_CONFIG_GLOBAL: "/dev/null", GIT_NO_REPLACE_OBJECTS: "1", GIT_OPTIONAL_LOCKS: "0" });
  const result = spawnSync("git", ["--no-lazy-fetch", "--no-replace-objects", "-c", "core.fsmonitor=false", "-c", "core.filemode=true", "-c", "core.hooksPath=/dev/null", "-C", root, ...args], { env, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 });
  require(result.status === 0, "worktree_git_proof_failed:" + text(args[0]));
  return result.stdout;
}

function exactRoot(value: string): string {
  require(exists(value), "worktree_root_missing");
  require(isAbsolute(value) && value === realpathSync(value) && isDirectory(value) && !pathHasSymlink(value), "worktree_root_not_canonical");
  require(gitRead(value, "rev-parse", "--show-toplevel").trim() === value, "worktree_toplevel_mismatch");
  require(gitRead(value, "rev-parse", "--is-bare-repository").trim() === "false", "worktree_bare_repository");
  return value;
}

function worktreeIdentity(identityRoot: string, filesRoot: string, base: string): Dict {
  exactRoot(identityRoot);
  exactRoot(filesRoot);
  require(identityRoot !== filesRoot, "worktree_must_be_distinct");
  require(REVISION.test(base), "worktree_base_required");
  const common = realpathSync(gitRead(identityRoot, "rev-parse", "--path-format=absolute", "--git-common-dir").trim());
  const actual = realpathSync(gitRead(filesRoot, "rev-parse", "--path-format=absolute", "--git-common-dir").trim());
  require(common === actual, "worktree_common_dir_mismatch");
  const gitDir = realpathSync(gitRead(filesRoot, "rev-parse", "--absolute-git-dir").trim());
  require(gitDir !== common && isFile(resolve(filesRoot, ".git")), "linked_worktree_required");
  const records = gitRead(identityRoot, "worktree", "list", "--porcelain", "-z").split("\0\0");
  require(records.some((record) => record.split("\0").includes("worktree " + filesRoot)), "registered_worktree_required");
  const head = gitRead(filesRoot, "rev-parse", "--verify", "HEAD^{commit}").trim();
  const branch = gitRead(filesRoot, "symbolic-ref", "--quiet", "HEAD").trim();
  require(branch.startsWith("refs/heads/"), "worktree_branch_required");
  const targetRef = "refs/remotes/origin/main";
  const target = gitRead(filesRoot, "rev-parse", "--verify", targetRef + "^{commit}").trim();
  require(gitRead(filesRoot, "rev-parse", "--verify", base + "^{commit}").trim() === base, "worktree_base_not_commit");
  gitRead(filesRoot, "merge-base", "--is-ancestor", base, head);
  gitRead(filesRoot, "merge-base", "--is-ancestor", base, target);
  return { schema: "git-worktree/1", root: filesRoot, base_commit: base, target_ref: targetRef, common_dir: common, head, branch, target_revision: target };
}

function worktreeFiles(root: string, dir: string, paths: Set<string>): void {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (dir === root && entry.name === ".git") {
      continue;
    }
    const path = resolve(dir, entry.name);
    if (entry.isDirectory()) {
      worktreeFiles(root, path, paths);
    } else {
      require(!entry.isSymbolicLink() || !isDirectory(path), "worktree_symlink_directory");
      paths.add(path.slice(root.length + 1));
    }
  }
}

function worktreeState(root: string, paths: Set<string>): unknown[][] {
  return [...paths].sort().map((name) => {
    const path = relativePath(root, name, false);
    if (!exists(path)) {
      return [name, "deleted"];
    }
    const info = lstatSync(path);
    require(!info.isSymbolicLink(), "worktree_symlink_input:" + name);
    if (info.isDirectory()) {
      return [name, "directory", info.mode & 0o7777];
    }
    require(info.isFile(), "worktree_nonregular_input:" + name);
    return [name, info.mode & 0o7777, digestFile(path)];
  });
}

function gitEntries(root: string, head: string, index: boolean): Dict {
  const raw = index ? gitRead(root, "ls-files", "--stage", "-z") : gitRead(root, "ls-tree", "-r", "-z", head);
  const entries: Dict = {};
  for (const entry of raw.split("\0").filter(Boolean)) {
    const at = entry.indexOf("\t");
    const [mode, second, third] = entry.slice(0, at).split(" ");
    if (index) {
      require(third === "0", "worktree_merge_unmerged_index");
      entries[entry.slice(at + 1)] = [mode, second];
    } else {
      require(second === "blob" && ["100644", "100755"].includes(text(mode)), "worktree_merge_tree_type_unsupported");
      entries[entry.slice(at + 1)] = [mode, third];
    }
  }
  return entries;
}

function cleanWorktree(root: string, head: string, paths: Set<string>): void {
  const flags = gitRead(root, "ls-files", "-v", "-z").split("\0").filter(Boolean);
  require(flags.every((entry) => /^[A-Z]/.test(entry) && entry[0] !== "S"), "worktree_merge_index_flags_unsupported");
  const tree = gitEntries(root, head, false);
  require(sameValue(gitEntries(root, head, true), tree), "worktree_merge_index_mismatch");
  const files = [...paths].filter((name) => isFile(resolve(root, name))).sort();
  require(sameValue(files, Object.keys(tree).sort()), "worktree_merge_uncommitted_files");
  for (const [name, entry] of Object.entries(tree)) {
    const [mode, objectId] = entry as string[];
    const diskMode = (statSync(resolve(root, name)).mode & 0o100) !== 0 ? "100755" : "100644";
    const rawHash = gitRead(root, "hash-object", "--no-filters", "--", name).trim();
    require(diskMode === mode && rawHash === objectId, "worktree_merge_head_bytes_mismatch");
  }
}

function worktreeObservation(identity: string, root: string, base: string, clean: boolean, inputs: string[] = []): Dict {
  const observation = worktreeIdentity(identity, root, base);
  const paths = new Set(gitRead(root, "ls-files", "--cached", "-z").split("\0").filter(Boolean));
  worktreeFiles(root, root, paths);
  for (const name of inputs) {
    require(!/[*?[\]]/.test(name), "worktree_glob_scope_unsupported");
    const path = relativePath(root, name, false);
    paths.add(name);
    if (isDirectory(path)) {
      worktreeFiles(root, path, paths);
    }
  }
  const state = worktreeState(root, paths);
  if (clean) {
    cleanWorktree(root, text(observation.head), paths);
  }
  return { ...observation, state_sha256: canonical(state) };
}

function worktreeBinding(observation: Dict): Dict {
  return Object.fromEntries(["schema", "root", "base_commit", "target_ref"].map((key) => [key, observation[key]]));
}

function worktreeRequest(args: Args, identity: string): { root: string; observation: Dict | null } {
  const target = args.worktree_root;
  require(Boolean(target) === Boolean(args.base_commit), "worktree_root_and_base_required");
  require(!target || !args.execution_root, "worktree_mapped_conflict");
  if (!target) {
    return { root: identity, observation: null };
  }
  require(args.root === identity, "worktree_identity_alias");
  require(!args.context || !inside(realpathSync(target), realpathSync(args.context)), "worktree_context_must_be_external");
  return { root: target, observation: worktreeObservation(identity, target, text(args.base_commit), args.stage === "merge") };
}

function collectFileRefs(value: unknown, paths: Set<string>): void {
  if (isDict(value)) {
    if (typeof value.path === "string") {
      paths.add(value.path);
    }
    Object.values(value).forEach((child) => collectFileRefs(child, paths));
  } else if (Array.isArray(value)) {
    value.forEach((child) => collectFileRefs(child, paths));
  }
}

function commandInputs(root: string, entry: unknown, paths: Set<string>): void {
  const command = isDict(entry) ? entry.command : entry;
  const cwd = isDict(entry) && entry.cwd !== "." ? relativePath(root, entry.cwd) : root;
  if (typeof command !== "string") {
    return;
  }
  for (const token of shlexSplit(command)) {
    if (!isAbsolute(token) && isFile(resolve(cwd, token))) {
      const name = resolve(cwd, token).slice(root.length + 1);
      relativePath(root, name);
      paths.add(name);
    }
  }
}

function worktreeInputs(bundle: Dict, root: string): string[] {
  const paths = new Set([".ai/matrix.json", MANIFEST, GRAPH, REGISTRY, POLICY, GEN, text((bundle.spec as Dict).path), "prek.toml", ".pre-commit-config.yaml", "package.json", ".ai/ci", ".github/workflows"]);
  for (const goal of bundle.goals as Dict[]) {
    (goal.scope as string[]).forEach((name) => paths.add(name));
    (goal.verification as unknown[]).forEach((entry) => commandInputs(root, entry, paths));
  }
  collectFileRefs(bundle, paths);
  collectFileRefs(read(relativePath(root, POLICY)), paths);
  instructionPaths(bundle, root).forEach((name) => paths.add(name));
  return [...paths].sort();
}

function sameValue(left: unknown, right: unknown): boolean {
  return dumps(left, null, true, true) === dumps(right, null, true, true);
}

function mutableEnrichment(path: string): boolean {
  const parts = path.split("/").filter((part) => part !== "");
  if (["/planning_complete", "/status", "/spec/sha256"].includes(path)) {
    return true;
  }
  if (parts[0] !== "goals") {
    return false;
  }
  if (parts.length === 4 && parts[2] === "readiness") {
    return STAGES.includes(parts[3] ?? "");
  }
  return parts.length === 3 && ["coverage_percent", "coverage_status", "legacy_safe_tdd", "legacy_risk_reason"].includes(parts[2] ?? "");
}

function preserveItems(previous: Dict[], proposed: unknown, path: string): void {
  require(Array.isArray(proposed), "enrichment_loss:" + path);
  const nextById = new Map<string, Dict>();
  for (const item of proposed as unknown[]) {
    if (isDict(item) && "id" in item) {
      nextById.set(String(item.id), item);
    }
  }
  for (const item of previous) {
    const id = String(item.id);
    require(nextById.has(id), "enrichment_loss:" + path);
    preserve(item, nextById.get(id), path + "/" + id);
  }
}

function preserve(previous: unknown, proposed: unknown, path = ""): void {
  if (isDict(previous)) {
    const next = dict(proposed, "enrichment_loss:" + path);
    for (const [key, value] of Object.entries(previous)) {
      require(Object.prototype.hasOwnProperty.call(next, key), "enrichment_loss:" + path + "/" + key);
      preserve(value, next[key], path + "/" + key);
    }
    return;
  }
  if (Array.isArray(previous) && previous.length > 0 && previous.every((item) => isDict(item) && "id" in item)) {
    preserveItems(previous as Dict[], proposed, path);
    return;
  }
  require(mutableEnrichment(path) || sameValue(previous, proposed), "enrichment_changed:" + path);
}

function validateGenerationNodes(graph: Dict, expected: Record<string, Dict>, edges: Dict[]): void {
  const nodes = Array.isArray(graph.nodes) ? graph.nodes as Dict[] : [];
  require(nodes.length === Object.keys(expected).length && new Set(nodes.map((node) => text(node.id))).size === nodes.length && nodes.every((node) => text(node.id) in expected), "generation_collision:nodes");
  require(nodes.every((node) => {
    const want = expected[text(node.id)] ?? {};
    return Object.entries(want).every(([key, value]) => sameValue(node[key], value));
  }) && sameValue(graph.edges, edges), "generation_collision:graph");
}

function validateGeneration(root: string, prefix: string, bundle: Dict, generation: string, spec: Dict): Dict {
  const names = ["goals.json", "graph.json", "handoff.md"];
  const paths = Object.fromEntries(names.map((name) => [name, relativePath(root, prefix + "/" + name)]));
  require(names.every((name) => isFile(paths[name] ?? "")), "generation_collision:non-file");
  const goalsPath = paths["goals.json"] ?? "";
  const graphPath = paths["graph.json"] ?? "";
  const handoffPath = paths["handoff.md"] ?? "";
  require(sameValue(read(goalsPath), bundle) && readFileSync(handoffPath, "utf8") === handoffText(bundle), "generation_collision:payload");
  const graph = dict(read(graphPath), "generation_collision:identity");
  const goalIds = (bundle.goals as Dict[]).map((goal) => text(goal.id));
  require(graph.generation === generation && graph.plan_id === bundle.id && sameValue(graph.goal_ids, goalIds) && SHA.test(text(graph.source_graph_sha256)), "generation_collision:identity");
  const repo = text((bundle.repository as Dict).id);
  const parent = "handoff:" + repo + ":" + text(bundle.id) + ":" + generation;
  const expected: Record<string, Dict> = {
    [text(spec.id)]: { id: spec.id, type: spec.type, repo_id: spec.repo_id, path: spec.path, backlinks: [parent] },
    [parent]: { id: parent, type: "handoff", repo_id: repo, path: prefix + "/handoff.md", backlinks: [spec.id] },
  };
  const edges: Dict[] = [{ source: spec.id, target: parent, type: "plans" }];
  for (const goal of bundle.goals as Dict[]) {
    const goalId = "plan:" + repo + ":" + text(bundle.id) + ":" + text(goal.id) + ":" + generation;
    expected[goalId] = { id: goalId, type: "plan", repo_id: repo, path: prefix + "/goals.json", backlinks: [parent] };
    (expected[parent]?.backlinks as string[]).push(goalId);
    edges.push({ source: parent, target: goalId, type: "plans" });
  }
  validateGenerationNodes(graph, expected, edges);
  return graph;
}

function writeJson(path: string, value: unknown): void {
  writeFileSync(path, dumps(value, 2, true) + "\n");
  const fd = openSync(path, "r");
  try {
    fsyncSync(fd);
  } finally {
    closeSync(fd);
  }
}

function replaceJson(path: string, value: unknown): void {
  const temporary = resolve(path, "..", `.readiness-${process.pid}-${Date.now()}`);
  try {
    writeJson(temporary, value);
    renameSync(temporary, path);
  } finally {
    if (exists(temporary)) {
      rmSync(temporary, { force: true });
    }
  }
}

export function publish(args: Args): Dict {
  const identity = pyPath(String(args.root ?? "."));
  const { root, observation } = worktreeRequest(args, identity);
  const candidate = pyPath(String(args.bundle));
  if (observation) {
    require(inside(root, candidate) && candidate !== root, "worktree_candidate_outside_root");
    relativePath(root, candidate.slice(root.length + 1));
    require(sameValue((read(relativePath(root, POLICY)) as Dict).worktree, worktreeBinding(observation)), "worktree_policy_mismatch");
  }
  const candidateHash = digestFile(candidate);
  const bundle = read(candidate);
  const record = dict(bundle, "migration_required:handoff-goals/1");
  require(!observation || !mapped(record), "worktree_mapped_conflict");
  bundleShape(record, identity, root);
  const generation = canonical(record);
  const base = resolve(root, `${GEN}/${String(record.id)}`);
  mkdirSync(base, { recursive: true });
  const lock = resolve(root, ".ai/workflows/.northstar-readiness-v1.lock");
  try {
    mkdirSync(lock);
  } catch {
    throw new Invalid("publication_locked:inspect existing publisher; never steal a lock");
  }
  try {
    return publishLocked(root, candidate, candidateHash, record, generation, base);
  } finally {
    rmSync(lock, { recursive: true, force: true });
  }
}

function previousRegistration(root: string, registry: Dict, registration: string, bundle: Dict): { plans: Dict[]; previous: Dict | undefined } {
  const plans = registry.plans as Dict[];
  const matches = plans.filter((item) => item.id === registration);
  require(matches.length <= 1, "duplicate_registration");
  const previous = matches[0];
  if (previous) {
    const ref = (previous.artifacts as Dict).bundle;
    fileRef(root, ref);
    preserve(read(relativePath(root, (ref as Dict).path)), bundle);
  }
  return { plans, previous };
}

function publishLocked(root: string, candidate: string, candidateHash: string, bundle: Dict, generation: string, base: string): Dict {
    require(digestFile(candidate) === candidateHash, "candidate_changed");
    const registryPath = resolve(root, REGISTRY);
    const registry = dict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] }, "unsupported_registry_schema");
    require(registry.schema === VERSION && Array.isArray(registry.plans), "unsupported_registry_schema");
    const registration = "northstar-plan-" + String(bundle.id);
    const { plans, previous } = previousRegistration(root, registry, registration, bundle);
    const prefix = `${GEN}/${String(bundle.id)}/${generation}`;
    const final = resolve(base, generation);
    const graphPath = relativePath(root, GRAPH);
    const live = read(graphPath) as Dict;
    const nodes = Array.isArray(live.nodes) ? live.nodes as Dict[] : [];
    const matching = nodes.filter((node) => node.path === (bundle.spec as Dict).path);
    require(matching.length === 1, "spec_graph_identity_missing_or_ambiguous");
    const spec = matching[0] as Dict;
    const parent = `handoff:${text((bundle.repository as Dict).id)}:${text(bundle.id)}:${generation}`;
    const graph = exists(final)
      ? validateGeneration(root, prefix, bundle, generation, spec)
      : buildGraph(bundle, generation, digestFile(graphPath), spec, parent, prefix);
    if (!exists(final)) {
      mkdirSync(final, { recursive: true });
      writeJson(resolve(final, "goals.json"), bundle);
      writeJson(resolve(final, "graph.json"), graph);
      writeFileSync(resolve(final, "handoff.md"), handoffText(bundle));
    }
    const artifacts = {
      bundle: { path: prefix + "/goals.json", sha256: digestFile(resolve(final, "goals.json")) },
      graph: { path: prefix + "/graph.json", sha256: digestFile(resolve(final, "graph.json")) },
      handoff: { path: prefix + "/handoff.md", sha256: digestFile(resolve(final, "handoff.md")) },
    };
    if (previous && previous.generation === generation) {
      require(sameValue(previous.artifacts, artifacts), "generation_collision");
    }
    const owned = {
      schema: VERSION, id: registration, plan_id: bundle.id, generation, status: bundle.status,
      handoff_path: artifacts.handoff.path, artifacts, planning_complete: bundle.planning_complete, execution_admitted: false,
    };
    const entry = previous ? { ...previous, ...owned } : owned;
    registry.plans = previous ? plans.map((item) => item.id === registration ? entry : item) : [...plans, entry];
    spliceGraph(live, graph);
    replaceJson(graphPath, live);
    replaceJson(registryPath, registry);
    return { schema: VERSION, published: entry, execution_ready: false, dispatch_authorized: false, authority_verification: "external-required" };
}

function buildGraph(bundle: Dict, generation: string, graphHash: string, spec: Dict, parent: string, prefix: string): Dict {
  const specNode = { ...spec, backlinks: [parent] };
  const handoff = { id: parent, type: "handoff", title: bundle.id, status: "active", repo_id: (bundle.repository as Dict).id, path: prefix + "/handoff.md", backlinks: [spec.id] };
  const graph: Dict = { schema_version: "1.1", generation, plan_id: bundle.id, goal_ids: (bundle.goals as Dict[]).map((goal) => goal.id), source_graph_sha256: graphHash, nodes: [specNode, handoff], edges: [{ source: spec.id, target: parent, type: "plans" }] };
  for (const goal of bundle.goals as Dict[]) {
    const goalId = `plan:${text((bundle.repository as Dict).id)}:${text(bundle.id)}:${text(goal.id)}:${generation}`;
    (graph.nodes as Dict[]).push({ id: goalId, type: "plan", title: goal.id, status: "planned", repo_id: (bundle.repository as Dict).id, path: prefix + "/goals.json", backlinks: [parent] });
    (handoff.backlinks as string[]).push(goalId);
    (graph.edges as Dict[]).push({ source: parent, target: goalId, type: "plans" });
  }
  return graph;
}

function mergeNode(nodes: Dict[], node: Dict): void {
  const current = nodes.find((item) => item.id === node.id);
  if (!current) {
    nodes.push({ ...node });
    return;
  }
  require(current.path === node.path, "graph_identity_conflict");
  const backlinks = Array.isArray(current.backlinks) ? current.backlinks as string[] : [];
  current.backlinks = backlinks;
  for (const link of (node.backlinks as string[]) ?? []) {
    if (!backlinks.includes(link)) {
      backlinks.push(link);
    }
  }
}

function spliceGraph(live: Dict, graph: Dict): void {
  const nodes = Array.isArray(live.nodes) ? live.nodes as Dict[] : [];
  const edges = Array.isArray(live.edges) ? live.edges as Dict[] : [];
  live.nodes = nodes;
  live.edges = edges;
  for (const node of graph.nodes as Dict[]) {
    mergeNode(nodes, node);
  }
  for (const edge of graph.edges as Dict[]) {
    if (!edges.some((item) => JSON.stringify(item) === JSON.stringify(edge))) {
      edges.push(edge);
    }
  }
}

function add(gaps: Dict[], code: string, detail: unknown, scope: unknown, stage: string, status = "blocked"): void {
  gaps.push({
    code, detail: String(detail).replace(/https?:\/\/\S+/g, "[redacted-url]"), scope, stage, status,
    responsible: "unassigned", source: "independent-context-and-repository-policy", freshness: "unavailable",
    evidence_refs: [], recovery: "Supply current independently verified evidence for this gate; rerun exact selection",
  });
}

function coverageInvalid(status: unknown, unknown: boolean, valid: boolean): boolean {
  if (status !== "unknown" && status !== "measured") {
    return true;
  }
  return (status === "unknown" && !unknown) || (status === "measured" && !valid);
}

function coverageFlags(goal: Dict, unknown: boolean, gaps: Dict[], stage: string): void {
  for (const key of ["coverage_required", "legacy_safe_tdd"]) {
    if (key in goal && typeof goal[key] !== "boolean") {
      add(gaps, "invalid_" + key, "Expected boolean", [goal.id], stage);
    }
  }
  if (unknown && goal.coverage_required === true) {
    add(gaps, "measured_coverage_required", "Goal strengthens policy to measured coverage", [goal.id], stage);
  }
}

function coverageOverride(goal: Dict, valid: boolean, gaps: Dict[], stage: string): void {
  if (valid && Number(goal.coverage_percent) >= 30 && goal.legacy_safe_tdd === true && !string(goal.legacy_risk_reason)) {
    add(gaps, "legacy_risk_reason_required", "High coverage legacy-safe override needs reason", [goal.id], stage);
  }
}

function coverage(goal: Dict, gaps: Dict[], stage: string): void {
  const percent = goal.coverage_percent;
  const status = goal.coverage_status ?? "measured";
  const valid = typeof percent === "number" && percent >= 0 && percent <= 100;
  const unknown = status === "unknown" && percent == null;
  if (coverageInvalid(status, unknown, valid)) {
    add(gaps, "invalid_coverage", "Declare measured 0..100 or unknown without a number", [goal.id], stage);
  }
  if (unknown && (goal.legacy_safe_tdd !== true || !string(goal.legacy_risk_reason))) {
    add(gaps, "unknown_coverage_tdd", "Unknown coverage requires legacy_safe_tdd=true and legacy_risk_reason", [goal.id], stage);
  }
  coverageFlags(goal, unknown, gaps, stage);
  coverageOverride(goal, valid, gaps, stage);
}

type Selection = { bundle: Dict; selected: string[]; subject: string; entry: Dict | null };

function selectDirect(root: string, goal: string, filesRoot: string): Selection {
  if (root !== filesRoot) {
    require(isAbsolute(goal) && inside(filesRoot, goal) && goal !== filesRoot, "worktree_direct_goal_outside_root");
    relativePath(filesRoot, goal.slice(filesRoot.length + 1));
  }
  const envelope = dict(read(goal), "migration_required:direct-goal/1");
  require(envelope.schema === "direct-goal/1", "migration_required:direct-goal/1");
  bundleShape(envelope.bundle, root, filesRoot);
  const bundle = dict(envelope.bundle, "direct_requires_one_goal");
  const goals = bundle.goals as Dict[];
  require(Array.isArray(goals) && goals.length === 1, "direct_requires_one_goal");
  return { bundle, selected: [text(goals[0]?.id)], subject: digestFile(goal), entry: null };
}

function oneMatch(root: string, handoff: string, matches: Dict[]): Dict {
  if (matches.length === 0) {
    legacyHandoff(root, handoff);
  }
  require(matches.length === 1, "handoff_missing_or_ambiguous");
  return matches[0] as Dict;
}

function legacyHandoff(root: string, handoff: string): void {
  const manifest = read(relativePath(root, MANIFEST));
  const branches = isDict(manifest) && Array.isArray(manifest.optional_branches) ? manifest.optional_branches as Dict[] : [];
  const found = branches.filter((branch) => legacyMatch(branch, handoff));
  require(found.length !== 1, "migration_required:registered legacy handoff; use migrate-handoff.sh");
}

function legacyMatch(branch: Dict, handoff: string): boolean {
  const identity = branch.id;
  if (typeof identity !== "string" || !identity.startsWith("northstar-handoff-")) {
    return false;
  }
  const path = ".ai/handoff/northstar-" + identity.slice("northstar-handoff-".length) + ".md";
  return handoff === identity || handoff === path || handoff === branch.handoff_path;
}

export function select(root: string, args: Args, filesRoot = root): Selection {
  require(Boolean(args.goal) !== Boolean(args.handoff), "selection_required:use exact --handoff with --goal-id or explicit --goal");
  if (args.goal) {
    require(!args.goal_id?.length, "direct_goal_selector_conflict");
    return selectDirect(root, args.goal, filesRoot);
  }
  require(Array.isArray(args.goal_id) && args.goal_id.length > 0 && new Set(args.goal_id).size === args.goal_id.length, "goal_selection_required");
  return selectHandoff(root, args, filesRoot);
}

function selectHandoff(root: string, args: Args, filesRoot: string): Selection {
  const entry = handoffEntry(filesRoot, args);
  const loadedPaths = handoffArtifacts(filesRoot, entry);
  const loaded = dict(read(loadedPaths.bundle ?? ""), "plan_identity_mismatch");
  bundleShape(loaded, root, filesRoot);
  require(entry.plan_id === loaded.id, "plan_identity_mismatch");
  require((args.goal_id ?? []).every((id) => (loaded.goals as Dict[]).some((goal) => goal.id === id)), "requested_goal_missing");
  require(entry.generation === canonical(loaded), "generation_digest_mismatch");
  const graph = dict(read(loadedPaths.graph ?? ""), "graph_identity_mismatch");
  require(graph.generation === entry.generation && sameValue(graph.goal_ids, (loaded.goals as Dict[]).map((goal) => goal.id)), "graph_identity_mismatch");
  validateLiveGraph(filesRoot, graph);
  return { bundle: loaded, selected: args.goal_id ?? [], subject: digestFile(loadedPaths.bundle ?? ""), entry };
}

function handoffEntry(root: string, args: Args): Dict {
  const registryPath = resolve(root, REGISTRY);
  const manifest = dict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] }, "unsupported_registry_schema");
  require(manifest.schema === VERSION, "unsupported_registry_schema");
  const matches = (Array.isArray(manifest.plans) ? manifest.plans as Dict[] : []).filter((item) => args.handoff === item.id || args.handoff === item.handoff_path);
  const entry = oneMatch(root, args.handoff ?? "", matches);
  require(entry.schema === VERSION, "migration_required:registered handoff");
  require(entry.status === "active" || (args.stage === "planning" && entry.status === "blocked"), "handoff_not_active");
  return entry;
}

function handoffArtifacts(root: string, entry: Dict): Record<string, string> {
  const generation = text(entry.generation);
  require(SHA.test(generation), "invalid_generation");
  const prefix = `${GEN}/${text(entry.plan_id)}/${generation}/`;
  const artifacts = dict(entry.artifacts, "incomplete_generation");
  require(Object.keys(artifacts).sort().join("\n") === "bundle\ngraph\nhandoff", "incomplete_generation");
  const loadedPaths: Record<string, string> = {};
  for (const [name, ref] of Object.entries(artifacts)) {
    const record = dict(ref, "incomplete_generation");
    require(text(record.path).startsWith(prefix), "mixed_generation");
    fileRef(root, record);
    loadedPaths[name] = relativePath(root, record.path);
  }
  require(entry.handoff_path === (artifacts.handoff as Dict).path, "handoff_path_mismatch");
  return loadedPaths;
}

function validateLiveGraph(root: string, graph: Dict): void {
  const live = dict(read(relativePath(root, GRAPH)), "generation_graph_missing");
  const liveNodes = new Map<string, Dict>();
  for (const node of Array.isArray(live.nodes) ? live.nodes as Dict[] : []) {
    liveNodes.set(text(node.id), node);
  }
  for (const node of Array.isArray(graph.nodes) ? graph.nodes as Dict[] : []) {
    const current = liveNodes.get(text(node.id));
    require(current !== undefined, "generation_graph_missing");
    const liveNode = current as Dict;
    require(["id", "type", "repo_id", "path", "status"].every((key) => sameValue(liveNode[key], node[key])), "generation_graph_identity_mismatch");
  }
  validateLiveEdges(graph, live, liveNodes);
}

function validateLiveEdges(graph: Dict, live: Dict, liveNodes: Map<string, Dict>): void {
  for (const edge of Array.isArray(graph.edges) ? graph.edges as Dict[] : []) {
    const source = liveNodes.get(text(edge.source));
    const target = liveNodes.get(text(edge.target));
    const edges = Array.isArray(live.edges) ? live.edges as Dict[] : [];
    const linked = edges.some((item) => sameValue(item, edge));
    const sourceLinks = backlinks(target);
    const targetLinks = backlinks(source);
    require(linked && sourceLinks.includes(edge.source) && targetLinks.includes(edge.target), "generation_graph_link_missing");
  }
}

function backlinks(node: Dict | undefined): unknown[] {
  const value = node?.backlinks;
  return Array.isArray(value) ? value : [];
}

interface Admission {
  identity: string;
  root: string;
  selection: Selection;
  context: Dict;
  worktree: Dict | null;
}

function boundFields(base: string[], admission: Admission, execution: string[], worktree: string[]): string[] {
  return [...base, ...(mapped(admission.selection.bundle) ? execution : []), ...(admission.worktree ? worktree : [])];
}

function checkObservation(record: Dict, admission: Admission, prefix: string): void {
  if (mapped(admission.selection.bundle)) {
    require(record.execution_revision === admission.context.execution_revision, prefix + "_execution_revision_mismatch");
  }
  if (admission.worktree) {
    require(sameValue(record.worktree, admission.worktree) && record.policy_sha256 === (admission.context.policy as Dict).sha256, prefix + "_worktree_mismatch");
  }
}

function checkAuthority(admission: Admission, stage: string, gaps: Dict[]): void {
  try {
    const { context, selection } = admission;
    const authority = dict(context.authority, "independent_authority_required");
    const fields = boundFields(["status", "stage", "subject_sha256", "issuer", "goals"], admission, ["execution_revision"], ["worktree", "policy_sha256"]);
    require(keysEqual(authority, fields), "unsupported_authority_fields");
    checkObservation(authority, admission, "authority");
    require(authority.status === "pass" && authority.stage === stage && authority.subject_sha256 === selection.subject && string(authority.issuer), "independent_authority_required");
    require(Array.isArray(authority.goals) && selection.selected.every((id) => (authority.goals as unknown[]).includes(id)), "independent_authority_required");
  } catch (error) {
    add(gaps, "authority_unavailable", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
  }
}

function gateRoot(admission: Admission, gate: Dict): string {
  return gate.root === "execution" ? executionRoot(admission.selection.bundle, admission.root) : admission.root;
}

function applyDigests(admission: Admission, gates: Dict[], stage: string, resolved: Dict[]): void {
  for (const gate of gates) {
    if (gate.stage !== stage || gate.kind !== "file_digest") {
      continue;
    }
    fileRef(gateRoot(admission, gate), gate);
    resolved.push({
      gate: gate.id, stage, scope: gate.scope, status: "ready",
      source: { policy: POLICY, sha256: (admission.context.policy as Dict).sha256 },
      responsible: gate.responsible ?? "unassigned", evidence_refs: [],
      freshness: { observed_at: "current-file-read", expires_at: "not-declared" },
      recovery: "Retain while exact binding and freshness remain valid; does not authorize dispatch",
    });
  }
}

function notApplicable(policy: Dict, context: Dict, stage: string, resolved: Dict[], goals: string[]): void {
  const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
  const gates = Array.isArray(policy.gates) ? policy.gates as Dict[] : [];
  for (const dimension of Object.keys(exclusions).sort()) {
    const covered = gates.some((gate) => gate.stage === stage && text(gate.dimension) === dimension);
    if (covered) {
      continue;
    }
    resolved.push({
      gate: dimension, stage, scope: { goals }, status: "not_applicable",
      source: { policy: POLICY, sha256: (context.policy as Dict).sha256 }, responsible: "unassigned",
      evidence_refs: [], freshness: "current-policy-digest", recovery: "Reevaluate if repository policy changes",
      reason: exclusions[dimension],
    });
  }
}

const TYPED = new Set(["ownership", "branch_target", "fixture", "protected_approval", "harness_trust", "tooling"]);

function gateShape(gate: Dict): void {
  require(ID.test(text(gate.id)), "gate_id_required");
  require(STAGES.includes(text(gate.stage)) && string(gate.kind), "unknown_gate_stage_or_kind");
  const allowed = new Set(["id", "stage", "scope", "kind", "dimension", "responsible", "root"]);
  require(gate.root === undefined || gate.root === "planning" || gate.root === "execution", "invalid_gate_root");
  const kind = text(gate.kind);
  if (kind === "file_digest") {
    allowed.add("path");
    allowed.add("sha256");
  } else if (kind === "executable_presence") {
    allowed.add("path");
  } else if (TYPED.has(kind)) {
    allowed.add("binding");
    require(isDict(gate.binding), "typed_binding_required");
  }
  require(Object.keys(gate).every((key) => allowed.has(key)), "unsupported_gate_fields");
}

function explicitScope(scope: unknown, ids: string[]): boolean {
  if (!isDict(scope)) {
    return false;
  }
  if (Object.keys(scope).length === 1 && scope.repository === true) {
    return true;
  }
  return Object.keys(scope).length === 1 && Array.isArray(scope.goals) && scope.goals.length > 0
    && scope.goals.every((id) => typeof id === "string" && ids.includes(id));
}

function filesUnder(root: string, dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = resolve(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...filesUnder(root, path));
    } else if (entry.isFile()) {
      found.push(path.slice(root.length + 1));
    }
  }
  return found;
}

function instructionSources(root: string): string[] {
  const names = ["AGENTS.md", ".rules.ts"].filter((name) => isFile(resolve(root, name)));
  const rules = resolve(root, ".ai/rules");
  if (exists(rules) && statSync(rules).isDirectory()) {
    names.push(...filesUnder(root, rules));
  }
  return names;
}

function executable(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function measured(goal: Dict): boolean {
  const percent = goal.coverage_percent;
  return (goal.coverage_status ?? "measured") === "measured" && typeof percent === "number" && percent >= 0 && percent <= 100;
}

function applies(scope: unknown, id: string): boolean {
  if (scope === "repository") {
    return true;
  }
  if (Array.isArray(scope)) {
    return scope.includes(id);
  }
  return isDict(scope) && (scope.repository === true || (Array.isArray(scope.goals) && scope.goals.includes(id)));
}

function goalRevision(bundle: Dict, id: string): string {
  const goals = new Map((bundle.goals as Dict[]).map((goal) => [text(goal.id), goal]));
  require(goals.has(id), "unknown_goal_revision_subject");
  const revisions: Record<string, string> = {};
  const pending: [string, boolean][] = [[id, false]];
  while (pending.length > 0) {
    const [current, expanded] = pending.pop() as [string, boolean];
    if (current in revisions) {
      continue;
    }
    const goal = goals.get(current) as Dict;
    const deps = goal.dependencies as string[];
    if (!expanded) {
      pending.push([current, true]);
      pending.push(...deps.filter((dep) => !(dep in revisions)).map((dep): [string, boolean] => [dep, false]));
    } else {
      revisions[current] = canonical({ repository: bundle.repository, plan_id: bundle.id, spec: bundle.spec, goal,
        ...(mapped(bundle) ? { execution: bundle.execution } : {}),
        dependencies: Object.fromEntries([...deps].sort().map((dep) => [dep, revisions[dep]])) });
    }
  }
  return revisions[id] as string;
}

function evaluatedGoals(selection: Selection): Set<string> {
  const goals = new Map((selection.bundle.goals as Dict[]).map((goal) => [text(goal.id), goal]));
  const evaluated = new Set<string>();
  const pending = [...selection.selected];
  while (pending.length > 0) {
    const id = pending.pop() as string;
    if (!evaluated.has(id)) {
      evaluated.add(id);
      pending.push(...((goals.get(id) as Dict).dependencies as string[]));
    }
  }
  return evaluated;
}

function completionBinding(admission: Admission, receipt: Dict): string[] {
  const fields = boundFields(["goal", "goal_sha256", "status", "issuer", "evidence", "observed_at", "expires_at"], admission, ["execution_revision"], ["integration_commit", "execution_commit"]);
  if (mapped(admission.selection.bundle)) {
    require(REVISION.test(text(admission.context.execution_revision)) && receipt.execution_revision === admission.context.execution_revision, "completion_execution_revision");
  }
  if (admission.worktree) {
    require(REVISION.test(text(receipt.execution_commit)), "completion_execution_required");
    require(REVISION.test(text(receipt.integration_commit)), "completion_integration_required");
    gitRead(text(admission.worktree.root), "merge-base", "--is-ancestor", text(receipt.integration_commit), text(admission.worktree.base_commit));
  }
  return fields;
}

function dependencyComplete(admission: Admission, id: string): boolean {
  const supplied = admission.context.completed_goals;
  const receipts = Array.isArray(supplied) ? supplied.filter(isDict).filter((receipt) => receipt.goal === id) : [];
  if (receipts.length !== 1) {
    return false;
  }
  try {
    const receipt = receipts[0] as Dict;
    require(keysEqual(receipt, completionBinding(admission, receipt)), "completion_fields");
    require(receipt.status === "complete" && receipt.goal_sha256 === goalRevision(admission.selection.bundle, id), "completion_revision");
    provenance(receipt);
    return true;
  } catch {
    return false;
  }
}

function provenance(receipt: Dict): void {
  require(string(receipt.issuer) && Array.isArray(receipt.evidence) && receipt.evidence.length > 0 && receipt.evidence.every(string), "evidence_provenance_required");
  require(string(receipt.observed_at) && string(receipt.expires_at), "evidence_freshness_required");
  const timezone = /(?:Z|[+-]\d{2}:\d{2})$/;
  require(timezone.test(text(receipt.observed_at)) && timezone.test(text(receipt.expires_at)), "evidence_expired_or_future");
  const now = Date.now();
  require(Date.parse(text(receipt.observed_at)) <= now && now < Date.parse(text(receipt.expires_at)), "evidence_expired_or_future");
}

function gateSubject(admission: Admission, gate: Dict): string {
  const { bundle } = admission.selection;
  const binding: Dict = {};
  if (mapped(bundle)) {
    require(REVISION.test(text(admission.context.execution_revision)), "gate_execution_revision_required");
    binding.execution = bundle.execution;
    binding.execution_revision = admission.context.execution_revision;
  }
  if (admission.worktree) {
    binding.worktree = admission.worktree;
  }
  const ids = (bundle.goals as Dict[]).map((goal) => text(goal.id)).filter((id) => applies(gate.scope, id)).sort();
  return canonical({ ...binding, repository: bundle.repository, plan_id: bundle.id, gate,
    policy_sources: admission.context.sources, policy: admission.context.policy,
    goals: Object.fromEntries(ids.map((id) => [id, goalRevision(bundle, id)])) });
}

function independentResult(admission: Admission, gate: Dict): void {
  const results = (admission.context.results as Dict[]).filter((result) => result.gate === gate.id);
  require(results.length === 1, "independent_result_missing_or_ambiguous");
  const receipt = results[0] as Dict;
  require(keysEqual(receipt, boundFields(["gate", "status", "stage", "scope", "subject_sha256", "issuer"], admission, ["execution_revision"], ["worktree", "policy_sha256"])), "unsupported_result_fields");
  checkObservation(receipt, admission, "result");
  require(receipt.status === "pass" && receipt.stage === gate.stage && sameValue(receipt.scope, gate.scope) && receipt.subject_sha256 === admission.selection.subject && string(receipt.issuer), "independent_result_invalid");
}

const BINDING_FIELDS: Record<string, string[]> = {
  ownership: ["roles"], branch_target: ["target", "branch"], fixture: ["file", "command", "isolation", "tool"],
  tooling: ["tool"], protected_approval: ["subject"], harness_trust: ["lock", "anchor"],
};

function branchBinding(admission: Admission, binding: Dict): void {
  require(["target", "branch"].every((key) => string(binding[key]) && !/[\s;&|`$<>]/.test(text(binding[key]))), "target_branch_required");
  if (admission.worktree) {
    require(binding.target === admission.worktree.target_ref && binding.branch === admission.worktree.branch, "worktree_branch_target_mismatch");
  }
}

function toolBinding(binding: Dict): void {
  const tool = text(binding.tool);
  require(string(tool) && /^[A-Za-z0-9_.+-]+$/.test(tool), "tool_name_required");
  const available = text(process.env.PATH).split(":").some((directory) => {
    const path = resolve(directory, tool);
    return isFile(path) && executable(path);
  });
  require(available, "tool_unavailable:" + tool);
}

function fixtureBinding(root: string, binding: Dict): void {
  require(keysEqual(dict(binding.file, "fixture_file_ref_required"), ["path", "sha256"]), "fixture_file_ref_required");
  fileRef(root, binding.file);
  require(["disposable-database", "transaction-rollback", "temporary-directory", "container"].includes(text(binding.isolation)), "fixture_isolation_required");
  require(typeof binding.command === "string", "fixture_command_required");
  validateCommands(root, [binding.command]);
  require(executable(relativePath(root, (binding.file as Dict).path)), "fixture_not_executable");
  toolBinding(binding);
}

function approvalBinding(admission: Admission, root: string, gate: Dict, binding: Dict): void {
  const subject = dict(binding.subject, "approval_subject_required");
  require(["full-file", "goal-scope"].includes(text(subject.mode)), "approval_subject_required");
  if (subject.mode === "full-file") {
    require(keysEqual(subject, ["mode", "file"]), "approval_subject_fields");
    require(keysEqual(dict(subject.file, "approval_file_ref_required"), ["path", "sha256"]), "approval_file_ref_required");
    fileRef(root, subject.file);
  } else {
    require(keysEqual(subject, ["mode", "goal", "goal_sha256"]) && typeof subject.goal === "string", "approval_goal_subject_mismatch");
    require(applies(gate.scope, text(subject.goal)) && subject.goal_sha256 === goalRevision(admission.selection.bundle, text(subject.goal)), "approval_goal_subject_mismatch");
  }
}

function sameFile(left: string, right: string): boolean {
  const a = statSync(left);
  const b = statSync(right);
  return a.dev === b.dev && a.ino === b.ino;
}

function trustSources(root: string, binding: Dict): { lock: Dict; anchor: Dict } {
  const lock = dict(binding.lock, "trust_sources_required");
  const anchor = dict(binding.anchor, "trust_sources_required");
  require([lock, anchor].every((ref) => keysEqual(ref, ["path", "sha256"])), "trust_sources_required");
  require(lock.path !== anchor.path, "trust_anchor_not_independent");
  try {
    fileRef(root, lock);
    fileRef(root, anchor);
  } catch (error) {
    throw new Invalid("trust_source_unavailable:expected=unavailable:actual=unverified:independent_source=" + text(anchor.path) + ":" + String(error));
  }
  require(!sameFile(relativePath(root, lock.path), relativePath(root, anchor.path)), "trust_anchor_not_independent");
  return { lock, anchor };
}

function trustBinding(admission: Admission, root: string, gate: Dict, binding: Dict): void {
  const { lock, anchor } = trustSources(root, binding);
  const spec = admission.selection.bundle.spec as Dict;
  require(anchor.sha256 !== spec.sha256 && !sameFile(relativePath(root, anchor.path), relativePath(admission.root, spec.path)), "trust_anchor_is_plan_source");
  const sources = gate.root === "execution" ? (admission.context.execution as Dict).sources : admission.context.sources;
  require((sources as Dict[]).some((source) => sameValue(source, anchor)), "trust_anchor_not_independently_approved");
  const data = dict(read(relativePath(root, anchor.path)), "trust_anchor_is_plan_source");
  require(!["goals", "bundle", "readiness", "planning_complete"].some((key) => key in data), "trust_anchor_is_plan_source");
  require(keysEqual(data, ["commit"]), "unsupported_trust_anchor_shape");
  const expected = text(data.commit);
  const actual = text((read(relativePath(root, lock.path)) as Dict).commit);
  require(REVISION.test(expected), "trust_expected_commit_unavailable");
  require(REVISION.test(actual), "trust_actual_commit_unavailable");
  require(expected === actual, "trust_commit_mismatch:expected=" + expected + ":actual=" + actual + ":independent_source=" + text(anchor.path));
}

function typedBinding(admission: Admission, gate: Dict): Dict {
  const binding = dict(gate.binding, "typed_binding_required");
  const kind = text(gate.kind);
  require(keysEqual(binding, BINDING_FIELDS[kind] ?? []), "unsupported_typed_binding");
  const root = gateRoot(admission, gate);
  switch (kind) {
    case "ownership": ownershipBinding(binding); break;
    case "branch_target": branchBinding(admission, binding); break;
    case "fixture": fixtureBinding(root, binding); break;
    case "tooling": toolBinding(binding); break;
    case "protected_approval": approvalBinding(admission, root, gate, binding); break;
    case "harness_trust": trustBinding(admission, root, gate, binding); break;
  }
  return binding;
}

function ownershipBinding(binding: Dict): void {
  const roles = binding.roles;
  require(Array.isArray(roles) && roles.length > 0 && roles.every((role) => ["owner", "reviewer"].includes(text(role))), "ownership_roles_required");
  require(new Set(roles as string[]).size === (roles as string[]).length, "ownership_roles_required");
}

function typedGate(admission: Admission, gate: Dict): void {
  const binding = typedBinding(admission, gate);
  const results = (admission.context.results as Dict[]).filter((receipt) => receipt.gate === gate.id);
  require(results.length === 1, "typed_evidence_missing_or_ambiguous");
  const receipt = results[0] as Dict;
  require(keysEqual(receipt, ["gate", "status", "stage", "scope", "subject_sha256", "issuer", "evidence", "observed_at", "expires_at", "value"]), "typed_evidence_fields");
  require(receipt.status === "pass" && receipt.stage === gate.stage && sameValue(receipt.scope, gate.scope) && receipt.subject_sha256 === gateSubject(admission, gate), "typed_evidence_subject_mismatch");
  provenance(receipt);
  if (gate.kind === "ownership") {
    const value = dict(receipt.value, "named_ownership_required");
    require(keysEqual(value, binding.roles as string[]) && Object.values(value).every((name) => string(name) && !["tbd", "unknown", "unassigned", "placeholder"].includes(text(name).trim().toLowerCase())), "named_ownership_required");
  } else {
    require(sameValue(receipt.value, binding), "typed_observation_mismatch");
  }
}

function runExtraGate(admission: Admission, gate: Dict): boolean {
  const root = gateRoot(admission, gate);
  switch (gate.kind) {
    case "executable_presence": {
      const path = relativePath(root, gate.path);
      require(isFile(path) && executable(path), "executable_unavailable");
      return true;
    }
    case "measured_coverage":
      require((admission.selection.bundle.goals as Dict[]).filter((goal) => applies(gate.scope, text(goal.id))).every(measured), "measured_coverage_required");
      return true;
    case "independent_result": independentResult(admission, gate); return true;
    default:
      if (TYPED.has(text(gate.kind))) {
        typedGate(admission, gate);
        return true;
      }
      return false;
  }
}

function resolvedGate(admission: Admission, gate: Dict, stage: string): Dict {
  const receipt = (admission.context.results as Dict[]).find((result) => result.gate === gate.id) ?? {};
  const refs = Array.isArray(receipt.evidence) ? receipt.evidence : [];
  return { gate: gate.id, stage, scope: gate.scope, status: "ready",
    source: { policy: POLICY, sha256: (admission.context.policy as Dict).sha256 }, responsible: gate.responsible ?? "unassigned",
    evidence_refs: refs.map((ref) => String(ref).replace(/https?:\/\/\S+/g, "[redacted-url]")),
    freshness: { observed_at: receipt.observed_at ?? "current-file-read", expires_at: receipt.expires_at ?? "not-declared" },
    recovery: "Retain while exact binding and freshness remain valid; does not authorize dispatch" };
}

function extraGates(admission: Admission, gates: Dict[], stage: string, gaps: Dict[], resolved: Dict[]): void {
  for (const gate of gates) {
    if (gate.stage !== stage || gate.kind === "file_digest") {
      continue;
    }
    try {
      if (runExtraGate(admission, gate)) {
        resolved.push(resolvedGate(admission, gate, stage));
      } else {
        add(gaps, "unsupported_gate", text(gate.kind), gate.scope, stage, "unknown");
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      const unavailable = ["unavailable", "missing", "required", "No such file"].some((token) => message.includes(token));
      add(gaps, "gate_failed", text(gate.id) + ":" + message, gate.scope, stage, unavailable ? "unknown" : "blocked");
    }
  }
}

function contextShape(admission: Admission): void {
  const { context } = admission;
  require(context.schema === "readiness-context/1", "independent_context_required");
  const allowed = boundFields(["schema", "repository", "policy", "sources", "authority", "results", "completed_goals", "extensions"], admission, ["execution", "execution_revision"], ["worktree"]);
  require(Object.keys(context).every((key) => allowed.includes(key)), "unsupported_context_fields");
  require(Array.isArray(context.results) && context.results.every(isDict), "invalid_independent_results");
  require(Array.isArray(context.completed_goals) && context.completed_goals.every(isDict), "invalid_completed_goals");
  repository(context.repository, admission.identity);
}

function policyBinding(admission: Admission, policy: Dict): void {
  const { bundle } = admission.selection;
  const { context, worktree } = admission;
  const allowed = boundFields(["schema", "repository", "sources", "gates", "not_applicable", "extensions"], admission, ["execution"], ["worktree"]);
  require(Object.keys(policy).every((key) => allowed.includes(key)), "unsupported_policy_fields");
  require(sameValue(policy.repository, bundle.repository) && sameValue(bundle.repository, context.repository), "policy_repository_mismatch");
  if (mapped(bundle)) {
    require(sameValue(policy.execution, bundle.execution) && sameValue(bundle.execution, context.execution), "execution_mapping_mismatch");
    require(REVISION.test(text(context.execution_revision)), "execution_revision_required");
  }
  if (worktree) {
    require(sameValue(policy.worktree, worktreeBinding(worktree)), "worktree_policy_mismatch");
    require(sameValue(context.worktree, worktree), "worktree_context_mismatch");
  }
}

function policySources(admission: Admission, policy: Dict): void {
  const { context, root } = admission;
  const approved = dict(context.policy, "unapproved_policy_revision");
  require(keysEqual(approved, ["sha256", "revision", "issuer"]), "unsupported_approval_fields");
  require(approved.sha256 === digestFile(relativePath(root, POLICY)) && string(approved.issuer) && string(approved.revision), "unapproved_policy_revision");
  const sources = policy.sources;
  require(Array.isArray(sources) && sources.length > 0 && sameValue(sources, context.sources), "policy_source_set_mismatch");
  const listed = new Set((sources as Dict[]).map((source) => text(source.path)));
  require(listed.size === (sources as Dict[]).length, "duplicate_policy_sources");
  const required = new Set(instructionSources(root));
  if (admission.worktree) {
    instructionPaths(admission.selection.bundle, root).forEach((name) => required.add(name));
  }
  require([...required].every((name) => listed.has(name)), "policy_source_set_incomplete");
  for (const source of sources as Dict[]) {
    fileRef(root, source);
  }
}

function gateDimensions(gate: Dict): string[] {
  const dimensions = string(gate.dimension) ? [text(gate.dimension)] : [];
  if (gate.kind === "ownership") {
    const roles = (gate.binding as Dict).roles;
    if (Array.isArray(roles)) {
      dimensions.push(...roles.filter((role) => role === "owner" || role === "reviewer").map((role) => role === "owner" ? "owners" : "reviewer"));
    }
  } else {
    const dimensionsByKind: Record<string, string> = { branch_target: "branch_target", fixture: "fixtures", tooling: "tooling", protected_approval: "registration_approval", harness_trust: "harness_trust" };
    const dimension = dimensionsByKind[text(gate.kind)];
    if (dimension) {
      dimensions.push(dimension);
    }
  }
  return dimensions;
}

function mappedTargetGates(admission: Admission, gates: Dict[], exclusions: Dict, stage: string): void {
  if (!mapped(admission.selection.bundle) || !["implementation", "merge"].includes(stage)) {
    return;
  }
  require(!("branch_target" in exclusions), "mapped_branch_target_cannot_be_exempted");
  for (const id of evaluatedGoals(admission.selection)) {
    const targets = gates.filter((gate) => gate.kind === "branch_target" && gate.stage === stage && applies(gate.scope, id));
    require(targets.length > 0 && targets.every((gate) => (gate.binding as Dict).target === (admission.selection.bundle.execution as Dict).target), "mapped_branch_target_required");
  }
}

function policyGates(admission: Admission, policy: Dict, stage: string): Dict[] {
  const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
  require(Object.entries(exclusions).every(([key, value]) => string(key) && string(value)), "explicit_not_applicable_reasons_required");
  require(Array.isArray(policy.gates), "policy_gates_required");
  const gates = policy.gates as Dict[];
  const ids = (admission.selection.bundle.goals as Dict[]).map((goal) => text(goal.id));
  for (const gate of gates) {
    gateShape(gate);
    require(explicitScope(gate.scope, ids), "explicit_gate_scope_required");
  }
  const covered = new Set(gates.flatMap(gateDimensions));
  require(DIMENSIONS.every((item) => item in exclusions || covered.has(item)), "policy_dimensions_required");
  require(!Object.keys(exclusions).some((item) => covered.has(item)), "contradictory_policy_dimension");
  require(new Set(gates.map((gate) => gate.id)).size === gates.length, "duplicate_policy_gate_ids");
  require(mapped(admission.selection.bundle) || gates.every((gate) => gate.root !== "execution"), "execution_requires_mapped_schema");
  mappedTargetGates(admission, gates, exclusions, stage);
  return gates;
}

function policyOk(admission: Admission, stage: string, gaps: Dict[], resolved: Dict[]): void {
  const { root, context, selection } = admission;
  const { bundle } = selection;
  contextShape(admission);
  const policy = dict(read(relativePath(root, POLICY)), "unsupported_policy_schema");
  require(policy.schema === "readiness-policy/1", "unsupported_policy_schema");
  policyBinding(admission, policy);
  policySources(admission, policy);
  const gates = policyGates(admission, policy, stage);
  const ids = (bundle.goals as Dict[]).map((goal) => text(goal.id));
  notApplicable(policy, context, stage, resolved, ids);
  checkAuthority(admission, stage, gaps);
  applyDigests(admission, gates, stage, resolved);
  extraGates(admission, gates, stage, gaps, resolved);
  for (const goal of bundle.goals as Dict[]) {
    coverage(goal, gaps, stage);
  }
}

function validRequirement(gate: unknown): gate is Dict {
  return isDict(gate) && string(gate.id) && ID.test(text(gate.id)) && STAGES.includes(text(gate.stage)) && string(gate.kind);
}

function goalRequirements(goal: Dict, gaps: Dict[], stage: string): void {
  const requirements = goal.requirements ?? [];
  if (!Array.isArray(requirements)) {
    add(gaps, "goal_requirement_invalid", "Expected requirement array", [goal.id], stage);
    return;
  }
  for (const gate of requirements) {
    if (!validRequirement(gate)) {
      add(gaps, "goal_requirement_invalid", "Requires id, stage and typed kind", [goal.id], stage);
      continue;
    }
    try {
      gateShape(gate);
    } catch (error) {
      add(gaps, "goal_requirement_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage);
    }
  }
}

function goalGaps(root: string, goal: Dict, gaps: Dict[], stage: string): void {
  coverage(goal, gaps, stage);
  goalRequirements(goal, gaps, stage);
  const readiness = goal.readiness as Dict;
  if (readiness[stage] !== "ready") {
    const status = readiness[stage] === "unknown" ? "unknown" : "blocked";
    add(gaps, "goal_not_ready", readiness[stage], [goal.id], stage, status);
  }
  try {
    validateCommands(root, goal.verification);
  } catch (error) {
    add(gaps, "verification_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage);
  }
}

function executionSelection(args: Args, selected: Selection): void {
  const { bundle } = selected;
  if (mapped(bundle)) {
    require(Boolean(args.execution_root), "execution_root_required");
  }
  if (args.execution_root) {
    require(mapped(bundle) && args.execution_root === executionRoot(bundle, ""), "execution_root_mismatch");
  }
  if (args.execution_record) {
    const records = (bundle.goals as Dict[]).filter((goal) => selected.selected.includes(text(goal.id)));
    require(records.length === 1 && sameValue(read(args.execution_record), records[0]), "execution_record_mismatch");
  }
}

function admissionWorktree(identity: string, root: string, args: Args, selected: Selection): { worktree: Dict | null; inputs: string[] } {
  if (!args.worktree_root) {
    return { worktree: null, inputs: [] };
  }
  require(!mapped(selected.bundle), "worktree_mapped_conflict");
  const inputs = worktreeInputs(selected.bundle, root);
  if (args.goal) {
    inputs.push(args.goal.slice(root.length + 1));
  }
  return { worktree: worktreeObservation(identity, root, text(args.base_commit), args.stage === "merge", inputs), inputs };
}

function reportSelection(report: Dict, selected: Selection): void {
  report.plan_id = selected.bundle.id;
  report.repository = selected.bundle.repository;
  report.bundle = { schema: selected.bundle.schema, id: selected.bundle.id, canonical_sha256: canonical(selected.bundle) };
  report.specification = selected.bundle.spec;
  report.goals = selected.selected;
  report.planning_complete = selected.bundle.planning_complete;
  report.handoff = selected.entry;
  report.subject_sha256 = selected.subject;
}

function fillReport(identity: string, args: Args, report: Dict, stage: string): void {
  const { root } = worktreeRequest(args, identity);
  const required = [MANIFEST, GRAPH, ".ai/matrix.json"];
  require(required.every((name) => isFile(resolve(root, name))), "v3_root_required");
  require(required.every((name) => isDict(read(relativePath(root, name)))), "v3_root_malformed");
  const selected = select(identity, args, root);
  const { worktree, inputs } = admissionWorktree(identity, root, args, selected);
  if (worktree) {
    report.worktree = worktree;
  }
  executionSelection(args, selected);
  reportSelection(report, selected);
  const context = args.context ? read(args.context) as Dict : {};
  const admission: Admission = { identity, root, selection: selected, context, worktree };
  collectReport(admission, args, report, stage, inputs);
}

function collectReport(admission: Admission, args: Args, report: Dict, stage: string, inputs: string[]): void {
  const { selection: selected, context, worktree, identity, root } = admission;
  if (mapped(selected.bundle)) {
    report.execution = selected.bundle.execution;
    report.execution_revision = context.execution_revision ?? null;
    report.execution_revision_source = "independent-context";
  }
  const gaps = report.gaps as Dict[];
  const resolved = report.resolved as Dict[];
  const stages = stage === "planning" ? ["preparation", "implementation", "merge"] : [stage];
  for (const item of stages) {
    collectGaps(admission, item, gaps, resolved);
  }
  scopeGoals(gaps, selected.selected);
  report.per_goal = perGoal(selected.selected, gaps, resolved, stages);
  if (worktree) {
    require(sameValue(worktree, worktreeObservation(identity, root, text(args.base_commit), args.stage === "merge", inputs)), "worktree_changed_during_validation");
  }
  report.execution_ready = stage !== "planning" && gaps.length === 0;
}

function dependencyGaps(admission: Admission, gaps: Dict[], stage: string): void {
  const evaluated = evaluatedGoals(admission.selection);
  for (const goal of admission.selection.bundle.goals as Dict[]) {
    if (!evaluated.has(text(goal.id))) {
      continue;
    }
    for (const dependency of goal.dependencies as string[]) {
      if (!dependencyComplete(admission, dependency)) {
        add(gaps, "dependency_incomplete", dependency, [goal.id], stage);
      }
    }
  }
}

function collectGaps(admission: Admission, stage: string, gaps: Dict[], resolved: Dict[]): void {
  try {
    const { selection: selected, root } = admission;
    for (const goal of selected.bundle.goals as Dict[]) {
      if (selected.selected.includes(text(goal.id))) {
        goalGaps(executionRoot(selected.bundle, root), goal, gaps, stage);
      }
    }
    dependencyGaps(admission, gaps, stage);
    policyOk(admission, stage, gaps, resolved);
  } catch (error) {
    add(gaps, "policy_context_invalid", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
  }
}

export function admit(args: Args): Dict {
  const root = pyPath(String(args.root ?? "."));
  const stage = args.stage ?? "implementation";
  const report: Dict = {
    schema: VERSION, stage, repository_root: root, planning_complete: false, execution_ready: false,
    dispatch_authorized: false, authority_verification: "external-required", goals: args.goal_id ?? [], gaps: [], resolved: [],
  };
  try {
    fillReport(root, args, report, stage);
  } catch (error) {
    add(report.gaps as Dict[], "admission_failed", error instanceof Error ? error.message : String(error), "repository", stage);
  }
  report.remaining_blockers = report.gaps;
  return report;
}

function scopeGoals(gaps: Dict[], selected: string[]): void {
  for (const gap of gaps) {
    gap.blocked_goals = selected;
    if (gap.scope !== "repository") {
      gap.scope = { goals: selected };
    }
  }
}

function perGoal(selected: string[], gaps: Dict[], resolved: Dict[], stages: string[]): Dict {
  const out: Dict = {};
  for (const id of selected) {
    const record: Dict = {};
    for (const stage of stages) {
      const findings = gaps.filter((gap) => gap.stage === stage);
      const extra = resolved.filter((item) => item.stage === stage);
      const status = findings.some((gap) => gap.status === "blocked") ? "blocked" : findings.length > 0 ? "unknown" : "ready";
      record[stage] = { status, findings: [...findings, ...extra] };
    }
    out[id] = record;
  }
  return out;
}

export function migrate(args: Args): Dict {
  const root = pyPath(String(args.root ?? "."));
  const legacy = read(String(args.legacy));
  const supplied = read(String(args.bundle)) as Dict;
  bundleShape(supplied, root);
  const bundle = structuredClone(supplied);
  const extensions = isDict(bundle.extensions) ? bundle.extensions : {};
  require(!("legacy_original" in extensions), "migration_extension_collision");
  extensions.legacy_original = legacy;
  extensions.legacy_sha256 = digestFile(String(args.legacy));
  bundle.extensions = extensions;
  for (const goal of bundle.goals as Dict[]) {
    goal.readiness = { preparation: "unknown", implementation: "unknown", merge: "unknown" };
  }
  return { schema: VERSION, bundle, dispatch_authorized: false, execution_ready: false, authority_verification: "external-required", next: "Review retained evidence; publish explicitly; revalidate independently" };
}

export function main(argv: string[]): number {
  try {
    const args = parseArgs(argv);
    const result = runOperation(args);
    process.stdout.write(dumps(result, 2, true) + "\n");
    return resultExit(args, result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.startsWith("invalid choice:")) {
      return 2;
    }
    process.stdout.write(dumps({ schema: VERSION, error: message, execution_ready: false, dispatch_authorized: false, authority_verification: "external-required" }) + "\n");
    return 1;
  }
}

function runOperation(args: Args): Dict {
  if (args.operation === "publish") {
    return publish(args);
  }
  return args.operation === "migrate" ? migrate(args) : admit(args);
}

function resultExit(args: Args, result: Dict): number {
  const gaps = Array.isArray(result.gaps) ? result.gaps : [];
  const planning = args.stage === "planning" && result.planning_complete === true && "per_goal" in result;
  return gaps.length > 0 && !planning ? 1 : 0;
}

function assignFlag(args: Args, flag: string, value: string | undefined, index: number): number {
  if (!flag.startsWith("--") || value === undefined) {
    return index;
  }
  const key = flag.slice(2).replaceAll("-", "_");
  (args as Dict)[key] = value;
  return index + 1;
}

function parseOperation(operation: string | undefined): string {
  if (!["admit", "publish", "migrate"].includes(operation ?? "")) {
    const shown = operation ?? "";
    process.stderr.write("invalid choice: '" + shown + "' (choose from 'admit', 'publish', 'migrate')\n");
    throw new Invalid("invalid choice: '" + shown + "' (choose from 'admit', 'publish', 'migrate')");
  }
  return operation as string;
}

function parseFlags(args: Args, argv: string[]): void {
  for (let index = 1; index < argv.length; index += 1) {
    const flag = argv[index] ?? "";
    const value = argv[index + 1];
    if (flag === "--goal-id" && value !== undefined) {
      args.goal_id = [...(args.goal_id ?? []), value];
      index += 1;
    } else {
      index = assignFlag(args, flag, value, index);
    }
  }
}

function parseArgs(argv: string[]): Args {
  const args: Args = { root: ".", stage: "implementation", goal_id: null, operation: parseOperation(argv[0]) };
  parseFlags(args, argv);
  const stages = ["planning", "preparation", "implementation", "merge"];
  if (!stages.includes(args.stage ?? "")) {
    const shown = args.stage ?? "";
    process.stderr.write("error: argument --stage: invalid choice: '" + shown + "' (choose from 'planning', 'preparation', 'implementation', 'merge')\n");
    throw new Invalid("invalid choice: --stage " + shown);
  }
  return args;
}
