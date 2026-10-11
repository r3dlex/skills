import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { assertNodeVersion, EXIT_NODE_UNAVAILABLE, EXIT_NODE_VERSION_UNSUPPORTED, NODE_UNAVAILABLE, NODE_VERSION_UNSUPPORTED } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { jsonStringSpan, replaceJsonString } from "./json-span.mjs";
import { run, text } from "./proc.mjs";

assertNodeVersion();

export interface Anchor {
  commit: string;
  path: string;
  blob: string;
  sha256: string;
}

export interface Site {
  stream: "stdout" | "stderr";
  prefix?: string;
  jsonPointer?: string;
}

export interface NormalizationClass {
  name: string;
  mask: string;
  sites: Site[];
}

export interface MaskSpan {
  name: string;
  stream: "stdout" | "stderr";
  start: number;
  end: number;
}

export interface CorpusCase {
  id: string;
  args: string[];
  stdin?: string;
  files?: Record<string, string>;
}

export interface Corpus {
  anchor: Anchor;
  candidate: string[];
  cases: CorpusCase[];
  normalizations?: NormalizationClass[];
  applyMasks?: MaskSpan[];
}

export class DifferentialError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DifferentialError";
  }
}

function sha256(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

export function materialize(root: string, anchor: Anchor): Buffer {
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

function siteRanges(text: string, site: Site): Array<[number, number]> {
  if (site.prefix === undefined) {
    return [];
  }
  const ranges: Array<[number, number]> = [];
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

function spanInside(span: MaskSpan, ranges: Array<[number, number]>): boolean {
  return ranges.some(([start, end]) => span.start >= start && span.end <= end);
}

function applyPrefixMask(text: string, site: Site, mask: string): string {
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

function applyJsonMask(body: string, pointer: string, mask: string): string {
  try {
    return replaceJsonString(body, pointer, mask);
  } catch (error) {
    throw new DifferentialError(error instanceof Error ? error.message : "mask site not located");
  }
}

export function normalize(text: string, classes: readonly NormalizationClass[], stream: "stdout" | "stderr"): string {
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

function refusal(status: number, stderr: Buffer): string | null {
  if (status === EXIT_NODE_UNAVAILABLE && stderr.equals(Buffer.from(`${NODE_UNAVAILABLE}\n`))) {
    return NODE_UNAVAILABLE;
  }
  if (status === EXIT_NODE_VERSION_UNSUPPORTED && stderr.equals(Buffer.from(`${NODE_VERSION_UNSUPPORTED}\n`))) {
    return NODE_VERSION_UNSUPPORTED;
  }
  return null;
}

export function outputsEqual(left: CaseResult, right: CaseResult): boolean {
  return left.status === right.status && left.stdout.equals(right.stdout) && left.stderr.equals(right.stderr);
}

export interface CaseResult {
  status: number;
  stdout: Buffer;
  stderr: Buffer;
  files: Record<string, Buffer>;
}

function readTree(dir: string, prefix = ""): Record<string, Buffer> {
  const out: Record<string, Buffer> = {};
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const relative = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      Object.assign(out, readTree(full, relative));
    } else if (entry.isFile()) {
      out[relative] = readFileSync(full);
    }
  }
  return out;
}

function seed(dir: string, files: Record<string, string> | undefined): void {
  mkdirSync(dir, { recursive: true });
  for (const [name, text] of Object.entries(files ?? {})) {
    writeFileSync(join(dir, name), text);
  }
}

function maskApplies(classes: readonly NormalizationClass[], stream: "stdout" | "stderr"): boolean {
  return classes.some((item) => item.sites.some((site) => site.stream === stream));
}

function spliceSpan(bytes: Buffer, start: number, end: number, mask: string): Buffer {
  return Buffer.concat([bytes.subarray(0, start), Buffer.from(mask), bytes.subarray(end)]);
}

function prefixByteRanges(bytes: Buffer, prefix: string): Array<[number, number]> {
  const needle = Buffer.from(prefix);
  const ranges: Array<[number, number]> = [];
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

function maskPrefixBytes(bytes: Buffer, site: Site, mask: string): Buffer {
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

function utf8Valid(bytes: Buffer): boolean {
  try {
    new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    return true;
  } catch {
    return false;
  }
}

function jsonByteSpan(bytes: Buffer, pointer: string): { start: number; end: number } {
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

function maskJsonBytes(bytes: Buffer, pointer: string, mask: string): Buffer {
  try {
    const span = jsonByteSpan(bytes, pointer);
    return spliceSpan(bytes, span.start, span.end, mask);
  } catch (error) {
    throw new DifferentialError(error instanceof Error ? error.message : "mask site not located");
  }
}

function maskSite(bytes: Buffer, site: Site, mask: string, stream: "stdout" | "stderr"): Buffer {
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

function maskStream(bytes: Buffer, classes: readonly NormalizationClass[], stream: "stdout" | "stderr"): Buffer {
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

function masked(result: CaseResult, classes: readonly NormalizationClass[]): CaseResult {
  return {
    ...result,
    stdout: maskStream(result.stdout, classes, "stdout"),
    stderr: maskStream(result.stderr, classes, "stderr"),
  };
}

function sameFiles(left: Record<string, Buffer>, right: Record<string, Buffer>): boolean {
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

function classNamed(corpus: Corpus, name: string): NormalizationClass {
  const item = (corpus.normalizations ?? []).find((entry) => entry.name === name);
  if (item === undefined) {
    throw new DifferentialError(`undeclared mask: ${name}`);
  }
  return item;
}

function pointerRanges(bytes: Buffer, pointer: string): Array<[number, number]> {
  try {
    const span = jsonByteSpan(bytes, pointer);
    return [[span.start, span.end]];
  } catch {
    return [];
  }
}

function declaredRanges(bytes: Buffer, item: NormalizationClass, stream: "stdout" | "stderr"): Array<[number, number]> {
  const ranges: Array<[number, number]> = [];
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

function spanFits(span: MaskSpan, ranges: Array<[number, number]>): boolean {
  return span.end >= span.start && spanInside(span, ranges);
}

function assertSupplied(reference: CaseResult, candidate: CaseResult, corpus: Corpus): void {
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

function coveredRuns(spans: readonly MaskSpan[], corpus: Corpus): Array<{ start: number; end: number; mask: string }> {
  const ordered = [...spans].sort((left, right) => left.start - right.start || left.end - right.end);
  const runs: Array<{ start: number; end: number; mask: string }> = [];
  for (const span of ordered) {
    const mask = classNamed(corpus, span.name).mask;
    const last = runs.at(-1);
    if (last !== undefined && span.start < last.end) {
      if (last.mask !== mask) {
        throw new DifferentialError("mask spans overlap");
      }
      last.end = Math.max(last.end, span.end);
    } else {
      runs.push({ start: span.start, end: span.end, mask });
    }
  }
  return runs;
}

function applyDeclaredSpans(bytes: Buffer, spans: readonly MaskSpan[], corpus: Corpus, stream: "stdout" | "stderr"): Buffer {
  const parts: Buffer[] = [];
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

function viewed(result: CaseResult, corpus: Corpus): CaseResult {
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

export function compareCase(reference: CaseResult, candidate: CaseResult, corpus: Corpus): void {
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

export function runAnchored(root: string, corpus: Corpus): void {
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
    compareCase(
      { ...ref, files: readTree(refDir) },
      { ...cand, files: readTree(candDir) },
      corpus,
    );
  }
}

export function main(argv: readonly string[]): number {
  const corpusPath = argv[0];
  const root = argv[1] ?? process.cwd();
  if (corpusPath === undefined) {
    process.stderr.write("usage: differential <corpus.json> [root]\n");
    return 2;
  }
  try {
    const corpus = JSON.parse(readFileSync(corpusPath, "utf8")) as Corpus;
    runAnchored(root, corpus);
    process.stdout.write("differential: pass\n");
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : "differential_failed";
    process.stderr.write(`${message}\n`);
    return 1;
  }
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
