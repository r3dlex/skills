import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { projection, select, loadCatalog, CatalogError } from "./catalog-model.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
const LIFECYCLES = new Set(["stable", "compatibility", "experimental", "deprecated"]);
export function parseCatalogArgs(argv) {
    const includes = [];
    const rest = [];
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index];
        if (flag !== "--include-lifecycle") {
            if (flag !== undefined) {
                rest.push(flag);
            }
            continue;
        }
        const value = argv[index + 1];
        if (value === undefined) {
            process.stderr.write("--include-lifecycle requires a value\n");
            return 2;
        }
        if (!LIFECYCLES.has(value)) {
            process.stderr.write(`unknown lifecycle: ${value}\n`);
            return 2;
        }
        includes.push(value);
        index += 1;
    }
    return { includes, rest };
}
export function catalogRows(root, host, includes, skill) {
    const payload = loadCatalog(root);
    const entries = select(payload, host, new Set(includes), skill);
    return {
        rows: entries.map((entry) => `${entry.name}\t${entry.source_path}`).join("\n"),
        projectionText: `${JSON.stringify(projection(payload, entries), null, 2)}\n`,
    };
}
export function writeProjection(dir, name, text) {
    mkdirSync(dir, { recursive: true });
    writeFileSync(join(dir, name), text);
}
export function failCatalog(error) {
    const message = error instanceof CatalogError ? error.message : "catalog query failed";
    process.stderr.write(`${message}\n`);
    return 2;
}
if (invokedDirectly(import.meta.url)) {
    const parsed = parseCatalogArgs(process.argv.slice(2));
    if (typeof parsed === "number") {
        process.exit(parsed);
    }
    try {
        const rows = catalogRows(repoRoot(import.meta.url), parsed.rest[0] ?? "", parsed.includes);
        process.stdout.write(rows.rows);
        process.exit(0);
    }
    catch (error) {
        process.exit(failCatalog(error));
    }
}
//# sourceMappingURL=catalog-install.mjs.map