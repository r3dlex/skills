import { writeFileSync } from "node:fs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { CatalogError, loadCatalog, projection, select } from "./catalog-model.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
function fail(message) {
    process.stderr.write(`${message}\n`);
    return 2;
}
function take(args, flag, value) {
    if (value === undefined) {
        return false;
    }
    if (flag === "--root") {
        args.root = value;
    }
    else if (flag === "--host") {
        args.host = value;
    }
    else if (flag === "--include-lifecycle") {
        args.lifecycles.push(value);
    }
    else if (flag === "--skill") {
        args.skill = value;
    }
    else if (flag === "--projection") {
        args.projection = value;
    }
    else {
        return false;
    }
    return true;
}
function parse(argv, fallbackRoot) {
    const args = { root: fallbackRoot, lifecycles: [] };
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index] ?? "";
        if (!take(args, flag, argv[index + 1])) {
            return fail(`unrecognized arguments: ${flag}`);
        }
        index += 1;
    }
    return args.host === undefined ? fail("the following arguments are required: --host") : args;
}
export function main(argv, root = repoRoot(import.meta.url)) {
    const parsed = parse(argv, root);
    if (typeof parsed === "number") {
        return parsed;
    }
    const unknown = parsed.lifecycles.filter((item) => !["stable", "compatibility", "experimental", "deprecated"].includes(item)).sort();
    const first = unknown[0];
    if (first !== undefined) {
        return fail(`unknown lifecycle: ${first}`);
    }
    try {
        const payload = loadCatalog(parsed.root);
        const entries = select(payload, parsed.host ?? "", new Set(parsed.lifecycles), parsed.skill);
        if (parsed.projection !== undefined) {
            writeFileSync(parsed.projection, `${JSON.stringify(projection(payload, entries), null, 2)}\n`);
        }
        for (const entry of entries) {
            process.stdout.write(`${entry.name}\t${entry.source_path}\n`);
        }
        return 0;
    }
    catch (error) {
        const message = error instanceof CatalogError ? error.message : "catalog query failed";
        return fail(message);
    }
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=catalog-query.mjs.map