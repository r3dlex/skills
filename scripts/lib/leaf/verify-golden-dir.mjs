import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
assertNodeVersion();
function files(dir, prefix = "") {
    const found = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const rel = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
        if (entry.isDirectory()) {
            found.push(...files(join(dir, entry.name), rel));
        }
        else if (entry.isFile() && !entry.name.endsWith(".MARKER")) {
            found.push(rel);
        }
    }
    return found.sort();
}
function contentCheck(repo, golden) {
    process.stdout.write("--- Net-new file content check ---\n");
    let errors = 0;
    for (const file of files(golden)) {
        if (file === "upstream.lock") {
            process.stdout.write("SKIP: upstream.lock (SHA field excluded from content diff, validated below)\n");
            continue;
        }
        const repoFile = join(repo, file);
        if (!existsSync(repoFile)) {
            process.stdout.write(`MISSING: ${file}\n`);
            errors += 1;
            continue;
        }
        const diff = spawnSync("diff", ["-q", join(golden, file), repoFile], { stdio: "ignore" });
        if (diff.status === 0) {
            process.stdout.write(`OK: ${file}\n`);
        }
        else {
            process.stdout.write(`CONTENT MISMATCH: ${file}\n`);
            process.stdout.write("  Expected (golden) differs from actual (repo)\n");
            process.stdout.write(`  Run: diff -u "${join(golden, file)}" "${repoFile}"\n`);
            errors += 1;
        }
    }
    return errors;
}
function markerCheck(repo) {
    process.stdout.write("\n--- Modified file marker checks ---\n");
    let errors = 0;
    for (const file of ["AGENTS.md", "README.md", ".gitignore"]) {
        const path = join(repo, file);
        if (!existsSync(path)) {
            process.stdout.write(`NOT FOUND: ${file} (expected modified file missing?)\n`);
            errors += 1;
            continue;
        }
        if (readFileSync(path, "utf8").includes("<!-- ai-sdlc-init:start -->")) {
            process.stdout.write(`OK: ${file} has ai-sdlc-init marker\n`);
        }
        else {
            process.stdout.write(`MISSING MARKER in ${file}\n`);
            process.stdout.write("  Expected to find: <!-- ai-sdlc-init:start -->\n");
            process.stdout.write("  The skill's step 9-11 should have inserted this marker.\n");
            errors += 1;
        }
    }
    return errors;
}
function lockCheck(repo) {
    process.stdout.write("\n--- upstream.lock structure check ---\n");
    const path = join(repo, "upstream.lock");
    if (!existsSync(path)) {
        process.stdout.write("NOT FOUND: upstream.lock\n");
        return 1;
    }
    const text = readFileSync(path, "utf8");
    let errors = 0;
    for (const field of ["source:", "via:", "pinned_sha:", "sync_script:"]) {
        if (text.includes(field)) {
            process.stdout.write(`OK: upstream.lock has ${field}\n`);
        }
        else {
            process.stdout.write(`MISSING FIELD in upstream.lock: ${field}\n`);
            errors += 1;
        }
    }
    return errors;
}
function usage() {
    const argv0 = process.env.SHIM_ARGV0 ?? "";
    process.stdout.write(`Usage: ${argv0} <repo-path> <golden-dir-path>\n`);
    process.stdout.write(`Example: ${argv0} /path/to/skills/repo reference/golden-skills\n`);
    return 1;
}
export function main(argv) {
    const repo = argv[0];
    const golden = argv[1];
    if (repo === undefined || golden === undefined || argv.length !== 2) {
        return usage();
    }
    if (!existsSync(golden)) {
        process.stdout.write(`FAIL: Golden directory not found: ${golden}\n`);
        return 1;
    }
    process.stdout.write("=== Verify Golden Dir ===\n");
    process.stdout.write(`Repo:       ${repo}\n`);
    process.stdout.write(`Golden dir: ${golden}\n\n`);
    let errors = contentCheck(repo, golden) + markerCheck(repo);
    process.stdout.write("\n--- CI workflow check ---\n");
    if (existsSync(join(repo, ".github/workflows/ci-prek.yml"))) {
        process.stdout.write("OK: ci-prek.yml exists\n");
    }
    else {
        process.stdout.write("MISSING: .github/workflows/ci-prek.yml\n");
        errors += 1;
    }
    errors += lockCheck(repo);
    const rules = join(repo, ".rules.ts");
    const validator = join(repo, "scripts/validate-rules.sh");
    if (existsSync(rules)) {
        process.stdout.write("\n--- Archgate .rules.ts structural validation ---\n");
        if (existsSync(validator)) {
            const ran = spawnSync("bash", [validator, rules], { stdio: "ignore" });
            if (ran.status === 0) {
                process.stdout.write("OK: validate-rules.sh passes on .rules.ts\n");
            }
            else {
                process.stdout.write("WARNING: validate-rules.sh failed on .rules.ts\n");
                process.stdout.write("  Run: bash scripts/validate-rules.sh .rules.ts\n");
                errors += 1;
            }
        }
        else {
            process.stdout.write("SKIP: scripts/validate-rules.sh not found or not executable\n");
            process.stdout.write(`  .rules.ts exists at: ${rules}\n`);
        }
    }
    else {
        process.stdout.write("NOT FOUND: .rules.ts\n");
        errors += 1;
    }
    process.stdout.write("\n=== Result ===\n");
    if (errors === 0) {
        process.stdout.write("PASS: All checks passed.\n");
        return 0;
    }
    process.stdout.write(`FAIL: ${errors} check(s) failed.\n`);
    return 1;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=verify-golden-dir.mjs.map