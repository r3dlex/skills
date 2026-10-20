import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { join, resolve, sep } from "node:path";
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

// ---------- canonical JSON and digests ----------

function sortDeep(value: Json): Json {
  if (Array.isArray(value)) {
    return value.map(sortDeep);
  }
  if (value !== null && typeof value === "object") {
    const out: Row = {};
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
    return JSON.parse(bytes.toString("utf8")) as Json;
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
  const leading = source.slice(member.lineStart, member.keyStart);
  const trailing = source.slice(member.tokenEnd, member.lineEnd);
  return /^[ ]*$/.test(leading) && trailing === "," + "\n";
}

function provenanceProjection(source: string, bytes: Buffer, members: Member[]): Envelope {
  const found = members.filter((member) => member.key === "provenance");
  if (found.length === 0) {
    return invalidEnvelope(bytes, "provenance-expected");
  }
  if (found.length > 1) {
    return invalidEnvelope(bytes, "projection-unique");
  }
  const member = found[0];
  if (member === undefined || member.token === null || !PROVENANCE_VALUES.includes(member.value)) {
    return invalidEnvelope(bytes, "provenance-expected");
  }
  if (!exactSpan(source, member)) {
    return invalidEnvelope(bytes, "projection-unique");
  }
  const projected = `${source.slice(0, member.lineStart)}${source.slice(member.lineEnd)}`;
  return {
    failure: "",
    kind: "projected",
    projection: Buffer.from(projected, "utf8"),
    provenance: member.value,
    schema: stringMember(members, "schema"),
  };
}

function classifyStdout(bytes: Buffer): Envelope {
  const source = bytes.toString("utf8");
  const members = membersOrNull(source);
  if (members === null) {
    return invalidEnvelope(bytes, "envelope-schema");
  }
  const schema = stringMember(members, "schema");
  if (schema === CONTRACT.refusal_schema) {
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
  if (fields.sha256 === "" || fields.path === "" || listed.has(fields.path)) {
    throw new Malformed("raw_manifest_row");
  }
  if (actual === undefined || actual.length !== Number(fields.bytes) || sha256Hex(actual) !== fields.sha256) {
    throw new Malformed(`raw_manifest_mismatch:${fields.path}`);
  }
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
  const inputs: Row = {};
  const listed = new Set<string>();
  for (const row of manifestRows(manifestBytes)) {
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
  if (row === null || !filled({ ...info }) || !HEX40.test(info.driver_commit)) {
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
  return filled({ ...target }) && HEX40.test(target.revision) ? target : null;
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
  if (typeof exit !== "number" || !Number.isInteger(exit)) {
    return false;
  }
  if (typeof sequence !== "number" || !Number.isInteger(sequence) || sequence <= 0) {
    return false;
  }
  const strings = ["cwd", "driver_commit", "started_at", "finished_at"];
  return strings.every((key) => asText(row[key]) !== "");
}

function readCaptureMeta(run: RawRun, base: string): CaptureMeta {
  const row = asRow(readJsonInput(run, `${base}/meta.json`));
  if (!metaShapeOk(row)) {
    throw new Malformed(`capture_meta:${base}`);
  }
  return row as unknown as CaptureMeta;
}

function writtenNamesFor(run: RawRun, base: string, phase: string): string[] {
  const map = asRow(readJsonInput(run, `${base}/meta.json`));
  if (map === null) {
    return [];
  }
  const meta = map as unknown as CaptureMeta;
  const source = phase === "before" ? meta.written_before : meta.written;
  const entry = asRow(source);
  return entry === null ? [] : Object.keys(entry).sort();
}

function readCapture(run: RawRun, lane: string, repository: string, plan: string, operation: string): Capture | null {
  const base = `captures/${lane}/${repository}/${plan}/${operation}`;
  if (!run.files.has(`${base}/meta.json`)) {
    return null;
  }
  const meta = readCaptureMeta(run, base);
  const after = new Map<string, string>();
  for (const name of writtenNamesFor(run, base, "after")) {
    after.set(name, sha256Hex(readBytes(run, `${base}/written-after/${name}`)));
  }
  const before = new Map<string, string>();
  for (const name of writtenNamesFor(run, base, "before")) {
    before.set(name, sha256Hex(readBytes(run, `${base}/written-before/${name}`)));
  }
  const stdout = readBytes(run, `${base}/stdout`);
  return {
    envelope: classifyStdout(stdout),
    lane,
    meta,
    operation,
    plan_id: plan,
    repository,
    stderr: readBytes(run, `${base}/stderr`),
    stdout,
    written_after_files: Object.fromEntries(after),
    written_before_files: Object.fromEntries(before),
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
        sites.push({ captures, operation, plan_id: plan.plan_id, repository: target.repository });
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

function commandKey(phase: string, subject: string, argv: ReadonlyArray<string>): string {
  return `${phase}|${subject}|${argv.join(" ")}`;
}

function parseCommand(row: Json): RecordedCommand | null {
  const entry = asRow(row);
  const argv = asList(entry?.argv);
  const phase = asText(entry?.phase);
  const subject = asText(entry?.subject);
  if (entry === null || argv.length === 0 || phase === "" || subject === "" || typeof entry.exit !== "number") {
    return null;
  }
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
  if (value === null || value.schema !== OBSERVATION_SCHEMA || typeof value.lanes_sha256 !== "string") {
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
  return bytes === null ? "" : bytes.toString("utf8").trim();
}

function reader(commands: Commands, subject: string, problems: string[]): (phase: string, argv: ReadonlyArray<string>) => string {
  return (phase, argv) => {
    const value = stdoutOf(commands, phase, subject, ["git", ...argv]);
    if (stdoutBytes(commands, phase, subject, ["git", ...argv]) === null) {
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
  return bytes === null ? "" : sha256Hex(bytes);
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
  return found;
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
    policy_blob: read("start", ["rev-parse", `${target.ref}:${CONTRACT.policy_path}`]),
    policy_sha256: "",
    problems,
    ref_finish: read("finish", ["rev-parse", "--verify", `${target.ref}^{commit}`]),
    ref_start: read("start", ["rev-parse", "--verify", `${target.ref}^{commit}`]),
    registry_blob: read("start", ["rev-parse", `${target.ref}:${CONTRACT.registry_path}`]),
    registry_sha256: "",
    repository: target.repository,
    toplevel_finish: read("finish", ["rev-parse", "--show-toplevel"]),
    toplevel_start: read("start", ["rev-parse", "--show-toplevel"]),
  };
  observed.policy_sha256 = blobDigest(commands, subject, observed.policy_blob);
  observed.registry_sha256 = blobDigest(commands, subject, observed.registry_blob);
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
  if (observed.common_start !== observed.common_finish || observed.head_start !== observed.head_finish) {
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
  keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.ref}:${CONTRACT.policy_path}`]));
  keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.ref}:${CONTRACT.registry_path}`]));
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
  return [...new Set(keys)].sort();
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

function liveMismatch(commands: Commands, keys: ReadonlyArray<string>, problems: string[]): void {
  for (const key of keys) {
    const command = commands.get(key);
    if (command === undefined) {
      continue;
    }
    const result = run(command.argv[0] || "git", command.argv.slice(1), command.cwd);
    const expected = Buffer.from(command.stdout, "base64").toString("utf8");
    if (result.status !== command.exit || text(result.stdout) !== expected) {
      problems.push(`live_mismatch:${key}`);
    }
  }
}

function laneMetadataProblems(lanes: Lanes, rows: Map<string, LaneObserved>): string[] {
  const problems: string[] = [];
  for (const lane of LANES) {
    const observed = rows.get(lane);
    const info = laneOf(lanes, lane);
    if (observed === undefined || observed.common_start !== info.common_dir || observed.head_start !== info.driver_commit) {
      problems.push(`lane_metadata:${lane}`);
    }
  }
  return problems;
}

function targetFacts(lanes: Lanes, targets: Map<string, TargetObserved>): Json[] {
  return lanes.targets.map((target) => {
    const observed = targets.get(target.repository);
    return {
      common_dir_finish: asText(observed?.common_finish),
      common_dir_start: asText(observed?.common_start),
      policy_blob: asText(observed?.policy_blob),
      policy_sha256: asText(observed?.policy_sha256),
      ref_finish: asText(observed?.ref_finish),
      ref_start: asText(observed?.ref_start),
      registry_blob: asText(observed?.registry_blob),
      registry_sha256: asText(observed?.registry_sha256),
      repository: target.repository,
      toplevel_start: asText(observed?.toplevel_start),
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
      lane,
      toplevel_start: asText(observed?.toplevel_start),
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
  problems.push(...commandSetProblems(commands, keys));
  problems.push(...laneMetadataProblems(lanes, laneRows));
  if (observe) {
    liveMismatch(commands, keys, problems);
  }
  return {
    facts: [...targetFacts(lanes, targets), ...laneFacts(laneRows)],
    git: problems.length === 0,
    lanes: laneRows,
    problems,
    targets,
  };
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
  const envelope = capture.envelope;
  if (envelope.kind === "refusal") {
    return field === "code" ? [envelope.code] : [];
  }
  if (envelope.kind !== "projected" || field !== "findings") {
    return [];
  }
  return asList(asRow(parseJson(envelope.projection))?.findings)
    .map((entry) => asText(asRow(entry)?.code))
    .sort();
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
    JSON.stringify(asRow(capture.meta.written) || {}) === JSON.stringify(capture.written_after_files) &&
    JSON.stringify(asRow(capture.meta.written_before) || {}) === JSON.stringify(capture.written_before_files)
  );
}

function writtenEqual(reference: Capture, candidate: Capture): boolean {
  return (
    JSON.stringify(reference.meta.written) === JSON.stringify(candidate.meta.written) &&
    JSON.stringify(reference.meta.written_before) === JSON.stringify(candidate.meta.written_before) &&
    JSON.stringify(reference.written_after_files) === JSON.stringify(candidate.written_after_files) &&
    JSON.stringify(reference.written_before_files) === JSON.stringify(candidate.written_before_files)
  );
}

function logQuiescent(reference: Capture, candidate: Capture): boolean {
  const stable = (capture: Capture): boolean => JSON.stringify(capture.meta.log_before) === JSON.stringify(capture.meta.log_after);
  return stable(reference) && stable(candidate) && JSON.stringify(reference.meta.log_after) === JSON.stringify(candidate.meta.log_after);
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
    meta_sha256: sha256Hex(Buffer.from(canonical(capture.meta as unknown as Json), "utf8")),
    projection_sha256: projectionDigest(capture),
    stderr_sha256: sha256Hex(capture.stderr),
    stdout_sha256: sha256Hex(capture.stdout),
    written_after_sha256: written("after"),
    written_before_sha256: written("before"),
  };
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
    both.every((capture) => capture.envelope.kind === "refusal" || memberValue(capture, "plan_id") === site.plan_id),
    "envelope plan binds the registry entry",
  );
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

  add(id: string, subject: string, ok: boolean, detail: string): void {
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
    return capture.meta.started_at <= capture.meta.finished_at && (previous === undefined || previous.meta.finished_at <= capture.meta.started_at);
  });
}

function repositoryTimingOk(sites: Site[], repository: string): boolean {
  const audits = captureList(sites.filter((site) => site.repository === repository && site.operation === "audit-merges"));
  const exports = captureList(sites.filter((site) => site.repository === repository && site.operation === "export-evidence"));
  const last = audits.map((capture) => capture.meta.finished_at).sort().pop() || "";
  const first = exports.map((capture) => capture.meta.started_at).sort().shift() || "";
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
    .filter((problem) => problem === "ref_moved" || problem.startsWith("revision_mismatch"));
}

function registryBound(run: RawRun, target: TargetInfo, observed: TargetObserved | undefined): boolean {
  const registry = readRegistry(run, target.repository);
  const recorded = asText(observed?.registry_sha256);
  return registry.present && recorded !== "" && sha256Hex(registry.bytes) === recorded;
}

function targetBoundAssertions(ledger: Ledger, run: RawRun, target: TargetInfo, observed: TargetObserved | undefined): void {
  const moving = refProblems(observed);
  ledger.add("target-repository-bound", target.repository, policyBound(run, target, observed), "policy identity binds the target repository");
  ledger.add("target-ref-bound", target.repository, moving.length === 0, moving.join(" ") || "pinned revision re-observed");
  ledger.add("registry-bound", target.repository, registryBound(run, target, observed), "registry copy equals the blob at the pinned revision");
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
  ledger.add("raw-inputs-bound", "run", captures.every((capture) => writtenMapsMatch(capture)), "written maps recompute from retained snapshot bytes");
  ledger.add("observe-git", "observed", observation.git, observation.problems.join(" ") || "retained observation consistent");
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
  const table: Row = {};
  for (const lane of LANES) {
    const row: Row = {};
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
  return capture.envelope.kind === "refusal" ? capture.envelope.code : "";
}

function siteJson(site: Site, result: SiteResult): Row {
  const reference = site.captures.get("reference");
  const candidate = site.captures.get("candidate");
  return {
    classification: result.classification,
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
  return {
    exit: 2,
    report: {
      assertions: [],
      contract: contractJson(),
      counts: { equal_refusal: 0, equal_success: 0, red: 0, sites: 0 },
      lanes: {},
      observed: { basis: "retained-local-observation", facts: [], git: false, problems: [detail] },
      problems: [{ code: "malformed", detail }],
      run: { directory: dir.split(sep).join("/"), inputs: {}, manifest_sha256: "" },
      schema: CONTRACT.schema,
      sites: [],
      verdict: "malformed",
    },
  };
}

function evaluateRun(dir: string, observe: boolean): { exit: number; report: Row } {
  let run: RawRun;
  let lanes: Lanes;
  try {
    run = readRun(dir);
    lanes = readLanes(run);
    readNormalizations(run);
  } catch (error) {
    return malformedReport(dir, error);
  }
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
      { counts, directory: dir, inputs: run.inputs, lanes, manifestSha: run.manifestSha, observation, results, sites, verdict },
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
  const result = run("git", args, cwd);
  return result.status === 0 ? text(result.stdout).trim() : "";
}

function gitBlob(cwd: string, spec: string): Buffer | null {
  const result = run("git", ["cat-file", "blob", spec], cwd);
  return result.status === 0 ? result.stdout : null;
}

function contained(cwd: string, candidate: string): boolean {
  const base = resolve(cwd);
  const full = resolve(base, candidate);
  return full !== base && full.startsWith(`${base}/`);
}

function field(row: Row, key: string): string {
  return asText(row[key]);
}

const CONTRACT_KEYS = [
  "capture_commit",
  "generation",
  "goal_id",
  "merge_commit",
  "plan_id",
  "publication_commit",
  "report_sha256",
  "run_directory",
  "run_sha256",
  "spec_sha256",
  "target_ref",
  "tool_path",
  "tool_sha256",
];

function contractStrings(contract: Row): boolean {
  return CONTRACT_KEYS.every((key) => typeof contract[key] === "string");
}

function registrationAt(cwd: string, revision: string): Row | null {
  const bytes = gitBlob(cwd, `${revision}:${CONTRACT.registry_path}`);
  const registry = bytes === null ? null : asRow(parseJson(bytes));
  if (registry === null) {
    return null;
  }
  return asList(registry.plans).map((entry) => asRow(entry)).find((plan) => plan !== null && field(plan, "plan_id") === CONTRACT.plan_id) || null;
}

function objectExists(cwd: string, revision: string): boolean {
  return run("git", ["cat-file", "-e", `${revision}^{commit}`], cwd).status === 0;
}

function isAncestor(cwd: string, ancestor: string, descendant: string): boolean {
  return run("git", ["merge-base", "--is-ancestor", ancestor, descendant], cwd).status === 0;
}

function specBinding(cwd: string, entry: Row, contract: Row, failures: ConsumerFailures): void {
  const spec = asRow(entry.spec);
  const path = spec === null ? "" : field(spec, "path");
  const bytes = path === "" ? null : gitBlob(cwd, `${field(contract, "target_ref_commit")}:${path}`);
  const digest = bytes === null ? "" : sha256Hex(bytes);
  failures.facts.registry_spec_sha256 = spec === null ? "" : field(spec, "sha256");
  if (digest === "" || digest !== (spec === null ? "" : field(spec, "sha256")) || digest !== field(contract, "spec_sha256")) {
    failures.failed.push("dependency-spec");
  }
}

function bundleGoalIds(bytes: Buffer | null): string[] {
  return bytes === null ? [] : asList(asRow(parseJson(bytes))?.goals).map((goal) => field(asRow(goal) || {}, "id"));
}

function bundleBinding(cwd: string, entry: Row, contract: Row, revision: string, failures: ConsumerFailures): void {
  const bundle = asRow(asRow(entry.artifacts)?.bundle) || {};
  const path = field(bundle, "path");
  const bytes = path === "" ? null : gitBlob(cwd, `${revision}:${path}`);
  const digest = bytes === null ? "" : sha256Hex(bytes);
  const goalIds = bundleGoalIds(bytes);
  failures.facts.bundle_sha256 = digest;
  const identity = field(entry, "generation") === field(contract, "generation") && HEX64.test(field(contract, "generation"));
  if (!identity || digest !== field(bundle, "sha256") || !goalIds.includes(field(contract, "goal_id"))) {
    failures.failed.push("dependency-generation");
  }
}

function consumerRegistration(cwd: string, contract: Row, revision: string, failures: ConsumerFailures): void {
  const entry = registrationAt(cwd, revision);
  if (entry === null) {
    failures.failed.push("dependency-registry");
    return;
  }
  failures.facts.registry_generation = field(entry, "generation");
  contract.target_ref_commit = revision;
  specBinding(cwd, entry, contract, failures);
  bundleBinding(cwd, entry, contract, revision, failures);
}

function lineageHistoryOk(cwd: string, contract: Row, merge: string, publication: string, capture: string, target: string, failures: ConsumerFailures): boolean {
  const objects = [merge, publication, capture];
  if (!objects.every((revision) => objectExists(cwd, revision))) {
    failures.failed.push("dependency-history-unavailable");
    return false;
  }
  if (gitOut(cwd, ["rev-parse", "--verify", `${target}^{commit}`]) === "") {
    failures.failed.push("dependency-history-unavailable");
    return false;
  }
  if (!isAncestor(cwd, publication, merge) || !isAncestor(cwd, merge, target)) {
    failures.failed.push("dependency-ancestry");
  }
  if (!isAncestor(cwd, merge, capture)) {
    failures.failed.push("consumer-head-binding");
  }
  return true;
}

function toolBinding(cwd: string, contract: Row, merge: string, capture: string, toolPath: string, failures: ConsumerFailures): void {
  const merged = gitBlob(cwd, `${merge}:${toolPath}`);
  const captured = gitBlob(cwd, `${capture}:${toolPath}`);
  const mergedSha = merged === null ? "" : sha256Hex(merged);
  failures.facts.merge_tool_sha256 = mergedSha;
  failures.facts.capture_tool_sha256 = captured === null ? "" : sha256Hex(captured);
  const bound = merged !== null && mergedSha === field(contract, "tool_sha256") && mergedSha === toolDigest() && captured !== null && captured.equals(merged);
  if (!bound) {
    failures.failed.push("dependency-tool");
  }
}

function completionMatches(completion: Row, contract: Row, merge: string, publication: string, capture: string, blob: string): boolean {
  const pairs: ReadonlyArray<[string, string]> = [
    ["merge_commit", merge],
    ["publication_commit", publication],
    ["goal_id", field(contract, "goal_id")],
    ["generation", field(contract, "generation")],
    ["plan_id", field(contract, "plan_id")],
    ["pr_head", capture],
  ];
  const identityOk = pairs.every(([key, value]) => field(completion, key) === value);
  return identityOk && (blob === "" || field(asRow(completion.tool) || {}, "blob") === blob);
}

function consumerLineage(cwd: string, contract: Row, failures: ConsumerFailures): void {
  const merge = field(contract, "merge_commit");
  const publication = field(contract, "publication_commit");
  const target = field(contract, "target_ref");
  const capture = field(contract, "capture_commit");
  const toolPath = field(contract, "tool_path");
  if (!lineageHistoryOk(cwd, contract, merge, publication, capture, target, failures)) {
    return;
  }
  toolBinding(cwd, contract, merge, capture, toolPath, failures);
  const completion = asRow(contract.completion_record);
  const blob = gitOut(cwd, ["rev-parse", `${merge}:${toolPath}`]);
  if (completion === null || !completionMatches(completion, contract, merge, publication, capture, blob)) {
    failures.failed.push("dependency-completion");
  }
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

function recompute(cwd: string, contract: Row, failures: ConsumerFailures): void {
  const runDirectory = field(contract, "run_directory");
  if (!contained(cwd, runDirectory)) {
    failures.failed.push("input-shape");
    failures.malformed = true;
    return;
  }
  const outcome = evaluateRun(resolve(cwd, runDirectory), false);
  const report = outcome.report;
  const observed = asRow(report.observed);
  failures.facts.recomputed_verdict = asText(report.verdict);
  failures.facts.recomputed_observed_git = observed?.git === true;
  if (outcome.exit !== 0 || report.verdict !== "pass" || observed?.git !== true) {
    failures.failed.push("raw-report-recomputation");
  }
  reportConsistency(report, contract, failures);
}

function evidenceContract(cwd: string, evidencePath: string, failures: ConsumerFailures): Row | null {
  let bytes: Buffer;
  try {
    bytes = readFileSync(resolve(cwd, evidencePath));
  } catch {
    failures.failed.push("input-shape");
    failures.facts.detail = "evidence missing";
    failures.malformed = true;
    return null;
  }
  const contract = asRow(asRow(parseJson(bytes))?.d13_contract);
  if (contract === null || !contractStrings(contract)) {
    failures.failed.push("input-shape");
    failures.facts.detail = "d13_contract missing or malformed";
    failures.malformed = true;
    return null;
  }
  return contract;
}

function runManifest(cwd: string, contract: Row): Buffer | null {
  try {
    return readFileSync(resolve(cwd, `${field(contract, "run_directory")}/raw-manifest.json`));
  } catch {
    return null;
  }
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
  const contract = evidenceContract(cwd, evidencePath, failures);
  if (contract === null) {
    return emit();
  }
  const manifest = runManifest(cwd, contract);
  if (manifest === null || sha256Hex(manifest) !== field(contract, "run_sha256")) {
    failures.failed.push("raw-inputs-bound");
    return emit();
  }
  recompute(cwd, contract, failures);
  const head = gitOut(cwd, ["rev-parse", "HEAD"]);
  const target = gitOut(cwd, ["rev-parse", "--verify", `${field(contract, "target_ref")}^{commit}`]);
  failures.facts.head = head;
  failures.facts.target = target;
  if (head === "" || target === "") {
    failures.failed.push("dependency-history-unavailable");
    return emit();
  }
  consumerRegistration(cwd, contract, target, failures);
  consumerLineage(cwd, contract, failures);
  failures.facts.registered_generation = field(contract, "generation");
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