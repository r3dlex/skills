import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { assertNodeVersion, EXIT_NODE_UNAVAILABLE, EXIT_NODE_VERSION_UNSUPPORTED, NODE_UNAVAILABLE, NODE_VERSION_UNSUPPORTED } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { replaceJsonString } from "./json-span.mjs";
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

function assertSpan(text: string, span: MaskSpan, corpus: Corpus): void {
  const item = (corpus.normalizations ?? []).find((entry) => entry.name === span.name);
  if (item === undefined) {
    throw new DifferentialError(`undeclared mask: ${span.name}`);
  }
  const ranges = item.sites
    .filter((site) => site.stream === span.stream && site.prefix !== undefined)
    .flatMap((site) => siteRanges(text, site));
  if (ranges.length > 0 && !spanInside(span, ranges)) {
    throw new DifferentialError("mask reaches outside declared sites");
  }
  if (ranges.length === 0 && item.sites.some((site) => site.prefix !== undefined && site.stream === span.stream)) {
    throw new DifferentialError("mask reaches outside declared sites");
  }
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

function maskStream(bytes: Buffer, classes: readonly NormalizationClass[], stream: "stdout" | "stderr"): Buffer {
  if (!maskApplies(classes, stream)) {
    return bytes;
  }
  return Buffer.from(normalize(text(bytes), classes, stream));
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

export function compareCase(reference: CaseResult, candidate: CaseResult, corpus: Corpus): void {
  const blocked = refusal(candidate.status, candidate.stderr);
  if (blocked !== null) {
    throw new DifferentialError(`candidate ended in ${blocked}`);
  }
  for (const span of corpus.applyMasks ?? []) {
    const body = text(span.stream === "stdout" ? candidate.stdout : candidate.stderr);
    assertSpan(body, span, corpus);
  }
  const classes = corpus.normalizations ?? [];
  const left = masked(reference, classes);
  const right = masked(candidate, classes);
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
