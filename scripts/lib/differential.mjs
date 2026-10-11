import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { assertNodeVersion, EXIT_NODE_UNAVAILABLE, EXIT_NODE_VERSION_UNSUPPORTED, NODE_UNAVAILABLE, NODE_VERSION_UNSUPPORTED } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { jsonStringSpan, replaceJsonString } from "./json-span.mjs";
import { run, text } from "./proc.mjs";
assertNodeVersion();
export class DifferentialError extends Error {
    constructor(message) {
        super(message);
        this.name = "DifferentialError";
    }
}
function sha256(bytes) {
    return createHash("sha256").update(bytes).digest("hex");
}
export function materialize(root, anchor) {
    const spec = `${anchor.commit}:${anchor.path}`;
    const blob = text(run("git", ["rev-parse", spec], root).stdout).trim();
    if (blob !== anchor.blob) {
        throw new DifferentialError(`anchor blob mismatch: ${blob} != ${anchor.blob}`);
    }
    const raw = run("git", ["cat-file", "blob", blob], root);
    if (raw.status !== 0) {
        throw new DifferentialError("anchor blob unreadable");
    }
    const bytes = raw.stdout;
    if (sha256(bytes) !== anchor.sha256) {
        throw new DifferentialError("anchor sha256 mismatch");
    }
    return bytes;
}
function siteRanges(text, site) {
    if (site.prefix === undefined) {
        return [];
    }
    const ranges = [];
    let from = 0;
    while (from <= text.length) {
        const at = text.indexOf(site.prefix, from);
        if (at < 0) {
            break;
        }
        const start = at + site.prefix.length;
        const lineEnd = text.indexOf("\n", start);
        const end = lineEnd < 0 ? text.length : lineEnd;
        ranges.push([start, end]);
        from = end + 1;
    }
    return ranges;
}
function spanInside(span, ranges) {
    return ranges.some(([start, end]) => span.start >= start && span.end <= end);
}
function applyPrefixMask(text, site, mask) {
    if (site.prefix === undefined) {
        return text;
    }
    const ranges = siteRanges(text, site);
    if (ranges.length === 0) {
        throw new DifferentialError(`mask site not located: ${site.prefix}`);
    }
    let out = text;
    for (const [start, end] of [...ranges].reverse()) {
        out = out.slice(0, start) + mask + out.slice(end);
    }
    return out;
}
function applyJsonMask(body, pointer, mask) {
    try {
        return replaceJsonString(body, pointer, mask);
    }
    catch (error) {
        throw new DifferentialError(error instanceof Error ? error.message : "mask site not located");
    }
}
export function normalize(text, classes, stream) {
    let out = text;
    for (const item of classes) {
        for (const site of item.sites) {
            if (site.stream !== stream) {
                continue;
            }
            if (site.jsonPointer !== undefined && stream === "stdout") {
                out = applyJsonMask(out, site.jsonPointer, item.mask);
            }
            if (site.prefix !== undefined) {
                out = applyPrefixMask(out, site, item.mask);
            }
        }
    }
    return out;
}
function refusal(status, stderr) {
    if (status === EXIT_NODE_UNAVAILABLE && stderr.equals(Buffer.from(`${NODE_UNAVAILABLE}\n`))) {
        return NODE_UNAVAILABLE;
    }
    if (status === EXIT_NODE_VERSION_UNSUPPORTED && stderr.equals(Buffer.from(`${NODE_VERSION_UNSUPPORTED}\n`))) {
        return NODE_VERSION_UNSUPPORTED;
    }
    return null;
}
export function outputsEqual(left, right) {
    return left.status === right.status && left.stdout.equals(right.stdout) && left.stderr.equals(right.stderr);
}
function readTree(dir, prefix = "") {
    const out = {};
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const relative = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
        const full = join(dir, entry.name);
        if (entry.isDirectory()) {
            Object.assign(out, readTree(full, relative));
        }
        else if (entry.isFile()) {
            out[relative] = readFileSync(full);
        }
    }
    return out;
}
function seed(dir, files) {
    mkdirSync(dir, { recursive: true });
    for (const [name, text] of Object.entries(files ?? {})) {
        writeFileSync(join(dir, name), text);
    }
}
function maskApplies(classes, stream) {
    return classes.some((item) => item.sites.some((site) => site.stream === stream));
}
function spliceSpan(bytes, start, end, mask) {
    return Buffer.concat([bytes.subarray(0, start), Buffer.from(mask), bytes.subarray(end)]);
}
function prefixByteRanges(bytes, prefix) {
    const needle = Buffer.from(prefix);
    const ranges = [];
    let from = 0;
    while (from <= bytes.length) {
        const at = bytes.indexOf(needle, from);
        if (at < 0) {
            break;
        }
        const start = at + needle.length;
        const lineEnd = bytes.indexOf(0x0a, start);
        const end = lineEnd < 0 ? bytes.length : lineEnd;
        ranges.push([start, end]);
        from = end + 1;
    }
    return ranges;
}
function maskPrefixBytes(bytes, site, mask) {
    if (site.prefix === undefined) {
        return bytes;
    }
    const ranges = prefixByteRanges(bytes, site.prefix);
    if (ranges.length === 0) {
        throw new DifferentialError(`mask site not located: ${site.prefix}`);
    }
    let out = bytes;
    for (const [start, end] of [...ranges].reverse()) {
        out = spliceSpan(out, start, end, mask);
    }
    return out;
}
function utf8Valid(bytes) {
    try {
        new TextDecoder("utf-8", { fatal: true }).decode(bytes);
        return true;
    }
    catch {
        return false;
    }
}
function jsonByteSpan(bytes, pointer) {
    if (utf8Valid(bytes)) {
        const decoded = bytes.toString("utf8");
        const span = jsonStringSpan(decoded, pointer);
        return {
            start: Buffer.byteLength(decoded.slice(0, span.start)),
            end: Buffer.byteLength(decoded.slice(0, span.end)),
        };
    }
    return jsonStringSpan(bytes.toString("latin1"), pointer);
}
function maskJsonBytes(bytes, pointer, mask) {
    try {
        const span = jsonByteSpan(bytes, pointer);
        return spliceSpan(bytes, span.start, span.end, mask);
    }
    catch (error) {
        throw new DifferentialError(error instanceof Error ? error.message : "mask site not located");
    }
}
function maskSite(bytes, site, mask, stream) {
    if (site.stream !== stream) {
        return bytes;
    }
    let out = bytes;
    if (site.jsonPointer !== undefined && stream === "stdout") {
        out = maskJsonBytes(out, site.jsonPointer, mask);
    }
    if (site.prefix !== undefined) {
        out = maskPrefixBytes(out, site, mask);
    }
    return out;
}
function maskStream(bytes, classes, stream) {
    if (!maskApplies(classes, stream)) {
        return bytes;
    }
    let out = bytes;
    for (const item of classes) {
        for (const site of item.sites) {
            out = maskSite(out, site, item.mask, stream);
        }
    }
    return out;
}
function masked(result, classes) {
    return {
        ...result,
        stdout: maskStream(result.stdout, classes, "stdout"),
        stderr: maskStream(result.stderr, classes, "stderr"),
    };
}
function sameFiles(left, right) {
    const names = new Set([...Object.keys(left), ...Object.keys(right)]);
    for (const name of names) {
        const leftBytes = left[name];
        const rightBytes = right[name];
        if (leftBytes === undefined || rightBytes === undefined || !leftBytes.equals(rightBytes)) {
            return false;
        }
    }
    return true;
}
function classNamed(corpus, name) {
    const item = (corpus.normalizations ?? []).find((entry) => entry.name === name);
    if (item === undefined) {
        throw new DifferentialError(`undeclared mask: ${name}`);
    }
    return item;
}
function pointerRanges(bytes, pointer) {
    try {
        const span = jsonByteSpan(bytes, pointer);
        return [[span.start, span.end]];
    }
    catch {
        return [];
    }
}
function declaredRanges(bytes, item, stream) {
    const ranges = [];
    for (const site of item.sites) {
        if (site.stream !== stream) {
            continue;
        }
        if (site.prefix !== undefined) {
            ranges.push(...prefixByteRanges(bytes, site.prefix));
        }
        if (site.jsonPointer !== undefined) {
            ranges.push(...pointerRanges(bytes, site.jsonPointer));
        }
    }
    return ranges;
}
function spanFits(span, ranges) {
    return span.end >= span.start && spanInside(span, ranges);
}
function assertSupplied(reference, candidate, corpus) {
    for (const span of corpus.applyMasks ?? []) {
        const item = classNamed(corpus, span.name);
        for (const result of [reference, candidate]) {
            const bytes = span.stream === "stdout" ? result.stdout : result.stderr;
            if (!spanFits(span, declaredRanges(bytes, item, span.stream))) {
                throw new DifferentialError("mask reaches outside declared sites");
            }
        }
    }
}
function coveredRuns(spans, corpus) {
    const ordered = [...spans].sort((left, right) => left.start - right.start || left.end - right.end);
    const runs = [];
    for (const span of ordered) {
        const mask = classNamed(corpus, span.name).mask;
        const last = runs.at(-1);
        if (last !== undefined && span.start < last.end) {
            if (last.mask !== mask) {
                throw new DifferentialError("mask spans overlap");
            }
            last.end = Math.max(last.end, span.end);
        }
        else {
            runs.push({ start: span.start, end: span.end, mask });
        }
    }
    return runs;
}
function applyDeclaredSpans(bytes, spans, corpus, stream) {
    const parts = [];
    let cursor = 0;
    for (const run of coveredRuns(spans.filter((span) => span.stream === stream), corpus)) {
        if (run.start < cursor) {
            throw new DifferentialError("mask spans overlap");
        }
        parts.push(bytes.subarray(cursor, run.start), Buffer.from(run.mask));
        cursor = run.end;
    }
    parts.push(bytes.subarray(cursor));
    return Buffer.concat(parts);
}
function viewed(result, corpus) {
    const spans = corpus.applyMasks ?? [];
    if (spans.length > 0) {
        return {
            ...result,
            stdout: applyDeclaredSpans(result.stdout, spans, corpus, "stdout"),
            stderr: applyDeclaredSpans(result.stderr, spans, corpus, "stderr"),
        };
    }
    return masked(result, corpus.normalizations ?? []);
}
export function compareCase(reference, candidate, corpus) {
    const blocked = refusal(candidate.status, candidate.stderr);
    if (blocked !== null) {
        throw new DifferentialError(`candidate ended in ${blocked}`);
    }
    assertSupplied(reference, candidate, corpus);
    const left = viewed(reference, corpus);
    const right = viewed(candidate, corpus);
    if (!outputsEqual(left, right) || !sameFiles(left.files, right.files)) {
        throw new DifferentialError("output divergence");
    }
}
export function runAnchored(root, corpus) {
    const bytes = materialize(root, corpus.anchor);
    const base = join(tmpdir(), `e6-diff-${Date.now()}`);
    mkdirSync(base, { recursive: true });
    const referencePath = join(base, "reference");
    writeFileSync(referencePath, bytes, { mode: 0o755 });
    for (const item of corpus.cases) {
        const refDir = join(base, `${item.id}-ref`);
        const candDir = join(base, `${item.id}-cand`);
        seed(refDir, item.files);
        seed(candDir, item.files);
        const stdin = Buffer.from(item.stdin ?? "");
        const ref = run(referencePath, item.args, refDir, undefined, stdin);
        const [cmd, ...args] = corpus.candidate;
        if (cmd === undefined) {
            throw new DifferentialError("candidate command missing");
        }
        const cand = run(cmd, [...args, ...item.args], candDir, undefined, stdin);
        compareCase({ ...ref, files: readTree(refDir) }, { ...cand, files: readTree(candDir) }, corpus);
    }
}
export function main(argv) {
    const corpusPath = argv[0];
    const root = argv[1] ?? process.cwd();
    if (corpusPath === undefined) {
        process.stderr.write("usage: differential <corpus.json> [root]\n");
        return 2;
    }
    try {
        const corpus = JSON.parse(readFileSync(corpusPath, "utf8"));
        runAnchored(root, corpus);
        process.stdout.write("differential: pass\n");
        return 0;
    }
    catch (error) {
        const message = error instanceof Error ? error.message : "differential_failed";
        process.stderr.write(`${message}\n`);
        return 1;
    }
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=differential.mjs.map