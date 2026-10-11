import { readFileSync } from "node:fs";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
assertNodeVersion();
export function productionDeps() {
    return {
        read: (path) => readFileSync(path, "utf8"),
        writeOut: (text) => {
            process.stdout.write(text);
        },
        writeErr: (text) => {
            process.stderr.write(text);
        },
    };
}
export function main(argv, deps = productionDeps()) {
    if (argv[0] !== "read") {
        deps.writeOut("e6-sample-ok\n");
        return 0;
    }
    const path = argv[1];
    if (path === undefined) {
        deps.writeErr("usage\n");
        return 2;
    }
    deps.writeOut(deps.read(path));
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=sample.mjs.map