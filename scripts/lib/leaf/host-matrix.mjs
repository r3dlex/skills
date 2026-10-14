import { readFileSync } from "node:fs";
import { join } from "node:path";
import { HOSTS } from "./catalog-model.mjs";
export const HOST_MATRIX_FILE = "host-matrix.json";
export const HOST_MATRIX_SCHEMA = "host-matrix/1";
// Never a payload host, an alias or a consumer: omo-ai has no payload, mechanism
// or entrypoint contract (M-6); the oh-my-openagent OpenCode-plugin adapter is
// retired and quarantined (root AGENTS.md). Both are recorded under `excluded`.
export const QUARANTINED = new Set(["omo-ai", "oh-my-openagent"]);
const TOP_KEYS = ["schema", "payload_hosts", "aliases", "consumers", "excluded"];
const CONSUMER_KEYS = new Set(["installer", "also", "delivery"]);
export class HostMatrixError extends Error {
    constructor(reason) {
        super(`host_matrix_invalid: ${reason}`);
        this.name = "HostMatrixError";
    }
}
function plain(value, what) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
        throw new HostMatrixError(`${what} must be a JSON object`);
    }
    return value;
}
function nonEmptyString(value, what) {
    if (typeof value !== "string" || value === "") {
        throw new HostMatrixError(`${what} must be a non-empty string`);
    }
    return value;
}
function uniqueNames(value, what) {
    if (!Array.isArray(value)) {
        throw new HostMatrixError(`${what} must be a list`);
    }
    const names = value.map((item, index) => nonEmptyString(item, `${what}[${index}]`));
    if (new Set(names).size !== names.length) {
        throw new HostMatrixError(`${what} has a duplicate`);
    }
    return names;
}
function requireKeys(record, keys, what) {
    for (const key of keys) {
        if (!Object.hasOwn(record, key)) {
            throw new HostMatrixError(`${what} is missing ${key}`);
        }
    }
    for (const key of Object.keys(record)) {
        if (!keys.includes(key)) {
            throw new HostMatrixError(`${what} has an unexpected key: ${key}`);
        }
    }
}
function readPayloadHosts(value) {
    const hosts = uniqueNames(value, "payload_hosts");
    for (const host of hosts) {
        if (!HOSTS.has(host)) {
            throw new HostMatrixError(`payload host ${host} is not in HOSTS`);
        }
    }
    for (const host of HOSTS) {
        if (!hosts.includes(host)) {
            throw new HostMatrixError(`payload_hosts is missing ${host}`);
        }
    }
    return hosts;
}
function readAliases(value, hosts) {
    const aliases = {};
    for (const [alias, target] of Object.entries(plain(value, "aliases"))) {
        const resolved = nonEmptyString(target, `aliases.${alias}`);
        if (hosts.has(alias)) {
            throw new HostMatrixError(`alias ${alias} is a payload host`);
        }
        if (QUARANTINED.has(alias)) {
            throw new HostMatrixError(`alias ${alias} is quarantined`);
        }
        if (!hosts.has(resolved)) {
            throw new HostMatrixError(`alias ${alias} targets ${resolved}, which is not a payload host`);
        }
        aliases[alias] = resolved;
    }
    return aliases;
}
function readInstaller(host, record) {
    if (!Object.hasOwn(record, "installer")) {
        throw new HostMatrixError(`consumers.${host} is missing installer`);
    }
    const installer = record.installer;
    if (installer === null) {
        return null;
    }
    if (typeof installer !== "string" || !installer.startsWith("scripts/")) {
        throw new HostMatrixError(`consumers.${host}.installer must be null or a path under scripts/`);
    }
    return installer;
}
function readAlso(host, value, aliases) {
    const also = uniqueNames(value, `consumers.${host}.also`);
    for (const alias of also) {
        if (aliases[alias] !== host) {
            throw new HostMatrixError(`consumers.${host}.also names ${alias}, which is not an alias of ${host}`);
        }
    }
    return also;
}
function readConsumer(host, value, aliases) {
    const record = plain(value, `consumers.${host}`);
    for (const key of Object.keys(record)) {
        if (!CONSUMER_KEYS.has(key)) {
            throw new HostMatrixError(`consumers.${host} has an unexpected key: ${key}`);
        }
    }
    const consumer = { installer: readInstaller(host, record) };
    if (Object.hasOwn(record, "also")) {
        consumer.also = readAlso(host, record.also, aliases);
    }
    if (Object.hasOwn(record, "delivery")) {
        consumer.delivery = nonEmptyString(record.delivery, `consumers.${host}.delivery`);
    }
    return consumer;
}
function readConsumers(value, hosts, aliases) {
    const record = plain(value, "consumers");
    for (const host of Object.keys(record)) {
        if (!hosts.includes(host)) {
            throw new HostMatrixError(`consumer ${host} is not a payload host`);
        }
    }
    const consumers = {};
    for (const host of hosts) {
        if (!Object.hasOwn(record, host)) {
            throw new HostMatrixError(`payload host ${host} has no consumer`);
        }
        consumers[host] = readConsumer(host, record[host], aliases);
    }
    return consumers;
}
function readExcluded(value, hosts, aliases) {
    const excluded = {};
    for (const [name, reason] of Object.entries(plain(value, "excluded"))) {
        if (hosts.has(name)) {
            throw new HostMatrixError(`excluded ${name} is a payload host`);
        }
        if (Object.hasOwn(aliases, name)) {
            throw new HostMatrixError(`excluded ${name} is an alias`);
        }
        excluded[name] = nonEmptyString(reason, `excluded.${name}`);
    }
    return excluded;
}
function rejectSkillNames(names, skillNames, what) {
    for (const name of names) {
        if (skillNames.has(name)) {
            throw new HostMatrixError(`${what} ${name} is a catalog skill name`);
        }
    }
}
export function validateHostMatrix(raw, skillNames) {
    const record = plain(raw, HOST_MATRIX_FILE);
    requireKeys(record, TOP_KEYS, HOST_MATRIX_FILE);
    if (record.schema !== HOST_MATRIX_SCHEMA) {
        throw new HostMatrixError(`schema must be ${HOST_MATRIX_SCHEMA}`);
    }
    const payloadHosts = readPayloadHosts(record.payload_hosts);
    const hostSet = new Set(payloadHosts);
    const aliases = readAliases(record.aliases, hostSet);
    rejectSkillNames(payloadHosts, skillNames, "payload host");
    rejectSkillNames(Object.keys(aliases), skillNames, "alias");
    return {
        schema: HOST_MATRIX_SCHEMA,
        payload_hosts: payloadHosts,
        aliases,
        consumers: readConsumers(record.consumers, payloadHosts, aliases),
        excluded: readExcluded(record.excluded, hostSet, aliases),
    };
}
export function hostMatrixPath(root) {
    return join(root, HOST_MATRIX_FILE);
}
function isEnoent(error) {
    return error instanceof Error && "code" in error && error.code === "ENOENT";
}
function readMatrixText(path) {
    try {
        return readFileSync(path, "utf8");
    }
    catch (error) {
        if (isEnoent(error)) {
            return undefined;
        }
        throw new HostMatrixError(`cannot read ${HOST_MATRIX_FILE}: ${error instanceof Error ? error.message : String(error)}`);
    }
}
function parseMatrix(text) {
    try {
        return JSON.parse(text);
    }
    catch (error) {
        throw new HostMatrixError(`${HOST_MATRIX_FILE} is not valid JSON: ${error instanceof Error ? error.message : String(error)}`);
    }
}
// Reads host-matrix.json beside catalog.json at `root`. A root without the file
// declares no aliases (undefined): payload hosts behave as before and every other
// name stays an unknown host. A present but invalid matrix is refused with a
// host_matrix_invalid diagnostic and never applied in part.
export function loadHostMatrix(root, skillNames) {
    const text = readMatrixText(hostMatrixPath(root));
    return text === undefined ? undefined : validateHostMatrix(parseMatrix(text), skillNames);
}
export function resolveHost(matrix, host) {
    if (matrix === undefined || !Object.hasOwn(matrix.aliases, host)) {
        return host;
    }
    return matrix.aliases[host] ?? host;
}
//# sourceMappingURL=host-matrix.mjs.map