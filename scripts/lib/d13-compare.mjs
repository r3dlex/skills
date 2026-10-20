import { createHash } from "node:crypto";
import { lstatSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { join, resolve, sep } from "node:path";
import { assertNodeVersion } from "./node-version.mjs";
import { invokedDirectly } from "./invoked.mjs";
import { run, text } from "./proc.mjs";
export const CONTRACT = {
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
class Malformed extends Error {
}
// ---------- canonical JSON and digests ----------
function sortDeep(value) {
    if (Array.isArray(value)) {
        return value.map(sortDeep);
    }
    if (value !== null && typeof value === "object") {
        const out = {};
        const source = value;
        for (const key of Object.keys(source).sort()) {
            const child = source[key];
            out[key] = sortDeep(child === undefined ? null : child);
        }
        return out;
    }
    return value;
}
export function canonical(value) {
    return `${JSON.stringify(sortDeep(value))}\n`;
}
export function sha256Hex(bytes) {
    return createHash("sha256").update(bytes).digest("hex");
}
function parseJson(bytes) {
    try {
        return JSON.parse(bytes.toString("utf8"));
    }
    catch {
        return null;
    }
}
function asRow(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value) ? value : null;
}
function asText(value) {
    return typeof value === "string" ? value : "";
}
function asList(value) {
    return Array.isArray(value) ? value : [];
}
function filled(row) {
    return Object.values(row).every((item) => item !== "");
}
function toolDigest() {
    const invoked = process.argv[1];
    if (invoked === undefined) {
        return "unavailable";
    }
    try {
        return sha256Hex(readFileSync(realpathSync(invoked)));
    }
    catch {
        return "unavailable";
    }
}
function contractJson() {
    return { ...CONTRACT, tool_sha256: toolDigest() };
}
const WHITESPACE = " \t\r\n";
const SIMPLE_ESCAPES = {
    "\"": "\"",
    "\\": "\\",
    "/": "/",
    b: "\b",
    f: "\f",
    n: "\n",
    r: "\r",
    t: "\t",
};
function skipWhitespace(source, at) {
    let index = at;
    while (index < source.length && WHITESPACE.includes(source[index] ?? "")) {
        index += 1;
    }
    return index;
}
function escapeValue(source, at) {
    const hex = source.slice(at, at + 4);
    if (!/^[0-9a-fA-F]{4}$/.test(hex)) {
        throw new Malformed("bad_escape");
    }
    return { end: at + 4, text: String.fromCharCode(Number.parseInt(hex, 16)) };
}
function readStringToken(source, at) {
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
function skipContainer(source, at, open, close) {
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
function skipMember(source, at, open) {
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
function skipJsonValue(source, at) {
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
function lineBounds(source, keyStart, valueEnd) {
    const start = source.lastIndexOf("\n", keyStart - 1) + 1;
    const found = source.indexOf("\n", valueEnd);
    return { end: found < 0 ? source.length : found + 1, start };
}
function scanMember(source, at) {
    const key = readStringToken(source, at);
    const colon = skipWhitespace(source, key.end);
    if (source[colon] !== ":") {
        throw new Malformed("expected_colon");
    }
    const valueStart = skipWhitespace(source, colon + 1);
    const token = source[valueStart] === "\"" ? readStringToken(source, valueStart) : null;
    const valueEnd = token === null ? skipJsonValue(source, valueStart) : token.end;
    const bounds = lineBounds(source, at, valueEnd);
    const member = {
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
function scanMembers(source) {
    let index = skipWhitespace(source, 0);
    if (source[index] !== "{") {
        throw new Malformed("not_an_object");
    }
    const members = [];
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
function membersOrNull(source) {
    try {
        return scanMembers(source);
    }
    catch {
        return null;
    }
}
function findMember(members, key) {
    return members.find((member) => member.key === key) ?? null;
}
function stringMember(members, key) {
    const member = findMember(members, key);
    return member === null || member.token === null ? "" : member.value;
}
function invalidEnvelope(bytes, failure) {
    return { bytes, failure, kind: "invalid" };
}
function exactSpan(source, member) {
    const leading = source.slice(member.lineStart, member.keyStart);
    const trailing = source.slice(member.tokenEnd, member.lineEnd);
    return /^[ ]*$/.test(leading) && trailing === "," + "\n";
}
function provenanceProjection(source, bytes, members) {
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
function classifyStdout(bytes) {
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
function walkFiles(dir, prefix, files) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        if (entry.isSymbolicLink()) {
            throw new Malformed(`symlink:${prefix}${entry.name}`);
        }
        const full = join(dir, entry.name);
        const rel = prefix === "" ? entry.name : `${prefix}/${entry.name}`;
        if (entry.isDirectory()) {
            walkFiles(full, rel, files);
        }
        else if (entry.isFile()) {
            files.set(rel, readFileSync(full));
        }
    }
}
function manifestRows(bytes) {
    const manifest = asRow(parseJson(bytes));
    const rows = asList(manifest?.files);
    if (manifest === null || manifest.schema !== MANIFEST_SCHEMA || !Array.isArray(manifest.files)) {
        throw new Malformed("raw_manifest_malformed");
    }
    return rows;
}
function rowFields(row) {
    const entry = asRow(row);
    const size = entry?.bytes;
    return {
        bytes: typeof size === "number" ? String(size) : "",
        path: asText(entry?.path),
        sha256: asText(entry?.sha256),
    };
}
function recordRow(files, row, inputs, listed) {
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
function readRun(dir) {
    if (!lstatSync(dir).isDirectory()) {
        throw new Malformed("run_not_a_directory");
    }
    const files = new Map();
    walkFiles(dir, "", files);
    const manifestBytes = files.get("raw-manifest.json");
    if (manifestBytes === undefined) {
        throw new Malformed("raw_manifest_missing");
    }
    const inputs = {};
    const listed = new Set();
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
function readBytes(run, path) {
    const bytes = run.files.get(path);
    if (bytes === undefined) {
        throw new Malformed(`missing_input:${path}`);
    }
    return bytes;
}
function readJsonInput(run, path) {
    try {
        return parseJson(readBytes(run, path));
    }
    catch {
        throw new Malformed(`malformed_input:${path}`);
    }
}
function laneInfo(value, label) {
    const row = asRow(value) || {};
    const info = {
        common_dir: asText(row.common_dir),
        driver_commit: asText(row.driver_commit),
        driver_root: asText(row.driver_root),
    };
    if (row === null || !filled({ ...info }) || !HEX40.test(info.driver_commit)) {
        throw new Malformed(`lanes_lane:${label}`);
    }
    return info;
}
function targetInfo(entry) {
    const row = asRow(entry);
    if (row === null) {
        return null;
    }
    const target = {
        common_dir: asText(row.common_dir),
        ref: asText(row.ref),
        repository: asText(row.repository),
        revision: asText(row.revision),
        root: asText(row.root),
        target: asText(row.target),
    };
    return filled({ ...target }) && HEX40.test(target.revision) ? target : null;
}
function readLanes(run) {
    const lanes = asRow(readJsonInput(run, "lanes.json"));
    if (lanes === null || lanes.schema !== LANES_SCHEMA) {
        throw new Malformed("lanes_schema");
    }
    const targets = [];
    for (const entry of asList(lanes.targets)) {
        const target = targetInfo(entry);
        if (target === null) {
            throw new Malformed("lanes_target");
        }
        targets.push(target);
    }
    return { candidate: laneInfo(lanes.candidate, "candidate"), reference: laneInfo(lanes.reference, "reference"), targets };
}
function readNormalizations(run) {
    const value = readJsonInput(run, "normalizations.json");
    if (!Array.isArray(value)) {
        throw new Malformed("normalizations_not_array");
    }
    if (value.length > 0) {
        throw new Malformed("caller_normalization_mask_forbidden");
    }
}
function metaShapeOk(row) {
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
function readCaptureMeta(run, base) {
    const row = asRow(readJsonInput(run, `${base}/meta.json`));
    if (!metaShapeOk(row)) {
        throw new Malformed(`capture_meta:${base}`);
    }
    return row;
}
function writtenNamesFor(run, base, phase) {
    const map = asRow(readJsonInput(run, `${base}/meta.json`));
    if (map === null) {
        return [];
    }
    const meta = map;
    const source = phase === "before" ? meta.written_before : meta.written;
    const entry = asRow(source);
    return entry === null ? [] : Object.keys(entry).sort();
}
function readCapture(run, lane, repository, plan, operation) {
    const base = `captures/${lane}/${repository}/${plan}/${operation}`;
    if (!run.files.has(`${base}/meta.json`)) {
        return null;
    }
    const meta = readCaptureMeta(run, base);
    const after = new Map();
    for (const name of writtenNamesFor(run, base, "after")) {
        after.set(name, sha256Hex(readBytes(run, `${base}/written-after/${name}`)));
    }
    const before = new Map();
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
function parseRegistryPlan(row) {
    const entry = asRow(row);
    if (entry === null) {
        return null;
    }
    const plan = {
        generation: asText(entry.generation),
        plan_id: asText(entry.plan_id),
        status: asText(entry.status),
    };
    return filled({ ...plan }) ? plan : null;
}
function parseRegistry(bytes) {
    const value = asRow(parseJson(bytes));
    if (value === null || !Array.isArray(value.plans)) {
        return null;
    }
    const plans = [];
    for (const row of asList(value.plans)) {
        const plan = parseRegistryPlan(row);
        if (plan === null) {
            return null;
        }
        plans.push(plan);
    }
    return plans;
}
function readRegistry(run, repository) {
    let bytes = Buffer.alloc(0);
    try {
        bytes = readBytes(run, `registries/${repository}.json`);
    }
    catch {
        return { bytes, plans: [], present: false };
    }
    const plans = parseRegistry(bytes);
    return plans === null ? { bytes, plans: [], present: false } : { bytes, plans, present: true };
}
function sitePath(lane, repository, plan, operation) {
    return `captures/${lane}/${repository}/${plan}/${operation}`;
}
function enumerateSites(run, lanes) {
    const sites = [];
    for (const target of lanes.targets) {
        for (const plan of readRegistry(run, target.repository).plans) {
            for (const operation of OPERATIONS) {
                const captures = new Map();
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
function expectedSites(lanes, run) {
    const keys = [];
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
function presentSiteDirs(run) {
    const dirs = new Set();
    for (const path of run.files.keys()) {
        const match = /^captures\/([^/]+)\/([^/]+)\/([^/]+)\/([^/]+)\//.exec(path);
        if (match !== null) {
            dirs.add(sitePath(match[1] || "", match[2] || "", match[3] || "", match[4] || ""));
        }
    }
    return [...dirs].sort();
}
function captureList(sites) {
    const all = [];
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
function pointerOf(path) {
    return path
        .map((part) => `/${String(part).replaceAll("~", "~0").replaceAll("/", "~1")}`)
        .join("");
}
function arrayPointerDifference(left, right, path) {
    const length = Math.max(left.length, right.length);
    for (let index = 0; index < length; index += 1) {
        const found = jsonPointerDifference(left[index] || null, right[index] || null, [...path, index]);
        if (found !== null) {
            return found;
        }
    }
    return pointerOf(path);
}
function objectPointerDifference(left, right, path) {
    const keys = [...new Set([...Object.keys(left), ...Object.keys(right)])].sort();
    for (const key of keys) {
        const found = jsonPointerDifference(left[key] || null, right[key] || null, [...path, key]);
        if (found !== null) {
            return found;
        }
    }
    return pointerOf(path);
}
function jsonPointerDifference(left, right, path = []) {
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
function firstDifference(left, right) {
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
function commandKey(phase, subject, argv) {
    return `${phase}|${subject}|${argv.join(" ")}`;
}
function parseCommand(row) {
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
function readCommands(run) {
    const value = asRow(readJsonInput(run, "observation.json"));
    const rows = asList(value?.commands);
    if (value === null || value.schema !== OBSERVATION_SCHEMA || typeof value.lanes_sha256 !== "string") {
        throw new Malformed("observation_schema");
    }
    const map = new Map();
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
function stdoutBytes(commands, phase, subject, argv) {
    const command = commands.get(commandKey(phase, subject, argv));
    if (command === undefined || command.exit !== 0) {
        return null;
    }
    return Buffer.from(command.stdout, "base64");
}
function stdoutOf(commands, phase, subject, argv) {
    const bytes = stdoutBytes(commands, phase, subject, argv);
    return bytes === null ? "" : bytes.toString("utf8").trim();
}
function reader(commands, subject, problems) {
    return (phase, argv) => {
        const value = stdoutOf(commands, phase, subject, ["git", ...argv]);
        if (stdoutBytes(commands, phase, subject, ["git", ...argv]) === null) {
            problems.push(`${phase}:${argv.join(" ")}`);
        }
        return value;
    };
}
function blobDigest(commands, subject, blob) {
    if (blob === "") {
        return "";
    }
    const bytes = stdoutBytes(commands, "start", subject, ["git", "cat-file", "blob", blob]);
    return bytes === null ? "" : sha256Hex(bytes);
}
function movementProblems(target, observed) {
    const found = [];
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
function targetIdentityKeys(target, phase) {
    const subject = `target:${target.repository}`;
    return [
        commandKey(phase, subject, ["git", "rev-parse", "--show-toplevel"]),
        commandKey(phase, subject, ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]),
        commandKey(phase, subject, ["git", "rev-parse", "--verify", `${target.ref}^{commit}`]),
    ];
}
function observeTarget(commands, target) {
    const subject = `target:${target.repository}`;
    const problems = [];
    const read = reader(commands, subject, problems);
    const exists = commands.get(commandKey("start", subject, ["git", "cat-file", "-e", `${target.revision}^{commit}`]));
    if (exists === undefined || exists.exit !== 0) {
        problems.push(`commit_missing:${target.revision}`);
    }
    const observed = {
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
function observeLane(commands, lane) {
    const subject = `lane:${lane}`;
    const problems = [];
    const read = reader(commands, subject, problems);
    const observed = {
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
function blobKeys(target, blobs) {
    const subject = `target:${target.repository}`;
    return blobs
        .filter((blob) => blob !== "")
        .map((blob) => commandKey("start", subject, ["git", "cat-file", "blob", blob]));
}
function targetKeys(target, observed) {
    const subject = `target:${target.repository}`;
    const keys = [];
    for (const phase of PHASES) {
        keys.push(...targetIdentityKeys(target, phase));
    }
    keys.push(commandKey("start", subject, ["git", "cat-file", "-e", `${target.revision}^{commit}`]));
    keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.ref}:${CONTRACT.policy_path}`]));
    keys.push(commandKey("start", subject, ["git", "rev-parse", `${target.ref}:${CONTRACT.registry_path}`]));
    keys.push(...blobKeys(target, [asText(observed?.policy_blob), asText(observed?.registry_blob)]));
    return keys;
}
function laneKeys(lane, phase) {
    const subject = `lane:${lane}`;
    return [
        commandKey(phase, subject, ["git", "rev-parse", "--show-toplevel"]),
        commandKey(phase, subject, ["git", "rev-parse", "--path-format=absolute", "--git-common-dir"]),
        commandKey(phase, subject, ["git", "rev-parse", "HEAD"]),
    ];
}
function requiredKeys(lanes, targets) {
    const keys = [];
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
function commandSetProblems(commands, keys) {
    const problems = [];
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
function liveMismatch(commands, keys, problems) {
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
function laneMetadataProblems(lanes, rows) {
    const problems = [];
    for (const lane of LANES) {
        const observed = rows.get(lane);
        const info = laneOf(lanes, lane);
        if (observed === undefined || observed.common_start !== info.common_dir || observed.head_start !== info.driver_commit) {
            problems.push(`lane_metadata:${lane}`);
        }
    }
    return problems;
}
function targetFacts(lanes, targets) {
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
function laneFacts(rows) {
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
function observeRun(run, lanes, observe) {
    const commands = readCommands(run);
    const problems = [];
    const targets = new Map();
    for (const target of lanes.targets) {
        const observed = observeTarget(commands, target);
        problems.push(...observed.problems);
        targets.set(target.repository, observed);
    }
    const laneRows = new Map();
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
const OPERATION_SCHEMA = {
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
function laneOf(lanes, lane) {
    return lane === "reference" ? lanes.reference : lanes.candidate;
}
function expectedProvenance(lanes, repository, lane) {
    const target = lanes.targets.find((row) => row.repository === repository);
    if (target === undefined || target.common_dir !== laneOf(lanes, lane).common_dir) {
        return "source-lane";
    }
    return "base-copy";
}
function projectedBytes(capture) {
    const envelope = capture.envelope;
    if (envelope.kind === "projected") {
        return envelope.projection;
    }
    return envelope.kind === "refusal" ? envelope.bytes : null;
}
function projectedSchema(capture) {
    return capture.envelope.kind === "projected" ? capture.envelope.schema : "";
}
function memberValue(capture, key) {
    const bytes = projectedBytes(capture);
    return bytes === null ? "" : asText(asRow(parseJson(bytes))?.[key]);
}
function codesOf(capture, field) {
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
function argvOk(capture, lanes, target, site) {
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
    return (JSON.stringify(capture.meta.argv) === JSON.stringify(expected) &&
        capture.meta.cwd === lane.driver_root &&
        capture.meta.driver_commit === lane.driver_commit);
}
function writtenMapsMatch(capture) {
    return (JSON.stringify(asRow(capture.meta.written) || {}) === JSON.stringify(capture.written_after_files) &&
        JSON.stringify(asRow(capture.meta.written_before) || {}) === JSON.stringify(capture.written_before_files));
}
function writtenEqual(reference, candidate) {
    return (JSON.stringify(reference.meta.written) === JSON.stringify(candidate.meta.written) &&
        JSON.stringify(reference.meta.written_before) === JSON.stringify(candidate.meta.written_before) &&
        JSON.stringify(reference.written_after_files) === JSON.stringify(candidate.written_after_files) &&
        JSON.stringify(reference.written_before_files) === JSON.stringify(candidate.written_before_files));
}
function logQuiescent(reference, candidate) {
    const stable = (capture) => JSON.stringify(capture.meta.log_before) === JSON.stringify(capture.meta.log_after);
    return stable(reference) && stable(candidate) && JSON.stringify(reference.meta.log_after) === JSON.stringify(candidate.meta.log_after);
}
function projectionDigest(capture) {
    const bytes = projectedBytes(capture);
    return bytes === null ? "unavailable" : sha256Hex(bytes);
}
function digestsFor(capture) {
    const written = (phase) => sha256Hex(Buffer.from(canonical({
        files: phase === "before" ? capture.written_before_files : capture.written_after_files,
        map: phase === "before" ? capture.meta.written_before : capture.meta.written,
    }), "utf8"));
    return {
        exit: capture.meta.exit,
        meta_sha256: sha256Hex(Buffer.from(canonical(capture.meta), "utf8")),
        projection_sha256: projectionDigest(capture),
        stderr_sha256: sha256Hex(capture.stderr),
        stdout_sha256: sha256Hex(capture.stdout),
        written_after_sha256: written("after"),
        written_before_sha256: written("before"),
    };
}
function addSiteAssertions(ledger, lanes, target, site, subject) {
    const reference = site.captures.get("reference");
    const candidate = site.captures.get("candidate");
    const both = reference === undefined || candidate === undefined ? [] : [reference, candidate];
    ledger.add("capture-argv", subject, both.length === 2 && both.every((capture) => argvOk(capture, lanes, target, site)), "argv template and lane cwd");
    ledger.add("envelope-schema", subject, both.every((capture) => capture.envelope.kind !== "invalid"), "every stdout classifies");
    const refusals = both.filter((capture) => capture.envelope.kind === "refusal").length;
    ledger.add("provenance-pair", subject, refusals === 0 || refusals === 2, "both envelopes carry provenance or both refuse");
    ledger.add("envelope-operation", subject, both.every((capture) => capture.envelope.kind === "refusal" || projectedSchema(capture) === OPERATION_SCHEMA[site.operation]), "audit versus export schema");
    ledger.add("envelope-plan", subject, both.every((capture) => capture.envelope.kind === "refusal" || memberValue(capture, "plan_id") === site.plan_id), "envelope plan binds the registry entry");
    ledger.add("provenance-expected", subject, both.every((capture) => capture.envelope.failure !== "provenance-expected"), "every projected envelope carries a valid provenance value");
    ledger.add("projection-unique", subject, both.every((capture) => capture.envelope.failure !== "projection-unique"), "one exact depth-one provenance member span");
    return both;
}
function compareSite(ledger, lanes, target, site) {
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
function outcomeAssertions(ledger, subject, reference, candidate) {
    const differences = [];
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
function classify(ledger, subject, exit) {
    if (SITE_ASSERTIONS.some((id) => ledger.failed(id, subject))) {
        return "red";
    }
    return exit === 0 ? "equal-success" : "equal-refusal";
}
function sortDifferences(differences) {
    return [...differences].sort((left, right) => JSON.stringify(left).localeCompare(JSON.stringify(right)));
}
// ---------- assertions ----------
class Ledger {
    rows = [];
    add(id, subject, ok, detail) {
        this.rows.push({ detail, id, ok, subject });
    }
    sorted() {
        return [...this.rows].sort((left, right) => (left.id === right.id ? left.subject.localeCompare(right.subject) : left.id.localeCompare(right.id)));
    }
    allOk() {
        return this.rows.every((row) => row.ok);
    }
    failed(id, subject) {
        return this.rows.some((row) => row.id === id && row.subject === subject && !row.ok);
    }
}
// ---------- global and per-target assertions ----------
function projectedAt(sites, repository, operation) {
    return sites.filter((site) => site.repository === repository &&
        (operation === "" || site.operation === operation) &&
        site.captures.get("reference")?.envelope.kind === "projected" &&
        site.captures.get("candidate")?.envelope.kind === "projected");
}
function serialized(captures) {
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
function repositoryTimingOk(sites, repository) {
    const audits = captureList(sites.filter((site) => site.repository === repository && site.operation === "audit-merges"));
    const exports = captureList(sites.filter((site) => site.repository === repository && site.operation === "export-evidence"));
    const last = audits.map((capture) => capture.meta.finished_at).sort().pop() || "";
    const first = exports.map((capture) => capture.meta.started_at).sort().shift() || "";
    return audits.length > 0 && exports.length > 0 && last <= first;
}
function auditsBeforeExports(sites) {
    return new Set(sites.map((site) => site.repository)).size > 0 && [...new Set(sites.map((site) => site.repository))].every((repository) => repositoryTimingOk(sites, repository));
}
function provenanceAt(sites, repository, lane, expected) {
    return sites
        .filter((site) => site.repository === repository)
        .map((site) => site.captures.get(lane))
        .filter((capture) => capture !== undefined)
        .every((capture) => capture.envelope.kind !== "projected" || capture.envelope.provenance === expected);
}
function observedProvenance(sites, repository, lane) {
    const values = new Set();
    for (const site of sites.filter((row) => row.repository === repository)) {
        const envelope = site.captures.get(lane)?.envelope;
        if (envelope !== undefined && envelope.kind === "projected") {
            values.add(envelope.provenance);
        }
    }
    return [...values].sort();
}
function uniqueTargetCount(lanes, commonDir) {
    return lanes.targets.filter((target) => target.common_dir === commonDir).length;
}
function policyIdentity(bytes) {
    return bytes === null ? "" : asText(asRow(asRow(parseJson(bytes))?.repository)?.id);
}
function policyBound(run, target, observed) {
    const policy = run.files.get(`policies/${target.repository}.json`) || null;
    const recorded = asText(observed?.policy_sha256);
    return policy !== null && recorded !== "" && sha256Hex(policy) === recorded && policyIdentity(policy) === target.repository;
}
function refProblems(observed) {
    return asList(observed?.problems)
        .map((problem) => asText(problem))
        .filter((problem) => problem === "ref_moved" || problem.startsWith("revision_mismatch"));
}
function registryBound(run, target, observed) {
    const registry = readRegistry(run, target.repository);
    const recorded = asText(observed?.registry_sha256);
    return registry.present && recorded !== "" && sha256Hex(registry.bytes) === recorded;
}
function targetBoundAssertions(ledger, run, target, observed) {
    const moving = refProblems(observed);
    ledger.add("target-repository-bound", target.repository, policyBound(run, target, observed), "policy identity binds the target repository");
    ledger.add("target-ref-bound", target.repository, moving.length === 0, moving.join(" ") || "pinned revision re-observed");
    ledger.add("registry-bound", target.repository, registryBound(run, target, observed), "registry copy equals the blob at the pinned revision");
}
function revisionCarries(capture, revision) {
    if (capture === undefined || capture.envelope.kind !== "projected") {
        return true;
    }
    if (capture.envelope.schema !== OPERATION_SCHEMA["audit-merges"]) {
        return true;
    }
    return memberValue(capture, "target_revision") === revision;
}
function revisionBound(sites, target) {
    return sites
        .filter((site) => site.repository === target.repository)
        .every((site) => LANES.every((lane) => revisionCarries(site.captures.get(lane), target.revision)));
}
function auditPairOk(sites, repository) {
    return projectedAt(sites, repository, "audit-merges").some((site) => {
        const reference = site.captures.get("reference");
        const candidate = site.captures.get("candidate");
        return reference !== undefined && candidate !== undefined && memberValue(reference, "target_revision") !== "" && memberValue(candidate, "target_revision") !== "";
    });
}
function targetAssertions(ledger, lanes, run, sites, observation) {
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
function lanesDistinct(lanes, sites) {
    const reference = observedProvenance(sites, "skills", "reference");
    const candidate = observedProvenance(sites, "skills", "candidate");
    const referenceOk = reference.length > 0 && reference.every((value) => value === "base-copy");
    const candidateOk = candidate.length > 0 && candidate.every((value) => value === "source-lane");
    return uniqueTargetCount(lanes, lanes.reference.common_dir) === 1 && referenceOk && candidateOk;
}
function laneAssertions(ledger, lanes, sites, captures) {
    ledger.add("common-dir-reference", "lanes", uniqueTargetCount(lanes, lanes.reference.common_dir) === 1, "exactly one target equals the reference common dir");
    ledger.add("common-dir-candidate", "lanes", lanes.candidate.common_dir !== lanes.reference.common_dir && uniqueTargetCount(lanes, lanes.candidate.common_dir) === 0, "candidate equals no target and differs from reference");
    const commits = captures.every((capture) => capture.meta.driver_commit === laneOf(lanes, capture.lane).driver_commit);
    ledger.add("driver-commits-distinct", "lanes", lanes.candidate.driver_commit !== lanes.reference.driver_commit && commits, "distinct full lane commits");
    ledger.add("lanes-distinct-own-repository", "lanes", lanesDistinct(lanes, sites), "the skills target alone anchors the reference lane");
}
function runAssertions(ledger, run, lanes, sites, captures, observation) {
    const counts = CONTRACT.required_targets.map((repository) => lanes.targets.filter((target) => target.repository === repository).length);
    ledger.add("targets-complete", "targets", counts.every((count) => count === 1), counts.join(","));
    const complete = sites.every((site) => site.captures.size === LANES.length);
    ledger.add("site-set", "registry", JSON.stringify(presentSiteDirs(run)) === JSON.stringify(expectedSites(lanes, run).sort()) && complete, "every registry plan, operation and lane is captured exactly");
    ledger.add("captures-serialized", "run", serialized(captures), "unique positive sequences and non-overlapping intervals");
    ledger.add("order-audits-before-exports", "run", auditsBeforeExports(sites), "every audit completes before any export starts");
    ledger.add("raw-inputs-bound", "run", captures.every((capture) => writtenMapsMatch(capture)), "written maps recompute from retained snapshot bytes");
    ledger.add("observe-git", "observed", observation.git, observation.problems.join(" ") || "retained observation consistent");
}
function siteResults(ledger, lanes, sites) {
    return sites.map((site) => {
        const target = lanes.targets.find((row) => row.repository === site.repository);
        const id = `${site.repository}/${site.plan_id}/${site.operation}`;
        if (target === undefined) {
            return { classification: "red", differences: [{ kind: "unknown-target" }], id };
        }
        return compareSite(ledger, lanes, target, site);
    });
}
function tally(results) {
    const counts = { equal_refusal: 0, equal_success: 0, red: 0, sites: results.length };
    const add = (key) => {
        counts[key] = Number(counts[key]) + 1;
    };
    for (const result of results) {
        add(result.classification.replaceAll("-", "_"));
    }
    return counts;
}
function expectedProvenanceTable(lanes) {
    const table = {};
    for (const lane of LANES) {
        const row = {};
        for (const target of lanes.targets) {
            row[target.repository] = expectedProvenance(lanes, target.repository, lane);
        }
        table[lane] = row;
    }
    return table;
}
function laneJson(info) {
    return { common_dir: info.common_dir, driver_commit: info.driver_commit, driver_root: info.driver_root };
}
function targetJson(target) {
    return {
        common_dir: target.common_dir,
        ref: target.ref,
        repository: target.repository,
        revision: target.revision,
        root: target.root,
        target: target.target,
    };
}
function provenanceJson(capture) {
    if (capture === undefined) {
        return "";
    }
    if (capture.envelope.kind === "projected") {
        return capture.envelope.provenance;
    }
    return capture.envelope.kind === "refusal" ? capture.envelope.code : "";
}
function siteJson(site, result) {
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
function buildReport(input, ledger) {
    return {
        assertions: ledger.sorted(),
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
function malformedReport(dir, error) {
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
function evaluateRun(dir, observe) {
    let run;
    let lanes;
    try {
        run = readRun(dir);
        lanes = readLanes(run);
        readNormalizations(run);
    }
    catch (error) {
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
        report: buildReport({ counts, directory: dir, inputs: run.inputs, lanes, manifestSha: run.manifestSha, observation, results, sites, verdict }, ledger),
    };
}
function gitOut(cwd, args) {
    const result = run("git", args, cwd);
    return result.status === 0 ? text(result.stdout).trim() : "";
}
function gitBlob(cwd, spec) {
    const result = run("git", ["cat-file", "blob", spec], cwd);
    return result.status === 0 ? result.stdout : null;
}
function contained(cwd, candidate) {
    const base = resolve(cwd);
    const full = resolve(base, candidate);
    return full !== base && full.startsWith(`${base}/`);
}
function field(row, key) {
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
function contractStrings(contract) {
    return CONTRACT_KEYS.every((key) => typeof contract[key] === "string");
}
function registrationAt(cwd, revision) {
    const bytes = gitBlob(cwd, `${revision}:${CONTRACT.registry_path}`);
    const registry = bytes === null ? null : asRow(parseJson(bytes));
    if (registry === null) {
        return null;
    }
    return asList(registry.plans).map((entry) => asRow(entry)).find((plan) => plan !== null && field(plan, "plan_id") === CONTRACT.plan_id) || null;
}
function objectExists(cwd, revision) {
    return run("git", ["cat-file", "-e", `${revision}^{commit}`], cwd).status === 0;
}
function isAncestor(cwd, ancestor, descendant) {
    return run("git", ["merge-base", "--is-ancestor", ancestor, descendant], cwd).status === 0;
}
function specBinding(cwd, entry, contract, failures) {
    const spec = asRow(entry.spec);
    const path = spec === null ? "" : field(spec, "path");
    const bytes = path === "" ? null : gitBlob(cwd, `${field(contract, "target_ref_commit")}:${path}`);
    const digest = bytes === null ? "" : sha256Hex(bytes);
    failures.facts.registry_spec_sha256 = spec === null ? "" : field(spec, "sha256");
    if (digest === "" || digest !== (spec === null ? "" : field(spec, "sha256")) || digest !== field(contract, "spec_sha256")) {
        failures.failed.push("dependency-spec");
    }
}
function bundleGoalIds(bytes) {
    return bytes === null ? [] : asList(asRow(parseJson(bytes))?.goals).map((goal) => field(asRow(goal) || {}, "id"));
}
function bundleBinding(cwd, entry, contract, revision, failures) {
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
function consumerRegistration(cwd, contract, revision, failures) {
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
function lineageHistoryOk(cwd, contract, merge, publication, capture, target, failures) {
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
function toolBinding(cwd, contract, merge, capture, toolPath, failures) {
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
function completionMatches(completion, contract, merge, publication, capture, blob) {
    const pairs = [
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
function consumerLineage(cwd, contract, failures) {
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
function reportConsistency(report, contract, failures) {
    const digest = sha256Hex(Buffer.from(canonical(report), "utf8"));
    const embedded = asRow(contract.report);
    const embeddedDigest = embedded === null ? "" : sha256Hex(Buffer.from(canonical(embedded), "utf8"));
    failures.facts.recomputed_report_sha256 = digest;
    failures.facts.embedded_report_sha256 = field(contract, "report_sha256");
    if (embedded === null || embeddedDigest !== digest || digest !== field(contract, "report_sha256")) {
        failures.failed.push("report-consistency");
    }
}
function recompute(cwd, contract, failures) {
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
function evidenceContract(cwd, evidencePath, failures) {
    let bytes;
    try {
        bytes = readFileSync(resolve(cwd, evidencePath));
    }
    catch {
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
function runManifest(cwd, contract) {
    try {
        return readFileSync(resolve(cwd, `${field(contract, "run_directory")}/raw-manifest.json`));
    }
    catch {
        return null;
    }
}
function consumerResult(cwd, evidencePath) {
    const failures = { failed: [], facts: {}, malformed: false };
    const emit = () => {
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
function usage() {
    process.stderr.write("usage: d13-compare.mjs <run-directory> [--observe]\n       d13-compare.mjs --contract\n       d13-compare.mjs --consumer-check <evidence.json>\n");
    return 2;
}
export function main(argv) {
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
    let outcome;
    try {
        outcome = evaluateRun(resolve(process.cwd(), positional[0] || ""), argv.includes("--observe"));
    }
    catch {
        return usage();
    }
    process.stdout.write(canonical(outcome.report));
    return outcome.exit;
}
if (invokedDirectly(import.meta.url)) {
    process.exitCode = main(process.argv.slice(2));
}
//# sourceMappingURL=d13-compare.mjs.map