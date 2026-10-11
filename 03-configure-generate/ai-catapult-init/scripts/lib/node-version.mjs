export const SUPPORTED_MAJOR = 26;
export const NODE_UNAVAILABLE = "node_unavailable";
export const NODE_VERSION_UNSUPPORTED = "node_version_unsupported";
export const EXIT_NODE_UNAVAILABLE = 127;
export const EXIT_NODE_VERSION_UNSUPPORTED = 126;
export function nodeMajor(version) {
    const head = version.replace(/^v/, "").split(".")[0] ?? "";
    const major = Number(head);
    return Number.isInteger(major) ? major : Number.NaN;
}
export function nodeVersionStatus(version) {
    return nodeMajor(version) === SUPPORTED_MAJOR ? "ok" : NODE_VERSION_UNSUPPORTED;
}
export function assertNodeVersion(version = process.versions.node) {
    if (nodeVersionStatus(version) === "ok") {
        return;
    }
    process.stderr.write(`${NODE_VERSION_UNSUPPORTED}\n`);
    process.exit(EXIT_NODE_VERSION_UNSUPPORTED);
}
//# sourceMappingURL=node-version.mjs.map