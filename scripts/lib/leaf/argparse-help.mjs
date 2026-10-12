import { spawnSync } from "node:child_process";
// Argparse renamed this heading in 3.10. The anchor's --help is that formatter.
export function optionHeading() {
    const probed = spawnSync("python3", ["-c", "import sys; print(0 if sys.version_info >= (3, 10) else 1)"], {
        encoding: "utf8",
    });
    return probed.stdout.trim() === "0" ? "options:" : "optional arguments:";
}
const NEGATIVE_NUMBER = /^-\d+(\.\d*)?$|^-\.\d+$/;
// Argparse will not consume a following token that parses as an optional.
export function optionLike(token) {
    return token !== undefined && token.length > 1 && token.startsWith("-") && !NEGATIVE_NUMBER.test(token);
}
export function helpRequested(argv, takesValue) {
    let skip = false;
    for (const flag of argv) {
        if (skip) {
            skip = false;
            continue;
        }
        if (takesValue.has(flag)) {
            skip = true;
            continue;
        }
        if (flag === "-h" || flag === "--help") {
            return true;
        }
    }
    return false;
}
export function writeHelp(usage, options) {
    process.stdout.write(`${usage}\n\n${optionHeading()}\n${options}`);
}
//# sourceMappingURL=argparse-help.mjs.map