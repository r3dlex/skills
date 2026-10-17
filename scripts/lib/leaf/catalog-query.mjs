import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readlinkSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { optionLike, writeHelp } from "./argparse-help.mjs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { CatalogError, loadCatalog, projection, select } from "./catalog-model.mjs";
import { HostMatrixError, loadHostMatrix, resolveHost } from "./host-matrix.mjs";
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
function matchingOptions(flag) {
    return ["--help", ...OPTIONS].filter((option) => option.startsWith(flag));
}
function resolveOption(flag) {
    if (OPTIONS.has(flag)) {
        return flag;
    }
    if (!flag.startsWith("--") || flag.length < 3) {
        return undefined;
    }
    const matches = matchingOptions(flag);
    return matches.length === 1 ? matches[0] : undefined;
}
function ambiguousOption(flag) {
    if (OPTIONS.has(flag) || !flag.startsWith("--") || flag.length < 3) {
        return undefined;
    }
    const matches = matchingOptions(flag);
    return matches.length > 1 ? matches.join(", ") : undefined;
}
// Argparse classifies every token before any action. An ambiguous option exits
// before help and before a missing-argument check.
function firstAmbiguous(argv) {
    for (const token of argv) {
        if (token === "--") {
            return undefined;
        }
        const matches = ambiguousOption(splitEquals(token).flag);
        if (matches !== undefined) {
            return { token, matches };
        }
    }
    return undefined;
}
function missingArgument(inline, next) {
    return inline === undefined && (next === undefined || optionLike(next));
}
function isEnoent(error) {
    return error instanceof Error && "code" in error && error.code === "ENOENT";
}
function isOsError(error) {
    return error instanceof Error && "code" in error && typeof error.code === "string";
}
function projectionProbe() {
    const pad = Array.from({ length: 12 }, () => "    x = 1");
    const lines = [
        "import json, sys",
        "from pathlib import Path",
        "payload = {'schema_version': '1.0', 'skills': []}",
        "entries = []",
        "def projection(payload, entries):",
        "    return {'schema_version': payload['schema_version'], 'skills': list(entries)}",
        "class Args: pass",
        "args = Args()",
        "args.projection = sys.argv[1]",
        "def main() -> int:",
        ...pad,
        "    if args.projection:",
        "        Path(args.projection).write_text(json.dumps(projection(payload, entries), indent=2, ensure_ascii=False) + \"\\n\", encoding=\"utf-8\")",
        "    for entry in entries:",
        "        print(f\"{entry['name']}\\t{entry['source_path']}\")",
        "    return 0",
        "if __name__ == \"__main__\": raise SystemExit(main())",
    ];
    return `${lines.join("\n")}\n`;
}
const PYTHON_FALLBACKS = [
    "/usr/bin/python3",
    "/usr/local/bin/python3",
    "/opt/homebrew/bin/python3",
    "/Library/Developer/CommandLineTools/usr/bin/python3",
];
function looksLikePython(path) {
    const base = path.slice(path.lastIndexOf("/") + 1);
    return /^python(?:\d+(?:\.\d+)*)?$/i.test(base);
}
function parentPython() {
    const fromProc = join("/proc", String(process.ppid), "exe");
    if (existsSync(fromProc)) {
        const linked = readlinkSync(fromProc);
        if (looksLikePython(linked)) {
            return linked;
        }
    }
    try {
        const comm = execFileSync("/bin/ps", ["-ww", "-p", String(process.ppid), "-o", "comm="], {
            encoding: "utf8",
        }).trim();
        if (looksLikePython(comm) && existsSync(comm)) {
            return comm;
        }
    }
    catch {
        return undefined;
    }
    return undefined;
}
function probeInterpreters() {
    const found = [];
    const parent = parentPython();
    if (parent !== undefined) {
        found.push(parent);
    }
    for (const candidate of PYTHON_FALLBACKS) {
        if (existsSync(candidate)) {
            found.push(candidate);
        }
    }
    return found;
}
function probeTrace(probe, projectionPath) {
    const ran = spawnSync("python3", [probe, projectionPath], { encoding: "utf8" });
    if (!isEnoent(ran.error)) {
        return ran.stderr ?? "";
    }
    for (const candidate of probeInterpreters()) {
        const again = spawnSync(candidate, [probe, projectionPath], { encoding: "utf8" });
        if (!isEnoent(again.error)) {
            return again.stderr ?? "";
        }
    }
    return "";
}
function projectionMissing(root, projectionPath) {
    const dir = mkdtempSync(join(tmpdir(), "catalog-query-"));
    const probe = join(dir, "probe.py");
    try {
        writeFileSync(probe, projectionProbe());
        const script = join(realpathSync(root), "scripts/catalog-query.py");
        return probeTrace(probe, projectionPath).replaceAll(probe, script);
    }
    finally {
        rmSync(dir, { recursive: true, force: true });
    }
}
function writeProjection(path, text, root) {
    try {
        writeFileSync(path, text);
        return 0;
    }
    catch (error) {
        if (!isOsError(error)) {
            throw error;
        }
        process.stderr.write(projectionMissing(root, path));
        return 1;
    }
}
let concatenatedHelpExit;
// 3.9 rejects -hfoo. 3.12+ prints help and exits 0. Match the python3 on PATH.
function concatenatedHelpExitsZero() {
    if (concatenatedHelpExit !== undefined) {
        return concatenatedHelpExit;
    }
    const probed = spawnSync("python3", ["-c", "import argparse,sys\ntry:\n argparse.ArgumentParser().parse_args(['-hfoo'])\nexcept SystemExit as exc:\n sys.exit(0 if exc.code in (None, 0) else exc.code)\n"], { encoding: "utf8" });
    concatenatedHelpExit = probed.status === 0;
    return concatenatedHelpExit;
}
function shortHelpClass(token) {
    if (!token.startsWith("-h") || token.startsWith("--") || token.length <= 2) {
        return undefined;
    }
    if (token.indexOf("=") === 2 || !concatenatedHelpExitsZero()) {
        return "ignored";
    }
    return "help";
}
function shortHelpValue(token) {
    const eq = token.indexOf("=");
    return eq === 2 ? token.slice(eq + 1) : token.slice(2);
}
function classifyToken(token) {
    if (token === "--") {
        return { kind: "terminator" };
    }
    if (token === "-h" || token === "--help") {
        return { kind: "help" };
    }
    const shortHelp = shortHelpClass(token);
    if (shortHelp === "help") {
        return { kind: "help" };
    }
    if (shortHelp === "ignored") {
        return { kind: "ignored", value: shortHelpValue(token) };
    }
    const parts = splitEquals(token);
    const ambiguous = ambiguousOption(parts.flag);
    if (ambiguous !== undefined) {
        return { kind: "ambiguous", flag: parts.flag, matches: ambiguous };
    }
    const flag = resolveOption(parts.flag);
    if (flag === "--help") {
        return parts.inline === undefined ? { kind: "help" } : { kind: "ignored", value: parts.inline };
    }
    if (flag === undefined) {
        return { kind: "unknown" };
    }
    return { kind: "option", flag, inline: parts.inline };
}
function applyFlag(args, flag, inline, next) {
    if (missingArgument(inline, next)) {
        return { status: argparseFail(`argument ${flag}: expected one argument`) };
    }
    const value = inline ?? next;
    if (!take(args, flag, value)) {
        return { status: argparseFail(`unrecognized arguments: ${flag}`) };
    }
    return { skip: inline === undefined ? 1 : 0 };
}
function consume(token, next, args) {
    const classified = classifyToken(token);
    if (classified.kind === "terminator") {
        return { stop: true };
    }
    if (classified.kind === "help") {
        writeHelp(USAGE, CATALOG_HELP_OPTIONS);
        return { status: 0 };
    }
    if (classified.kind === "ignored") {
        return { status: argparseFail(`argument -h/--help: ignored explicit argument '${classified.value}'`) };
    }
    if (classified.kind === "ambiguous") {
        return { status: argparseFail(`ambiguous option: ${classified.flag} could match ${classified.matches}`) };
    }
    if (classified.kind === "unknown") {
        return { unknown: true };
    }
    return applyFlag(args, classified.flag, classified.inline, next);
}
function parse(argv, fallbackRoot) {
    const early = firstAmbiguous(argv);
    if (early !== undefined) {
        return argparseFail(`ambiguous option: ${early.token} could match ${early.matches}`);
    }
    const args = { root: fallbackRoot, lifecycles: [] };
    const unknown = [];
    for (let index = 0; index < argv.length; index += 1) {
        const token = argv[index] ?? "";
        const consumed = consume(token, argv[index + 1], args);
        if ("stop" in consumed) {
            unknown.push(...argv.slice(index));
            break;
        }
        if ("status" in consumed) {
            return consumed.status;
        }
        if ("unknown" in consumed) {
            unknown.push(token);
            continue;
        }
        index += consumed.skip;
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
function emitQuery(parsed, root) {
    const payload = loadCatalog(parsed.root);
    // An alias (omc, omx) resolves to its payload host here, before select(), so
    // rows and projection bytes are the payload host's; HOSTS stays the enum.
    const matrix = loadHostMatrix(parsed.root, new Set(payload.skills.map((entry) => entry.name)));
    const entries = select(payload, resolveHost(matrix, parsed.host ?? ""), new Set(parsed.lifecycles), parsed.skill);
    if (parsed.projection) {
        const wrote = writeProjection(parsed.projection, `${JSON.stringify(projection(payload, entries), null, 2)}\n`, root);
        if (wrote !== 0) {
            return wrote;
        }
    }
    for (const entry of entries) {
        process.stdout.write(`${entry.name}\t${entry.source_path}\n`);
    }
    return 0;
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
        return emitQuery(parsed, root);
    }
    catch (error) {
        const message = error instanceof CatalogError || error instanceof HostMatrixError ? error.message : "catalog query failed";
        return fail(message);
    }
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=catalog-query.mjs.map