import { pyRepr } from "./py-repr.mjs";
export const V10_TYPES = new Set([
    "brd", "prd", "adr", "plan", "issue", "pr", "test", "handoff", "workflow", "validation",
]);
export const V11_ADDED_TYPES = new Set(["eval-result", "trajectory-trace"]);
export const KNOWN_TYPES = new Set([...V10_TYPES, ...V11_ADDED_TYPES]);
function pyInt(part) {
    const stripped = part.trim();
    if (!/^[-+]?(?:\d+_)*\d+$/.test(stripped)) {
        throw new Error(`invalid literal for int() with base 10: '${part}'`);
    }
    return Number(stripped.replaceAll("_", ""));
}
export function parseVersion(value) {
    return String(value).split(".").map((part) => pyInt(part));
}
function below(version) {
    const floor = [1, 0];
    const length = Math.min(version.length, floor.length);
    for (let index = 0; index < length; index += 1) {
        const left = version[index] ?? 0;
        const right = floor[index] ?? 0;
        if (left < right) {
            return true;
        }
        if (left > right) {
            return false;
        }
    }
    return version.length < floor.length;
}
function pyMapping(value) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        return JSON.stringify(value);
    }
    const parts = Object.entries(value).map(([key, item]) => `${pyRepr(key)}: ${pyRepr(item)}`);
    return `{${parts.join(", ")}}`;
}
function asRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value)
        ? value
        : undefined;
}
function indexNodes(nodes) {
    const indexed = new Map();
    for (const raw of nodes) {
        const node = asRecord(raw);
        if (node === undefined) {
            throw new Error(`node is not an object: ${JSON.stringify(raw)}`);
        }
        const nodeId = node.id;
        if (typeof nodeId !== "string" || nodeId === "") {
            throw new Error("node missing id");
        }
        if (indexed.has(nodeId)) {
            throw new Error(`duplicate node id '${nodeId}'`);
        }
        indexed.set(nodeId, node);
    }
    return indexed;
}
function requireText(node, field) {
    const value = node[field];
    if (typeof value !== "string" || value === "") {
        throw new Error(`node ${String(node.id)} missing ${field}`);
    }
}
function checkNode(node, nodes) {
    const nodeType = node.type;
    if (typeof nodeType !== "string" || !KNOWN_TYPES.has(nodeType)) {
        throw new Error(`unknown node type ${typeof nodeType === "string" ? `'${nodeType}'` : "None"}`);
    }
    requireText(node, "title");
    requireText(node, "status");
    requireText(node, "repo_id");
    if (!node.path && !node.host_url) {
        throw new Error(`node ${String(node.id)} missing path/host_url`);
    }
    const backlinks = Array.isArray(node.backlinks) ? node.backlinks : [];
    for (const backlink of backlinks) {
        if (!nodes.has(String(backlink))) {
            throw new Error(`dangling backlink ${String(backlink)}`);
        }
    }
}
export function validateGraph(graph) {
    if (!("schema_version" in graph)) {
        throw new Error("graph missing schema_version");
    }
    const version = parseVersion(String(graph.schema_version));
    if (below(version)) {
        throw new Error(`unsupported schema_version ${String(graph.schema_version)}`);
    }
    const nodes = indexNodes(Array.isArray(graph.nodes) ? graph.nodes : []);
    for (const node of nodes.values()) {
        checkNode(node, nodes);
    }
    for (const raw of Array.isArray(graph.edges) ? graph.edges : []) {
        const edge = asRecord(raw) ?? {};
        if (!nodes.has(String(edge.source))) {
            throw new Error(`dangling edge source ${pyMapping(raw)}`);
        }
        if (!nodes.has(String(edge.target))) {
            throw new Error(`dangling edge target ${pyMapping(raw)}`);
        }
    }
}
//# sourceMappingURL=traceability.mjs.map