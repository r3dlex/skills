import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { isAbsolute, join, relative, resolve, sep } from "node:path";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { run, text } from "./proc.mjs";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type Row = { [key: string]: Json };

interface ContractConstants {
  allowed_classes: string[];
  argv_template: string[];
  consumers: string[];
  excluded_fields: string[];
  goal_id: string;
  permitted_sites: { [key: string]: string[] };
  plan_id: string;
  policy_path: string;
  projected_schemas: string[];
  refusal_schema: string;
  registry_path: string;
  required_targets: string[];
  schema: string;
  spec_path: string;
  spec_sha256_lineage: string;
  superseded_tool_sha256: string[];
}

export const CONTRACT: ContractConstants = {
  allowed_classes: ["time-field", "scratch-path", "interpreter-diagnostic"],
  argv_template: [
    "bash",
    "04-validate-handoff/autobahn/contract-run.sh",
    "<operation>",
    "--root",
    "<target.root>",
    "--target",
    "<target.target>",
    "--plan",
    "<plan_id>",
  ],
  consumers: [".ai/evidence/e6-sk-02-v1-port.json"],
  excluded_fields: ["/provenance"],
  goal_id: "e6-d13-cc-01",
  permitted_sites: { "evidence-export/1": [], "merge-audit/1": [] },
  plan_id: "e6-d13-comparison-contract",
  policy_path: ".ai/policies/readiness-policy.json",
  projected_schemas: ["merge-audit/1", "evidence-export/1"],
  refusal_schema: "readiness-contract/2",
  registry_path: ".ai/workflows/northstar-readiness-v2.json",
  required_targets: ["skills", "aitool-root", "ai-catapult", "ai-factory"],
  schema: "d13-comparison/1",
  spec_path: "docs/specifications/ACTIVE/e6-d13-comparison-contract.md",
  spec_sha256_lineage: "151f2d22541ede2819338f75536a9d11b5d18beb9820a6e51f55894d4f286839",
  superseded_tool_sha256: [],
};

const OPERATIONS = ["audit-merges", "export-evidence"];
const LANES = ["reference", "candidate"];
const PHASES = ["start", "finish"];
const CAPTURE_SCHEMA = "d13-capture/1";
const LANES_SCHEMA = "d13-lanes/1";
const OBSERVATION_SCHEMA = "d13-local-observation/1";
const MANIFEST_SCHEMA = "d13-raw-manifest/1";
const CONSUMER_SCHEMA = "d13-consumer-check/1";
const PROVENANCE_VALUES = ["base-copy", "source-lane"];
const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;

class Malformed extends Error {}
class Inconsistent extends Error {}

// ---------- canonical JSON and digests ----------

function sortDeep(value: Json): Json {
  if (Array.isArray(value)) {
    return value.map(sortDeep);
  }
  if (value !== null && typeof value === "object") {
    const out: Row = Object.create(null) as Row;
    const source = value;
    for (const key of Object.keys(source).sort()) {
      const child = source[key];
      out[key] = sortDeep(child === undefined ? null : child);
    }
    return out;
  }
  return value;
}

export function canonical(value: Json): string {
  return `${JSON.stringify(sortDeep(value))}\n`;
}

export function sha256Hex(bytes: Buffer): string {
  return createHash("sha256").update(bytes).digest("hex");
}

function parseJson(bytes: Buffer): Json {
  try {
    return JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes)) as Json;
  } catch {
    return null;
  }
}

function asRow(value: Json | undefined): Row | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
}

function asText(value: Json | undefined): string {
  return typeof value === "string" ? value : "";
}

function asList(value: Json | undefined): Json[] {
  return Array.isArray(value) ? value : [];
}

function filled(row: Row): boolean {
  return Object.values(row).every((item) => item !== "");
}

function toolDigest(): string {
  const invoked = process.argv[1];
  if (invoked === undefined) {
    return "unavailable";
  }
  try {
    return sha256Hex(readFileSync(realpathSync(invoked)));
  } catch {
    return "unavailable";
  }
}

function contractJson(): Row {
  return { ...CONTRACT, tool_sha256: toolDigest() };
}

// ---------- depth-one JSON walk ----------

interface Member {
  key: string;
  keyStart: number;
  lineEnd: number;
  lineStart: number;
  token: string | null;
  tokenEnd: number;
  value: string;
}

const WHITESPACE = " \t\r\n";
const SIMPLE_ESCAPES: Readonly<Record<string, string>> = {
  "\"": "\"",
  "\\": "\\",
  "/": "/",
  b: "\b",
  f: "\f",
  n: "\n",
  r: "\r",
  t: "\t",
};

function skipWhitespace(source: string, at: number): number {
  let index = at;
  while (index < source.length && WHITESPACE.includes(source[index] ?? "")) {
    index += 1;
  }
  return index;
}

function escapeValue(source: string, at: number): { end: number; text: string } {
  const hex = source.slice(at, at + 4);
  if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
    throw new Malformed("bad_escape");
  }
  return { end: at + 4, text: String.fromCharCode(Number.parseInt(hex, 16)) };
}

function readStringToken(source: string, at: number): { end: number; token: string; value: string } {
  if (source[at] !== "\"") {
    throw new Malformed("expected_string");
  }
  let index = at + 1;
  let value = "";
  while (index < source.length) {
    const char = source[index] ?? "";
    index += 1;
    if (char === "\"") {
      return { end: index, token: source.slice(at, index), value };
    }
    if (char !== "\\") {
      value += char;
      continue;
    }
    const simple = SIMPLE_ESCAPES[source[index] ?? ""];
    if (simple !== undefined) {
      value += simple;
      index += 1;
      continue;
    }
    if (source[index] === "u") {
      const unicode = escapeValue(source, index + 1);
      value += unicode.text;
      index = unicode.end;
      continue;
    }
    throw new Malformed("bad_escape");
  }
  throw new Malformed("unterminated_string");
}

function skipContainer(source: string, at: number, open: string, close: string): number {
  let index = skipWhitespace(source, at + 1);
  while (index < source.length) {
    if (source[index] === close) {
      return index + 1;
    }
    index = skipMember(source, index, open);
    if (source[index] === ",") {
      index = skipWhitespace(source, index + 1);
    }
  }
  throw new Malformed("unterminated_container");
}

function skipMember(source: string, at: number, open: string): number {
  if (open === "[") {
    return skipWhitespace(source, skipJsonValue(source, at));
  }
  const key = readStringToken(source, at);
  const colon = skipWhitespace(source, key.end);
  if (source[colon] !== ":") {
    throw new Malformed("expected_colon");
  }
  return skipWhitespace(source, skipJsonValue(source, colon + 1));
}

function skipJsonValue(source: string, at: number): number {
  const index = skipWhitespace(source, at);
  const char = source[index];
  if (char === "{") {
    return skipContainer(source, index, "{", "}");
  }
  if (char === "[") {
    return skipContainer(source, index, "[", "]");
  }
  if (char === "\"") {
    return readStringToken(source, index).end;
  }
  let end = index;
  while (end < source.length && !",}] \t\r\n".includes(source[end] ?? "")) {
    end += 1;
  }
  return end;
}

function lineBounds(source: string, keyStart: number, valueEnd: number): { end: number; start: number } {
  const start = source.lastIndexOf("\n", keyStart - 1) + 1;
  const found = source.indexOf("\n", valueEnd);
  return { end: found < 0 ? source.length : found + 1, start };
}

function scanMember(source: string, at: number): { index: number; member: Member } {
  const key = readStringToken(source, at);
  const colon = skipWhitespace(source, key.end);
  if (source[colon] !== ":") {
    throw new Malformed("expected_colon");
  }
  const valueStart = skipWhitespace(source, colon + 1);
  const token = source[valueStart] === "\"" ? readStringToken(source, valueStart) : null;
  const valueEnd = token === null ? skipJsonValue(source, valueStart) : token.end;
  const bounds = lineBounds(source, at, valueEnd);
  const member: Member = {
    key: key.value,
    keyStart: at,
    lineEnd: bounds.end,
    lineStart: bounds.start,
    token: token === null ? null : token.token,
    tokenEnd: token === null ? valueEnd : token.end,
    value: token === null ? "" : token.value,
  };
  return { index: valueEnd, member };
}

function scanMembers(source: string): Member[] {
  let index = skipWhitespace(source, 0);
  if (source[index] !== "{") {
    throw new Malformed("not_an_object");
  }
  const members: Member[] = [];
  index = skipWhitespace(source, index + 1);
  while (index < source.length && source[index] !== "}") {
    const scanned = scanMember(source, index);
    members.push(scanned.member);
    index = skipWhitespace(source, scanned.index);
    if (source[index] === ",") {
      index = skipWhitespace(source, index + 1);
    }
  }
  if (source[index] !== "}") {
    throw new Malformed("unterminated_object");
  }
  return members;
}

function membersOrNull(source: string): Member[] | null {
  try {
    if (asRow(JSON.parse(source) as Json) === null) return null;
    return scanMembers(source);
  } catch {
    return null;
  }
}

function findMember(members: Member[], key: string): Member | null {
  return members.find((member) => member.key === key) ?? null;
}

function stringMember(members: Member[], key: string): string {
  const member = findMember(members, key);
  return member === null || member.token === null ? "" : member.value;
}

// ---------- projection ----------

type Envelope =
  | { failure: ""; kind: "projected"; projection: Buffer; provenance: string; schema: string }
  | { code: string; failure: ""; kind: "refusal"; bytes: Buffer; schema: string }
  | { failure: string; kind: "invalid"; bytes: Buffer };

function invalidEnvelope(bytes: Buffer, failure: string): Envelope {
  return { bytes, failure, kind: "invalid" };
}

function exactSpan(source: string, member: Member): boolean {
  return source.slice(member.lineStart, member.lineEnd) === `  "provenance": "${member.value}",\n`;
}

function provenanceProjection(source: string, bytes: Buffer, members: Member[]): Envelope {
  const found = members.filter((member) => member.key === "provenance");
  if (found.length === 0) {
    return invalidEnvelope(bytes, "provenance-expected");
  }
  if (new Set(members.map((entry) => entry.key)).size !== members.length) {
    return invalidEnvelope(bytes, "projection-unique");
  }
  const member = found[0];
  if (member === undefined || member.token === null || !PROVENANCE_VALUES.includes(member.value)) {
    return invalidEnvelope(bytes, "provenance-expected");
  }
  if (!exactSpan(source, member)) {
    return invalidEnvelope(bytes, "projection-unique");
  }
  // The walk uses validated Unicode indices; convert only its boundaries to
  // byte offsets. Never decode/re-encode any bytes which remain compared.
  const start = Buffer.byteLength(source.slice(0, member.lineStart), "utf8");
  const end = Buffer.byteLength(source.slice(0, member.lineEnd), "utf8");
  return {
    failure: "",
    kind: "projected",
    projection: Buffer.concat([bytes.subarray(0, start), bytes.subarray(end)]),
    provenance: member.value,
    schema: stringMember(members, "schema"),
  };
}

function classifyStdout(bytes: Buffer): Envelope {
  if (asRow(parseJson(bytes)) === null) return invalidEnvelope(bytes, "envelope-schema");
  const source = bytes.toString("utf8");
  const members = membersOrNull(source);
  if (members === null) {
    return invalidEnvelope(bytes, "envelope-schema");
  }
  const schema = stringMember(members, "schema");
  if (schema === CONTRACT.refusal_schema) {
    if (new Set(members.map((member) => member.key)).size !== members.length) return invalidEnvelope(bytes, "envelope-schema");
    return { bytes, code: stringMember(members, "code"), failure: "", kind: "refusal", schema };
  }
  if (!CONTRACT.projected_schemas.includes(schema)) {
    return invalidEnvelope(bytes, "envelope-schema");
  }
  return provenanceProjection(source, bytes, members);
}

// ---------- retained run ----------

interface RawRun {
  dir: string;
  files: Map<string, Buffer>;
  inputs: Row;
  manifestSha: string;
}

function walkFiles(dir: string, prefix: string, files: Map<string, Buffer>): void {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    if (entry.isSymbolicLink()) {
      throw new Malformed(`symlink:${prefix}${entry.name}`);
    }
    const full = join(dir, entry.name);
    const rel = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) {
      walkFiles(full, rel, files);
    } else if (entry.isFile()) {
      files.set(rel, readFileSync(full));
    } else {
      throw new Malformed(`nonregular_input:${rel}`);
    }
  }
}

function manifestRows(bytes: Buffer): Json[] {
  const manifest = asRow(parseJson(bytes));
  const rows = asList(manifest?.files);
  if (manifest === null || manifest.schema !== MANIFEST_SCHEMA || !Array.isArray(manifest.files)) {
    throw new Malformed("raw_manifest_malformed");
  }
  return rows;
}

interface RowFields {
  bytes: string;
  path: string;
  sha256: string;
}

function rowFields(row: Json): RowFields {
  const entry = asRow(row);
  const size = entry?.bytes;
  return {
    bytes: typeof size === "number" ? String(size) : "",
    path: asText(entry?.path),
    sha256: asText(entry?.sha256),
  };
}

function recordRow(files: Map<string, Buffer>, row: Json, inputs: Row, listed: Set<string>): void {
  const fields = rowFields(row);
  const actual = files.get(fields.path);
  if (!HEX64.test(fields.sha256) || !safeRelative(fields.path) || listed.has(fields.path) || !/^\d+$/.test(fields.bytes)) {
    throw new Malformed("raw_manifest_row");
  }
  if (actual === undefined) throw new Malformed(`raw_manifest_missing_input:${fields.path}`);
  if (actual.length !== Number(fields.bytes) || sha256Hex(actual) !== fields.sha256) throw new Inconsistent(`raw_manifest_mismatch:${fields.path}`);
  listed.add(fields.path);
  inputs[fields.path] = fields.sha256;
}

function readRun(dir: string): RawRun {
  if (!lstatSync(dir).isDirectory()) {
    throw new Malformed("run_not_a_directory");
  }
  const files = new Map<string, Buffer>();
  walkFiles(dir, "", files);
  const manifestBytes = files.get("raw-manifest.json");
  if (manifestBytes === undefined) {
    throw new Malformed("raw_manifest_missing");
  }
  const inputs: Row = Object.create(null) as Row;
  const listed = new Set<string>();
  const rows = manifestRows(manifestBytes);
  const paths = rows.map((row) => rowFields(row).path);
  if (JSON.stringify(paths) !== JSON.stringify([...paths].sort())) throw new Malformed("raw_manifest_unsorted");
  for (const row of rows) {
    recordRow(files, row, inputs, listed);
  }
  files.delete("raw-manifest.json");
  for (const path of files.keys()) {
    if (!listed.has(path)) {
      throw new Malformed(`unlisted_input:${path}`);
    }
  }
  return { dir, files, inputs, manifestSha: sha256Hex(manifestBytes) };
}

function readBytes(run: RawRun, path: string): Buffer {
  const bytes = run.files.get(path);
  if (bytes === undefined) {
    throw new Malformed(`missing_input:${path}`);
  }
  return bytes;
}

function readJsonInput(run: RawRun, path: string): Json {
  try {
    return parseJson(readBytes(run, path));
  } catch {
    throw new Malformed(`malformed_input:${path}`);
  }
}

// ---------- lanes, targets and captures ----------

interface TargetInfo {
  common_dir: string;
  ref: string;
  repository: string;
  revision: string;
  root: string;
  target: string;
}

interface LaneInfo {
  common_dir: string;
  driver_commit: string;
  driver_root: string;
}

interface Lanes {
  candidate: LaneInfo;
  reference: LaneInfo;
  targets: TargetInfo[];
}

interface CaptureMeta {
  argv: string[];
  cwd: string;
  driver_commit: string;
  exit: number;
  finished_at: string;
  log_after: Json;
  log_before: Json;
  sequence: number;
  started_at: string;
  written: Json;
  written_before: Json;
}

interface Capture {
  envelope: Envelope;
  lane: string;
  meta: CaptureMeta;
  meta_bytes: Buffer;
  operation: string;
  plan_id: string;
  repository: string;
  stderr: Buffer;
  stdout: Buffer;
  written_after_files: Row;
  written_before_files: Row;
}

interface Site {
  captures: Map<string, Capture>;
  generation: string;
  operation: string;
  plan_id: string;
  repository: string;
}

function laneInfo(value: Json | undefined, label: string): LaneInfo {
  const row = asRow(value) || {};
  const info: LaneInfo = {
    common_dir: asText(row.common_dir),
    driver_commit: asText(row.driver_commit),
    driver_root: asText(row.driver_root),
  };
  if (!filled({ ...info }) || !HEX40.test(info.driver_commit) || !isAbsolute(info.driver_root) || !isAbsolute(info.common_dir)) {
    throw new Malformed(`lanes_lane:${label}`);
  }
  return info;
}

function targetInfo(entry: Json): TargetInfo | null {
  const row = asRow(entry);
  if (row === null) {
    return null;
  }
  const target: TargetInfo = {
    common_dir: asText(row.common_dir),
    ref: asText(row.ref),
    repository: asText(row.repository),
    revision: asText(row.revision),
    root: asText(row.root),
    target: asText(row.target),
  };
  return filled({ ...target }) && HEX40.test(target.revision) && isAbsolute(target.root) && isAbsolute(target.common_dir) ? target : null;
}

function readLanes(run: RawRun): Lanes {
  const lanes = asRow(readJsonInput(run, "lanes.json"));
  if (lanes === null || lanes.schema !== LANES_SCHEMA) {
    throw new Malformed("lanes_schema");
  }
  const targets: TargetInfo[] = [];
  for (const entry of asList(lanes.targets)) {
    const target = targetInfo(entry);
    if (target === null) {
      throw new Malformed("lanes_target");
    }
    targets.push(target);
  }
  if (new Set(targets.map((target) => target.repository)).size !== targets.length) throw new Malformed("duplicate_target");
  return { candidate: laneInfo(lanes.candidate, "candidate"), reference: laneInfo(lanes.reference, "reference"), targets };
}

function readNormalizations(run: RawRun): void {
  const value = readJsonInput(run, "normalizations.json");
  if (!Array.isArray(value)) {
    throw new Malformed("normalizations_not_array");
  }
  if (value.length > 0) {
    throw new Malformed("caller_normalization_mask_forbidden");
  }
}

function metaShapeOk(row: Row | null): boolean {
  if (row === null || row.schema !== CAPTURE_SCHEMA || asList(row.argv).length === 0) {
    return false;
  }
  const exit = row.exit;
  const sequence = row.sequence;
  if (typeof exit !== "number" || !Number.isSafeInteger(exit)) {
    return false;
  }
  if (typeof sequence !== "number" || !Number.isSafeInteger(sequence) || sequence <= 0) {
    return false;
  }
  const strings = ["cwd", "driver_commit", "started_at", "finished_at"];
  return [strings.every((key) => asText(row[key]) !== ""), asList(row.argv).every((arg) => typeof arg === "string"), HEX40.test(asText(row.driver_commit))].every(Boolean);
}

function logShape(value: Json | undefined): boolean {
  const row = asRow(value);
  if (row === null || typeof row.lines !== "number" || !Number.isSafeInteger(row.lines) || row.lines < 0) return false;
  if (Object.keys(row).sort().join(",") !== "lines,sha256") return false;
  return row.sha256 === null ? row.lines === 0 : HEX64.test(asText(row.sha256));
}

function mapShape(value: Json | undefined): boolean {
  const row = asRow(value);
  return row !== null && Object.entries(row).every(([path, digest]) => safeRelative(path) && HEX64.test(asText(digest)));
}

function operationMetaShape(row: Row, operation: string): boolean {
  const logs = [row.log_before, row.log_after];
  const maps = [row.written_before, row.written];
  return operation === "audit-merges" ? [...logs, ...maps].every((value) => value === null) : logs.every(logShape) && maps.every(mapShape);
}

function readCaptureMeta(run: RawRun, base: string): CaptureMeta {
  const row = asRow(readJsonInput(run, `${base}/meta.json`));
  if (!metaShapeOk(row) || row === null || !operationMetaShape(row, base.split("/").pop() || "")) {
    throw new Malformed(`capture_meta:${base}`);
  }
  return row as unknown as CaptureMeta;
}

function writtenFilesFor(run: RawRun, base: string, phase: string): Row {
  const prefix = `${base}/written-${phase}/`;
  const files: Row = Object.create(null) as Row;
  for (const path of [...run.files.keys()].sort()) {
    if (path.startsWith(prefix)) files[path.slice(prefix.length)] = sha256Hex(readBytes(run, path));
  }
  return files;
}

function readCapture(run: RawRun, lane: string, repository: string, plan: string, operation: string): Capture | null {
  const base = `captures/${lane}/${repository}/${plan}/${operation}`;
  if (!run.files.has(`${base}/meta.json`)) {
    return null;
  }
  const meta = readCaptureMeta(run, base);
  const stdout = readBytes(run, `${base}/stdout`);
  return {
    envelope: classifyStdout(stdout),
    lane,
    meta,
    meta_bytes: readBytes(run, `${base}/meta.json`),
    operation,
    plan_id: plan,
    repository,
    stderr: readBytes(run, `${base}/stderr`),
    stdout,
    written_after_files: writtenFilesFor(run, base, "after"),
    written_before_files: writtenFilesFor(run, base, "before"),
  };
}

// ---------- registries and sites ----------

interface RegistryPlan {
  generation: string;
  plan_id: string;
  status: string;
}

interface Registry {
  bytes: Buffer;
  plans: RegistryPlan[];
  present: boolean;
}

function parseRegistryPlan(row: Json): RegistryPlan | null {
  const entry = asRow(row);
  if (entry === null) {
    return null;
  }
  const plan: RegistryPlan = {
    generation: asText(entry.generation),
    plan_id: asText(entry.plan_id),
    status: asText(entry.status),
  };
  return filled({ ...plan }) ? plan : null;
}

function parseRegistry(bytes: Buffer): RegistryPlan[] | null {
  const value = asRow(parseJson(bytes));
  if (value === null || !Array.isArray(value.plans)) {
    return null;
  }
  const plans: RegistryPlan[] = [];
  for (const row of asList(value.plans)) {
    const plan = parseRegistryPlan(row);
    if (plan === null) {
      return null;
    }
    plans.push(plan);
  }
  if (new Set(plans.map((plan) => plan.plan_id)).size !== plans.length) return null;
  return plans;
}

function readRegistry(run: RawRun, repository: string): Registry {
  let bytes: Buffer = Buffer.alloc(0);
  try {
    bytes = readBytes(run, `registries/${repository}.json`);
  } catch {
    return { bytes, plans: [], present: false };
  }
  const plans = parseRegistry(bytes);
  return plans === null ? { bytes, plans: [], present: false } : { bytes, plans, present: true };
}

function sitePath(lane: string, repository: string, plan: string, operation: string): string {
  return `captures/${lane}/${repository}/${plan}/${operation}`;
}

function enumerateSites(run: RawRun, lanes: Lanes): Site[] {
  const sites: Site[] = [];
  for (const target of lanes.targets) {
    for (const plan of readRegistry(run, target.repository).plans) {
      for (const operation of OPERATIONS) {
        const captures = new Map<string, Capture>();
        for (const lane of LANES) {
          const capture = readCapture(run, lane, target.repository, plan.plan_id, operation);
          if (capture !== null) {
            captures.set(lane, capture);
          }
        }
        sites.push({ captures, generation: plan.generation, operation, plan_id: plan.plan_id, repository: target.repository });
      }
    }
  }
  return sites;
}

function expectedSites(lanes: Lanes, run: RawRun): string[] {
  const keys: string[] = [];
  for (const target of lanes.targets) {
    for (const plan of readRegistry(run, target.repository).plans) {
      for (const operation of OPERATIONS) {
        for (const lane of LANES) {
          keys.push(sitePath(lane, target.repository, plan.plan_id, operation));
        }
      }
    }
  }
  return keys;
}

function presentSiteDirs(run: RawRun): string[] {
  const dirs = new Set<string>();
  for (const path of run.files.keys()) {
    const match = /^captures\/([^/]+)\/([^/]+)\/([^/]+)\/([^/]+)\//.exec(path);
    if (match !== null) {
      dirs.add(sitePath(match[1] || "", match[2] || "", match[3] || "", match[4] || ""));
    }
  }
  return [...dirs].sort();
}

function captureList(sites: Site[]): Capture[] {
  const all: Capture[] = [];
  for (const site of sites) {
    for (const lane of LANES) {
      const capture = site.captures.get(lane);
      if (capture !== undefined) {
        all.push(capture);
      }
    }
  }
  return all;
}

// ---------- byte and pointer differences ----------

function pointerOf(path: ReadonlyArray<string | number>): string {
  return path
    .map((part) => `/${String(part).replaceAll("~", "~0").replaceAll("/", "~1")}`)
    .join("");
}

function arrayPointerDifference(left: Json[], right: Json[], path: ReadonlyArray<string | number>): string | null {
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index += 1) {
    const found = jsonPointerDifference(left[index] || null, right[index] || null, [...path, index]);
    if (found !== null) {
      return found;
    }
  }
  return pointerOf(path);
}

function objectPointerDifference(left: Row, right: Row, path: ReadonlyArray<string | number>): string | null {
  const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
  for (const key of keys) {
    const found = jsonPointerDifference(left[key] || null, right[key] || null, [...path, key]);
    if (found !== null) {
      return found;
    }
  }
  return pointerOf(path);
}

function jsonPointerDifference(left: Json, right: Json, path: ReadonlyArray<string | number> = []): string | null {
  if (JSON.stringify(sortDeep(left)) === JSON.stringify(sortDeep(right))) {
    return null;
  }
  if (Array.isArray(left) && Array.isArray(right)) {
    return arrayPointerDifference(left, right, path);
  }
  const leftRow = asRow(left);
  const rightRow = asRow(right);
  if (leftRow !== null && rightRow !== null) {
    return objectPointerDifference(leftRow, rightRow, path);
  }
  return pointerOf(path);
}

function firstDifference(left: Buffer, right: Buffer): Row {
  const leftJson = parseJson(left);
  const rightJson = parseJson(right);
  const pointer = jsonPointerDifference(leftJson, rightJson);
  if (pointer !== null) {
    return { kind: "json-pointer", pointer };
  }
  let offset = 0;
  while (offset < left.length && offset < right.length && left[offset] === right[offset]) {
    offset += 1;
  }
  return { kind: "byte-offset", offset };
}

// ---------- bounded local Git observation ----------

interface RecordedCommand {
  argv: string[];
  cwd: string;
  exit: number;
  phase: string;
  stderr: string;
  stdout: string;
  subject: string;
}

interface TargetObserved {
  common_finish: string;
  common_start: string;
  policy_blob: string;
  policy_sha256: string;
  problems: string[];
  ref_finish: string;
  ref_start: string;
  registry_blob: string;
  registry_sha256: string;
  repository: string;
  toplevel_finish: string;
  toplevel_start: string;
}

interface LaneObserved {
  common_finish: string;
  common_start: string;
  head_finish: string;
  head_start: string;
  problems: string[];
  toplevel_finish: string;
  toplevel_start: string;
}

interface Observation {
  facts: Json[];
  git: boolean;
  lanes: Map<string, LaneObserved>;
  problems: string[];
  targets: Map<string, TargetObserved>;
}

type Commands = Map<string, RecordedCommand>;

function localGit(cwd: string, args: ReadonlyArray<string>): ReturnType<typeof run> {
  // Object reads in a partial clone must fail locally, not lazily fetch. Ignore
  // replacement objects so reported commit/blob identities name their own bytes.
  return run("git", args, cwd, { ...process.env, GIT_NO_LAZY_FETCH: "1", GIT_TERMINAL_PROMPT: "0", GIT_OPTIONAL_LOCKS: "0", GIT_NO_REPLACE_OBJECTS: "1" });
}

function commandKey(phase: string, subject: string, argv: ReadonlyArray<string>): string {
  return JSON.stringify([phase, subject, argv]);
}

function base64Ok(value: Json | undefined): boolean {
  return typeof value === "string" && Buffer.from(value, "base64").toString("base64") === value;
}

function commandShape(entry: Row): boolean {
  return Number.isInteger(entry.exit) && base64Ok(entry.stdout) && base64Ok(entry.stderr) && PHASES.includes(asText(entry.phase)) && isAbsolute(asText(entry.cwd));
}

function parseCommand(row: Json): RecordedCommand | null {
  const entry = asRow(row);
  const argv = asList(entry?.argv);
  const phase = asText(entry?.phase);
  const subject = asText(entry?.subject);
  if (entry === null || argv.length === 0 || subject === "" || typeof entry.exit !== "number" || !commandShape(entry)) {
    return null;
  }
  if (!argv.every((arg) => typeof arg === "string")) return null;
  return {
    argv: argv.map((item) => asText(item)),
    cwd: asText(entry.cwd),
    exit: entry.exit,
    phase,
    stderr: asText(entry.stderr),
    stdout: asText(entry.stdout),
    subject,
  };
}

function readCommands(run: RawRun): Commands {
  const value = asRow(readJsonInput(run, "observation.json"));
  const rows = asList(value?.commands);
  if (value === null || value.schema !== OBSERVATION_SCHEMA || !HEX64.test(asText(value.lanes_sha256)) || !Array.isArray(value.commands)) {
    throw new Malformed("observation_schema");
  }
  const map: Commands = new Map();
  for (const row of rows) {
    const command = parseCommand(row);
    if (command === null) {
      throw new Malformed("observation_row");
    }
    const key = commandKey(command.phase, command.subject, command.argv);
    if (map.has(key)) {
      throw new Malformed(`observation_duplicate:${key}`);
    }
    map.set(key, command);
  }
  return map;
}

function stdoutBytes(commands: Commands, phase: string, subject: string, argv: ReadonlyArray<string>): Buffer | null {
  const command = commands.get(commandKey(phase, subject, argv));
  if (command === undefined || command.exit !== 0) {
    return null;
  }
  return Buffer.from(command.stdout, "base64");
}

function stdoutOf(commands: Commands, phase: string, subject: string, argv: ReadonlyArray<string>): string {
  const bytes = stdoutBytes(commands, phase, subject, argv);
  if (bytes === null) return "";
  const decoded = bytes.toString("utf8");
  return Buffer.from(decoded, "utf8").equals(bytes) && /^[^\r\n]+\n$/.test(decoded) ? decoded.slice(0, -1) : "";
}

function reader(commands: Commands, subject: string, problems: string[]): (phase: string, argv: ReadonlyArray<string>) => string {
  return (phase, argv) => {
    const value = stdoutOf(commands, phase, subject, ["git", ...argv]);
    if (value === "") {
      problems.push(`${phase}:${argv.join(" ")}`);
    }
    return value;
  };
}

function blobDigest(commands: Commands, subject: string, blob: string): string {
  if (blob === "") {
    return "";
  }
  const bytes = stdoutBytes(commands, "start", subject, ["git", "cat-file", "blob", blob]);
  if (bytes === null || !HEX40.test(blob)) return "";
  const actual = createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
  return actual === blob ? sha256Hex(bytes) : "";
}

function movementProblems(target: TargetInfo, observed: TargetObserved): string[] {
  const found: string[] = [];
  if (observed.common_start !== observed.common_finish) {
    found.push("common_dir_moved");
  }
  if (observed.toplevel_start !== observed.toplevel_finish) {
    found.push("toplevel_moved");
  }
  if (observed.ref_start !== observed.ref_finish) {
    found.push("ref_moved");
  }
  if (observed.ref_start !== target.revision) {
    found.push(`revision_mismatch:${target.revision}`);
  }
  if (observed.common_start !== target.common_dir) {
    found.push(`common_dir_mismatch:${target.repository}`);
  }
  if (observed.toplevel_start !== target.root) found.push(`root_mismatch:${target.repository}`);
  if (target.target === "main" && target.ref !== "refs/remotes/origin/main") found.push("wrong_main_ref");
  if (!literalRef(target.ref)) found.push("ref_not_fully_qualified");
  return found;
}

function literalRef(ref: string): boolean {
  if (!ref.startsWith("refs/") || !safeRelative(ref)) return false;
  const special = /[~^:?*[\]\\\s]/u.test(ref);
  const components = ref.split("/");
  return !special && !ref.includes("..") && !ref.includes("@{") && !ref.includes(String.fromCharCode(127)) && !ref.endsWith(".") && components.every((part) => !part.startsWith(".") && !part.endsWith(".lock"));
}

function targetIdentityKeys(target: TargetInfo, phase: string): string[] {
  const subject = `target:${target.repository}`;
  return [
    commandKey(phase, subject, ["git", "rev-parse", "--show-toplevel"]),
    commandKey(phase, subject, ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]),
    commandKey(phase, subject, ["git", "rev-parse", "--verify", `${target.ref}^{commit}`]),
  ];
}

function observeTarget(commands: Commands, target: TargetInfo): TargetObserved {
  const subject = `target:${target.repository}`;
  const problems: string[] = [];
  const read = reader(commands, subject, problems);
  const exists = commands.get(commandKey("start", subject, ["git", "cat-file", "-e", `${target.revision}^{commit}`]));
  if (exists === undefined || exists.exit !== 0) {
    problems.push(`commit_missing:${target.revision}`);
  }
  const observed: TargetObserved = {
    common_finish: read("finish", ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
    common_start: read("start", ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
    policy_blob: read("start", ["rev-parse", `${target.revision}:${CONTRACT.policy_path}`]),
    policy_sha256: "",
    problems,
    ref_finish: read("finish", ["rev-parse", "--verify", `${target.ref}^{commit}`]),
    ref_start: read("start", ["rev-parse", "--verify", `${target.ref}^{commit}`]),
    registry_blob: read("start", ["rev-parse", `${target.revision}:${CONTRACT.registry_path}`]),
    registry_sha256: "",
    repository: target.repository,
    toplevel_finish: read("finish", ["rev-parse", "--show-toplevel"]),
    toplevel_start: read("start", ["rev-parse", "--show-toplevel"]),
  };
  observed.policy_sha256 = blobDigest(commands, subject, observed.policy_blob);
  observed.registry_sha256 = blobDigest(commands, subject, observed.registry_blob);
  if (observed.policy_sha256 === "" || observed.registry_sha256 === "") problems.push("blob_response_invalid");
  observed.problems.push(...movementProblems(target, observed));
  return observed;
}

function observeLane(commands: Commands, lane: string): LaneObserved {
  const subject = `lane:${lane}`;
  const problems: string[] = [];
  const read = reader(commands, subject, problems);
  const observed: LaneObserved = {
    common_finish: read("finish", ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
    common_start: read("start", ["rev-parse", "--path-format=absolute", "--git-common-dir"]),
    head_finish: read("finish", ["rev-parse", "HEAD"]),
    head_start: read("start", ["rev-parse", "HEAD"]),
    problems,
    toplevel_finish: read("finish", ["rev-parse", "--show-toplevel"]),
    toplevel_start: read("start", ["rev-parse", "--show-toplevel"]),
  };
  if (observed.common_start !== observed.common_finish || observed.head_start !== observed.head_finish || observed.toplevel_start !== observed.toplevel_finish) {
    problems.push("lane_moved");
  }
  return observed;
}

function blobKeys(target: TargetInfo, blobs: ReadonlyArray<string>): string[] {
  const subject = `target:${target.repository}`;
  return blobs
    .filter((blob) => blob !== "")
    .map((blob) => commandKey("start", subject, ["git", "cat-file", "blob", blob]));
}

function targetKeys(target: TargetInfo, observed: TargetObserved | undefined): string[] {
  const subject = `target:${target.repository}`;
  const keys: string[] = [];
  for (const phase of PHASES) {
    keys.push(...targetIdentityKeys(target, phase));
  }
  keys.push(commandKey("start", subject, ["git", "cat-file", "-e", `${target.revision}^{commit}`]));
  keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.revision}:${CONTRACT.policy_path}`]));
  keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.revision}:${CONTRACT.registry_path}`]));
  keys.push(...blobKeys(target, [asText(observed?.policy_blob), asText(observed?.registry_blob)]));
  return keys;
}

function laneKeys(lane: string, phase: string): string[] {
  const subject = `lane:${lane}`;
  return [
    commandKey(phase, subject, ["git", "rev-parse", "--show-toplevel"]),
    commandKey(phase, subject, ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]),
    commandKey(phase, subject, ["git", "rev-parse", "HEAD"]),
  ];
}

function requiredKeys(lanes: Lanes, targets: Map<string, TargetObserved>): string[] {
  const keys: string[] = [];
  for (const target of lanes.targets) {
    keys.push(...targetKeys(target, targets.get(target.repository)));
  }
  for (const lane of LANES) {
    for (const phase of PHASES) {
      keys.push(...laneKeys(lane, phase));
    }
  }
  return [...new Set(keys)];
}

function commandSetProblems(commands: Commands, keys: ReadonlyArray<string>): string[] {
  const problems: string[] = [];
  for (const key of keys) {
    if (!commands.has(key)) {
      problems.push(`missing_command:${key}`);
    }
  }
  for (const key of commands.keys()) {
    if (!keys.includes(key)) {
      problems.push(`unexpected_command:${key}`);
    }
  }
  return problems;
}

function subjectRoot(lanes: Lanes, subject: string): string {
  if (subject.startsWith("lane:")) return laneOf(lanes, subject.slice(5)).driver_root;
  return lanes.targets.find((target) => `target:${target.repository}` === subject)?.root || "";
}

function physicalIdentity(path: string): boolean {
  try { return isAbsolute(path) && realpathSync(path) === path; } catch { return false; }
}

function commandResponses(commands: Commands, lanes: Lanes): string[] {
  const problems: string[] = [];
  for (const [key, command] of commands) {
    if (command.cwd !== subjectRoot(lanes, command.subject)) problems.push(`cwd_mismatch:${key}`);
    if (command.exit !== 0 || command.stderr !== "") problems.push(`required_read_failed:${key}`);
    if (command.argv.includes("-e") && command.stdout !== "") problems.push(`commit_response_invalid:${key}`);
  }
  return problems;
}

function liveProblem(key: string, command: RecordedCommand, targets: Map<string, TargetObserved>, problems: string[]): void {
  problems.push(`live_mismatch:${key}`);
  const target = targets.get(command.subject.replace(/^target:/, ""));
  if (target === undefined) return;
  if (command.argv.includes("--verify")) target.problems.push("ref_moved");
  else target.problems.push(`live_identity_mismatch:${key}`);
}

function liveMismatch(commands: Commands, keys: ReadonlyArray<string>, lanes: Lanes, targets: Map<string, TargetObserved>, problems: string[]): void {
  const ordered = PHASES.flatMap((phase) => keys.filter((key) => commands.get(key)?.phase === phase));
  for (const key of ordered) {
    const command = commands.get(key);
    if (command === undefined) {
      continue;
    }
    const cwd = subjectRoot(lanes, command.subject);
    if (!physicalIdentity(cwd)) { problems.push(`live_root_not_physical:${key}`); continue; }
    const result = localGit(cwd, command.argv.slice(1));
    if (result.status !== command.exit || !result.stdout.equals(Buffer.from(command.stdout, "base64")) || !result.stderr.equals(Buffer.from(command.stderr, "base64"))) {
      liveProblem(key, command, targets, problems);
    }
  }
}

function laneMetadataProblems(lanes: Lanes, rows: Map<string, LaneObserved>): string[] {
  const problems: string[] = [];
  for (const lane of LANES) {
    const observed = rows.get(lane);
    const info = laneOf(lanes, lane);
    if (observed === undefined || observed.common_start !== info.common_dir || observed.head_start !== info.driver_commit || observed.toplevel_start !== info.driver_root) {
      problems.push(`lane_metadata:${lane}`);
    }
  }
  return problems;
}

function targetFacts(lanes: Lanes, targets: Map<string, TargetObserved>): Json[] {
  return lanes.targets.map((target) => {
    const observed = targets.get(target.repository);
    if (observed === undefined) return { repository: target.repository };
    return {
      common_dir_finish: observed.common_finish,
      common_dir_start: observed.common_start,
      policy_blob: observed.policy_blob,
      policy_sha256: observed.policy_sha256,
      ref_finish: observed.ref_finish,
      ref_start: observed.ref_start,
      registry_blob: observed.registry_blob,
      registry_sha256: observed.registry_sha256,
      repository: target.repository,
      toplevel_start: observed.toplevel_start,
      toplevel_finish: observed.toplevel_finish,
    };
  });
}

function laneFacts(rows: Map<string, LaneObserved>): Json[] {
  return LANES.map((lane) => {
    const observed = rows.get(lane);
    return {
      common_dir_finish: asText(observed?.common_finish),
      common_dir_start: asText(observed?.common_start),
      head_start: asText(observed?.head_start),
      head_finish: asText(observed?.head_finish),
      lane,
      toplevel_start: asText(observed?.toplevel_start),
      toplevel_finish: asText(observed?.toplevel_finish),
    };
  });
}

function observeRun(run: RawRun, lanes: Lanes, observe: boolean): Observation {
  const commands = readCommands(run);
  const problems: string[] = [];
  const targets = new Map<string, TargetObserved>();
  for (const target of lanes.targets) {
    const observed = observeTarget(commands, target);
    problems.push(...observed.problems);
    targets.set(target.repository, observed);
  }
  const laneRows = new Map<string, LaneObserved>();
  for (const lane of LANES) {
    const observed = observeLane(commands, lane);
    problems.push(...observed.problems);
    laneRows.set(lane, observed);
  }
  const keys = requiredKeys(lanes, targets);
  const transcript = asRow(readJsonInput(run, "observation.json"));
  if (asText(transcript?.lanes_sha256) !== sha256Hex(readBytes(run, "lanes.json"))) problems.push("lanes_digest_mismatch");
  problems.push(...commandSetProblems(commands, keys));
  problems.push(...commandResponses(commands, lanes));
  problems.push(...laneMetadataProblems(lanes, laneRows));
  if (observe) {
    livePhysicalMetadata(lanes, problems);
    liveMismatch(commands, keys, lanes, targets, problems);
  }
  return {
    facts: [...targetFacts(lanes, targets), ...laneFacts(laneRows)],
    git: problems.length === 0,
    lanes: laneRows,
    problems,
    targets,
  };
}

function livePhysicalMetadata(lanes: Lanes, problems: string[]): void {
  for (const target of lanes.targets) {
    if (!physicalIdentity(target.root) || !physicalIdentity(target.common_dir)) problems.push(`live_target_not_physical:${target.repository}`);
  }
  for (const lane of LANES) {
    const info = laneOf(lanes, lane);
    if (!physicalIdentity(info.driver_root) || !physicalIdentity(info.common_dir)) problems.push(`live_lane_not_physical:${lane}`);
  }
}

// ---------- site comparison ----------

interface SiteResult {
  classification: string;
  differences: Json[];
  id: string;
}

const OPERATION_SCHEMA: Readonly<Record<string, string>> = {
  "audit-merges": "merge-audit/1",
  "export-evidence": "evidence-export/1",
};

const SITE_ASSERTIONS = [
  "capture-argv",
  "envelope-plan",
  "envelope-schema",
  "envelope-operation",
  "exit-equal",
  "finding-codes-equal",
  "log-quiescent",
  "projection-equal",
  "projection-unique",
  "provenance-expected",
  "provenance-pair",
  "refusal-codes-equal",
  "refusal-exit",
  "stderr-equal",
  "written-equal",
];

function laneOf(lanes: Lanes, lane: string): LaneInfo {
  return lane === "reference" ? lanes.reference : lanes.candidate;
}

function expectedProvenance(lanes: Lanes, repository: string, lane: string): string {
  const target = lanes.targets.find((row) => row.repository === repository);
  if (target === undefined || target.common_dir !== laneOf(lanes, lane).common_dir) {
    return "source-lane";
  }
  return "base-copy";
}

function projectedBytes(capture: Capture): Buffer | null {
  const envelope = capture.envelope;
  if (envelope.kind === "projected") {
    return envelope.projection;
  }
  return envelope.kind === "refusal" ? envelope.bytes : null;
}

function projectedSchema(capture: Capture): string {
  return capture.envelope.kind === "projected" ? capture.envelope.schema : "";
}

function memberValue(capture: Capture, key: string): string {
  const bytes = projectedBytes(capture);
  return bytes === null ? "" : asText(asRow(parseJson(bytes))?.[key]);
}

function codesOf(capture: Capture, field: string): string[] {
  const row = asRow(parseJson(capture.stdout)) || {};
  const entries = asList(field === "code" ? row.refusals : row.findings);
  const codes = entries.map((entry) => asText(asRow(entry)?.code));
  if (field === "code" && typeof row.code === "string") codes.push(row.code);
  return codes.sort();
}

function argvOk(capture: Capture, lanes: Lanes, target: TargetInfo, site: Site): boolean {
  const expected = [
    "bash",
    "04-validate-handoff/autobahn/contract-run.sh",
    site.operation,
    "--root",
    target.root,
    "--target",
    target.target,
    "--plan",
    site.plan_id,
  ];
  const lane = laneOf(lanes, capture.lane);
  return (
    JSON.stringify(capture.meta.argv) === JSON.stringify(expected) &&
    capture.meta.cwd === lane.driver_root &&
    capture.meta.driver_commit === lane.driver_commit
  );
}

function writtenMapsMatch(capture: Capture): boolean {
  return (
    canonical(asRow(capture.meta.written) || {}) === canonical(capture.written_after_files) &&
    canonical(asRow(capture.meta.written_before) || {}) === canonical(capture.written_before_files)
  );
}

function writtenEqual(reference: Capture, candidate: Capture): boolean {
  const nonempty = (capture: Capture): boolean => capture.operation !== "export-evidence" || capture.meta.exit !== 0 || Object.keys(capture.written_after_files).length > 0;
  return (
    nonempty(reference) && nonempty(candidate) &&
    canonical(reference.meta.written) === canonical(candidate.meta.written) &&
    canonical(reference.meta.written_before) === canonical(candidate.meta.written_before) &&
    canonical(reference.written_after_files) === canonical(candidate.written_after_files) &&
    canonical(reference.written_before_files) === canonical(candidate.written_before_files)
  );
}

function logQuiescent(reference: Capture, candidate: Capture): boolean {
  const stable = (capture: Capture): boolean => canonical(capture.meta.log_before) === canonical(capture.meta.log_after);
  return stable(reference) && stable(candidate) && canonical(reference.meta.log_after) === canonical(candidate.meta.log_after);
}

function projectionDigest(capture: Capture): string {
  const bytes = projectedBytes(capture);
  return bytes === null ? "unavailable" : sha256Hex(bytes);
}

function digestsFor(capture: Capture): Row {
  const written = (phase: string): string =>
    sha256Hex(
      Buffer.from(
        canonical({
          files: phase === "before" ? capture.written_before_files : capture.written_after_files,
          map: phase === "before" ? capture.meta.written_before : capture.meta.written,
        }),
        "utf8",
      ),
    );
  return {
    exit: capture.meta.exit,
    meta_sha256: sha256Hex(capture.meta_bytes),
    projection_sha256: projectionDigest(capture),
    stderr_sha256: sha256Hex(capture.stderr),
    stdout_sha256: sha256Hex(capture.stdout),
    written_after_sha256: written("after"),
    written_before_sha256: written("before"),
    written_before: capture.meta.written_before,
    written_after: capture.meta.written,
    written_before_files: capture.written_before_files,
    written_after_files: capture.written_after_files,
    written_changes: writtenChanges(capture),
  };
}

function writtenChanges(capture: Capture): Json[] {
  const before = capture.written_before_files;
  const after = capture.written_after_files;
  const paths = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return paths.filter((path) => before[path] !== after[path]).map((path) => ({ path, before: before[path] || null, after: after[path] || null }));
}

function addSiteAssertions(ledger: Ledger, lanes: Lanes, target: TargetInfo, site: Site, subject: string): Capture[] {
  const reference = site.captures.get("reference");
  const candidate = site.captures.get("candidate");
  const both = reference === undefined || candidate === undefined ? [] : [reference, candidate];
  ledger.add("capture-argv", subject, both.length === 2 && both.every((capture) => argvOk(capture, lanes, target, site)), "argv template and lane cwd");
  ledger.add("envelope-schema", subject, both.every((capture) => capture.envelope.kind !== "invalid"), "every stdout classifies");
  const refusals = both.filter((capture) => capture.envelope.kind === "refusal").length;
  ledger.add("provenance-pair", subject, refusals === 0 || refusals === 2, "both envelopes carry provenance or both refuse");
  ledger.add(
    "envelope-operation",
    subject,
    both.every((capture) => capture.envelope.kind === "refusal" || projectedSchema(capture) === OPERATION_SCHEMA[site.operation]),
    "audit versus export schema",
  );
  ledger.add(
    "envelope-plan",
    subject,
    both.every((capture) => envelopePlanOk(capture, site, target)),
    "envelope plan binds the registry entry",
  );
  ledger.add("refusal-exit", subject, both.every((capture) => capture.envelope.kind !== "refusal" || capture.meta.exit !== 0), "generic refusals never become successes");
  ledger.add(
    "provenance-expected",
    subject,
    both.every((capture) => capture.envelope.failure !== "provenance-expected"),
    "every projected envelope carries a valid provenance value",
  );
  ledger.add(
    "projection-unique",
    subject,
    both.every((capture) => capture.envelope.failure !== "projection-unique"),
    "one exact depth-one provenance member span",
  );
  return both;
}

function envelopePlanOk(capture: Capture, site: Site, target: TargetInfo): boolean {
  const bytes = projectedBytes(capture);
  const row = bytes === null ? null : asRow(parseJson(bytes));
  if (row === null) return false;
  const planOk = row.plan_id === undefined ? capture.envelope.kind === "refusal" : row.plan_id === site.plan_id;
  // This generation is read from the pinned target's retained registry, not
  // from another capture or a caller-selected expected value.
  const generation = site.generation;
  return planOk && (row.generation === undefined || row.generation === generation) && target.repository === site.repository;
}

function compareSite(ledger: Ledger, lanes: Lanes, target: TargetInfo, site: Site): SiteResult {
  const subject = `${site.repository}/${site.plan_id}/${site.operation}`;
  const reference = site.captures.get("reference");
  const candidate = site.captures.get("candidate");
  const both = addSiteAssertions(ledger, lanes, target, site, subject);
  if (reference === undefined || candidate === undefined || both.length !== 2) {
    ledger.add("site-pair", subject, false, "a lane capture is absent");
    return { classification: "red", differences: [{ kind: "missing-capture" }], id: subject };
  }
  const differences = outcomeAssertions(ledger, subject, reference, candidate);
  ledger.add("written-equal", subject, writtenEqual(reference, candidate), "complete written maps and snapshots");
  if (site.operation === "export-evidence") {
    ledger.add("log-quiescent", subject, logQuiescent(reference, candidate), "stable export log samples");
  }
  return { classification: classify(ledger, subject, reference.meta.exit), differences, id: subject };
}

function outcomeAssertions(ledger: Ledger, subject: string, reference: Capture, candidate: Capture): Json[] {
  const differences: Json[] = [];
  ledger.add("exit-equal", subject, reference.meta.exit === candidate.meta.exit, "exact exits");
  ledger.add("refusal-codes-equal", subject, JSON.stringify(codesOf(reference, "code")) === JSON.stringify(codesOf(candidate, "code")), "sorted refusal code lists");
  ledger.add("finding-codes-equal", subject, JSON.stringify(codesOf(reference, "findings")) === JSON.stringify(codesOf(candidate, "findings")), "sorted finding code lists");
  const left = projectedBytes(reference);
  const right = projectedBytes(candidate);
  const equal = left !== null && right !== null && left.equals(right);
  ledger.add("projection-equal", subject, equal, "projected stdout bytes");
  if (!equal && left !== null && right !== null) {
    differences.push(firstDifference(left, right));
  }
  const stderrEqual = reference.stderr.equals(candidate.stderr);
  ledger.add("stderr-equal", subject, stderrEqual, "stderr bytes");
  if (!stderrEqual) {
    differences.push({ stream: "stderr", ...firstDifference(reference.stderr, candidate.stderr) });
  }
  return sortDifferences(differences);
}

function classify(ledger: Ledger, subject: string, exit: number): string {
  if (SITE_ASSERTIONS.some((id) => ledger.failed(id, subject))) {
    return "red";
  }
  return exit === 0 ? "equal-success" : "equal-refusal";
}

function sortDifferences(differences: Json[]): Json[] {
  return [...differences].sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
}

// ---------- assertions ----------

class Ledger {
  private readonly rows: Assertion[] = [];
  private readonly keys = new Set<string>();

  add(id: string, subject: string, ok: boolean, detail: string): void {
    const key = JSON.stringify([id, subject]);
    if (this.keys.has(key)) throw new Malformed(`duplicate_assertion:${key}`);
    this.keys.add(key);
    this.rows.push({ detail, id, ok, subject });
  }

  sorted(): Assertion[] {
    return [...this.rows].sort((left, right) => (left.id === right.id ? left.subject.localeCompare(right.subject) : left.id.localeCompare(right.id)));
  }

  allOk(): boolean {
    return this.rows.every((row) => row.ok);
  }

  failed(id: string, subject: string): boolean {
    return this.rows.some((row) => row.id === id && row.subject === subject && !row.ok);
  }
}

interface Assertion {
  detail: string;
  id: string;
  ok: boolean;
  subject: string;
}

// ---------- global and per-target assertions ----------

function projectedAt(sites: Site[], repository: string, operation: string): Site[] {
  return sites.filter(
    (site) =>
      site.repository === repository &&
      (operation === "" || site.operation === operation) &&
      site.captures.get("reference")?.envelope.kind === "projected" &&
      site.captures.get("candidate")?.envelope.kind === "projected",
  );
}

function serialized(captures: Capture[]): boolean {
  const sequences = captures.map((capture) => capture.meta.sequence);
  if (new Set(sequences).size !== sequences.length) {
    return false;
  }
  const ordered = [...captures].sort((left, right) => left.meta.sequence - right.meta.sequence);
  return ordered.every((capture, index) => {
    const previous = ordered[index - 1];
    const start = capture.meta.started_at;
    const finish = capture.meta.finished_at;
    return utcValid(start) && utcValid(finish) && Date.parse(start) <= Date.parse(finish) && (previous === undefined || Date.parse(previous.meta.finished_at) <= Date.parse(start));
  });
}

function repositoryTimingOk(sites: Site[], repository: string): boolean {
  const audits = captureList(sites.filter((site) => site.repository === repository && site.operation === "audit-merges"));
  const exports = captureList(sites.filter((site) => site.repository === repository && site.operation === "export-evidence"));
  const last = Math.max(...audits.map((capture) => Date.parse(capture.meta.finished_at)));
  const first = Math.min(...exports.map((capture) => Date.parse(capture.meta.started_at)));
  return audits.length > 0 && exports.length > 0 && last <= first;
}

function auditsBeforeExports(sites: Site[]): boolean {
  return new Set(sites.map((site) => site.repository)).size > 0 && [...new Set(sites.map((site) => site.repository))].every((repository) => repositoryTimingOk(sites, repository));
}

function provenanceAt(sites: Site[], repository: string, lane: string, expected: string): boolean {
  return sites
    .filter((site) => site.repository === repository)
    .map((site) => site.captures.get(lane))
    .filter((capture): capture is Capture => capture !== undefined)
    .every((capture) => capture.envelope.kind !== "projected" || capture.envelope.provenance === expected);
}

function observedProvenance(sites: Site[], repository: string, lane: string): string[] {
  const values = new Set<string>();
  for (const site of sites.filter((row) => row.repository === repository)) {
    const envelope = site.captures.get(lane)?.envelope;
    if (envelope !== undefined && envelope.kind === "projected") {
      values.add(envelope.provenance);
    }
  }
  return [...values].sort();
}

function uniqueTargetCount(lanes: Lanes, commonDir: string): number {
  return lanes.targets.filter((target) => target.common_dir === commonDir).length;
}

function policyIdentity(bytes: Buffer | null): string {
  return bytes === null ? "" : asText(asRow(asRow(parseJson(bytes))?.repository)?.id);
}

function policyBound(run: RawRun, target: TargetInfo, observed: TargetObserved | undefined): boolean {
  const policy = run.files.get(`policies/${target.repository}.json`) || null;
  const recorded = asText(observed?.policy_sha256);
  return policy !== null && recorded !== "" && sha256Hex(policy) === recorded && policyIdentity(policy) === target.repository;
}

function refProblems(observed: TargetObserved | undefined): string[] {
  return asList(observed?.problems)
    .map((problem) => asText(problem))
    .filter((problem) => problem === "ref_moved" || problem === "wrong_main_ref" || problem === "ref_not_fully_qualified" || problem.startsWith("revision_mismatch") || problem.includes("--verify"));
}

function registryBound(run: RawRun, target: TargetInfo, observed: TargetObserved | undefined): boolean {
  const registry = readRegistry(run, target.repository);
  const recorded = asText(observed?.registry_sha256);
  const policy = run.files.get(`policies/${target.repository}.json`);
  const policyOk = policy !== undefined && sha256Hex(policy) === observed?.policy_sha256;
  return registry.present && recorded !== "" && sha256Hex(registry.bytes) === recorded && policyOk;
}

function targetBoundAssertions(ledger: Ledger, run: RawRun, target: TargetInfo, observed: TargetObserved | undefined): void {
  const moving = refProblems(observed);
  const rootsBound = targetRootsBound(target, observed);
  ledger.add("target-repository-bound", target.repository, policyBound(run, target, observed) && rootsBound, "physical roots and policy identity bind the target repository");
  ledger.add("target-ref-bound", target.repository, moving.length === 0, moving.join(" ") || "pinned revision re-observed");
  ledger.add("registry-bound", target.repository, registryBound(run, target, observed), "registry copy equals the blob at the pinned revision");
}

function targetRootsBound(target: TargetInfo, observed: TargetObserved | undefined): boolean {
  if (observed === undefined) return false;
  const identities = [observed.toplevel_start === target.root, observed.toplevel_finish === target.root, observed.common_start === target.common_dir, observed.common_finish === target.common_dir];
  return identities.every(Boolean) && !observed.problems.some((problem) => problem.startsWith("live_identity_mismatch"));
}

function revisionCarries(capture: Capture | undefined, revision: string): boolean {
  if (capture === undefined || capture.envelope.kind !== "projected") {
    return true;
  }
  if (capture.envelope.schema !== OPERATION_SCHEMA["audit-merges"]) {
    return true;
  }
  return memberValue(capture, "target_revision") === revision;
}

function revisionBound(sites: Site[], target: TargetInfo): boolean {
  return sites
    .filter((site) => site.repository === target.repository)
    .every((site) => LANES.every((lane) => revisionCarries(site.captures.get(lane), target.revision)));
}

function auditPairOk(sites: Site[], repository: string): boolean {
  return projectedAt(sites, repository, "audit-merges").some((site) => {
    const reference = site.captures.get("reference");
    const candidate = site.captures.get("candidate");
    return reference !== undefined && candidate !== undefined && memberValue(reference, "target_revision") !== "" && memberValue(candidate, "target_revision") !== "";
  });
}

function targetAssertions(ledger: Ledger, lanes: Lanes, run: RawRun, sites: Site[], observation: Observation): void {
  for (const target of lanes.targets) {
    targetBoundAssertions(ledger, run, target, observation.targets.get(target.repository));
    ledger.add("target-revision", target.repository, revisionBound(sites, target), "merge-audit envelopes carry the pinned revision");
    ledger.add("lane-observed-per-target", target.repository, projectedAt(sites, target.repository, "").length > 0, "provenance-bearing pair");
    ledger.add("audit-pair-per-target", target.repository, auditPairOk(sites, target.repository), "qualifying merge-audit pair");
    for (const lane of LANES) {
      const wanted = expectedProvenance(lanes, target.repository, lane);
      ledger.add("provenance-expected", `${lane}/${target.repository}`, provenanceAt(sites, target.repository, lane, wanted), `expected ${wanted}`);
    }
  }
}

function lanesDistinct(lanes: Lanes, sites: Site[]): boolean {
  const reference = observedProvenance(sites, "skills", "reference");
  const candidate = observedProvenance(sites, "skills", "candidate");
  const referenceOk = reference.length > 0 && reference.every((value) => value === "base-copy");
  const candidateOk = candidate.length > 0 && candidate.every((value) => value === "source-lane");
  return uniqueTargetCount(lanes, lanes.reference.common_dir) === 1 && referenceOk && candidateOk;
}

function laneAssertions(ledger: Ledger, lanes: Lanes, sites: Site[], captures: Capture[]): void {
  ledger.add("common-dir-reference", "lanes", uniqueTargetCount(lanes, lanes.reference.common_dir) === 1, "exactly one target equals the reference common dir");
  ledger.add(
    "common-dir-candidate",
    "lanes",
    lanes.candidate.common_dir !== lanes.reference.common_dir && uniqueTargetCount(lanes, lanes.candidate.common_dir) === 0,
    "candidate equals no target and differs from reference",
  );
  const commits = captures.every((capture) => capture.meta.driver_commit === laneOf(lanes, capture.lane).driver_commit);
  ledger.add("driver-commits-distinct", "lanes", lanes.candidate.driver_commit !== lanes.reference.driver_commit && commits, "distinct full lane commits");
  ledger.add("lanes-distinct-own-repository", "lanes", lanesDistinct(lanes, sites), "the skills target alone anchors the reference lane");
}

function runAssertions(ledger: Ledger, run: RawRun, lanes: Lanes, sites: Site[], captures: Capture[], observation: Observation): void {
  const counts = CONTRACT.required_targets.map((repository) => lanes.targets.filter((target) => target.repository === repository).length);
  ledger.add("targets-complete", "targets", counts.every((count) => count === 1), counts.join(","));
  const complete = sites.every((site) => site.captures.size === LANES.length);
  ledger.add(
    "site-set",
    "registry",
    JSON.stringify(presentSiteDirs(run)) === JSON.stringify(expectedSites(lanes, run).sort()) && complete,
    "every registry plan, operation and lane is captured exactly",
  );
  ledger.add("captures-serialized", "run", serialized(captures), "unique positive sequences and non-overlapping intervals");
  ledger.add("order-audits-before-exports", "run", auditsBeforeExports(sites), "every audit completes before any export starts");
  ledger.add("raw-inputs-bound", "run", captures.every((capture) => writtenMapsMatch(capture)) && rawLayoutOk(run, lanes, captures), "complete raw inventory and independently enumerated written maps");
  ledger.add("observe-git", "observed", observation.git, observation.problems.join(" ") || "retained observation consistent");
}

function rawLayoutOk(run: RawRun, lanes: Lanes, captures: Capture[]): boolean {
  const allowed = new Set(["lanes.json", "normalizations.json", "observation.json"]);
  for (const target of lanes.targets) {
    allowed.add(`registries/${target.repository}.json`);
    allowed.add(`policies/${target.repository}.json`);
  }
  const snapshots: string[] = [];
  for (const capture of captures) {
    const base = sitePath(capture.lane, capture.repository, capture.plan_id, capture.operation);
    for (const file of ["stdout", "stderr", "meta.json"]) allowed.add(`${base}/${file}`);
    if (capture.operation === "export-evidence") snapshots.push(`${base}/written-before/`, `${base}/written-after/`);
  }
  return [...run.files.keys()].every((path) => allowed.has(path) || snapshots.some((prefix) => path.startsWith(prefix)));
}

function siteResults(ledger: Ledger, lanes: Lanes, sites: Site[]): SiteResult[] {
  return sites.map((site) => {
    const target = lanes.targets.find((row) => row.repository === site.repository);
    const id = `${site.repository}/${site.plan_id}/${site.operation}`;
    if (target === undefined) {
      return { classification: "red", differences: [{ kind: "unknown-target" }], id };
    }
    return compareSite(ledger, lanes, target, site);
  });
}

function tally(results: SiteResult[]): Row {
  const counts: Row = { equal_refusal: 0, equal_success: 0, red: 0, sites: results.length };
  const add = (key: string): void => {
    counts[key] = Number(counts[key]) + 1;
  };
  for (const result of results) {
    add(result.classification.replaceAll("-", "_"));
  }
  return counts;
}

// ---------- report ----------

interface ReportInput {
  counts: Row;
  directory: string;
  inputs: Row;
  lanes: Lanes;
  manifestSha: string;
  observation: Observation;
  results: SiteResult[];
  sites: Site[];
  verdict: string;
}

function expectedProvenanceTable(lanes: Lanes): Row {
  const table: Row = Object.create(null) as Row;
  for (const lane of LANES) {
    const row: Row = Object.create(null) as Row;
    for (const target of lanes.targets) {
      row[target.repository] = expectedProvenance(lanes, target.repository, lane);
    }
    table[lane] = row;
  }
  return table;
}

function laneJson(info: LaneInfo): Row {
  return { common_dir: info.common_dir, driver_commit: info.driver_commit, driver_root: info.driver_root };
}

function targetJson(target: TargetInfo): Row {
  return {
    common_dir: target.common_dir,
    ref: target.ref,
    repository: target.repository,
    revision: target.revision,
    root: target.root,
    target: target.target,
  };
}

function provenanceJson(capture: Capture | undefined): string {
  if (capture === undefined) {
    return "";
  }
  if (capture.envelope.kind === "projected") {
    return capture.envelope.provenance;
  }
  return "";
}

function captureCodes(capture: Capture | undefined): Json {
  return capture === undefined ? null : { refusal: codesOf(capture, "code"), findings: codesOf(capture, "findings") };
}

function siteJson(site: Site, result: SiteResult): Row {
  const reference = site.captures.get("reference");
  const candidate = site.captures.get("candidate");
  return {
    classification: result.classification,
    codes: {
      reference: captureCodes(reference),
      candidate: captureCodes(candidate),
    },
    digests: {
      candidate: candidate === undefined ? null : digestsFor(candidate),
      reference: reference === undefined ? null : digestsFor(reference),
    },
    differences: result.differences,
    exits: {
      candidate: candidate === undefined ? null : candidate.meta.exit,
      reference: reference === undefined ? null : reference.meta.exit,
    },
    id: result.id,
    lanes: {
      candidate: candidate === undefined ? null : candidate.meta.sequence,
      reference: reference === undefined ? null : reference.meta.sequence,
    },
    normalizations: [],
    operation: site.operation,
    plan_id: site.plan_id,
    projections: {
      candidate: candidate === undefined ? null : projectionDigest(candidate),
      reference: reference === undefined ? null : projectionDigest(reference),
    },
    provenance: {
      candidate: provenanceJson(candidate),
      reference: provenanceJson(reference),
    },
    repository: site.repository,
  };
}

function buildReport(input: ReportInput, ledger: Ledger): Row {
  return {
    assertions: ledger.sorted() as unknown as Json,
    contract: contractJson(),
    counts: input.counts,
    lanes: {
      candidate: laneJson(input.lanes.candidate),
      expected_provenance: expectedProvenanceTable(input.lanes),
      reference: laneJson(input.lanes.reference),
      targets: input.lanes.targets.map(targetJson),
    },
    observed: {
      basis: "retained-local-observation",
      facts: input.observation.facts,
      git: input.observation.git,
      problems: input.observation.problems,
    },
    run: {
      directory: input.directory.split(sep).join("/"),
      inputs: input.inputs,
      manifest_sha256: input.manifestSha,
    },
    schema: CONTRACT.schema,
    sites: input.sites.map((site, index) => siteJson(site, input.results[index] || { classification: "red", differences: [], id: `${site.repository}/${site.plan_id}/${site.operation}` })),
    verdict: input.verdict,
  };
}

function malformedReport(dir: string, error: unknown): { exit: number; report: Row } {
  const detail = error instanceof Error ? error.message : "malformed_input";
  const mismatch = error instanceof Inconsistent;
  return {
    exit: mismatch ? 1 : 2,
    report: {
      assertions: [{ id: "raw-inputs-bound", subject: "run", ok: false, detail }],
      contract: contractJson(),
      counts: { equal_refusal: 0, equal_success: 0, red: 0, sites: 0 },
      lanes: {},
      observed: { basis: "retained-local-observation", facts: [], git: false, problems: [detail] },
      problems: [{ code: mismatch ? "raw-inputs-bound" : "malformed", detail }],
      run: { directory: dir.split(sep).join("/"), inputs: {}, manifest_sha256: "" },
      schema: CONTRACT.schema,
      sites: [],
      verdict: mismatch ? "red" : "malformed",
    },
  };
}

function evaluateRun(dir: string, observe: boolean): { exit: number; report: Row } {
  try {
    const run = readRun(dir);
    const lanes = readLanes(run);
    readNormalizations(run);
    return evaluateValidRun(run, lanes, observe);
  } catch (error) {
    return malformedReport(relative(process.cwd(), dir), error);
  }
}

function evaluateValidRun(run: RawRun, lanes: Lanes, observe: boolean): { exit: number; report: Row } {
  const ledger = new Ledger();
  const observation = observeRun(run, lanes, observe);
  const sites = enumerateSites(run, lanes);
  const captures = captureList(sites);
  targetAssertions(ledger, lanes, run, sites, observation);
  laneAssertions(ledger, lanes, sites, captures);
  runAssertions(ledger, run, lanes, sites, captures, observation);
  const results = siteResults(ledger, lanes, sites);
  const counts = tally(results);
  const verdict = ledger.allOk() && counts.red === 0 ? "pass" : "red";
  return {
    exit: verdict === "pass" ? 0 : 1,
    report: buildReport(
      { counts, directory: relative(process.cwd(), run.dir), inputs: run.inputs, lanes, manifestSha: run.manifestSha, observation, results, sites, verdict },
      ledger,
    ),
  };
}

// ---------- consumer check ----------

interface ConsumerFailures {
  failed: string[];
  facts: Row;
  malformed: boolean;
}

function gitOut(cwd: string, args: ReadonlyArray<string>): string {
  const result = localGit(cwd, args);
  return result.status === 0 ? text(result.stdout).trim() : "";
}

function gitBlob(cwd: string, spec: string): Buffer | null {
  const result = localGit(cwd, ["cat-file", "blob", spec]);
  return result.status === 0 ? result.stdout : null;
}

function field(row: Row, key: string): string {
  return asText(row[key]);
}

const REGISTERED_GENERATION = "43e817985b91695b8db47511aa7fb8d6dc98436157c3c600fe89e8b2c836417f";
const TOOL_PATH = "scripts/lib/d13-compare.mjs";
const RETAINED_PREFIX = "tests/fixtures/e6-v1-port/";
const RUN_PREFIX = `${RETAINED_PREFIX}d13/`;
const DRIVER_DIRS = ["04-validate-handoff/autobahn", "02-govern-plan/northstar", "scripts/lib"];
const COMMIT_KEYS = ["capture_commit", "merge_commit", "publication_commit", "pr_head", "tool_blob"];
const DIGEST_KEYS = ["generation", "report_sha256", "run_sha256", "spec_sha256", "tool_sha256"];
const IDENTITY_KEYS = ["goal_id", "plan_id", "target_ref", "tool_path", "run_directory", "repository", "host_locator", "branch", "base_target"];
const COMPLETION_KEYS = ["repository", "host_locator", "plan_id", "generation", "goal_id", "branch", "base_target", "pr_head", "merge_commit", "publication_commit"];

function safeRelative(path: string): boolean {
  return path !== "" && !isAbsolute(path) && !path.includes("\\") && [...path].every((char) => char.charCodeAt(0) >= 32) && path.split("/").every((part) => part !== "" && part !== "." && part !== "..");
}

function utcValid(value: string): boolean {
  if (!/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{3})?Z$/.test(value)) return false;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) && new Date(parsed).toISOString() === (value.includes(".") ? value : value.replace("Z", ".000Z"));
}

function retainedPath(cwd: string, path: string, prefix: string): string {
  if (!safeRelative(path) || !path.startsWith(prefix)) throw new Malformed(`retained_path_out_of_scope:${path}`);
  let current = realpathSync(cwd);
  for (const part of path.split("/")) {
    current = join(current, part);
    if (lstatSync(current).isSymbolicLink()) throw new Malformed(`retained_symlink:${path}`);
  }
  if (realpathSync(current) !== current) throw new Malformed(`retained_not_physical:${path}`);
  return current;
}

function requireRecord(value: Json | undefined, label: string): Row {
  const row = asRow(value);
  if (row === null) throw new Malformed(label);
  return row;
}

function completionShape(record: Row): boolean {
  const tool = asRow(record.tool) || {};
  const numbersOk = typeof record.pr_number === "number" && Number.isSafeInteger(record.pr_number) && record.pr_number > 0;
  const sourceOk = ["observed_at", "collected_by", "source_locator"].every((key) => field(record, key) !== "");
  const commitsOk = ["pr_head", "merge_commit", "publication_commit"].every((key) => HEX40.test(field(record, key)));
  const toolOk = HEX40.test(field(tool, "blob")) && HEX64.test(field(tool, "sha256")) && field(tool, "path") !== "";
  return [COMPLETION_KEYS.every((key) => field(record, key) !== ""), numbersOk, sourceOk, utcValid(field(record, "observed_at")), commitsOk, toolOk, HEX64.test(field(record, "generation"))].every(Boolean);
}

function validateContract(contract: Row): void {
  const commitsOk = COMMIT_KEYS.every((key) => HEX40.test(field(contract, key)));
  const digestsOk = DIGEST_KEYS.every((key) => HEX64.test(field(contract, key)));
  const stringsOk = IDENTITY_KEYS.every((key) => field(contract, key) !== "");
  if (![commitsOk, digestsOk, stringsOk, asRow(contract.report) !== null].every(Boolean)) throw new Malformed("d13_contract_shape");
  if (!Number.isSafeInteger(contract.pr_number) || Number(contract.pr_number) <= 0) throw new Malformed("d13_contract_pr_number");
  const completion = requireRecord(contract.completion_record, "completion_record_missing");
  if (!completionShape(completion)) throw new Malformed("completion_record_shape");
  const receipts = requireRecord(contract.receipts, "receipts_missing");
  for (const name of ["collection", "custody", "completion"]) {
    const receipt = requireRecord(receipts[name], `receipt_missing:${name}`);
    if (field(receipt, "path") === "" || !HEX64.test(field(receipt, "sha256"))) throw new Malformed(`receipt_shape:${name}`);
  }
}

function retainBindings(cwd: string, contract: Row, failures: ConsumerFailures): void {
  const receipts = requireRecord(contract.receipts, "receipts_missing");
  for (const name of ["collection", "custody", "completion"]) {
    const receipt = requireRecord(receipts[name], "receipt_missing");
    const path = retainedPath(cwd, field(receipt, "path"), RETAINED_PREFIX);
    const bytes = readFileSync(path);
    if (bytes.length === 0) throw new Malformed(`empty_receipt:${name}`);
    failures.facts[`receipt_${name}_sha256`] = sha256Hex(bytes);
    if (sha256Hex(bytes) !== field(receipt, "sha256")) failures.failed.push("retained-receipts-bound");
    if (name === "completion" && !completionReceiptMatches(bytes, contract)) failures.failed.push("dependency-completion");
  }
}

function completionReceiptMatches(bytes: Buffer, contract: Row): boolean {
  const retained = asRow(parseJson(bytes));
  if (retained === null || !completionShape(retained)) throw new Malformed("retained_completion_malformed");
  return canonical(retained) === canonical(contract.completion_record || null);
}

function registrationAt(cwd: string, revision: string): Row | null {
  const bytes = gitBlob(cwd, `${revision}:${CONTRACT.registry_path}`);
  const registry = bytes === null ? null : asRow(parseJson(bytes));
  if (registry === null) {
    return null;
  }
  const matches = asList(registry.plans).map((entry) => asRow(entry)).filter((plan) => plan !== null && (field(plan, "plan_id") === CONTRACT.plan_id || field(plan, "id") === `northstar-plan-${CONTRACT.plan_id}`));
  return matches.length === 1 ? matches[0] || null : null;
}

function objectExists(cwd: string, revision: string): boolean {
  return gitOut(cwd, ["cat-file", "-t", revision]) === "commit";
}

function isAncestor(cwd: string, ancestor: string, descendant: string): boolean {
  return localGit(cwd, ["merge-base", "--is-ancestor", ancestor, descendant]).status === 0;
}

// Match the existing generation/2 canonical digest (Python JSON uses ASCII
// escapes and no LF). Report canonicalization deliberately remains separate.
function identityDigest(value: Json): string {
  const encoded = JSON.stringify(sortDeep(value)).replace(/[\u007f-\uffff]/g, (char) => `\\u${char.charCodeAt(0).toString(16).padStart(4, "0")}`);
  return sha256Hex(Buffer.from(encoded, "utf8"));
}

interface FrozenRegistration { entry: Row; identity: string; policy: Row; }

function validArtifact(cwd: string, revision: string, prefix: string, name: string, artifact: Row, failures: ConsumerFailures): Buffer | null {
  const path = field(artifact, "path");
  const bytes = safeRelative(path) && path.startsWith(prefix) ? gitBlob(cwd, `${revision}:${path}`) : null;
  if (bytes === null) { failures.failed.push("dependency-generation"); return null; }
  const needsDigest = name !== "sidecar" || artifact.sha256 !== undefined;
  if (needsDigest && sha256Hex(bytes) !== field(artifact, "sha256")) failures.failed.push("dependency-generation");
  const names: Record<string, string> = { bundle: "goals.json", graph: "graph.json", handoff: "handoff.md", sidecar: "sidecar.json" };
  if (names[name] !== undefined && path !== `${prefix}${names[name]}`) failures.failed.push("dependency-generation");
  return bytes;
}

function artifactBytes(cwd: string, revision: string, entry: Row, failures: ConsumerFailures): Map<string, Buffer> {
  const artifacts = asRow(entry.artifacts) || {};
  const prefix = `.ai/handoff/readiness-v2/${CONTRACT.plan_id}/${field(entry, "generation")}/`;
  const result = new Map<string, Buffer>();
  for (const [name, value] of Object.entries(artifacts)) {
    const artifact = asRow(value) || {};
    const bytes = validArtifact(cwd, revision, prefix, name, artifact, failures);
    if (bytes !== null) result.set(name, bytes);
  }
  for (const name of ["bundle", "graph", "handoff", "sidecar"]) if (!result.has(name)) failures.failed.push("dependency-generation");
  return result;
}

function bundleIdentity(bytes: Buffer | undefined): Row | null {
  if (bytes === undefined) return null;
  const bundle = asRow(parseJson(bytes));
  if (bundle === null || bundle.schema !== "handoff-goals/2" || bundle.id !== CONTRACT.plan_id) return null;
  if (!bundleRepositoryOk(bundle)) return null;
  const goals = asList(bundle.goals);
  return goals.length === 1 && asRow(goals[0])?.id === CONTRACT.goal_id ? bundle : null;
}

function bundleRepositoryOk(bundle: Row): boolean {
  return asRow(bundle.repository)?.id === "skills" && asRow(bundle.spec)?.path === CONTRACT.spec_path;
}

function specBinding(cwd: string, revision: string, entry: Row, contract: Row, failures: ConsumerFailures): string {
  const spec = asRow(entry.spec) || {};
  const bytes = field(spec, "path") === CONTRACT.spec_path ? gitBlob(cwd, `${revision}:${CONTRACT.spec_path}`) : null;
  const digest = bytes === null ? "" : sha256Hex(bytes);
  if (digest !== CONTRACT.spec_sha256_lineage || digest !== field(spec, "sha256") || digest !== field(contract, "spec_sha256")) failures.failed.push("dependency-spec");
  return digest;
}

function generationBinding(cwd: string, publication: string, entry: Row, bundle: Row | null, specSha: string, contract: Row, failures: ConsumerFailures): Row {
  const policyBytes = gitBlob(cwd, `${publication}:${CONTRACT.policy_path}`);
  const policy = policyBytes === null ? {} : asRow(parseJson(policyBytes)) || {};
  const policySha = policyBytes === null ? "" : sha256Hex(policyBytes);
  const anchor = asText(asRow(policy.approval)?.anchor_sha256);
  const generation = bundle === null ? "" : identityDigest({ schema: "generation/2", bundle_sha256: identityDigest(bundle), spec_sha256: specSha, policy_sha256: policySha, anchor_sha256: anchor });
  const policyOk = frozenPolicyOk(policy, policySha, anchor, entry);
  if (![policyOk, generation === REGISTERED_GENERATION, generation === entry.generation, generation === contract.generation].every(Boolean)) failures.failed.push("dependency-generation");
  failures.facts.recomputed_generation = generation;
  return policy;
}

function frozenPolicyOk(policy: Row, digest: string, anchor: string, entry: Row): boolean {
  return digest === entry.policy_sha256 && anchor === entry.anchor_sha256 && HEX64.test(anchor) && asRow(policy.repository)?.id === "skills";
}

function registrationIdOk(entry: Row): boolean {
  return entry.id === `northstar-plan-${CONTRACT.plan_id}` && entry.plan_id === CONTRACT.plan_id && entry.schema === "readiness-contract/2" && entry.mode === "live";
}

function sidecarOk(bytes: Buffer | undefined): boolean {
  if (bytes === undefined) return false;
  const sidecar = asRow(parseJson(bytes));
  if (sidecar === null) return false;
  return sidecar.schema === "readiness-sidecar/1" && sidecar.plan_id === CONTRACT.plan_id && asRow(sidecar.goals)?.[CONTRACT.goal_id] !== undefined;
}

function generatedArtifactsOk(files: Map<string, Buffer>, bundle: Row | null, entry: Row): boolean {
  if (bundle === null) return false;
  const generation = field(entry, "generation");
  const prefix = `.ai/handoff/readiness-v2/${CONTRACT.plan_id}/${generation}`;
  const graph = expectedGraph(bundle, generation, prefix);
  const actual = parseJson(files.get("graph") || Buffer.alloc(0));
  const handoff = `# Northstar handoff (readiness-contract/2): ${CONTRACT.plan_id}\n\nGeneration: ${generation}\n\nGoals: ${CONTRACT.goal_id}\n\nPublication grants no authority. Admission requires one verified plan approval carried by tag approval/${CONTRACT.plan_id}/${generation.slice(0, 12)}.\n`;
  const actualHandoff = files.get("handoff") || Buffer.alloc(0);
  return canonical(actual) === canonical(graph) && actualHandoff.equals(Buffer.from(handoff)) && entry.handoff_path === `${prefix}/handoff.md`;
}

function expectedGraph(bundle: Row, generation: string, prefix: string): Row {
  const goal = asRow(asList(bundle.goals)[0]) || {};
  const parent = `handoff:skills:${CONTRACT.plan_id}:${generation}`;
  const node = `plan:skills:${CONTRACT.plan_id}:${CONTRACT.goal_id}:${generation}`;
  const goalRevision = identityDigest({ schema: "goal-revision/2", repository: "skills", id: CONTRACT.goal_id, scope: goal.scope || [], acceptance_criteria: goal.acceptance_criteria || [], dependencies: asList(goal.dependencies).sort(), verification: goal.verification || [] });
  return { schema_version: "1.1", contract: "readiness-contract/2", generation, plan_id: CONTRACT.plan_id, goal_ids: [CONTRACT.goal_id], nodes: [{ id: parent, type: "handoff", repo_id: "skills", path: `${prefix}/handoff.md` }, { id: node, type: "plan", repo_id: "skills", path: `${prefix}/goals.json`, goal_revision: goalRevision }], edges: [{ source: parent, target: node, type: "plans" }] };
}

function frozenRegistration(cwd: string, revision: string, publication: string, contract: Row, failures: ConsumerFailures): FrozenRegistration | null {
  const entry = registrationAt(cwd, revision);
  if (entry === null) { failures.failed.push("dependency-registry"); return null; }
  if (!registrationIdOk(entry)) failures.failed.push("dependency-registry");
  const files = artifactBytes(cwd, revision, entry, failures);
  const bundle = bundleIdentity(files.get("bundle"));
  const specSha = specBinding(cwd, revision, entry, contract, failures);
  const policy = generationBinding(cwd, publication, entry, bundle, specSha, contract, failures);
  if (!sidecarOk(files.get("sidecar"))) failures.failed.push("dependency-generation");
  if (!generatedArtifactsOk(files, bundle, entry)) failures.failed.push("dependency-generation");
  const digests: Row = Object.fromEntries([...files].map(([name, bytes]) => [name, sha256Hex(bytes)]));
  failures.facts.registry_spec_sha256 = specSha;
  return { entry, identity: canonical({ entry, digests }), policy };
}

function consumerRegistration(cwd: string, contract: Row, head: string, target: string, failures: ConsumerFailures): Row {
  const publication = field(contract, "publication_commit");
  const published = frozenRegistration(cwd, publication, publication, contract, failures);
  const registered = frozenRegistration(cwd, target, publication, contract, failures);
  const consumed = frozenRegistration(cwd, head, publication, contract, failures);
  if (published === null) { failures.failed.push("dependency-generation", "consumer-head-binding"); return {}; }
  if (registered?.identity !== published.identity) failures.failed.push("dependency-generation");
  if (consumed?.identity !== published.identity) failures.failed.push("consumer-head-binding");
  captureRegistration(cwd, contract, published.identity, failures);
  failures.facts.registry_generation = asText(registered?.entry.generation);
  failures.facts.registration_identity_sha256 = registered === null ? "" : sha256Hex(Buffer.from(registered.identity));
  return published.policy;
}

function captureRegistration(cwd: string, contract: Row, identity: string, failures: ConsumerFailures): void {
  for (const revision of [field(contract, "capture_commit"), field(contract, "merge_commit")]) {
    const captured = frozenRegistration(cwd, revision, field(contract, "publication_commit"), contract, failures);
    if (captured?.identity !== identity) failures.failed.push("consumer-head-binding");
  }
}

function branchMatches(policy: Row, branch: string): boolean {
  const pattern = field(policy, "branch_pattern");
  if (!/^\^[A-Za-z0-9/_()|<>-]+\$$/.test(pattern)) return false;
  const filled = pattern.replace("<plan_id>", CONTRACT.plan_id).replace("<goal_id>", CONTRACT.goal_id);
  try { return new RegExp(filled).test(branch); } catch { return false; }
}

function completionMatches(completion: Row, contract: Row, policy: Row): boolean {
  const tool = asRow(completion.tool) || {};
  const identityOk = COMPLETION_KEYS.every((key) => completion[key] === contract[key]) && completion.pr_number === contract.pr_number;
  const exact = contract.repository === "skills" && contract.plan_id === CONTRACT.plan_id && contract.goal_id === CONTRACT.goal_id && contract.base_target === policy.target;
  const toolOk = tool.path === TOOL_PATH && tool.blob === contract.tool_blob && tool.sha256 === contract.tool_sha256;
  return [identityOk, exact, toolOk, branchMatches(policy, field(contract, "branch"))].every(Boolean);
}

function commitParents(cwd: string, revision: string): string[] {
  return gitOut(cwd, ["cat-file", "-p", revision]).split("\n").filter((line) => line.startsWith("parent ")).map((line) => line.slice(7));
}

function lineageHistoryOk(cwd: string, contract: Row, head: string, target: string, failures: ConsumerFailures): boolean {
  const merge = field(contract, "merge_commit");
  const publication = field(contract, "publication_commit");
  const capture = field(contract, "capture_commit");
  const prHead = field(contract, "pr_head");
  if (![head, target, merge, publication, capture, prHead].every((revision) => objectExists(cwd, revision)) || gitOut(cwd, ["rev-parse", "--is-shallow-repository"]) !== "false") {
    failures.failed.push("dependency-history-unavailable"); return false;
  }
  if (publication === merge || !isAncestor(cwd, publication, merge) || !isAncestor(cwd, merge, target)) failures.failed.push("dependency-ancestry");
  mergeCompletionBinding(cwd, contract, failures);
  if (!isAncestor(cwd, merge, head) || !isAncestor(cwd, merge, capture) || !isAncestor(cwd, capture, head)) failures.failed.push("consumer-head-binding");
  return true;
}

function mergeCompletionBinding(cwd: string, contract: Row, failures: ConsumerFailures): void {
  const parents = commitParents(cwd, field(contract, "merge_commit"));
  const prHead = field(contract, "pr_head");
  const valid = parents.length === 2 && parents[1] === prHead && prHead !== contract.capture_commit && isAncestor(cwd, field(contract, "publication_commit"), prHead);
  if (!valid) failures.failed.push("dependency-completion");
  const completion = asRow(contract.completion_record) || {};
  const observed = Date.parse(field(completion, "observed_at"));
  if (![field(contract, "publication_commit"), field(contract, "merge_commit")].every((revision) => observed >= commitTime(cwd, revision))) failures.failed.push("dependency-completion");
}

function commitTime(cwd: string, revision: string): number {
  const header = gitOut(cwd, ["cat-file", "-p", revision]).split("\n\n")[0] || "";
  const match = /^committer .* (\d+) [+-]\d{4}$/m.exec(header);
  return match === null ? Number.POSITIVE_INFINITY : Number(match[1]) * 1000;
}

function toolBinding(cwd: string, contract: Row, head: string, failures: ConsumerFailures): void {
  const merge = field(contract, "merge_commit");
  const merged = gitBlob(cwd, `${merge}:${TOOL_PATH}`);
  const committed = gitBlob(cwd, `${head}:${TOOL_PATH}`);
  const digest = merged === null ? "" : sha256Hex(merged);
  const blob = gitOut(cwd, ["rev-parse", `${merge}:${TOOL_PATH}`]);
  failures.facts.merge_tool_sha256 = digest;
  failures.facts.merge_tool_blob = blob;
  if (contract.tool_path !== TOOL_PATH || digest !== contract.tool_sha256 || digest !== toolDigest() || blob !== contract.tool_blob) failures.failed.push("dependency-tool");
  if (committed === null || sha256Hex(committed) !== toolDigest()) failures.failed.push("consumer-head-binding");
}

function inventoryTree(cwd: string, revision: string, path: string, inventory: Row): boolean {
  const listing = gitOut(cwd, ["cat-file", "-p", `${revision}:${path}`]);
  if (listing === "") return false;
  return listing.split("\n").every((line) => inventoryEntry(cwd, revision, path, line, inventory));
}

function inventoryEntry(cwd: string, revision: string, path: string, line: string, inventory: Row): boolean {
  const match = /^(\d{6}) (blob|tree) ([0-9a-f]{40})\t([^/]+)$/.exec(line);
  if (match === null) return false;
  const name = match[4] || "";
  if (!safeRelative(name)) return false;
  const child = `${path}/${name}`;
  if (match[2] === "tree") return inventoryTree(cwd, revision, child, inventory);
  if (!["100644", "100755"].includes(match[1] || "")) return false;
  const bytes = gitBlob(cwd, match[3] || "");
  if (bytes === null) return false;
  inventory[child] = { mode: match[1] || "", sha256: sha256Hex(bytes) };
  return true;
}

function driverInventory(cwd: string, revision: string): Row | null {
  const inventory: Row = {};
  return DRIVER_DIRS.every((path) => inventoryTree(cwd, revision, path, inventory)) ? inventory : null;
}

function captureBinding(cwd: string, contract: Row, head: string, report: Row, failures: ConsumerFailures): void {
  const capture = field(contract, "capture_commit");
  const recorded = asRow(asRow(report.lanes)?.candidate);
  const captured = driverInventory(cwd, capture);
  const current = driverInventory(cwd, head);
  failures.facts.capture_driver_artifacts = captured;
  failures.facts.head_driver_artifacts = current;
  const merged = gitBlob(cwd, `${field(contract, "merge_commit")}:${TOOL_PATH}`);
  const checker = gitBlob(cwd, `${capture}:${TOOL_PATH}`);
  const toolOk = merged !== null && checker !== null && checker.equals(merged);
  const inputsOk = captured !== null && current !== null && canonical(captured) === canonical(current);
  if (recorded?.driver_commit !== capture || !toolOk || !inputsOk) failures.failed.push("consumer-head-binding");
}

function consumerLineage(cwd: string, contract: Row, head: string, target: string, report: Row, failures: ConsumerFailures): void {
  if (!lineageHistoryOk(cwd, contract, head, target, failures)) return;
  const policy = consumerRegistration(cwd, contract, head, target, failures);
  toolBinding(cwd, contract, head, failures);
  captureBinding(cwd, contract, head, report, failures);
  if (!completionMatches(asRow(contract.completion_record) || {}, contract, policy)) failures.failed.push("dependency-completion");
}

function reportConsistency(report: Row, contract: Row, failures: ConsumerFailures): void {
  const digest = sha256Hex(Buffer.from(canonical(report), "utf8"));
  const embedded = asRow(contract.report);
  const embeddedDigest = embedded === null ? "" : sha256Hex(Buffer.from(canonical(embedded), "utf8"));
  failures.facts.recomputed_report_sha256 = digest;
  failures.facts.embedded_report_sha256 = field(contract, "report_sha256");
  if (embedded === null || embeddedDigest !== digest || digest !== field(contract, "report_sha256")) {
    failures.failed.push("report-consistency");
  }
}

function recompute(cwd: string, contract: Row, failures: ConsumerFailures): Row {
  const runDirectory = field(contract, "run_directory");
  if (!runDirectory.startsWith(RUN_PREFIX) || runDirectory.slice(RUN_PREFIX.length).split("/").length !== 1) throw new Malformed("run_directory_scope");
  const path = retainedPath(cwd, runDirectory, RUN_PREFIX);
  const manifest = readFileSync(retainedPath(cwd, `${runDirectory}/raw-manifest.json`, RUN_PREFIX));
  failures.facts.raw_manifest_sha256 = sha256Hex(manifest);
  if (sha256Hex(manifest) !== contract.run_sha256) failures.failed.push("raw-inputs-bound");
  const outcome = evaluateRun(path, false);
  const report = outcome.report;
  const observed = asRow(report.observed);
  failures.facts.recomputed_verdict = asText(report.verdict);
  failures.facts.recomputed_observed_git = observed?.git === true;
  if (outcome.exit === 2) failures.malformed = true;
  if (asList(report.assertions).some(rawBindingFailed)) failures.failed.push("raw-inputs-bound");
  if (![outcome.exit === 0, report.verdict === "pass", observed?.git === true].every(Boolean)) {
    failures.failed.push("raw-report-recomputation");
  }
  reportConsistency(report, contract, failures);
  return report;
}

function rawBindingFailed(assertion: Json): boolean {
  const row = asRow(assertion) || {};
  return row.id === "raw-inputs-bound" && row.ok === false;
}

function evidenceContract(cwd: string, evidencePath: string, failures: ConsumerFailures): Row | null {
  let bytes: Buffer;
  try {
    const label = isAbsolute(evidencePath) ? relative(realpathSync(cwd), evidencePath) : evidencePath;
    if (!CONTRACT.consumers.includes(label)) throw new Malformed("evidence_path_scope");
    bytes = readFileSync(retainedPath(cwd, label, ".ai/evidence/"));
  } catch {
    failures.failed.push("input-shape");
    failures.facts.detail = "evidence missing";
    failures.malformed = true;
    return null;
  }
  const contract = asRow(asRow(parseJson(bytes))?.d13_contract);
  if (contract === null) {
    failures.failed.push("input-shape");
    failures.facts.detail = "d13_contract missing or malformed";
    failures.malformed = true;
    return null;
  }
  validateContract(contract);
  return contract;
}

function consumerPins(cwd: string, targetRef: string): Row {
  return { head: gitOut(cwd, ["rev-parse", "HEAD"]), target: gitOut(cwd, ["rev-parse", "--verify", `${targetRef}^{commit}`]), root: gitOut(cwd, ["rev-parse", "--show-toplevel"]), common_dir: gitOut(cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]) };
}

function checkConsumer(cwd: string, evidencePath: string, failures: ConsumerFailures): void {
  const contract = evidenceContract(cwd, evidencePath, failures);
  if (contract === null) return;
  if (contract.target_ref !== "refs/remotes/origin/main") { failures.failed.push("dependency-ancestry"); return; }
  const pins = consumerPins(cwd, field(contract, "target_ref"));
  Object.assign(failures.facts, pins);
  if (!HEX40.test(field(pins, "head")) || !HEX40.test(field(pins, "target"))) { failures.failed.push("dependency-history-unavailable"); return; }
  retainBindings(cwd, contract, failures);
  const report = recompute(cwd, contract, failures);
  const recomputed = failures.failed.length === 0;
  consumerLineage(cwd, contract, field(pins, "head"), field(pins, "target"), report, failures);
  const finish = consumerPins(cwd, field(contract, "target_ref"));
  failures.facts.finish = finish;
  if (canonical(pins) !== canonical(finish) || pins.root !== realpathSync(cwd)) failures.failed.push("consumer-head-binding");
  failures.facts.recomputation = recomputed ? "pass" : "red";
  failures.facts.local_lineage = failures.failed.length === 0 ? "pass" : "red";
  failures.facts.registered_generation = field(contract, "generation");
}

function consumerResult(cwd: string, evidencePath: string): { exit: number; report: Row } {
  const failures: ConsumerFailures = { failed: [], facts: {}, malformed: false };
  const emit = (): { exit: number; report: Row } => {
    const failed = [...new Set(failures.failed)].sort();
    return {
      exit: failures.malformed || failed.includes("input-shape") ? 2 : failed.length > 0 ? 1 : 0,
      report: {
        capture_authenticity: "unverified",
        consumer_readiness: "unready",
        failed,
        facts: failures.facts,
        fresh_git: false,
        live_remote_freshness: "unverified",
        schema: CONSUMER_SCHEMA,
      },
    };
  };
  try { checkConsumer(cwd, evidencePath, failures); } catch (error) {
    failures.failed.push("input-shape"); failures.malformed = true;
    failures.facts.detail = error instanceof Error ? error.message : "missing_or_malformed_input";
  }
  return emit();
}

// ---------- command line ----------

function usage(): number {
  process.stderr.write(
    "usage: d13-compare.mjs <run-directory> [--observe]\n       d13-compare.mjs --contract\n       d13-compare.mjs --consumer-check <evidence.json>\n",
  );
  return 2;
}

export function main(argv: ReadonlyArray<string>): number {
  assertNodeVersion();
  if (argv.length === 1 && argv[0] === "--contract") {
    process.stdout.write(canonical(contractJson()));
    return 0;
  }
  if (argv.length === 2 && argv[0] === "--consumer-check") {
    const outcome = consumerResult(process.cwd(), argv[1] || "");
    process.stdout.write(canonical(outcome.report));
    return outcome.exit;
  }
  const positional = argv.filter((argument) => argument !== "--observe");
  if (positional.length !== 1) {
    return usage();
  }
  let outcome: { exit: number; report: Row };
  try {
    outcome = evaluateRun(resolve(process.cwd(), positional[0] || ""), argv.includes("--observe"));
  } catch {
    return usage();
  }
  process.stdout.write(canonical(outcome.report));
  return outcome.exit;
}

if (invokedDirectly(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
