import { createHash } from "node:crypto";
import { mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { assertNodeVersion, EXIT_NODE_UNAVAILABLE, EXIT_NODE_VERSION_UNSUPPORTED, NODE_UNAVAILABLE, NODE_VERSION_UNSUPPORTED } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { run } from "./proc.mjs";

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
  const blob = run("git", ["rev-parse", spec], root).stdout.trim();
  if (blob !== anchor.blob) {
    throw new DifferentialError(`anchor blob mismatch: ${blob} != ${anchor.blob}`);
  }
  const raw = run("git", ["cat-file", "blob", blob], root);
  if (raw.status !== 0) {
    throw new DifferentialError("anchor blob unreadable");
  }
  const bytes = Buffer.from(raw.stdout, "utf8");
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

function applyJsonMask(text: string, pointer: string, mask: string): string {
  const value = JSON.parse(text) as unknown;
  const parts = pointer.split("/").slice(1);
  let cursor: unknown = value;
  for (const part of parts.slice(0, -1)) {
    if (typeof cursor !== "object" || cursor === null) {
      throw new DifferentialError("mask site not located");
    }
    cursor = (cursor as Record<string, unknown>)[part];
  }
  const leaf = parts[parts.length - 1];
  if (typeof cursor !== "object" || cursor === null || leaf === undefined) {
    throw new DifferentialError("mask site not located");
  }
  const record = cursor as Record<string, unknown>;
  if (typeof record[leaf] !== "string") {
    throw new DifferentialError("mask site not located");
  }
  record[leaf] = mask;
  return JSON.stringify(value);
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

function refusal(status: number, stderr: string): string | null {
  if (status === EXIT_NODE_UNAVAILABLE && stderr === `${NODE_UNAVAILABLE}\n`) {
    return NODE_UNAVAILABLE;
  }
  if (status === EXIT_NODE_VERSION_UNSUPPORTED && stderr === `${NODE_VERSION_UNSUPPORTED}\n`) {
    return NODE_VERSION_UNSUPPORTED;
  }
  return null;
}

export function outputsEqual(left: ProcResult, right: ProcResult): boolean {
  return left.status === right.status && left.stdout === right.stdout && left.stderr === right.stderr;
}

export interface ProcResult {
  status: number;
  stdout: string;
  stderr: string;
  files: Record<string, string>;
}

function readTree(dir: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const name of readdirSync(dir)) {
    out[name] = readFileSync(join(dir, name), "utf8");
  }
  return out;
}

function seed(dir: string, files: Record<string, string> | undefined): void {
  mkdirSync(dir, { recursive: true });
  for (const [name, text] of Object.entries(files ?? {})) {
    writeFileSync(join(dir, name), text);
  }
}

function masked(result: ProcResult, classes: readonly NormalizationClass[]): ProcResult {
  return {
    ...result,
    stdout: normalize(result.stdout, classes, "stdout"),
    stderr: normalize(result.stderr, classes, "stderr"),
  };
}

function sameFiles(left: Record<string, string>, right: Record<string, string>): boolean {
  const names = new Set([...Object.keys(left), ...Object.keys(right)]);
  for (const name of names) {
    if (left[name] !== right[name]) {
      return false;
    }
  }
  return true;
}

export function compareCase(reference: ProcResult, candidate: ProcResult, corpus: Corpus): void {
  const blocked = refusal(candidate.status, candidate.stderr);
  if (blocked !== null) {
    throw new DifferentialError(`candidate ended in ${blocked}`);
  }
  for (const span of corpus.applyMasks ?? []) {
    const text = span.stream === "stdout" ? candidate.stdout : candidate.stderr;
    assertSpan(text, span, corpus);
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
    const ref = run(referencePath, item.args, refDir);
    const [cmd, ...args] = corpus.candidate;
    if (cmd === undefined) {
      throw new DifferentialError("candidate command missing");
    }
    const cand = run(cmd, [...args, ...item.args], candDir);
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
