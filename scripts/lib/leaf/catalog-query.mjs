import { writeFileSync } from "node:fs";
import { helpRequested, optionLike, writeHelp } from "./argparse-help.mjs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { CatalogError, loadCatalog, projection, select } from "./catalog-model.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
const USAGE = [
    "usage: catalog-query.py [-h] [--root ROOT] --host HOST",
    "                        [--include-lifecycle INCLUDE_LIFECYCLE]",
    "                        [--skill SKILL] [--projection PROJECTION]",
].join("\n");
const OPTIONS = new Set(["--root", "--host", "--include-lifecycle", "--skill", "--projection"]);
function fail(message) {
    process.stderr.write(`${message}\n`);
    return 2;
}
function argparseFail(message) {
    process.stderr.write(`${USAGE}\ncatalog-query.py: error: ${message}\n`);
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
function splitEquals(token) {
    const eq = token.indexOf("=");
    if (token.startsWith("--") && eq > 2) {
        return { flag: token.slice(0, eq), inline: token.slice(eq + 1) };
    }
    return { flag: token };
}
function resolveOption(flag) {
    if (OPTIONS.has(flag)) {
        return flag;
    }
    if (!flag.startsWith("--") || flag.length < 3) {
        return undefined;
    }
    const matches = [...OPTIONS].filter((option) => option.startsWith(flag));
    return matches.length === 1 ? matches[0] : undefined;
}
function missingArgument(inline, next) {
    return inline === undefined && (next === undefined || optionLike(next));
}
function parse(argv, fallbackRoot) {
    const args = { root: fallbackRoot, lifecycles: [] };
    const unknown = [];
    for (let index = 0; index < argv.length; index += 1) {
        const token = argv[index] ?? "";
        const parts = splitEquals(token);
        const flag = resolveOption(parts.flag);
        if (flag === undefined) {
            unknown.push(token);
            continue;
        }
        const inline = parts.inline;
        const next = argv[index + 1];
        if (missingArgument(inline, next)) {
            return argparseFail(`argument ${flag}: expected one argument`);
        }
        const value = inline ?? next;
        if (!take(args, flag, value)) {
            return argparseFail(`unrecognized arguments: ${flag}`);
        }
        if (inline === undefined) {
            index += 1;
        }
    }
    if (args.host === undefined) {
        return argparseFail("the following arguments are required: --host");
    }
    return unknown.length === 0 ? args : argparseFail(`unrecognized arguments: ${unknown.join(" ")}`);
}
const CATALOG_HELP_OPTIONS = [
    "  -h, --help            show this help message and exit",
    "  --root ROOT",
    "  --host HOST",
    "  --include-lifecycle INCLUDE_LIFECYCLE",
    "  --skill SKILL",
    "  --projection PROJECTION",
    "",
].join("\n");
export function main(argv, root = repoRoot(import.meta.url)) {
    if (helpRequested(argv, OPTIONS)) {
        writeHelp(USAGE, CATALOG_HELP_OPTIONS);
        return 0;
    }
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
        if (parsed.projection) {
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