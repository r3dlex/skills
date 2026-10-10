import { readFileSync } from "node:fs";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { compareMeasured } from "./freeze-compare.mjs";
import { classChanges, compareInventory, excluded, inventoryPaths, tracked } from "./freeze-inventory.mjs";
import { measure } from "./freeze-measure.mjs";
import { run, text } from "./proc.mjs";
assertNodeVersion();
const BASELINE = ".ai/rules/legacy-freeze-baseline.json";
export function loadBaseline(root, path = BASELINE) {
    return JSON.parse(readFileSync(`${root}/${path}`, "utf8"));
}
export function originBaseline(root) {
    const shown = run("git", ["show", `origin/main:${BASELINE}`], root);
    if (shown.status !== 0) {
        return undefined;
    }
    return JSON.parse(text(shown.stdout));
}
function shellFiles(root, baseline) {
    return tracked(root).filter((path) => path.endsWith(".sh") && !excluded(path, baseline.excludes)).sort();
}
export function check(root, baseline = loadBaseline(root), previous) {
    const present = new Set(inventoryPaths(root, baseline));
    const problems = compareInventory(present, baseline.entries);
    if (previous !== undefined) {
        problems.push(...classChanges(previous.entries, baseline.entries, present));
    }
    const py = [...present].filter((path) => path.endsWith(".py") && !excluded(path, baseline.excludes));
    const sh = shellFiles(root, baseline).filter((path) => !excluded(path, baseline.excludes));
    try {
        problems.push(...compareMeasured(measure(root, py, sh), baseline.measured));
    }
    catch (error) {
        problems.push(error instanceof Error ? error.message : "measure_failed");
    }
    return problems;
}
export function main(argv) {
    if (argv[0] === "--measure") {
        const root = argv[1] ?? process.cwd();
        const baseline = loadBaseline(root);
        const py = tracked(root).filter((path) => path.endsWith(".py") && !excluded(path, baseline.excludes));
        const sh = shellFiles(root, baseline);
        process.stdout.write(`${JSON.stringify(measure(root, py, sh), null, 2)}\n`);
        return 0;
    }
    const root = argv[0] ?? process.cwd();
    const previous = argv[1] === undefined ? originBaseline(root) : loadBaseline(root, argv[1]);
    try {
        const problems = check(root, loadBaseline(root), previous);
        if (problems.length === 0) {
            process.stdout.write("legacy-freeze: pass\n");
            return 0;
        }
        for (const problem of problems) {
            process.stderr.write(`${problem}\n`);
        }
        return 1;
    }
    catch (error) {
        const message = error instanceof Error ? error.message : "legacy_freeze_failed";
        process.stderr.write(`${message}\n`);
        return 1;
    }
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=check-legacy-freeze.mjs.map