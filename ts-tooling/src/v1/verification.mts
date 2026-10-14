import { accessSync, constants, realpathSync, statSync } from "node:fs";
import { isAbsolute, resolve, sep } from "node:path";

export class VerificationError extends Error {
  readonly code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = "VerificationError";
    this.code = code;
  }
}

const FORBIDDEN = /[;&|`$><\n\\]|\$\(/;
const TRAVERSAL = /(^|[/\s])\.\.([/\s]|$)/;
function hasControl(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    if (code <= 0x1f || code === 0x7f) {
      return true;
    }
  }
  return false;
}
const SAFE_TASK = /^(test|lint|check|typecheck|build|verify|validate|coverage|ci)(?:$|[:._-])/i;
const DELIVERY_TASK = /(deploy|publish|release|promote|ship|upload)/i;

const EXACT = new Set<string>([
  "pytest",
  "pytest\u0000-q",
  "npm\u0000test",
  "prek\u0000run",
  "prek\u0000run\u0000--all-files",
  "python3\u0000-m\u0000pytest",
  "python3\u0000-m\u0000pytest\u0000-q",
  "python3\u0000-m\u0000pytest\u0000--version",
  "python3\u0000-m\u0000unittest",
  "python3\u0000-m\u0000unittest\u0000-v",
  "python3\u0000-m\u0000unittest\u0000discover",
  "python3\u0000-m\u0000unittest\u0000--help",
  "git\u0000diff\u0000--check",
  "docker\u0000compose\u0000config",
  "bash\u0000scripts/archgate.sh\u0000--mode\u0000structural\u0000--rules\u0000.rules.ts\u0000--format\u0000json",
  "bash\u0000scripts/check-put-tenant-prefix-allowlist.sh",
  "python3\u0000scripts/validate-obra-coverage-roadmap.py",
  "python3\u0000scripts/validate-cross-repo-regression-fixtures.py",
  "mix\u0000compile\u0000--warnings-as-errors",
  "mix\u0000coveralls",
  "mix\u0000credo\u0000--strict",
  "mix\u0000dialyzer",
  "mix\u0000format\u0000--check-formatted",
  "mix\u0000test",
  "mix\u0000test\u0000--warnings-as-errors",
  "cargo\u0000clippy\u0000--all-targets\u0000--all-features\u0000--\u0000-D\u0000warnings",
  "cargo\u0000fmt\u0000--check",
  "cargo\u0000llvm-cov\u0000--all-features\u0000--summary-only\u0000--ignore-filename-regex\u0000src/bin/xtask.rs\u0000--fail-under-lines\u000095\u0000--fail-under-functions\u000095\u0000--fail-under-regions\u000095",
  "cargo\u0000run\u0000--bin\u0000xtask\u0000--\u0000fixtures\u0000verify",
  "cargo\u0000test\u0000--all-features",
  "poetry\u0000run\u0000pipeline-runner\u0000archgate",
  "poetry\u0000run\u0000pipeline-runner\u0000check",
  "poetry\u0000run\u0000pipeline-runner\u0000lint",
  "poetry\u0000run\u0000pipeline-runner\u0000spec-check",
  "poetry\u0000run\u0000pipeline-runner\u0000test",
  "poetry\u0000run\u0000pytest",
  "poetry\u0000run\u0000pytest\u0000-v\u0000--cov=solera_ai\u0000--cov-report=term-missing\u0000--cov-fail-under=80",
  "poetry\u0000run\u0000ruff\u0000check\u0000.",
]);

function stop(code: number, message: string): never {
  throw new VerificationError(code, message);
}

function keyOf(argv: readonly string[]): string {
  return argv.join("\u0000");
}

function bashTests(argv: readonly string[]): boolean {
  return argv.length >= 2 && argv[0] === "bash" && (argv[1] ?? "").startsWith("tests/") && argv[1] !== "tests/";
}

function npmRun(argv: readonly string[]): boolean {
  return argv.length === 3 && argv[0] === "npm" && argv[1] === "run" && npmAllowed(argv[2] ?? "");
}

function moonRun(argv: readonly string[]): boolean {
  return argv.length === 3 && argv[0] === "moon" && argv[1] === "run" && moonAllowed(argv[2] ?? "");
}

function allowed(argv: string[]): boolean {
  return EXACT.has(keyOf(argv)) || npmRun(argv) || bashTests(argv) || moonRun(argv);
}

function npmAllowed(target: string): boolean {
  return SAFE_TASK.test(target) && DELIVERY_TASK.test(target) === false;
}

function moonAllowed(target: string): boolean {
  const task = target.slice(target.lastIndexOf(":") + 1);
  return SAFE_TASK.test(task) && DELIVERY_TASK.test(target) === false;
}

export function pyRepr(value: string): string {
  return `'${value.replaceAll("\\", "\\\\").replaceAll("'", "\\'")}'`;
}

function executable(name: string, cwd: string): string | null {
  const path = process.env.PATH ?? "";
  for (const directory of path.split(":")) {
    const base = directory !== "" && isAbsolute(directory) ? directory : resolve(cwd, directory);
    const candidate = resolve(base, name);
    if (isFile(candidate) && canExec(candidate)) {
      return realpathSync(candidate);
    }
  }
  return null;
}

function isFile(path: string): boolean {
  try {
    return statSync(path).isFile();
  } catch {
    return false;
  }
}

function canExec(path: string): boolean {
  try {
    accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function takeQuoted(command: string, index: number, mark: "'" | '"'): { text: string; index: number } {
  let text = "";
  let cursor = index;
  while (cursor < command.length) {
    const ch = command[cursor] ?? "";
    if (ch === mark) {
      return { text, index: cursor };
    }
    if (mark === '"' && ch === "\\") {
      text += command[cursor + 1] ?? "";
      cursor += 2;
      continue;
    }
    text += ch;
    cursor += 1;
  }
  throw new Error("No closing quotation");
}

function takeBare(command: string, index: number): { text: string; index: number } {
  let text = "";
  let cursor = index;
  while (cursor < command.length) {
    const ch = command[cursor] ?? "";
    if (ch === " " || ch === "\t" || ch === "'" || ch === '"') {
      break;
    }
    if (ch === "\\") {
      text += command[cursor + 1] ?? "";
      cursor += 2;
      continue;
    }
    text += ch;
    cursor += 1;
  }
  return { text, index: cursor };
}

export function shlexSplit(command: string): string[] {
  const argv: string[] = [];
  let current = "";
  let started = false;
  let index = 0;
  while (index < command.length) {
    const ch = command[index] ?? "";
    if (ch === " " || ch === "\t") {
      if (started) {
        argv.push(current);
        current = "";
        started = false;
      }
      index += 1;
      continue;
    }
    const quoted = ch === "'" || ch === '"';
    const taken = quoted ? takeQuoted(command, index + 1, ch) : takeBare(command, index);
    current += taken.text;
    started = true;
    index = quoted ? taken.index + 1 : taken.index;
  }
  if (started) {
    argv.push(current);
  }
  return argv;
}

interface Entry {
  cwd: string;
  command: string;
  raw: string;
}

function entryOf(value: unknown, index: number): Entry {
  if (typeof value === "string") {
    return { cwd: ".", command: value.trim(), raw: value };
  }
  if (value !== null && typeof value === "object" && !Array.isArray(value)) {
    return objectEntry(value as Record<string, unknown>, index);
  }
  stop(2, `verification[${index}] must be a non-empty string or exact object`);
}

function objectEntry(value: Record<string, unknown>, index: number): Entry {
  const keys = Object.keys(value);
  if (keys.length !== 2 || keys.includes("cwd") === false || keys.includes("command") === false) {
    stop(2, `verification[${index}] object must have exactly cwd and command keys`);
  }
  const cwd = value.cwd;
  const command = value.command;
  if (typeof cwd !== "string" || cwd.trim() === "") {
    stop(2, `verification[${index}].cwd must be a non-empty string`);
  }
  if (typeof command !== "string" || command.trim() === "") {
    stop(2, `verification[${index}].command must be a non-empty string`);
  }
  if (cwd !== cwd.trim()) {
    stop(3, `verification[${index}].cwd must be normalized`);
  }
  return { cwd, command: command.trim(), raw: command };
}

function rejectControl(index: number, raw: string, cwd: string, command: string): void {
  if (hasControl(raw) || hasControl(cwd)) {
    stop(3, `verification[${index}] contains an ASCII control character`);
  }
  if (FORBIDDEN.test(command)) {
    stop(3, `verification[${index}] command contains shell metacharacters`);
  }
  if (TRAVERSAL.test(command)) {
    stop(3, `verification[${index}] command contains path traversal`);
  }
}

function cwdUnsafe(cwd: string): boolean {
  return isAbsolute(cwd) || cwd.includes("\\") || cwd.split("/").some((part) => part === "" || part === "." || part === "..");
}

function commandCwd(root: string, cwd: string, index: number): string {
  if (cwd === ".") {
    return root;
  }
  if (cwdUnsafe(cwd)) {
    stop(3, `verification[${index}].cwd must be a normalized relative descendant`);
  }
  let resolved = "";
  try {
    resolved = realpathSync(resolve(root, cwd));
  } catch (error) {
    stop(3, `verification[${index}].cwd is unreadable: ${osError(error)}`);
  }
  if (!statSync(resolved).isDirectory() || !resolved.startsWith(root + sep)) {
    stop(3, `verification[${index}].cwd escapes the owning root`);
  }
  return resolved;
}

export function osError(error: unknown): string {
  const coded = error as NodeJS.ErrnoException;
  if (coded.code === "ENOENT") {
    return `[Errno 2] No such file or directory: '${coded.path ?? ""}'`;
  }
  if (coded.code === "EACCES") {
    return `[Errno 13] Permission denied: '${coded.path ?? ""}'`;
  }
  return coded.message ?? String(error);
}

export interface Validated {
  command: string;
  argv: string[];
  cwd: string;
}

function scriptArg(argv: string[]): string | null {
  if (argv[0] === "bash") {
    return argv[1] ?? null;
  }
  if (argv.length >= 2 && argv[0] === "python3" && (argv[1] ?? "").startsWith("scripts/")) {
    return argv[1] ?? null;
  }
  return null;
}

function checkScript(root: string, cwd: string, argv: string[], index: number): void {
  const name = scriptArg(argv);
  if (name === null) {
    return;
  }
  let script = "";
  try {
    script = realpathSync(resolve(cwd, name));
  } catch (error) {
    stop(3, `verification[${index}] script is unreadable: ${osError(error)}`);
  }
  if (!isFile(script) || (script !== root && !script.startsWith(root + sep))) {
    stop(3, `verification[${index}] script escapes the owning root`);
  }
}

function one(root: string, value: unknown, index: number): Validated {
  const entry = entryOf(value, index);
  if (entry.command === "") {
    stop(2, `verification[${index}] command must be a non-empty string`);
  }
  rejectControl(index, entry.raw, entry.cwd, entry.command);
  const cwd = commandCwd(root, entry.cwd, index);
  let argv: string[];
  try {
    argv = shlexSplit(entry.command);
  } catch (error) {
    stop(2, `verification[${index}] command cannot be parsed: ${error instanceof Error ? error.message : String(error)}`);
  }
  if (argv.length === 0 || !allowed(argv)) {
    stop(3, `verification[${index}] command is not allowlisted: ${pyRepr(entry.command)}`);
  }
  checkScript(root, cwd, argv, index);
  const found = executable(argv[0] ?? "", cwd);
  if (found === null) {
    stop(3, `verification[${index}] executable is unavailable: ${argv[0] ?? ""}`);
  }
  argv[0] = found;
  return { command: entry.command, argv, cwd };
}

export function validate(root: string, entries: unknown): Validated[] {
  const resolved = realpathSync(root);
  if (!Array.isArray(entries) || entries.length === 0) {
    stop(2, "goal record has no non-empty verification[] array");
  }
  return entries.map((entry, index) => one(resolved, entry, index));
}
