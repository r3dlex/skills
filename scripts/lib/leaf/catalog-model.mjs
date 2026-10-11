import { readFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";
import { frontmatterName } from "./frontmatter.mjs";
import { pyRepr } from "./py-repr.mjs";
export const LIFECYCLES = new Set(["stable", "compatibility", "experimental", "deprecated"]);
export const HOSTS = new Set(["codex", "claude-code", "gemini", "copilot", "auggie", "opencode"]);
export const DEFAULT_LIFECYCLES = new Set(["stable", "compatibility"]);
export class CatalogError extends Error {
    constructor(message) {
        super(message);
        this.name = "CatalogError";
    }
}
const REQUIRED = ["name", "source_path", "owner_phase", "applies_to_phases", "lifecycle", "supported_hosts"];
function asRecord(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value)
        ? value
        : undefined;
}
function uniqueStrings(value) {
    if (!Array.isArray(value) || value.length === 0 || value.some((item) => typeof item !== "string" || item === "")) {
        return undefined;
    }
    const phases = value;
    return new Set(phases).size === phases.length ? phases : undefined;
}
function missingFields(entry) {
    return REQUIRED.some((field) => !(field in entry));
}
function rejectSource(name, source) {
    if (typeof source !== "string" || source === "") {
        throw new CatalogError(`invalid source_path for ${name}: ${pyRepr(source)}`);
    }
    const parts = source.split("/");
    if (isAbsolute(source) || parts.includes("..")) {
        throw new CatalogError(`duplicate or unsafe source_path: ${pyRepr(source)}`);
    }
    return source;
}
function rejectPhases(name, owner, applies, phases) {
    if (typeof owner !== "string" || !Array.isArray(applies) || applies.some((item) => typeof item !== "string")) {
        throw new CatalogError(`invalid phase metadata types for ${name}`);
    }
    const phaseSet = new Set(phases);
    if (!phaseSet.has(owner) || applies.some((item) => !phaseSet.has(item))) {
        throw new CatalogError(`invalid phase metadata for ${name}`);
    }
}
function rejectHosts(name, hosts) {
    if (!Array.isArray(hosts) || hosts.some((item) => typeof item !== "string") || hosts.some((item) => !HOSTS.has(item))) {
        throw new CatalogError(`invalid supported_hosts for ${name}`);
    }
    return hosts;
}
function acceptSkill(root, raw, phases, names, paths) {
    const entry = asRecord(raw);
    if (entry === undefined || missingFields(entry)) {
        throw new CatalogError("catalog skill entry is missing required fields");
    }
    const name = entry.name;
    if (typeof name !== "string" || name === "" || names.has(name)) {
        throw new CatalogError(`duplicate or invalid skill name: ${pyRepr(name)}`);
    }
    const source = rejectSource(name, entry.source_path);
    if (paths.has(source)) {
        throw new CatalogError(`duplicate or unsafe source_path: ${pyRepr(source)}`);
    }
    rejectPhases(name, entry.owner_phase, entry.applies_to_phases, phases);
    const lifecycle = entry.lifecycle;
    if (typeof lifecycle !== "string" || !LIFECYCLES.has(lifecycle)) {
        throw new CatalogError(`invalid lifecycle for ${name}`);
    }
    rejectHosts(name, entry.supported_hosts);
    confirmSkillFile(root, name, source);
    names.add(name);
    paths.add(source);
}
function confirmSkillFile(root, name, source) {
    try {
        if (frontmatterName(join(root, source, "SKILL.md")) !== name) {
            throw new CatalogError(`frontmatter name mismatch for ${name}: ${source}`);
        }
    }
    catch (error) {
        if (error instanceof CatalogError) {
            throw error;
        }
        throw new CatalogError(`missing SKILL.md for ${name}: ${source}`);
    }
}
function readPayload(root) {
    try {
        return JSON.parse(readFileSync(join(root, "catalog.json"), "utf8"));
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        throw new CatalogError(`invalid catalog: ${message}`);
    }
}
export function loadCatalog(root) {
    const payload = asRecord(readPayload(root));
    if (payload?.schema_version !== "1.0") {
        throw new CatalogError("catalog schema_version must be 1.0");
    }
    const phases = uniqueStrings(payload.phases);
    if (phases === undefined) {
        throw new CatalogError("phases must be a non-empty unique list");
    }
    if (!Array.isArray(payload.skills)) {
        throw new CatalogError("skills must be a list");
    }
    const names = new Set();
    const paths = new Set();
    for (const raw of payload.skills) {
        acceptSkill(root, raw, phases, names, paths);
    }
    return payload;
}
export function select(payload, host, included, name) {
    if (!HOSTS.has(host)) {
        throw new CatalogError(`unknown host: ${host}`);
    }
    const enabled = new Set([...DEFAULT_LIFECYCLES, ...(included ?? [])]);
    const unknown = [...enabled].filter((item) => !LIFECYCLES.has(item)).sort();
    const firstUnknown = unknown[0];
    if (firstUnknown !== undefined) {
        throw new CatalogError(`unknown lifecycle: ${firstUnknown}`);
    }
    let entries = payload.skills.filter((entry) => entry.supported_hosts.includes(host) && enabled.has(entry.lifecycle));
    if (name) {
        const matches = payload.skills.filter((entry) => entry.name === name && entry.supported_hosts.includes(host));
        const match = matches[0];
        if (match === undefined) {
            throw new CatalogError(`unknown skill for ${host}: ${name}`);
        }
        if (!enabled.has(match.lifecycle)) {
            throw new CatalogError(`skill ${name} requires --include-lifecycle ${match.lifecycle}`);
        }
        entries = [match];
    }
    return [...entries].sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0));
}
export function projection(payload, entries) {
    return { schema_version: payload.schema_version, skills: [...entries] };
}
export function catalogPath(root, source) {
    return resolve(root, source);
}
//# sourceMappingURL=catalog-model.mjs.map