import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
assertNodeVersion();
function run(cmd, args, cwd) {
    const result = spawnSync(cmd, args, { cwd, encoding: "utf8" });
    return { status: result.status ?? 1, out: result.stdout ?? "", err: result.stderr ?? "" };
}
function same(label, left, right) {
    if (left.status === right.status && left.out === right.out && left.err === right.err) {
        process.stdout.write(`parity ok: ${label}\n`);
        return true;
    }
    process.stderr.write(`parity diverge: ${label} legacy=${left.status} ts=${right.status}\n`);
    process.stderr.write(`legacy stdout: ${left.out}\nlegacy stderr: ${left.err}\n`);
    process.stderr.write(`ts stdout: ${right.out}\nts stderr: ${right.err}\n`);
    return false;
}
function materialize(root, anchor, path, dest) {
    const shown = spawnSync("git", ["-C", root, "show", `${anchor}:${path}`], { encoding: "buffer" });
    if (shown.status !== 0) {
        throw new Error(`cannot materialize ${path}`);
    }
    writeFileSync(dest, shown.stdout);
}
function scanSecret(root, anchor, dir) {
    const legacyScan = join(dir, "scan-secret-material.py");
    if (anchor !== "") {
        materialize(root, anchor, "scripts/scan-secret-material.py", legacyScan);
    }
    const legacyBin = anchor === "" ? join(root, "scripts/scan-secret-material.py") : legacyScan;
    const portBin = join(root, "scripts/lib/leaf/scan-secret-material.mjs");
    let failed = same("scan-secret clean", run("python3", [legacyBin], dir), run("node", [portBin], dir)) ? 0 : 1;
    writeFileSync(join(dir, "secret.txt"), "-----BEGIN PRIVATE KEY-----\nfixture\n");
    if (!same("scan-secret hit", run("python3", [legacyBin], dir), run("node", [portBin], dir))) {
        failed += 1;
    }
    return failed;
}
export function main(root = process.cwd(), anchor = "") {
    let failed = 0;
    const dir = mkdtempSync(join(tmpdir(), "e6-secret-"));
    try {
        const queryArgs = ["--root", root, "--host", "codex"];
        const legacyBin = anchor === "" ? join(root, "scripts/catalog-query.py") : join(dir, "catalog-query.py");
        if (anchor !== "") {
            materialize(root, anchor, "scripts/catalog-query.py", join(dir, "catalog-query.py"));
            materialize(root, anchor, "scripts/catalog.py", join(dir, "catalog.py"));
            materialize(root, anchor, "scripts/validate_skill_frontmatter.py", join(dir, "validate_skill_frontmatter.py"));
        }
        const legacy = run("python3", [legacyBin, ...queryArgs], root);
        const port = run("node", [join(root, "scripts/lib/leaf/catalog-query.mjs"), ...queryArgs], root);
        if (!same("catalog-query codex", legacy, port)) {
            failed += 1;
        }
        failed += scanSecret(root, anchor, dir);
    }
    finally {
        rmSync(dir, { recursive: true, force: true });
    }
    return failed === 0 ? 0 : 1;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.cwd(), process.argv[2] ?? ""));
}
//# sourceMappingURL=leaf-parity.mjs.map