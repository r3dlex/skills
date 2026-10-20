import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import { accessSync, closeSync, constants, fsyncSync, lstatSync, mkdirSync, mkdtempSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmdirSync, rmSync, statSync, writeFileSync, type Dirent } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { canonical, compare, digest, dumps, equal, Float, hashable, ID, Invalid, match, numeric, parse, pyKey, pyStr, read, redactText, require, REVISION, SHA, string, strip, typeName, VERSION, whitespace, type Args } from "./json.mjs";
import { osError, pyRepr, shlexSplit, validate as validateCommands } from "./verification.mjs";

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
  return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof Float);
}

function dict(value: unknown, message: string): Dict {
  if (!isDict(value)) {
    throw new Invalid(message);
  }
  return value;
}

function pythonDict(value: unknown): Dict {
  if (!isDict(value)) throw new TypeError("'" + typeName(value) + "' object has no attribute 'get'");
  return value;
}

function get(record: Dict, key: string, fallback: unknown): unknown {
  return Object.hasOwn(record, key) ? record[key] : fallback;
}

function field(record: Dict, key: string): unknown {
  if (!Object.hasOwn(record, key)) throw new Error(pyRepr(key));
  return record[key];
}

function iterable(value: unknown): unknown[] {
  if (Array.isArray(value)) return value;
  if (typeof value === "string") return Array.from(value);
  if (isDict(value)) return Object.keys(value);
  throw new TypeError("'" + typeName(value) + "' object is not iterable");
}

function contains(value: unknown, item: unknown): boolean {
  if (Array.isArray(value)) return value.some((entry) => sameValue(entry, item));
  if (isDict(value)) { hashable(item); return typeof item === "string" && Object.hasOwn(value, item); }
  if (typeof value === "string") {
    if (typeof item !== "string") throw new TypeError("'in <string>' requires string as left operand, not " + typeName(item));
    return value.includes(item);
  }
  throw new TypeError("argument of type '" + typeName(value) + "' is not iterable");
}

function append(value: unknown, item: unknown): void {
  if (!Array.isArray(value)) throw new TypeError("'" + typeName(value) + "' object has no attribute 'append'");
  value.push(item);
}

function startsWith(value: unknown, prefix: string): boolean {
  if (typeof value !== "string") throw new TypeError("'" + typeName(value) + "' object has no attribute 'startswith'");
  return value.startsWith(prefix);
}

function unsafeTarget(value: string): boolean { return Array.from(value).some(whitespace) || /[;&|`$<>]/.test(value); }

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
  return Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));
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
  if (text.includes("\0")) throw new TypeError("embedded null byte");
  let resolved: string;
  try { resolved = mustExist ? realpathSync(path) : resolveMissing(path); }
  catch (error) { throw new Error(osError(error), { cause: error }); }
  require(resolved !== root && inside(root, resolved), "outside_root:" + text);
  return path;
}

function resolveMissing(path: string): string {
  if (exists(path)) return realpathSync(path);
  const parent = resolve(path, "..");
  return resolve(resolveMissing(parent), path.slice(parent.length + 1));
}

function fileRef(root: string, value: unknown): void {
  const record = dict(value, "file_digest_required");
  require(match(SHA, "sha256" in record ? record.sha256 : ""), "file_digest_required");
  const path = relativePath(root, record.path);
  require(isFile(path) && digestFile(path) === record.sha256, "stale_file:" + text(record.path));
}

function repository(value: unknown, root: string): void {
  const record = dict(value, "repository_id_required");
  require(match(ID, "id" in record ? record.id : ""), "repository_id_required");
  require(record.root === root, "repository_root_mismatch");
}

function stringList(goal: Dict, key: string): string[] {
  const list = goal[key];
  require(Array.isArray(list) && list.length > 0 && list.every((item) => string(item)), key + "_required");
  return list as string[];
}

function goalShape(goal: unknown, root: string, filesRoot = root): void {
  const record = dict(goal, "goal_id_required");
  require(match(ID, "id" in record ? record.id : ""), "goal_id_required");
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
  require(keysEqual(readiness, STAGES), "stage_readiness_required");
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
  require(new Set(records.map((source) => pyKey(source.path))).size === records.length, "duplicate_execution_sources");
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
  require(string(binding.target) && !unsafeTarget(text(binding.target)), "execution_target_required");
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
    const child = resolve(path, entry.name);
    if (entry.isDirectory()) {
      directories.add(child);
      collectDirectories(child, directories);
    } else if (isDirectory(child)) directories.add(child);
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
  require(match(ID, "id" in record ? record.id : ""), "bundle_id_required");
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
  for (const entry of worktreeDirectory(dir)) {
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

function worktreeDirectory(path: string): Dirent[] {
  try { return readdirSync(path, { withFileTypes: true }); }
  catch { throw new Invalid("worktree_unreadable_directory"); }
}

function worktreeState(root: string, paths: Set<string>): unknown[][] {
  return [...paths].sort(compare).map((name) => {
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
  const entries: Dict = Object.create(null) as Dict;
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
  return [...paths].sort(compare);
}

function sameValue(left: unknown, right: unknown): boolean {
  return equal(left, right);
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
      nextById.set(pyKey(item.id), item);
    }
  }
  for (const item of previous) {
    const id = item.id;
    const key = pyKey(id);
    require(nextById.has(key), "enrichment_loss:" + path);
    if (typeof id !== "string") throw new TypeError('can only concatenate str (not "' + typeName(id) + '") to str');
    preserve(item, nextById.get(key), path + "/" + id);
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
  const nodes = iterable(get(graph, "nodes", []));
  require(nodes.length === Object.keys(expected).length && new Set(nodes.map((node) => pyKey(get(pythonDict(node), "id", null)))).size === nodes.length && nodes.every((node) => Object.hasOwn(expected, pyKey(get(pythonDict(node), "id", null)))), "generation_collision:nodes");
  require(nodes.every((value) => {
    const node = pythonDict(value);
    const want = expected[pyKey(node.id)] ?? {};
    return Object.entries(want).every(([key, value]) => sameValue(get(node, key, null), value));
  }) && sameValue(graph.edges, edges), "generation_collision:graph");
}

function validateGeneration(root: string, prefix: string, bundle: Dict, generation: string, spec: Dict): Dict {
  const names = ["goals.json", "graph.json", "handoff.md"];
  const paths = Object.fromEntries(names.map((name) => [name, relativePath(root, prefix + "/" + name)]));
  require(names.every((name) => isFile(paths[name] ?? "")), "generation_collision:non-file");
  const goalsPath = paths["goals.json"] ?? "";
  const graphPath = paths["graph.json"] ?? "";
  const handoffPath = paths["handoff.md"] ?? "";
   require(sameValue(read(goalsPath), bundle) && readFileSync(handoffPath, "utf8").replace(/\r\n?/g, "\n") === handoffText(bundle), "generation_collision:payload");
  const graph = pythonDict(read(graphPath));
  const goalIds = (bundle.goals as Dict[]).map((goal) => text(goal.id));
  require(graph.generation === generation && graph.plan_id === bundle.id && sameValue(graph.goal_ids, goalIds) && match(SHA, get(graph, "source_graph_sha256", "")), "generation_collision:identity");
  const repo = text((bundle.repository as Dict).id);
  const parent = "handoff:" + repo + ":" + text(bundle.id) + ":" + generation;
  const expected: Record<string, Dict> = {
    [pyKey(field(spec, "id"))]: { id: spec.id, type: field(spec, "type"), repo_id: field(spec, "repo_id"), path: field(spec, "path"), backlinks: [parent] },
    [pyKey(parent)]: { id: parent, type: "handoff", repo_id: repo, path: prefix + "/handoff.md", backlinks: [spec.id] },
  };
  const edges: Dict[] = [{ source: spec.id, target: parent, type: "plans" }];
  for (const goal of bundle.goals as Dict[]) {
    const goalId = "plan:" + repo + ":" + text(bundle.id) + ":" + text(goal.id) + ":" + generation;
    expected[pyKey(goalId)] = { id: goalId, type: "plan", repo_id: repo, path: prefix + "/goals.json", backlinks: [parent] };
    (expected[pyKey(parent)]?.backlinks as string[]).push(goalId);
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
  const temporary = resolve(path, "..", ".readiness-" + randomUUID());
  closeSync(openSync(temporary, "wx", 0o600));
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
  const base = relativePath(root, `${GEN}/${String(record.id)}`, false);
  mkdirSync(base, { recursive: true });
  const lock = resolve(relativePath(root, ".ai/workflows"), ".northstar-readiness-v1.lock");
  try {
    mkdirSync(lock);
  } catch {
    throw new Invalid("publication_locked:inspect existing publisher; never steal a lock");
  }
  try {
    return publishLocked(identity, root, candidate, candidateHash, record, generation, base, args, observation);
  } finally {
    rmdirSync(lock);
  }
}

function previousRegistration(root: string, registry: Dict, registration: string, bundle: Dict): { plans: Dict[]; previous: Dict | undefined } {
  const plans = registry.plans as Dict[];
  const matches = plans.filter((item) => pythonDict(item).id === registration);
  require(matches.length <= 1, "duplicate_registration");
  const previous = matches[0];
  if (previous) {
    const ref = (previous.artifacts as Dict).bundle;
    fileRef(root, ref);
    preserve(read(relativePath(root, (ref as Dict).path)), bundle);
  }
  return { plans, previous };
}

function publishLocked(identity: string, root: string, candidate: string, candidateHash: string, bundle: Dict, generation: string, base: string, args: Args, observation: Dict | null): Dict {
    require(digestFile(candidate) === candidateHash, "candidate_changed");
    const registryPath = relativePath(root, REGISTRY, false);
    const registryHash = optionalDigest(registryPath);
    const registry = pythonDict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] });
    require(registry.schema === VERSION && Array.isArray(registry.plans), "unsupported_registry_schema");
    const registration = "northstar-plan-" + String(bundle.id);
    const { plans, previous } = previousRegistration(root, registry, registration, bundle);
    const prefix = `${GEN}/${String(bundle.id)}/${generation}`;
    const final = resolve(base, generation);
    const graphPath = relativePath(root, GRAPH);
    const graphHash = digestFile(graphPath);
    const live = pythonDict(read(graphPath));
    require(Array.isArray(live.nodes), "source_graph_nodes_required");
    const nodes = (live.nodes as unknown[]).map(pythonDict);
    const matching = nodes.filter((node) => node.path === (bundle.spec as Dict).path);
    require(matching.length === 1, "spec_graph_identity_missing_or_ambiguous");
    require(new Set(nodes.map((node) => pyKey(node.id))).size === nodes.length, "source_graph_duplicate_ids");
    const spec = matching[0] as Dict;
    const parent = `handoff:${text((bundle.repository as Dict).id)}:${text(bundle.id)}:${generation}`;
    const graph = exists(final)
      ? validateGeneration(root, prefix, bundle, generation, spec)
      : buildGraph(bundle, generation, graphHash, spec, parent, prefix);
    if (!exists(final)) publishPayload(base, final, bundle, graph);
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
    bundleShape(bundle, identity, root);
    require(digestFile(candidate) === candidateHash, "candidate_changed");
    require(optionalDigest(registryPath) === registryHash && digestFile(graphPath) === graphHash, "publication_source_changed");
    publicationWorktree(identity, root, args, observation);
    replaceJson(graphPath, live);
    require(digestFile(candidate) === candidateHash, "candidate_changed");
    require(optionalDigest(registryPath) === registryHash, "publication_source_changed");
    bundleShape(bundle, identity, root);
    replaceJson(registryPath, registry);
    return { schema: VERSION, published: entry, execution_ready: false, dispatch_authorized: false, authority_verification: "external-required" };
}

function optionalDigest(path: string): string | null { return exists(path) ? digestFile(path) : null; }

function publishPayload(base: string, final: string, bundle: Dict, graph: Dict): void {
  const staging = mkdtempSync(resolve(base, ".staging-"));
  try {
    writeJson(resolve(staging, "goals.json"), bundle);
    writeJson(resolve(staging, "graph.json"), graph);
    writeFileSync(resolve(staging, "handoff.md"), handoffText(bundle));
    const fd = openSync(resolve(staging, "handoff.md"), "r");
    try { fsyncSync(fd); } finally { closeSync(fd); }
    renameSync(staging, final);
  } finally {
    if (exists(staging)) rmSync(staging, { recursive: true });
  }
}

function publicationWorktree(identity: string, root: string, args: Args, observation: Dict | null): void {
  if (!observation) return;
  const current = worktreeObservation(identity, root, text(args.base_commit), false);
  require(Object.entries(observation).every(([key, value]) => key === "state_sha256" || sameValue(current[key], value)), "worktree_changed_during_publication");
}

function buildGraph(bundle: Dict, generation: string, graphHash: string, spec: Dict, parent: string, prefix: string): Dict {
  const specNode = { ...spec, backlinks: [parent] };
  const specId = field(spec, "id");
  const handoff = { id: parent, type: "handoff", title: bundle.id, status: "active", repo_id: (bundle.repository as Dict).id, path: prefix + "/handoff.md", backlinks: [specId] };
  const graph: Dict = { schema_version: "1.1", generation, plan_id: bundle.id, goal_ids: (bundle.goals as Dict[]).map((goal) => goal.id), source_graph_sha256: graphHash, nodes: [specNode, handoff], edges: [{ source: specId, target: parent, type: "plans" }] };
  for (const goal of bundle.goals as Dict[]) {
    const goalId = `plan:${text((bundle.repository as Dict).id)}:${text(bundle.id)}:${text(goal.id)}:${generation}`;
    (graph.nodes as Dict[]).push({ id: goalId, type: "plan", title: goal.id, status: "planned", repo_id: (bundle.repository as Dict).id, path: prefix + "/goals.json", backlinks: [parent] });
    (handoff.backlinks as string[]).push(goalId);
    (graph.edges as Dict[]).push({ source: parent, target: goalId, type: "plans" });
  }
  return graph;
}

function mergeNode(nodes: Dict[], node: Dict): void {
  const current = nodes.find((item) => sameValue(item.id, node.id));
  if (!current) {
    nodes.push({ ...node });
    return;
  }
  require(current.path === node.path, "graph_identity_conflict");
  const backlinks = get(current, "backlinks", []);
  current.backlinks = backlinks;
  for (const link of (node.backlinks as string[]) ?? []) {
    if (!contains(backlinks, link)) {
      append(backlinks, link);
    }
  }
}

function spliceGraph(live: Dict, graph: Dict): void {
  const nodes = Array.isArray(live.nodes) ? live.nodes as Dict[] : [];
  nodes.forEach((node) => { pyKey(field(node, "id")); });
  const edges = get(live, "edges", []);
  live.nodes = nodes;
  live.edges = edges;
  for (const node of graph.nodes as Dict[]) {
    mergeNode(nodes, node);
  }
  for (const edge of graph.edges as Dict[]) {
    if (!contains(edges, edge)) {
      append(edges, edge);
    }
  }
}

function add(gaps: Dict[], code: string, detail: unknown, scope: unknown, stage: string, status = "blocked"): void {
  gaps.push({
    code, detail: redactText(pyStr(detail)), scope, stage, status,
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
  if ("coverage_required" in goal && typeof goal.coverage_required !== "boolean") {
    add(gaps, "invalid_coverage_required", "Expected boolean", [goal.id], stage);
  }
  if (unknown && goal.coverage_required === true) {
    add(gaps, "measured_coverage_required", "Goal strengthens policy to measured coverage", [goal.id], stage);
  }
  if ("legacy_safe_tdd" in goal && typeof goal.legacy_safe_tdd !== "boolean") {
    add(gaps, "invalid_legacy_safe_tdd", "Expected boolean", [goal.id], stage);
  }
}

function coverageOverride(goal: Dict, valid: boolean, gaps: Dict[], stage: string): void {
  if (valid && Number(goal.coverage_percent) >= 30 && goal.legacy_safe_tdd === true && !string(goal.legacy_risk_reason)) {
    add(gaps, "legacy_risk_reason_required", "High coverage legacy-safe override needs reason", [goal.id], stage);
  }
}

function coverage(goal: Dict, gaps: Dict[], stage: string): void {
  const percent = goal.coverage_percent;
  const status = "coverage_status" in goal ? goal.coverage_status : "measured";
  const valid = numeric(percent) && Number(percent) >= 0 && Number(percent) <= 100;
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
  const branches = iterable(get(pythonDict(manifest), "optional_branches", [])).filter(isDict);
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
  const graph = pythonDict(read(loadedPaths.graph ?? ""));
  require(graph.generation === entry.generation && sameValue(graph.goal_ids, (loaded.goals as Dict[]).map((goal) => goal.id)), "graph_identity_mismatch");
  validateLiveGraph(filesRoot, graph);
  return { bundle: loaded, selected: args.goal_id ?? [], subject: digestFile(loadedPaths.bundle ?? ""), entry };
}

function handoffEntry(root: string, args: Args): Dict {
  const registryPath = resolve(root, REGISTRY);
  const manifest = pythonDict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] });
  require(manifest.schema === VERSION, "unsupported_registry_schema");
  const matches = iterable(get(manifest, "plans", [])).filter(isDict).filter((item) => args.handoff === item.id || args.handoff === item.handoff_path);
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
  require(keysEqual(artifacts, ["bundle", "graph", "handoff"]), "incomplete_generation");
  const loadedPaths: Record<string, string> = {};
  for (const [name, ref] of Object.entries(artifacts)) {
    const record = pythonDict(ref);
    require(startsWith(get(record, "path", ""), prefix), "mixed_generation");
    fileRef(root, record);
    loadedPaths[name] = relativePath(root, record.path);
  }
  require(entry.handoff_path === (artifacts.handoff as Dict).path, "handoff_path_mismatch");
  return loadedPaths;
}

function validateLiveGraph(root: string, graph: Dict): void {
  const live = pythonDict(read(relativePath(root, GRAPH)));
  const liveNodes = new Map<string, Dict>();
  for (const value of iterable(get(live, "nodes", []))) {
    const node = pythonDict(value);
    liveNodes.set(pyKey(get(node, "id", null)), node);
  }
  for (const value of iterable(field(graph, "nodes"))) {
    const node = pythonDict(value);
    const current = liveNodes.get(pyKey(field(node, "id")));
    require(current !== undefined, "generation_graph_missing");
    const liveNode = current as Dict;
    require(["id", "type", "repo_id", "path", "status"].every((key) => sameValue(get(liveNode, key, null), get(node, key, null))), "generation_graph_identity_mismatch");
  }
  validateLiveEdges(graph, live, liveNodes);
}

function validateLiveEdges(graph: Dict, live: Dict, liveNodes: Map<string, Dict>): void {
  for (const value of iterable(field(graph, "edges"))) {
    const edges = iterable(get(live, "edges", []));
    require(edges.some((item) => sameValue(item, value)), "generation_graph_link_missing");
    const edge = pythonDict(value);
    const source = liveNodes.get(pyKey(field(edge, "source")));
    const target = liveNodes.get(pyKey(field(edge, "target")));
    const sourceLinks = backlinks(target);
    const targetLinks = backlinks(source);
    require(sourceLinks.some((link) => sameValue(link, edge.source)) && targetLinks.some((link) => sameValue(link, edge.target)), "generation_graph_link_missing");
  }
}

function backlinks(node: Dict | undefined): unknown[] {
  return iterable(get(pythonDict(node), "backlinks", []));
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
    const authority = dict(context.authority, "unsupported_authority_fields");
    const fields = boundFields(["status", "stage", "subject_sha256", "issuer", "goals"], admission, ["execution_revision"], ["worktree", "policy_sha256"]);
    require(keysEqual(authority, fields), "unsupported_authority_fields");
    checkObservation(authority, admission, "authority");
    require(authority.status === "pass" && authority.stage === stage && authority.subject_sha256 === selection.subject && string(authority.issuer), "independent_authority_required");
    if (Array.isArray(authority.goals)) authority.goals.forEach(hashable);
    require(Array.isArray(authority.goals) && selection.selected.every((id) => (authority.goals as unknown[]).includes(id)), "independent_authority_required");
  } catch (error) {
    add(gaps, "authority_unavailable", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
  }
}

function gateRoot(admission: Admission, gate: Dict): string {
  return gate.root === "execution" ? executionRoot(admission.selection.bundle, admission.root) : admission.root;
}

function notApplicable(policy: Dict, context: Dict, stage: string, resolved: Dict[], goals: string[], additive: Dict[]): void {
  const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
  for (const dimension of Object.keys(exclusions).sort(compare)) {
    const exempt = goals.filter((id) => !additive.some((gate) => gate.stage === stage && applies(gate.scope, id) && gateDimensions(gate).includes(dimension))).sort(compare);
    if (exempt.length === 0) {
      continue;
    }
    resolved.push({
      gate: dimension, stage, scope: { goals: exempt }, status: "not_applicable",
      source: { policy: POLICY, sha256: (context.policy as Dict).sha256 }, responsible: "unassigned",
      evidence_refs: [], freshness: "current-policy-digest", recovery: "Reevaluate if repository policy changes",
      reason: exclusions[dimension],
    });
  }
}

const TYPED = new Set(["ownership", "branch_target", "fixture", "protected_approval", "harness_trust", "tooling"]);

function gateShape(gate: Dict): void {
  require(isDict(gate), "gate_id_required");
  require(match(ID, "id" in gate ? gate.id : ""), "gate_id_required");
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
  if (sameValue(scope, { repository: true })) {
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
    } else if (isFile(path)) {
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
  return ("coverage_status" in goal ? goal.coverage_status : "measured") === "measured" && numeric(percent) && Number(percent) >= 0 && Number(percent) <= 100;
}

function applies(scope: unknown, id: string): boolean {
  if (scope === "repository") {
    return true;
  }
  if (Array.isArray(scope)) {
    return scope.includes(id);
  }
  return isDict(scope) && (sameValue(scope, { repository: true }) || (Array.isArray(scope.goals) && scope.goals.includes(id)));
}

function goalRevision(bundle: Dict, id: string): string {
  const goals = new Map((bundle.goals as Dict[]).map((goal) => [text(goal.id), goal]));
  require(goals.has(id), "unknown_goal_revision_subject");
  const revisions: Record<string, string> = Object.create(null) as Record<string, string>;
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
  const supplied = isDict(admission.context) ? admission.context.completed_goals : [];
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
  const observed = isoDateTime(text(receipt.observed_at).replaceAll("Z", "+00:00"));
  const expires = isoDateTime(text(receipt.expires_at).replaceAll("Z", "+00:00"));
  const now = Date.now();
  require(observed.zoned && expires.zoned && observed.time <= now && now < expires.time, "evidence_expired_or_future");
}

function invalidIso(value: string): never { throw new Error("Invalid isoformat string: " + pyRepr(value)); }

function utcDate(year: number, month: number, day: number): number {
  const date = new Date(0);
  date.setUTCFullYear(year, month - 1, day);
  return date.getTime();
}

function calendarDate(value: string): { time: number; length: number } {
  const match = /^(?:(\d{4})-(\d{2})-(\d{2})|(\d{4})(\d{2})(\d{2}))/.exec(value);
  if (!match) return weekDate(value);
  const year = Number(match[1] ?? match[4]), month = Number(match[2] ?? match[5]), day = Number(match[3] ?? match[6]);
  const time = utcDate(year, month, day), date = new Date(time);
  if (year < 1 || date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return invalidIso(value);
  return { time, length: match[0].length };
}

function weekDate(value: string): { time: number; length: number } {
  const match = /^(?:(\d{4})-W(\d{2})(?:-([1-7]))?|(\d{4})W(\d{2})([1-7])?)/.exec(value);
  if (!match) return invalidIso(value);
  const year = Number(match[1] ?? match[4]), week = Number(match[2] ?? match[5]), day = Number(match[3] ?? match[6] ?? 1);
  const jan4 = utcDate(year, 1, 4);
  const monday = jan4 - ((new Date(jan4).getUTCDay() + 6) % 7) * 86400000;
  const time = monday + ((week - 1) * 7 + day - 1) * 86400000;
  if (year < 1 || week < 1 || week > 53 || new Date(time + (4 - day) * 86400000).getUTCFullYear() !== year) return invalidIso(value);
  return { time, length: match[0].length };
}

function clock(value: string, offset: boolean, original: string): number {
  const parts = clockParts(value, original);
  const { hour, minute, second, fraction } = parts;
  if (!offset && !validClock(parts)) return invalidIso(original);
  const time = ((hour * 60 + minute) * 60 + second + fraction) * 1000;
  if (offset && time >= 86400000) return invalidIso(original);
  return time;
}

function validClock(parts: { hour: number; minute: number; second: number; fraction: number }): boolean {
  const { hour, minute, second, fraction } = parts;
  return (hour < 24 && minute < 60 && second < 60) || (hour === 24 && minute === 0 && second === 0 && fraction === 0);
}

function clockParts(value: string, original: string): { hour: number; minute: number; second: number; fraction: number } {
  const match = /^(?:(\d{2}):(\d{2})(?::(\d{2})(?:[.,](\d+))?)?|(\d{2})(?:(\d{2})(?:(\d{2})(?:[.,](\d+))?)?)?)$/.exec(value);
  if (!match) return invalidIso(original);
  const [h = "0", m = "0", s = "0", f = "0"] = [1, 2, 3, 4].map((index) => match[index] ?? match[index + 4] ?? "0");
  return { hour: Number(h), minute: Number(m), second: Number(s), fraction: Number("0." + f.slice(0, 6)) };
}

function isoDateTime(value: string): { time: number; zoned: boolean } {
  const date = calendarDate(value);
  const rest = value.slice(date.length);
  if (!rest) return { time: date.time, zoned: false };
  const separator = Array.from(rest)[0] ?? "";
  const time = rest.slice(separator.length);
  const zoneAt = time.search(/[Z+-]/);
  const plain = zoneAt < 0 ? time : time.slice(0, zoneAt);
  const zone = zoneAt < 0 ? "" : time.slice(zoneAt);
  const local = date.time + clock(plain, false, value);
  if (new Date(local).getUTCFullYear() > 9999) return invalidIso(value);
  return { time: local - zoneOffset(zone, value), zoned: zone !== "" };
}

function zoneOffset(zone: string, value: string): number {
  if (zone === "" || zone === "Z") return 0;
  if (!zone.startsWith("+") && !zone.startsWith("-")) return invalidIso(value);
  return clock(zone.slice(1), true, value) * (zone.startsWith("-") ? -1 : 1);
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
  require(["target", "branch"].every((key) => string(binding[key]) && !unsafeTarget(text(binding[key]))), "target_branch_required");
  if (admission.worktree) {
    require(binding.target === admission.worktree.target_ref && binding.branch === admission.worktree.branch, "worktree_branch_target_mismatch");
  }
}

function toolBinding(binding: Dict): void {
  const tool = text(binding.tool);
  require(string(tool) && /^[A-Za-z0-9_.+-]+$(?![\s\S])/.test(tool), "tool_name_required");
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
    require((admission.selection.bundle.goals as Dict[]).some((goal) => goal.id === subject.goal), "approval_goal_subject_mismatch");
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
    if (error instanceof TypeError) throw error;
    throw new Invalid("trust_source_unavailable:expected=unavailable:actual=unverified:independent_source=" + pyStr(anchor.path) + ":" + (error instanceof Error ? error.message : String(error)));
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
    require(keysEqual(value, binding.roles as string[]) && Object.values(value).every((name) => string(name) && !["tbd", "unknown", "unassigned", "placeholder"].includes(strip(text(name)).toLowerCase())), "named_ownership_required");
  } else {
    require(sameValue(receipt.value, binding), "typed_observation_mismatch");
  }
}

function runExtraGate(admission: Admission, gate: Dict): boolean {
  const root = gateRoot(admission, gate);
  switch (gate.kind) {
    case "file_digest": fileRef(root, gate); return true;
    case "executable_presence": {
      const path = relativePath(root, gate.path);
      require(isFile(path) && executable(path), "executable_unavailable");
      return true;
    }
    case "measured_coverage":
      require((admission.selection.bundle.goals as Dict[]).filter((goal) => evaluatedGoals(admission.selection).has(text(goal.id)) && applies(gate.scope, text(goal.id))).every(measured), "measured_coverage_required");
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
    source: { policy: POLICY, sha256: (admission.context.policy as Dict).sha256 }, responsible: get(gate, "responsible", "unassigned"),
    evidence_refs: refs.map((ref) => redactText(pyStr(ref))),
    freshness: { observed_at: get(receipt, "observed_at", "current-file-read"), expires_at: get(receipt, "expires_at", "not-declared") },
    recovery: "Retain while exact binding and freshness remain valid; does not authorize dispatch" };
}

function extraGates(admission: Admission, gates: Dict[], stage: string, gaps: Dict[], resolved: Dict[]): void {
  const evaluated = evaluatedGoals(admission.selection);
  for (const gate of gates) {
    if (gate.stage !== stage || ![...evaluated].some((id) => applies(gate.scope, id))) {
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
      Object.assign(gaps[gaps.length - 1] ?? {}, failedGate(admission, gate));
    }
  }
}

function failedGate(admission: Admission, gate: Dict): Dict {
  const receipt = (admission.context.results as Dict[]).find((result) => result.gate === gate.id) ?? {};
  const recovery: Record<string, string> = {
    ownership: "Supply named required owner/reviewer and an independent current receipt",
    branch_target: "Supply the approved exact target/branch binding and independent current receipt",
    fixture: "Prepare the isolated executable fixture and obtain independent current fixture evidence",
    tooling: "Install the declared tool in the governed environment and refresh independent evidence",
    protected_approval: "Obtain approval only for this changed or missing exact subject; retain unaffected receipts",
    harness_trust: "Verify expected commit against the independent provenance anchor; never rewrite trust to fit the lock",
  };
  return { responsible: get(gate, "responsible", "unassigned"), source: { policy: POLICY, gate: gate.id, issuer: get(receipt, "issuer", "unavailable") },
    freshness: { observed_at: get(receipt, "observed_at", "unavailable"), expires_at: get(receipt, "expires_at", "unavailable"), validated: false },
    evidence_refs: Array.isArray(receipt.evidence) ? receipt.evidence.map((ref) => redactText(pyStr(ref))) : [],
    recovery: recovery[text(gate.kind)] ?? "Resolve the specified gate evidence and rerun this exact stage" };
}

function contextShape(admission: Admission): void {
  const context = pythonDict(admission.context);
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
  const approved = dict(context.policy, "unsupported_approval_fields");
  require(keysEqual(approved, ["sha256", "revision", "issuer"]), "unsupported_approval_fields");
  require(approved.sha256 === digestFile(relativePath(root, POLICY)) && string(approved.issuer) && string(approved.revision), "unapproved_policy_revision");
  const sources = policy.sources;
  require(Array.isArray(sources) && sources.length > 0 && sameValue(sources, context.sources), "policy_source_set_mismatch");
  require(new Set((sources as Dict[]).map((source) => pyKey(pythonDict(source).path))).size === (sources as Dict[]).length, "duplicate_policy_sources");
  const listed = new Set((sources as Dict[]).map((source) => source.path));
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
  if ("dimension" in gate) hashable(gate.dimension);
  const dimensions = "dimension" in gate ? [gate.dimension as string] : [];
  hashable(gate.kind);
  if (gate.kind === "ownership") {
    const binding = pythonDict(get(gate, "binding", {}));
    const roles = iterable(get(binding, "roles", []));
    dimensions.push(...roles.filter((role) => role === "owner" || role === "reviewer").map((role) => role === "owner" ? "owners" : "reviewer"));
  } else {
    const dimensionsByKind: Record<string, string> = { branch_target: "branch_target", fixture: "fixtures", tooling: "tooling", protected_approval: "registration_approval", harness_trust: "harness_trust" };
    const dimension = Object.hasOwn(dimensionsByKind, text(gate.kind)) ? dimensionsByKind[text(gate.kind)] : undefined;
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

function policyGates(admission: Admission, policy: Dict, stage: string, additive: Dict[]): Dict[] {
  require(Array.isArray(policy.gates), "policy_gates_required");
  const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
  require(Object.entries(exclusions).every(([key, value]) => string(key) && string(value)), "explicit_not_applicable_reasons_required");
  const declared = policy.gates as Dict[];
  const covered = new Set(declared.filter(isDict).flatMap(gateDimensions));
  require(DIMENSIONS.every((item) => item in exclusions || covered.has(item)), "policy_dimensions_required");
  require(!Object.keys(exclusions).some((item) => covered.has(item)), "contradictory_policy_dimension");
  const ids = (admission.selection.bundle.goals as Dict[]).map((goal) => text(goal.id));
  for (const gate of declared) {
    gateShape(gate);
    require(explicitScope(gate.scope, ids), "explicit_gate_scope_required");
  }
  const gates = [...declared, ...additive];
  require(mapped(admission.selection.bundle) || gates.every((gate) => gate.root !== "execution"), "execution_requires_mapped_schema");
  mappedTargetGates(admission, gates, exclusions, stage);
  require(new Set(gates.map((gate) => gate.id)).size === gates.length, "duplicate_policy_gate_ids");
  return gates;
}

function policyOk(admission: Admission, stage: string, gaps: Dict[], resolved: Dict[], additive: Dict[]): void {
  const { context, selection } = admission;
  let policy: Dict, gates: Dict[];
  try {
    contextShape(admission);
    const root = admission.root;
    require(isFile(resolve(root, POLICY)), "unsupported_policy_source:" + POLICY);
    policy = pythonDict(read(relativePath(root, POLICY)));
    require(policy.schema === "readiness-policy/1", "unsupported_policy_schema");
    policyBinding(admission, policy);
    policySources(admission, policy);
    gates = policyGates(admission, policy, stage, additive);
  } catch (error) {
    add(gaps, "policy_context_invalid", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
    return;
  }
  const ids = [...evaluatedGoals(selection)];
  notApplicable(policy, context, stage, resolved, ids, additive);
  checkAuthority(admission, stage, gaps);
  extraGates(admission, gates, stage, gaps, resolved);
}

function validRequirement(gate: unknown): gate is Dict {
  return isDict(gate) && string(gate.id) && ID.test(text(gate.id)) && STAGES.includes(text(gate.stage)) && string(gate.kind);
}

function goalRequirements(goal: Dict, gaps: Dict[], stage: string, additive: Dict[]): void {
  const requirements = "requirements" in goal ? goal.requirements : [];
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
      additive.push({ ...gate, scope: { goals: [goal.id] } });
    } catch (error) {
      add(gaps, "goal_requirement_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage);
    }
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
  let context: Dict = {};
  let contextError: string | null = null;
  try { if (args.context) context = read(args.context) as Dict; }
  catch (error) { contextError = error instanceof Error ? osError(error) : String(error); }
  const admission: Admission = { identity, root, selection: selected, context, worktree };
  collectReport(admission, args, report, stage, inputs, contextError);
}

function collectReport(admission: Admission, args: Args, report: Dict, stage: string, inputs: string[], contextError: string | null): void {
  const { selection: selected, context, worktree, identity, root } = admission;
  if (mapped(selected.bundle)) {
    report.execution = selected.bundle.execution;
    report.execution_revision = isDict(context) ? context.execution_revision ?? null : null;
    report.execution_revision_source = "independent-context";
  }
  const gaps = report.gaps as Dict[];
  const resolved = report.resolved as Dict[];
  const stages = stage === "planning" ? ["preparation", "implementation", "merge"] : [stage];
  for (const item of stages) {
    collectGaps(admission, item, gaps, resolved);
    planGaps(selected.bundle, gaps, item, contextError);
  }
  report.per_goal = perGoal(selected.selected, gaps, resolved, stages);
  if (worktree) {
    require(sameValue(worktree, worktreeObservation(identity, root, text(args.base_commit), args.stage === "merge", inputs)), "worktree_changed_during_validation");
  }
  report.execution_ready = stage !== "planning" && gaps.length === 0;
}

function planGaps(bundle: Dict, gaps: Dict[], stage: string, contextError: string | null): void {
  if (!bundle.planning_complete || bundle.status !== "active") add(gaps, "plan_not_active_or_incomplete", bundle.status, "repository", stage);
  if (contextError) add(gaps, "context_unavailable", contextError, "repository", stage, "unknown");
}

function goalFindings(admission: Admission, goal: Dict, local: Dict[], stage: string, additive: Dict[]): void {
  const { selection, root } = admission;
  const selected = selection.selected.includes(text(goal.id));
  if (selected) {
    coverage(goal, local, stage);
    const readiness = (goal.readiness as Dict)[stage];
    if (readiness !== "ready") add(local, "goal_not_ready", readiness, [goal.id], stage, readiness === "unknown" ? "unknown" : "blocked");
  }
  for (const dependency of goal.dependencies as string[]) {
    if (!dependencyComplete(admission, dependency)) add(local, "dependency_incomplete", dependency, [goal.id], stage);
  }
  if (selected) {
    try { validateCommands(executionRoot(selection.bundle, root), goal.verification); }
    catch (error) { add(local, "verification_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage); }
  }
  goalRequirements(goal, local, stage, additive);
}

function collectGaps(admission: Admission, stage: string, gaps: Dict[], resolved: Dict[]): void {
  const local: Dict[] = [];
  const additive: Dict[] = [];
  const { selection: selected } = admission;
  const evaluated = evaluatedGoals(selected);
  for (const goal of selected.bundle.goals as Dict[]) {
    if (!evaluated.has(text(goal.id))) continue;
    goalFindings(admission, goal, local, stage, additive);
  }
  policyOk(admission, stage, local, resolved, additive);
  gaps.push(...scopeGoals(local, admission.selection));
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
  return redact(report) as Dict;
}

function redact(value: unknown): unknown {
  if (typeof value === "string") return redactText(value);
  if (Array.isArray(value)) return value.map(redact);
  if (isDict(value)) return Object.fromEntries(Object.entries(value).map(([key, item]) => [redact(key) as string, redact(item)]));
  return value;
}

function scopeGoals(gaps: Dict[], selection: Selection): Dict[] {
  const visible: Dict[] = [];
  for (const gap of gaps) {
    const affected = [...new Set(selection.selected)].sort(compare).filter((id) => {
      const closure = evaluatedGoals({ ...selection, selected: [id] });
      return [...closure].some((goal) => applies(gap.scope, goal));
    });
    if (affected.length > 0) {
      gap.blocked_goals = affected;
      if (gap.scope !== "repository" && !sameValue(gap.scope, { repository: true })) gap.scope = { goals: affected };
      visible.push(gap);
    }
  }
  return visible;
}

function perGoal(selected: string[], gaps: Dict[], resolved: Dict[], stages: string[]): Dict {
  const out: Dict = Object.create(null) as Dict;
  for (const id of selected) {
    const record: Dict = {};
    for (const stage of stages) {
      const findings = gaps.filter((gap) => gap.stage === stage && applies(gap.scope, id));
      const extra = resolved.filter((item) => item.stage === stage && applies(item.scope, id));
      const status = findings.some((gap) => gap.status === "blocked") ? "blocked" : findings.length > 0 ? "unknown" : "ready";
      record[stage] = { status, findings: [...findings, ...extra] };
    }
    out[id] = record;
  }
  return out;
}

export function migrate(args: Args): Dict {
  require(!args.worktree_root && !args.base_commit, "worktree_migration_unsupported");
  const root = pyPath(String(args.root ?? "."));
  const legacy = read(String(args.legacy));
  const supplied = read(String(args.bundle)) as Dict;
  bundleShape(supplied, root);
  const bundle = parse(dumps(supplied)) as Dict;
  const extensions = "extensions" in bundle ? bundle.extensions : {};
  require(isDict(extensions) && !("legacy_original" in extensions), "migration_extension_collision");
  const extensionRecord = extensions as Dict;
  extensionRecord.legacy_original = legacy;
  extensionRecord.legacy_sha256 = digestFile(String(args.legacy));
  bundle.extensions = extensions;
  for (const goal of bundle.goals as Dict[]) {
    goal.readiness = { preparation: "unknown", implementation: "unknown", merge: "unknown" };
  }
  return { schema: VERSION, bundle, dispatch_authorized: false, execution_ready: false, authority_verification: "external-required", next: "Review retained evidence; publish explicitly; revalidate independently" };
}

export function main(argv: string[]): number {
  try {
    const args = parseArgs(argv);
    if (args.operation === "help") {
      process.stdout.write(HELP);
      return 0;
    }
    const result = runOperation(args);
    process.stdout.write(dumps(result, 2, true) + "\n");
    return resultExit(args, result);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (message.startsWith("invalid choice:") || message.startsWith("usage:")) {
      return 2;
    }
    process.stdout.write(dumps({ schema: VERSION, error: message, execution_ready: false, dispatch_authorized: false, authority_verification: "external-required" }) + "\n");
    return 1;
  }
}

export { add, applies, collectGaps, coverage, dependencyComplete, gateDimensions, gateSubject, gitRead, goalRevision, instructionPaths, typedGate, worktreeBinding, worktreeInputs, worktreeObservation };

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

const FLAGS = ["--help", "--root", "--handoff", "--goal-id", "--goal", "--context", "--execution-record", "--execution-root", "--worktree-root", "--base-commit", "--bundle", "--legacy", "--stage"];
const USAGE = `usage: readiness_contract.py [-h] [--root ROOT] [--handoff HANDOFF]
                             [--goal-id GOAL_ID] [--goal GOAL]
                             [--context CONTEXT]
                             [--execution-record EXECUTION_RECORD]
                             [--execution-root EXECUTION_ROOT]
                             [--worktree-root WORKTREE_ROOT]
                             [--base-commit BASE_COMMIT] [--bundle BUNDLE]
                             [--legacy LEGACY]
                             [--stage {planning,preparation,implementation,merge}]
                             {admit,publish,migrate}
`;
const HELP = USAGE + `
Versioned, read-only admission; publication is an explicit separate
subcommand. Context is supplied by the caller's independent authority adapter.
JSON labels do not authenticate a human or runtime. No goal can create its own
policy exemption.

positional arguments:
  {admit,publish,migrate}

options:
  -h, --help            show this help message and exit
  --root ROOT
  --handoff HANDOFF
  --goal-id GOAL_ID
  --goal GOAL
  --context CONTEXT
  --execution-record EXECUTION_RECORD
  --execution-root EXECUTION_ROOT
  --worktree-root WORKTREE_ROOT
  --base-commit BASE_COMMIT
  --bundle BUNDLE
  --legacy LEGACY
  --stage {planning,preparation,implementation,merge}
`;

function usageError(message: string): never {
  process.stderr.write(USAGE + "readiness_contract.py: error: " + message + "\n");
  throw new Invalid("usage:" + message);
}

function optionName(raw: string, shown = raw): string | null {
  const matches = FLAGS.filter((flag) => flag.startsWith(raw));
  if (FLAGS.includes(raw)) return raw;
  if (matches.length > 1) usageError("ambiguous option: " + shown + " could match " + matches.join(", "));
  return matches[0] ?? null;
}

function optionValue(args: Args, flag: string, value: string): void {
  if (flag === "--stage" && !["planning", ...STAGES].includes(value)) usageError("argument --stage: invalid choice: " + pyRepr(value) + " (choose from 'planning', 'preparation', 'implementation', 'merge')");
  if (flag === "--goal-id") args.goal_id = [...(args.goal_id ?? []), value];
  else (args as Dict)[flag.slice(2).replaceAll("-", "_")] = value;
}

function parseArgs(argv: string[]): Args {
  const args: Args = { root: ".", stage: "implementation", goal_id: null };
  const extra: string[] = [];
  let positionalOnly = false;
  for (let index = 0; index < argv.length; index += 1) {
    const raw = argv[index] ?? "";
    switch (argumentKind(raw, positionalOnly)) {
      case "help": return { ...args, operation: "help" };
      case "separator": positionalOnly = true; break;
      case "option":
        index = parseOption(args, argv, index, extra);
        if (args.operation === "help") return args;
        break;
      default:
        if (args.operation) extra.push(raw);
        else args.operation = parseOperation(raw);
    }
  }
  if (!args.operation) usageError("the following arguments are required: operation");
  if (extra.length > 0) usageError("unrecognized arguments: " + extra.join(" "));
  return args;
}

function argumentKind(raw: string, positionalOnly: boolean): string {
  if (positionalOnly) return "positional";
  if (raw === "-" || /^-\.?\p{Decimal_Number}/u.test(raw)) return "positional";
  if (raw === "--help" || /^-h(?:$|[^=-])/.test(raw)) return "help";
  if (raw === "--") return "separator";
  return raw.startsWith("-") ? "option" : "positional";
}

function parseOperation(raw: string): string {
  if (!["admit", "publish", "migrate"].includes(raw)) usageError("argument operation: invalid choice: " + pyRepr(raw) + " (choose from 'admit', 'publish', 'migrate')");
  return raw;
}

function parseOption(args: Args, argv: string[], index: number, extra: string[]): number {
  const raw = argv[index] ?? "";
  if (raw.startsWith("-h") && !raw.startsWith("--")) usageError("argument -h/--help: ignored explicit argument " + pyRepr(raw.slice(2).replace(/^=/, "")));
  const at = raw.indexOf("=");
  const name = at < 0 ? raw : raw.slice(0, at);
  const flag = optionName(name, raw);
  if (!flag) { extra.push(raw); return index; }
  if (flag === "--help") {
    helpOption(args, raw, at);
    return index;
  }
  const value = at < 0 ? argv[++index] : raw.slice(at + 1);
  requireOptionValue(flag, value, at);
  optionValue(args, flag, value as string);
  return index;
}

function helpOption(args: Args, raw: string, at: number): void {
  if (at >= 0) usageError("argument -h/--help: ignored explicit argument " + pyRepr(raw.slice(at + 1)));
  args.operation = "help";
}

function requireOptionValue(flag: string, value: string | undefined, at: number): void {
  if (value === undefined || (at < 0 && value.startsWith("-") && !/^-\.?\p{Decimal_Number}/u.test(value))) usageError("argument " + flag + ": expected one argument");
}
