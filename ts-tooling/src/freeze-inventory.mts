import { readFileSync } from "node:fs";
import { run, text } from "./proc.mjs";
import { CLASSES, OWNERS, type Baseline, type LedgerClass, type LedgerEntry } from "./freeze-types.mjs";

const PY_CMD = /(?:^|[^A-Za-z0-9_./-])python3?(?=$|[^A-Za-z0-9_])/;
const INLINE = /(?:^|[^A-Za-z0-9_./-])python3?(?:\s+-[A-Za-z0-9]+)*\s+-c\b/;

export function excluded(path: string, patterns: readonly string[]): boolean {
  return patterns.some((pattern) => globToRegExp(pattern).test(path));
}

function globToRegExp(pattern: string): RegExp {
  const body = pattern
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, "\0")
    .replace(/\*/g, "[^/]*")
    .replaceAll("\0", ".*");
  return new RegExp(`^${body}$`);
}

function windowAt(lines: readonly string[], index: number): string {
  const stripped = lines[index]?.trim() ?? "";
  if (!stripped.endsWith("\\")) {
    return stripped;
  }
  return `${stripped.slice(0, -1)} ${lines[index + 1]?.trim() ?? ""}`;
}

function lineEmbeds(window: string): boolean {
  if (window.includes("<<") && PY_CMD.test(window)) {
    return true;
  }
  return INLINE.test(window);
}

export function embedsPython(text: string): boolean {
  const lines = text.split("\n");
  for (let index = 0; index < lines.length; index += 1) {
    const window = windowAt(lines, index);
    if (!window.startsWith("#") && lineEmbeds(window)) {
      return true;
    }
  }
  return false;
}

export function tracked(root: string): string[] {
  const listed = run("git", ["ls-files", "-z"], root);
  if (listed.status !== 0) {
    throw new Error("git ls-files failed");
  }
  return text(listed.stdout).split("\0").filter((path) => path !== "").sort();
}

export function inventoryPaths(root: string, baseline: Baseline): string[] {
  const found: string[] = [];
  for (const path of tracked(root)) {
    if (baseline.infrastructure_shells.includes(path)) {
      continue;
    }
    if (path.endsWith(".py") || (path.endsWith(".sh") && !path.startsWith("tests/"))) {
      found.push(path);
      continue;
    }
    if (path.startsWith("tests/") && path.endsWith(".sh") && embedsPython(readFileSync(`${root}/${path}`, "utf8"))) {
      found.push(path);
    }
  }
  return found;
}

function requireOwner(entry: LedgerEntry): string | null {
  if (entry.class !== "eligible") {
    return null;
  }
  if (entry.owner === undefined || !OWNERS.includes(entry.owner as (typeof OWNERS)[number])) {
    return `eligible entry has no owning goal: ${entry.path}`;
  }
  return null;
}

function requireConsumers(entry: LedgerEntry): string | null {
  if (entry.class !== "kept-language") {
    return null;
  }
  if (entry.consumers === undefined || entry.consumers.length === 0) {
    return `kept-language entry cites no consumer: ${entry.path}`;
  }
  return null;
}

export function entryProblems(entry: LedgerEntry): string[] {
  const problems: string[] = [];
  if (!CLASSES.includes(entry.class)) {
    problems.push(`unknown class: ${entry.path}`);
  }
  const owner = requireOwner(entry);
  const consumers = requireConsumers(entry);
  if (owner !== null) {
    problems.push(owner);
  }
  if (consumers !== null) {
    problems.push(consumers);
  }
  if (entry.class === "compat-shim" && (entry.entrypoint === undefined || entry.entrypoint === "")) {
    problems.push(`compat-shim has no entrypoint: ${entry.path}`);
  }
  return problems;
}

export function compareInventory(present: ReadonlySet<string>, entries: readonly LedgerEntry[]): string[] {
  const byPath = new Map(entries.map((entry) => [entry.path, entry]));
  const problems: string[] = [];
  for (const path of present) {
    if (!byPath.has(path)) {
      problems.push(`unlisted file: ${path}`);
    }
  }
  for (const entry of entries) {
    problems.push(...entryProblems(entry));
    if (entry.in_flight !== undefined && !present.has(entry.path)) {
      continue;
    }
    if (!present.has(entry.path)) {
      problems.push(`ledger entry absent: ${entry.path}`);
    }
  }
  return problems;
}

export function classOf(entries: readonly LedgerEntry[], path: string): LedgerClass | undefined {
  return entries.find((entry) => entry.path === path)?.class;
}

const FIXED = new Set<LedgerClass>(["scaffold-template", "kept-language", "test-wrapper"]);

function addedProblem(entry: LedgerEntry): string | null {
  if (entry.in_flight !== undefined || entry.class === "compat-shim") {
    return null;
  }
  return `growth: ${entry.class} ${entry.path}`;
}

function priorProblems(entry: LedgerEntry, prior: LedgerEntry | undefined, present: ReadonlySet<string>): string[] {
  if (prior === undefined) {
    const added = addedProblem(entry);
    return added === null ? [] : [added];
  }
  if (prior.class === entry.class) {
    return [];
  }
  const problems = [`reclassified: ${entry.path}`];
  if (prior.class === "kept-language" || FIXED.has(prior.class)) {
    problems.push(`${prior.class} left its class: ${entry.path}`);
  }
  if (entry.in_flight !== undefined && present.has(entry.path)) {
    problems.push(`in-flight class differs: ${entry.path}`);
  }
  return problems;
}

function removedProblems(previous: readonly LedgerEntry[], current: readonly LedgerEntry[]): string[] {
  const now = new Set(current.map((entry) => entry.path));
  return previous.flatMap((entry) => {
    if (now.has(entry.path) || entry.in_flight !== undefined) {
      return [];
    }
    if (entry.class === "eligible") {
      return [];
    }
    return [`removed: ${entry.class} ${entry.path}`];
  });
}

export function classChanges(previous: readonly LedgerEntry[], current: readonly LedgerEntry[], present: ReadonlySet<string>): string[] {
  const before = new Map(previous.map((entry) => [entry.path, entry]));
  return [
    ...current.flatMap((entry) => priorProblems(entry, before.get(entry.path), present)),
    ...removedProblems(previous, current),
  ];
}
