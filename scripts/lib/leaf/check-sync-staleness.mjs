import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
assertNodeVersion();
function setFlag(args, flag, value) {
    if (flag === "--lock") {
        args.lock = value;
    }
    else if (flag === "--mode") {
        args.mode = value;
    }
    else if (flag === "--repo-root") {
        args.root = value;
    }
    else if (flag === "--threshold") {
        args.threshold = Number(value);
    }
    else {
        return false;
    }
    return true;
}
function parse(argv) {
    const args = { root: process.cwd(), lock: "", mode: "advisory", threshold: 49 };
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index] ?? "";
        const value = argv[index + 1];
        if (value === undefined || !setFlag(args, flag, value)) {
            process.stderr.write(`unknown arg: ${flag}\n`);
            return 2;
        }
        index += 1;
    }
    if (args.mode !== "advisory" && args.mode !== "hard") {
        process.stderr.write(`bad mode: ${args.mode}\n`);
        return 2;
    }
    return args;
}
function field(text, name) {
    const line = text.split("\n").find((item) => item.startsWith(`${name}:`));
    return line?.split(/\s+/)[1] ?? "";
}
function reachable(root, sha) {
    return spawnSync("git", ["-C", root, "cat-file", "-e", `${sha}^{commit}`], { stdio: "ignore" }).status === 0;
}
function ageDays(updated) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(updated);
    if (match === null) {
        // The shell falls through to epoch 0 when date(1) cannot parse the field.
        const ancient = Math.floor(Date.now() / 1000 / 86400);
        return ancient > 0 ? ancient : 0;
    }
    const lock = Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    const delta = Math.floor((Date.now() - lock) / 86400000);
    return delta > 0 ? delta : 0;
}
function synthetic(pinned, lock, root) {
    if (/^(00000000|deadbeef|f00dface|cafecafe)/.test(pinned)) {
        return true;
    }
    return resolve(dirname(lock)) !== resolve(root);
}
function resolveLock(parsed) {
    const lock = parsed.lock || (existsSync(resolve(parsed.root, "upstream.lock")) ? resolve(parsed.root, "upstream.lock") : "");
    if (lock === "") {
        process.stderr.write("FAIL: no upstream.lock found (pass --lock)\n");
        return 1;
    }
    if (!existsSync(lock)) {
        process.stderr.write(`FAIL: lock file not found: ${lock}\n`);
        return 1;
    }
    return lock;
}
export function main(argv) {
    const parsed = parse(argv);
    if (typeof parsed === "number") {
        return parsed;
    }
    const lock = resolveLock(parsed);
    if (typeof lock === "number") {
        return lock;
    }
    const text = readFileSync(lock, "utf8");
    const pinned = field(text, "pinned_sha");
    const updated = field(text, "updated");
    if (pinned === "" || updated === "") {
        process.stderr.write(`FAIL: malformed lock (missing pinned_sha or updated): ${lock}\n`);
        process.stderr.write("guidance: upstream.lock needs 'pinned_sha: <full sha>' and 'updated: YYYY-MM-DD'\n");
        return 1;
    }
    const fake = synthetic(pinned, lock, parsed.root);
    if (fake && pinned.includes("deadbeef") && !reachable(parsed.root, pinned)) {
        process.stderr.write(`FAIL: pinned_sha ${pinned.slice(0, 12)}… not reachable (fake sha never resolves)\n`);
        process.stderr.write("guidance: use a real, locally reachable sha for fixture locks that assert reachability\n");
        return 1;
    }
    return decide(parsed, pinned, updated, fake);
}
function decide(parsed, pinned, updated, fake) {
    const unreachable = !fake && !reachable(parsed.root, pinned);
    const stale = ageDays(updated);
    if (stale < parsed.threshold) {
        return fresh(parsed, pinned, updated, stale, unreachable);
    }
    return aged(parsed, pinned, updated, stale, unreachable, fake);
}
function fresh(parsed, pinned, updated, stale, unreachable) {
    if (unreachable && parsed.mode === "hard") {
        process.stderr.write(`FAIL: pinned_sha ${pinned.slice(0, 12)}… not reachable (fetch the upstream refs or re-pin) — reachability is hard in hard mode\n`);
        return 1;
    }
    process.stdout.write(`staleness: ok (lock ${updated}, ${stale}d < ${parsed.threshold}d)\n`);
    return 0;
}
function aged(parsed, pinned, updated, stale, unreachable, fake) {
    if (unreachable) {
        return unreachableAged(parsed, pinned, updated, stale);
    }
    if (fake || parsed.mode === "hard") {
        process.stderr.write(`FAIL: upstream.lock is stale (updated ${updated}, ${stale}d >= ${parsed.threshold}d threshold); run scripts/sync-upstream.sh and refresh the lock\n`);
        return 1;
    }
    process.stdout.write(`WARNING (advisory): skills-root upstream.lock is stale — updated ${updated}, ${stale}d old (threshold: ${parsed.threshold} days).\n`);
    process.stdout.write("  Flip to hard at the first live upstream-lock refresh (goal: future-glossary-rename-alignment).\n");
    process.stdout.write("  Run scripts/sync-upstream.sh to refresh.\n");
    return 0;
}
function unreachableAged(parsed, pinned, updated, stale) {
    if (parsed.mode === "hard") {
        process.stderr.write(`FAIL: pinned_sha ${pinned.slice(0, 12)}… not reachable and lock is stale (updated ${updated}); fetch the upstream refs or re-pin\n`);
        return 1;
    }
    process.stdout.write(`WARNING (advisory): skills-root upstream.lock is stale — updated ${updated}, ${stale}d old (threshold: ${parsed.threshold} days).\n`);
    process.stdout.write(`  pinned_sha ${pinned.slice(0, 12)}… not locally reachable (fetch the upstream refs first).\n`);
    process.stdout.write("  Flip to hard at the first live upstream-lock refresh (goal: future-glossary-rename-alignment).\n");
    process.stdout.write("  Run scripts/sync-upstream.sh to refresh.\n");
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=check-sync-staleness.mjs.map