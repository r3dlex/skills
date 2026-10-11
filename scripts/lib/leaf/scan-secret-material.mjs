import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { pySplitlines } from "./py-text.mjs";
assertNodeVersion();
const SKIP = new Set([".git", ".omx", ".venv", "node_modules", "__pycache__"]);
const PATTERNS = [
    /-----BEGIN (?:RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY-----/,
    /gh[pousr]_[A-Za-z0-9_]{30,}/,
    /github_pat_[A-Za-z0-9_]{80,}/,
    /sk-[A-Za-z0-9]{32,}/,
    /xox[baprs]-[A-Za-z0-9-]{20,}/,
    /AKIA[0-9A-Z]{16}/,
];
function walk(root) {
    const found = [];
    for (const entry of readdirSync(root, { withFileTypes: true })) {
        const path = join(root, entry.name);
        if (entry.isDirectory()) {
            if (!SKIP.has(entry.name)) {
                found.push(...walk(path));
            }
        }
        else if (entry.isFile()) {
            found.push(path);
        }
    }
    return found;
}
function skipped(path) {
    return path.split("/").some((part) => SKIP.has(part));
}
export function main() {
    const offenders = [];
    for (const path of walk(".")) {
        if (skipped(path) || !statSync(path).isFile()) {
            continue;
        }
        let text;
        try {
            text = readFileSync(path, "utf8");
        }
        catch {
            continue;
        }
        pySplitlines(text).forEach((line, index) => {
            if (PATTERNS.some((pattern) => pattern.test(line))) {
                offenders.push(`${path}:${index + 1}`);
            }
        });
    }
    if (offenders.length > 0) {
        process.stdout.write("Potential committed secret material found:\n");
        process.stdout.write(`${offenders.join("\n")}\n`);
        return 1;
    }
    process.stdout.write("No committed secret material matched the guarded patterns.\n");
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main());
}
//# sourceMappingURL=scan-secret-material.mjs.map