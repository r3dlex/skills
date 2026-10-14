import { accessSync, closeSync, constants, existsSync, fsyncSync, lstatSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";
import { canonical, digest, dumps, ID, Invalid, read, require, SHA, string, VERSION } from "./json.mjs";
import { validate as validateCommands } from "./verification.mjs";
const POLICY = ".ai/policies/readiness-policy.json";
const MANIFEST = ".ai/workflows/repo-workflow.json";
const GRAPH = ".ai/traceability/graph.json";
const REGISTRY = ".ai/workflows/northstar-readiness-v1.json";
const GEN = ".ai/handoff/readiness-v1";
const MAPPED = "mapped-handoff-goals/1";
const STAGES = ["preparation", "implementation", "merge"];
const DIMENSIONS = ["owners", "reviewer", "branch_target", "fixtures", "tooling", "registration_approval", "harness_trust"];
function isDict(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}
function dict(value, message) {
    if (!isDict(value)) {
        throw new Invalid(message);
    }
    return value;
}
function text(value) {
    return typeof value === "string" ? value : "";
}
function pyPath(path) {
    return realpathSync(path);
}
function exists(path) {
    try {
        lstatSync(path);
        return true;
    }
    catch {
        return false;
    }
}
function isFile(path) {
    try {
        return statSync(path).isFile();
    }
    catch {
        return false;
    }
}
function digestFile(path) {
    return digest(path);
}
function symlinkComponent(root, path) {
    let current = path;
    while (current !== root && current.startsWith(root + "/")) {
        try {
            if (lstatSync(current).isSymbolicLink()) {
                return true;
            }
        }
        catch {
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
export function relativePath(root, name, mustExist = true) {
    require(string(name), "path_required");
    const text = name;
    const unsafe = isAbsolute(text) || text.includes("\\") || text.split("/").some((part) => part === "" || part === "." || part === "..");
    require(!unsafe, "unsafe_path:" + text);
    const path = resolve(root, text);
    require(!symlinkComponent(root, path), "symlink_path:" + text);
    if (mustExist) {
        try {
            return realpathSync(path);
        }
        catch (error) {
            throw new Invalid("outside_root:" + text, error.code === "ENOENT" ? "enoent" : "");
        }
    }
    return path;
}
function fileRef(root, value) {
    const record = dict(value, "file_digest_required");
    require(SHA.test(text(record.sha256)), "file_digest_required");
    const path = relativePath(root, record.path);
    require(isFile(path) && digestFile(path) === record.sha256, "stale_file:" + text(record.path));
}
function repository(value, root) {
    const record = dict(value, "repository_id_required");
    require(ID.test(text(record.id)), "repository_id_required");
    require(record.root === root, "repository_root_mismatch");
}
function stringList(goal, key) {
    const list = goal[key];
    require(Array.isArray(list) && list.length > 0 && list.every((item) => string(item)), key + "_required");
    return list;
}
function goalShape(goal, root) {
    const record = dict(goal, "goal_id_required");
    require(ID.test(text(record.id)), "goal_id_required");
    repository(record.repository, root);
    require(string(record.issue_ref), "goal_issue_required");
    stringList(record, "scope");
    stringList(record, "acceptance_criteria");
    for (const scope of stringList(record, "scope")) {
        relativePath(root, scope, false);
    }
    const deps = record.dependencies;
    require(Array.isArray(deps) && deps.every((item) => typeof item === "string" && ID.test(item)), "invalid_dependencies");
    require(new Set(deps).size === deps.length && !deps.includes(text(record.id)), "invalid_dependencies");
    const readiness = dict(record.readiness, "stage_readiness_required");
    require(STAGES.every((stage) => stage in readiness), "stage_readiness_required");
    require(Object.values(readiness).every((item) => item === "ready" || item === "blocked" || item === "unknown"), "stage_readiness_required");
    require(Array.isArray(record.verification) && record.verification.length > 0, "verification_required");
}
function acyclic(goals) {
    const ids = goals.map((goal) => String(goal.id));
    const edges = new Map(goals.map((goal) => [String(goal.id), goal.dependencies]));
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
function mappedExecutionRoot(bundle) {
    if (bundle.schema !== MAPPED || !isDict(bundle.execution) || !isDict(bundle.execution.repository)) {
        return;
    }
    const declared = text(bundle.execution.repository.root);
    if (!declared) {
        return;
    }
    // A missing execution root is a runtime ENOENT, matching Path.resolve(strict=True).
    realpathSync(declared);
}
export function bundleShape(bundle, root) {
    const record = dict(bundle, "migration_required:handoff-goals/1");
    require(record.schema === "handoff-goals/1" || record.schema === MAPPED, "migration_required:handoff-goals/1");
    mappedExecutionRoot(record);
    require(ID.test(text(record.id)), "bundle_id_required");
    repository(record.repository, root);
    require(string(record.issue_ref), "bundle_issue_required");
    require(typeof record.planning_complete === "boolean", "planning_complete_required");
    require(record.status === "active" || record.status === "blocked" || record.status === "superseded", "bundle_status_required");
    fileRef(root, record.spec);
    require(Array.isArray(record.goals) && record.goals.length > 0, "goals_required");
    const goals = record.goals;
    for (const goal of goals) {
        goalShape(goal, root);
        require(JSON.stringify(dict(goal, "goal_repository_mismatch").repository) === JSON.stringify(record.repository), "goal_repository_mismatch");
    }
    const ids = goals.map((goal) => text(goal.id));
    require(new Set(ids).size === ids.length, "duplicate_goal_ids");
    require(goals.every((goal) => (goal.dependencies ?? []).every((dep) => ids.includes(dep))), "unknown_dependency");
    acyclic(goals);
}
function handoffText(bundle) {
    const planning = bundle.planning_complete === true ? "true" : "false";
    const goals = bundle.goals.map((goal) => String(goal.id)).join(", ");
    return `# Northstar handoff: ${String(bundle.id)}\n\nPlanning complete: ${planning}\n\nExecution readiness: independently revalidate; planning is not admission.\n\nGoals: ${goals}\n`;
}
function sameValue(left, right) {
    return dumps(left, null, true, true) === dumps(right, null, true, true);
}
function preserve(previous, proposed, path = "") {
    if (isDict(previous)) {
        const next = dict(proposed, "enrichment_loss:" + path);
        for (const [key, value] of Object.entries(previous)) {
            require(Object.prototype.hasOwnProperty.call(next, key), "enrichment_loss:" + path + "/" + key);
            preserve(value, next[key], path + "/" + key);
        }
        return;
    }
    if (Array.isArray(previous) && previous.length > 0 && previous.every((item) => isDict(item) && "id" in item)) {
        require(Array.isArray(proposed), "enrichment_loss:" + path);
        const items = proposed;
        const nextById = new Map();
        for (const item of items) {
            if (isDict(item) && "id" in item) {
                nextById.set(String(item.id), item);
            }
        }
        for (const item of previous) {
            const id = String(item.id);
            require(nextById.has(id), "enrichment_loss:" + path);
            preserve(item, nextById.get(id), path + "/" + id);
        }
        return;
    }
    const parts = path.split("/").filter((part) => part !== "");
    const stageField = parts.length === 4 && parts[0] === "goals" && parts[2] === "readiness" && STAGES.includes(parts[3] ?? "");
    const coverageField = parts.length === 3 && parts[0] === "goals" && ["coverage_percent", "coverage_status", "legacy_safe_tdd", "legacy_risk_reason"].includes(parts[2] ?? "");
    const mutable = path === "/planning_complete" || path === "/status" || path === "/spec/sha256" || stageField || coverageField;
    require(mutable || sameValue(previous, proposed), "enrichment_changed:" + path);
}
function validateGeneration(root, prefix, bundle, generation, spec) {
    const names = ["goals.json", "graph.json", "handoff.md"];
    const paths = Object.fromEntries(names.map((name) => [name, relativePath(root, prefix + "/" + name)]));
    require(names.every((name) => isFile(paths[name] ?? "")), "generation_collision:non-file");
    const goalsPath = paths["goals.json"] ?? "";
    const graphPath = paths["graph.json"] ?? "";
    const handoffPath = paths["handoff.md"] ?? "";
    require(sameValue(read(goalsPath), bundle) && readFileSync(handoffPath, "utf8") === handoffText(bundle), "generation_collision:payload");
    const graph = dict(read(graphPath), "generation_collision:identity");
    const goalIds = bundle.goals.map((goal) => text(goal.id));
    require(graph.generation === generation && graph.plan_id === bundle.id && sameValue(graph.goal_ids, goalIds) && SHA.test(text(graph.source_graph_sha256)), "generation_collision:identity");
    const repo = text(bundle.repository.id);
    const parent = "handoff:" + repo + ":" + text(bundle.id) + ":" + generation;
    const expected = {
        [text(spec.id)]: { id: spec.id, type: spec.type, repo_id: spec.repo_id, path: spec.path, backlinks: [parent] },
        [parent]: { id: parent, type: "handoff", repo_id: repo, path: prefix + "/handoff.md", backlinks: [spec.id] },
    };
    const edges = [{ source: spec.id, target: parent, type: "plans" }];
    for (const goal of bundle.goals) {
        const goalId = "plan:" + repo + ":" + text(bundle.id) + ":" + text(goal.id) + ":" + generation;
        expected[goalId] = { id: goalId, type: "plan", repo_id: repo, path: prefix + "/goals.json", backlinks: [parent] };
        (expected[parent]?.backlinks).push(goalId);
        edges.push({ source: parent, target: goalId, type: "plans" });
    }
    const nodes = Array.isArray(graph.nodes) ? graph.nodes : [];
    require(nodes.length === Object.keys(expected).length && new Set(nodes.map((node) => text(node.id))).size === nodes.length && nodes.every((node) => text(node.id) in expected), "generation_collision:nodes");
    require(nodes.every((node) => {
        const want = expected[text(node.id)] ?? {};
        return Object.entries(want).every(([key, value]) => sameValue(node[key], value));
    }) && sameValue(graph.edges, edges), "generation_collision:graph");
    return graph;
}
function writeJson(path, value) {
    writeFileSync(path, dumps(value, 2, true) + "\n");
    const fd = openSync(path, "r");
    try {
        fsyncSync(fd);
    }
    finally {
        closeSync(fd);
    }
}
function replaceJson(path, value) {
    const temporary = resolve(path, "..", `.readiness-${process.pid}-${Date.now()}`);
    try {
        writeJson(temporary, value);
        renameSync(temporary, path);
    }
    finally {
        if (exists(temporary)) {
            rmSync(temporary, { force: true });
        }
    }
}
export function publish(args) {
    const root = pyPath(String(args.root ?? "."));
    const candidate = pyPath(String(args.bundle));
    const candidateHash = digestFile(candidate);
    const bundle = read(candidate);
    bundleShape(bundle, root);
    if (!isDict(bundle)) {
        throw new Invalid("migration_required:handoff-goals/1");
    }
    const generation = canonical(bundle);
    const base = resolve(root, `${GEN}/${String(bundle.id)}`);
    mkdirSync(base, { recursive: true });
    const lock = resolve(root, ".ai/workflows/.northstar-readiness-v1.lock");
    try {
        mkdirSync(lock);
    }
    catch {
        throw new Invalid("publication_locked:inspect existing publisher; never steal a lock");
    }
    try {
        require(digestFile(candidate) === candidateHash, "candidate_changed");
        const registryPath = resolve(root, REGISTRY);
        const registry = dict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] }, "unsupported_registry_schema");
        require(registry.schema === VERSION && Array.isArray(registry.plans), "unsupported_registry_schema");
        const registration = "northstar-plan-" + String(bundle.id);
        const plans = registry.plans;
        const matches = plans.filter((item) => item.id === registration);
        require(matches.length <= 1, "duplicate_registration");
        const previous = matches[0];
        if (previous) {
            const ref = previous.artifacts.bundle;
            fileRef(root, ref);
            preserve(read(relativePath(root, ref.path)), bundle);
        }
        const prefix = `${GEN}/${String(bundle.id)}/${generation}`;
        const final = resolve(base, generation);
        const graphPath = relativePath(root, GRAPH);
        const live = read(graphPath);
        const nodes = Array.isArray(live.nodes) ? live.nodes : [];
        const matching = nodes.filter((node) => node.path === bundle.spec.path);
        require(matching.length === 1, "spec_graph_identity_missing_or_ambiguous");
        const spec = matching[0];
        const parent = `handoff:${text(bundle.repository.id)}:${text(bundle.id)}:${generation}`;
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
    finally {
        rmSync(lock, { recursive: true, force: true });
    }
}
function buildGraph(bundle, generation, graphHash, spec, parent, prefix) {
    const specNode = { ...spec, backlinks: [parent] };
    const handoff = { id: parent, type: "handoff", title: bundle.id, status: "active", repo_id: bundle.repository.id, path: prefix + "/handoff.md", backlinks: [spec.id] };
    const graph = { schema_version: "1.1", generation, plan_id: bundle.id, goal_ids: bundle.goals.map((goal) => goal.id), source_graph_sha256: graphHash, nodes: [specNode, handoff], edges: [{ source: spec.id, target: parent, type: "plans" }] };
    for (const goal of bundle.goals) {
        const goalId = `plan:${text(bundle.repository.id)}:${text(bundle.id)}:${text(goal.id)}:${generation}`;
        graph.nodes.push({ id: goalId, type: "plan", title: goal.id, status: "planned", repo_id: bundle.repository.id, path: prefix + "/goals.json", backlinks: [parent] });
        handoff.backlinks.push(goalId);
        graph.edges.push({ source: parent, target: goalId, type: "plans" });
    }
    return graph;
}
function mergeNode(nodes, node) {
    const current = nodes.find((item) => item.id === node.id);
    if (!current) {
        nodes.push({ ...node });
        return;
    }
    require(current.path === node.path, "graph_identity_conflict");
    const backlinks = Array.isArray(current.backlinks) ? current.backlinks : [];
    current.backlinks = backlinks;
    for (const link of node.backlinks ?? []) {
        if (!backlinks.includes(link)) {
            backlinks.push(link);
        }
    }
}
function spliceGraph(live, graph) {
    const nodes = Array.isArray(live.nodes) ? live.nodes : [];
    const edges = Array.isArray(live.edges) ? live.edges : [];
    live.nodes = nodes;
    live.edges = edges;
    for (const node of graph.nodes) {
        mergeNode(nodes, node);
    }
    for (const edge of graph.edges) {
        if (!edges.some((item) => JSON.stringify(item) === JSON.stringify(edge))) {
            edges.push(edge);
        }
    }
}
function add(gaps, code, detail, scope, stage, status = "blocked") {
    gaps.push({
        code, detail: String(detail).replace(/https?:\/\/\S+/g, "[redacted-url]"), scope, stage, status,
        responsible: "unassigned", source: "independent-context-and-repository-policy", freshness: "unavailable",
        evidence_refs: [], recovery: "Supply current independently verified evidence for this gate; rerun exact selection",
    });
}
function coverageInvalid(status, unknown, valid) {
    if (status !== "unknown" && status !== "measured") {
        return true;
    }
    return (status === "unknown" && !unknown) || (status === "measured" && !valid);
}
function coverage(goal, gaps, stage) {
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
}
function selectDirect(root, goal) {
    const envelope = dict(read(goal), "migration_required:direct-goal/1");
    require(envelope.schema === "direct-goal/1", "migration_required:direct-goal/1");
    bundleShape(envelope.bundle, root);
    const bundle = dict(envelope.bundle, "direct_requires_one_goal");
    const goals = bundle.goals;
    require(Array.isArray(goals) && goals.length === 1, "direct_requires_one_goal");
    return { bundle, selected: [text(goals[0]?.id)], subject: digestFile(goal), entry: null };
}
function oneMatch(root, handoff, matches) {
    if (matches.length === 0) {
        legacyHandoff(root, handoff);
    }
    require(matches.length === 1, "handoff_missing_or_ambiguous");
    return matches[0];
}
function legacyHandoff(root, handoff) {
    const manifest = read(relativePath(root, MANIFEST));
    const branches = isDict(manifest) && Array.isArray(manifest.optional_branches) ? manifest.optional_branches : [];
    const found = branches.filter((branch) => legacyMatch(branch, handoff));
    require(found.length !== 1, "migration_required:registered legacy handoff; use migrate-handoff.sh");
}
function legacyMatch(branch, handoff) {
    const identity = branch.id;
    if (typeof identity !== "string" || !identity.startsWith("northstar-handoff-")) {
        return false;
    }
    const path = ".ai/handoff/northstar-" + identity.slice("northstar-handoff-".length) + ".md";
    return handoff === identity || handoff === path || handoff === branch.handoff_path;
}
export function select(root, args) {
    require(Boolean(args.goal) !== Boolean(args.handoff), "selection_required:use exact --handoff with --goal-id or explicit --goal");
    if (args.goal) {
        return selectDirect(root, args.goal);
    }
    require(Array.isArray(args.goal_id) && new Set(args.goal_id).size === args.goal_id.length, "goal_selection_required");
    const registryPath = resolve(root, REGISTRY);
    const manifest = dict(exists(registryPath) ? read(registryPath) : { schema: VERSION, plans: [] }, "unsupported_registry_schema");
    require(manifest.schema === VERSION, "unsupported_registry_schema");
    const matches = (Array.isArray(manifest.plans) ? manifest.plans : []).filter((item) => args.handoff === item.id || args.handoff === item.handoff_path);
    const entry = oneMatch(root, args.handoff ?? "", matches);
    require(entry.schema === VERSION, "migration_required:registered handoff");
    require(entry.status === "active" || (args.stage === "planning" && entry.status === "blocked"), "handoff_not_active");
    const generation = text(entry.generation);
    require(SHA.test(generation), "invalid_generation");
    const prefix = `${GEN}/${text(entry.plan_id)}/${generation}/`;
    const artifacts = dict(entry.artifacts, "incomplete_generation");
    require(Object.keys(artifacts).sort().join("\n") === "bundle\ngraph\nhandoff", "incomplete_generation");
    const loadedPaths = {};
    for (const [name, ref] of Object.entries(artifacts)) {
        const record = dict(ref, "incomplete_generation");
        require(text(record.path).startsWith(prefix), "mixed_generation");
        fileRef(root, record);
        loadedPaths[name] = relativePath(root, record.path);
    }
    require(entry.handoff_path === artifacts.handoff.path, "handoff_path_mismatch");
    const loaded = dict(read(loadedPaths.bundle ?? ""), "plan_identity_mismatch");
    bundleShape(loaded, root);
    require(entry.plan_id === loaded.id, "plan_identity_mismatch");
    require((args.goal_id ?? []).every((id) => loaded.goals.some((goal) => goal.id === id)), "requested_goal_missing");
    require(generation === canonical(loaded), "generation_digest_mismatch");
    const graph = dict(read(loadedPaths.graph ?? ""), "graph_identity_mismatch");
    require(graph.generation === generation && sameValue(graph.goal_ids, loaded.goals.map((goal) => goal.id)), "graph_identity_mismatch");
    const live = dict(read(relativePath(root, GRAPH)), "generation_graph_missing");
    const liveNodes = new Map();
    for (const node of Array.isArray(live.nodes) ? live.nodes : []) {
        liveNodes.set(text(node.id), node);
    }
    for (const node of Array.isArray(graph.nodes) ? graph.nodes : []) {
        const current = liveNodes.get(text(node.id));
        require(current !== undefined, "generation_graph_missing");
        const liveNode = current;
        require(["id", "type", "repo_id", "path", "status"].every((key) => sameValue(liveNode[key], node[key])), "generation_graph_identity_mismatch");
    }
    for (const edge of Array.isArray(graph.edges) ? graph.edges : []) {
        const source = liveNodes.get(text(edge.source));
        const target = liveNodes.get(text(edge.target));
        const edges = Array.isArray(live.edges) ? live.edges : [];
        const linked = edges.some((item) => sameValue(item, edge));
        const sourceLinks = Array.isArray(target?.backlinks) ? target.backlinks : [];
        const targetLinks = Array.isArray(source?.backlinks) ? source.backlinks : [];
        require(linked && sourceLinks.includes(edge.source) && targetLinks.includes(edge.target), "generation_graph_link_missing");
    }
    return { bundle: loaded, selected: args.goal_id ?? [], subject: digestFile(loadedPaths.bundle ?? ""), entry };
}
function checkAuthority(context, stage, subject, gaps) {
    try {
        const authority = dict(context.authority, "independent_authority_required");
        require(authority.status === "pass" && authority.stage === stage && authority.subject_sha256 === subject, "independent_authority_required");
    }
    catch (error) {
        add(gaps, "authority_unavailable", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
    }
}
function applyDigests(root, gates, stage, context, resolved) {
    for (const gate of gates) {
        if (gate.stage !== stage || gate.kind !== "file_digest") {
            continue;
        }
        fileRef(root, gate);
        resolved.push({
            gate: gate.id, stage, scope: gate.scope, status: "ready",
            source: { policy: POLICY, sha256: context.policy.sha256 },
            responsible: gate.responsible ?? "unassigned", evidence_refs: [],
            freshness: { observed_at: "current-file-read", expires_at: "not-declared" },
            recovery: "Retain while exact binding and freshness remain valid; does not authorize dispatch",
        });
    }
}
function notApplicable(policy, context, stage, resolved, goals) {
    const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
    const gates = Array.isArray(policy.gates) ? policy.gates : [];
    for (const dimension of Object.keys(exclusions).sort()) {
        const covered = gates.some((gate) => gate.stage === stage && text(gate.dimension) === dimension);
        if (covered) {
            continue;
        }
        resolved.push({
            gate: dimension, stage, scope: { goals }, status: "not_applicable",
            source: { policy: POLICY, sha256: context.policy.sha256 }, responsible: "unassigned",
            evidence_refs: [], freshness: "current-policy-digest", recovery: "Reevaluate if repository policy changes",
            reason: exclusions[dimension],
        });
    }
}
const TYPED = new Set(["ownership", "branch_target", "fixture", "protected_approval", "harness_trust", "tooling"]);
function gateShape(gate) {
    require(ID.test(text(gate.id)), "gate_id_required");
    require(STAGES.includes(text(gate.stage)) && string(gate.kind), "unknown_gate_stage_or_kind");
    const allowed = new Set(["id", "stage", "scope", "kind", "dimension", "responsible", "root"]);
    require(gate.root === undefined || gate.root === "planning" || gate.root === "execution", "invalid_gate_root");
    const kind = text(gate.kind);
    if (kind === "file_digest") {
        allowed.add("path");
        allowed.add("sha256");
    }
    else if (kind === "executable_presence") {
        allowed.add("path");
    }
    else if (TYPED.has(kind)) {
        allowed.add("binding");
        require(isDict(gate.binding), "typed_binding_required");
    }
    require(Object.keys(gate).every((key) => allowed.has(key)), "unsupported_gate_fields");
}
function explicitScope(scope, ids) {
    if (!isDict(scope)) {
        return false;
    }
    if (Object.keys(scope).length === 1 && scope.repository === true) {
        return true;
    }
    return Object.keys(scope).length === 1 && Array.isArray(scope.goals) && scope.goals.length > 0
        && scope.goals.every((id) => typeof id === "string" && ids.includes(id));
}
function filesUnder(root, dir) {
    const found = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const path = resolve(dir, entry.name);
        if (entry.isDirectory()) {
            found.push(...filesUnder(root, path));
        }
        else if (entry.isFile()) {
            found.push(path.slice(root.length + 1));
        }
    }
    return found;
}
function instructionSources(root) {
    const names = ["AGENTS.md", ".rules.ts"].filter((name) => isFile(resolve(root, name)));
    const rules = resolve(root, ".ai/rules");
    if (exists(rules) && statSync(rules).isDirectory()) {
        names.push(...filesUnder(root, rules));
    }
    return names;
}
function executable(path) {
    try {
        accessSync(path, constants.X_OK);
        return true;
    }
    catch {
        return false;
    }
}
function measured(goal) {
    const percent = goal.coverage_percent;
    return (goal.coverage_status ?? "measured") === "measured" && typeof percent === "number" && percent >= 0 && percent <= 100;
}
function extraGates(root, bundle, gates, stage, gaps) {
    const ids = bundle.goals.map((goal) => text(goal.id));
    for (const gate of gates) {
        if (gate.stage !== stage) {
            continue;
        }
        const scope = gate.scope;
        const repositoryWide = isDict(scope) && scope.repository === true;
        const targets = repositoryWide ? ids : (isDict(scope) && Array.isArray(scope.goals) ? scope.goals : []);
        if (!repositoryWide && targets.every((id) => !ids.includes(id))) {
            continue;
        }
        const kind = text(gate.kind);
        if (kind === "file_digest" || TYPED.has(kind) || kind === "independent_result") {
            continue;
        }
        try {
            if (kind === "executable_presence") {
                const path = relativePath(root, gate.path);
                require(isFile(path) && executable(path), "executable_unavailable");
            }
            else if (kind === "measured_coverage") {
                const wanted = new Set(targets);
                require(bundle.goals.filter((goal) => wanted.has(text(goal.id))).every(measured), "measured_coverage_required");
            }
            else {
                add(gaps, "unsupported_gate", kind, scope, stage, "unknown");
            }
        }
        catch (error) {
            const message = error instanceof Error ? error.message : String(error);
            const unavailable = ["unavailable", "missing", "required", "No such file"].some((token) => message.includes(token));
            add(gaps, "gate_failed", text(gate.id) + ":" + message, scope, stage, unavailable ? "unknown" : "blocked");
        }
    }
}
function policyOk(root, bundle, context, stage, subject, gaps, resolved) {
    require(context.schema === "readiness-context/1", "independent_context_required");
    repository(context.repository, root);
    const policy = dict(read(relativePath(root, POLICY)), "unsupported_policy_schema");
    require(policy.schema === "readiness-policy/1", "unsupported_policy_schema");
    const allowed = ["schema", "repository", "sources", "gates", "not_applicable", "extensions"];
    require(Object.keys(policy).every((key) => allowed.includes(key)), "unsupported_policy_fields");
    require(JSON.stringify(policy.repository) === JSON.stringify(bundle.repository), "policy_repository_mismatch");
    const approved = dict(context.policy, "unapproved_policy_revision");
    require(approved.sha256 === digestFile(relativePath(root, POLICY)), "unapproved_policy_revision");
    const sources = policy.sources;
    require(Array.isArray(sources) && JSON.stringify(sources) === JSON.stringify(context.sources), "policy_source_set_mismatch");
    const listed = new Set(sources.map((source) => text(source.path)));
    require(instructionSources(root).every((name) => listed.has(name)), "policy_source_set_incomplete");
    for (const source of sources) {
        fileRef(root, source);
    }
    const exclusions = dict(policy.not_applicable, "explicit_not_applicable_reasons_required");
    const gates = Array.isArray(policy.gates) ? policy.gates : [];
    const ids = bundle.goals.map((goal) => text(goal.id));
    for (const gate of gates) {
        gateShape(gate);
        require(explicitScope(gate.scope, ids), "explicit_gate_scope_required");
    }
    const covered = new Set(gates.map((gate) => text(gate.dimension)));
    require(DIMENSIONS.every((item) => item in exclusions || covered.has(item)), "policy_dimensions_required");
    notApplicable(policy, context, stage, resolved, ids);
    checkAuthority(context, stage, subject, gaps);
    applyDigests(root, gates, stage, context, resolved);
    extraGates(root, bundle, gates, stage, gaps);
    for (const goal of bundle.goals) {
        coverage(goal, gaps, stage);
    }
}
function goalRequirements(goal, gaps, stage) {
    const requirements = goal.requirements ?? [];
    if (!Array.isArray(requirements)) {
        add(gaps, "goal_requirement_invalid", "Expected requirement array", [goal.id], stage);
        return;
    }
    for (const gate of requirements) {
        if (!isDict(gate) || !string(gate.id) || !ID.test(text(gate.id)) || !STAGES.includes(text(gate.stage)) || !string(gate.kind)) {
            add(gaps, "goal_requirement_invalid", "Requires id, stage and typed kind", [goal.id], stage);
            continue;
        }
        try {
            gateShape(gate);
        }
        catch (error) {
            add(gaps, "goal_requirement_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage);
        }
    }
}
function goalGaps(root, goal, gaps, stage) {
    coverage(goal, gaps, stage);
    goalRequirements(goal, gaps, stage);
    const readiness = goal.readiness;
    if (readiness[stage] !== "ready") {
        const status = readiness[stage] === "unknown" ? "unknown" : "blocked";
        add(gaps, "goal_not_ready", readiness[stage], [goal.id], stage, status);
    }
    try {
        validateCommands(root, goal.verification);
    }
    catch (error) {
        add(gaps, "verification_invalid", error instanceof Error ? error.message : String(error), [goal.id], stage);
    }
}
function fillReport(root, args, report, stage) {
    require([MANIFEST, GRAPH, ".ai/matrix.json"].every((name) => isFile(resolve(root, name))), "v3_root_required");
    const selected = select(root, args);
    const context = args.context ? read(args.context) : {};
    report.plan_id = selected.bundle.id;
    report.repository = selected.bundle.repository;
    report.bundle = { schema: selected.bundle.schema, id: selected.bundle.id, canonical_sha256: canonical(selected.bundle) };
    report.specification = selected.bundle.spec;
    report.goals = selected.selected;
    report.planning_complete = selected.bundle.planning_complete;
    report.handoff = selected.entry;
    report.subject_sha256 = selected.subject;
    const gaps = report.gaps;
    const resolved = report.resolved;
    const stages = stage === "planning" ? ["preparation", "implementation", "merge"] : [stage];
    for (const item of stages) {
        collectGaps(root, selected, context, item, gaps, resolved);
    }
    scopeGoals(gaps, selected.selected);
    report.execution_ready = stage !== "planning" && gaps.length === 0;
    report.per_goal = perGoal(selected.selected, gaps, resolved, stages);
}
function collectGaps(root, selected, context, stage, gaps, resolved) {
    try {
        for (const goal of selected.bundle.goals) {
            if (selected.selected.includes(text(goal.id))) {
                goalGaps(root, goal, gaps, stage);
            }
        }
        if (isDict(context)) {
            policyOk(root, selected.bundle, context, stage, selected.subject, gaps, resolved);
        }
    }
    catch (error) {
        add(gaps, "policy_context_invalid", error instanceof Error ? error.message : String(error), "repository", stage, "unknown");
    }
}
export function admit(args) {
    const root = pyPath(String(args.root ?? "."));
    const stage = args.stage ?? "implementation";
    const report = {
        schema: VERSION, stage, repository_root: root, planning_complete: false, execution_ready: false,
        dispatch_authorized: false, authority_verification: "external-required", goals: args.goal_id ?? [], gaps: [], resolved: [],
    };
    try {
        fillReport(root, args, report, stage);
    }
    catch (error) {
        add(report.gaps, "admission_failed", error instanceof Error ? error.message : String(error), "repository", stage);
    }
    report.remaining_blockers = report.gaps;
    return report;
}
function scopeGoals(gaps, selected) {
    for (const gap of gaps) {
        gap.blocked_goals = selected;
        if (gap.scope !== "repository") {
            gap.scope = { goals: selected };
        }
    }
}
function perGoal(selected, gaps, resolved, stages) {
    const out = {};
    for (const id of selected) {
        const record = {};
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
export function migrate(args) {
    const root = pyPath(String(args.root ?? "."));
    const legacy = read(String(args.legacy));
    const supplied = read(String(args.bundle));
    bundleShape(supplied, root);
    const bundle = structuredClone(supplied);
    const extensions = isDict(bundle.extensions) ? bundle.extensions : {};
    require(!("legacy_original" in extensions), "migration_extension_collision");
    extensions.legacy_original = legacy;
    extensions.legacy_sha256 = digestFile(String(args.legacy));
    bundle.extensions = extensions;
    for (const goal of bundle.goals) {
        goal.readiness = { preparation: "unknown", implementation: "unknown", merge: "unknown" };
    }
    return { schema: VERSION, bundle, dispatch_authorized: false, execution_ready: false, authority_verification: "external-required", next: "Review retained evidence; publish explicitly; revalidate independently" };
}
export function main(argv) {
    try {
        const args = parseArgs(argv);
        const result = args.operation === "publish" ? publish(args) : args.operation === "migrate" ? migrate(args) : admit(args);
        process.stdout.write(dumps(result, 2, true) + "\n");
        const gaps = Array.isArray(result.gaps) ? result.gaps : [];
        const planning = args.stage === "planning" && result.planning_complete === true && "per_goal" in result;
        return gaps.length > 0 && !planning ? 1 : 0;
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        process.stdout.write(dumps({ schema: VERSION, error: message, execution_ready: false, dispatch_authorized: false, authority_verification: "external-required" }) + "\n");
        return 1;
    }
}
function assignFlag(args, flag, value, index) {
    if (!flag.startsWith("--") || value === undefined) {
        return index;
    }
    const key = flag.slice(2).replaceAll("-", "_");
    args[key] = value;
    return index + 1;
}
function parseArgs(argv) {
    const args = { root: ".", stage: "implementation", goal_id: null };
    const operation = argv[0];
    if (operation !== "admit" && operation !== "publish" && operation !== "migrate") {
        const shown = operation ?? "";
        process.stderr.write("invalid choice: '" + shown + "' (choose from 'admit', 'publish', 'migrate')\n");
        throw new Invalid("invalid choice: '" + shown + "' (choose from 'admit', 'publish', 'migrate')");
    }
    args.operation = operation;
    for (let index = 1; index < argv.length; index += 1) {
        const flag = argv[index] ?? "";
        const value = argv[index + 1];
        if (flag === "--goal-id" && value !== undefined) {
            args.goal_id = [...(args.goal_id ?? []), value];
            index += 1;
        }
        else {
            index = assignFlag(args, flag, value, index);
        }
    }
    return args;
}
