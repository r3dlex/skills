import { run, text } from "./proc.mjs";
import { RANK, type FileStat, type Measured } from "./freeze-types.mjs";

const TOOL_ENV = { ...process.env, PYTHONDONTWRITEBYTECODE: "1" };

function requireTool(name: string): void {
  const found = run("bash", ["-c", `command -v ${name}`], process.cwd(), TOOL_ENV);
  if (found.status !== 0 || text(found.stdout).trim() === "") {
    throw new Error(`tool_missing:${name}`);
  }
}

function relative(root: string, filename: string): string {
  if (filename.startsWith(`${root}/`)) {
    return filename.slice(root.length + 1);
  }
  return filename;
}

function bump(current: { violations: number; max: number; worst: string }, row: { complexity?: number; rank?: string }, kind: "c901" | "xenon"): void {
  current.violations += 1;
  if (kind === "c901") {
    current.max = Math.max(current.max, row.complexity ?? 0);
    return;
  }
  if ((RANK[row.rank ?? "A"] ?? 0) > (RANK[current.worst] ?? 0)) {
    current.worst = row.rank ?? "A";
  }
}

function group(rows: Array<{ path: string; complexity?: number; rank?: string }>, kind: "c901" | "xenon"): FileStat[] {
  const byPath = new Map<string, { violations: number; max: number; worst: string }>();
  for (const row of rows) {
    const current = byPath.get(row.path) ?? { violations: 0, max: 0, worst: "A" };
    bump(current, row, kind);
    byPath.set(row.path, current);
  }
  return [...byPath.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, stat]) => (kind === "c901"
      ? { path, violations: stat.violations, max: stat.max }
      : { path, violations: stat.violations, blocks: stat.violations, worst: stat.worst }));
}

export function measureC901(root: string, files: readonly string[]): FileStat[] {
  requireTool("ruff");
  if (files.length === 0) {
    return [];
  }
  const result = run("ruff", [
    "check", "--no-cache", "--config", "ruff.toml", "--output-format", "json", ...files,
  ], root, TOOL_ENV);
  const parsed = JSON.parse(text(result.stdout) || "[]") as Array<{ filename: string; message: string }>;
  const rows = parsed.map((item) => {
    const match = /\((\d+)\s*>/.exec(item.message);
    return { path: relative(root, item.filename), complexity: match ? Number(match[1]) : 0 };
  });
  return group(rows, "c901");
}

export function measureXenon(root: string, files: readonly string[]): { blocks: FileStat[]; averageOk: boolean } {
  requireTool("xenon");
  if (files.length === 0) {
    return { blocks: [], averageOk: true };
  }
  const result = run("xenon", ["--max-absolute", "B", "--max-average", "A", ...files], root, TOOL_ENV);
  const report = `${text(result.stdout)}\n${text(result.stderr)}`;
  const averageOk = !report.includes("average complexity");
  const rows: Array<{ path: string; rank: string }> = [];
  for (const line of report.split("\n")) {
    const match = /block "([^:]+):\d+ [^"]+" has a rank of ([A-F])/.exec(line);
    if (match?.[1] !== undefined && match[2] !== undefined) {
      rows.push({ path: match[1], rank: match[2] });
    }
  }
  return { blocks: group(rows, "xenon"), averageOk };
}

export function measureMypy(root: string, files: readonly string[]): FileStat[] {
  requireTool("mypy");
  if (files.length === 0) {
    return [];
  }
  const result = run("mypy", [
    "--strict", "--cache-dir=/dev/null", "--no-error-summary", "--show-error-codes", ...files,
  ], root, TOOL_ENV);
  const counts = new Map<string, number>();
  for (const line of text(result.stdout).split("\n")) {
    if (!line.includes(": error:")) {
      continue;
    }
    const path = relative(root, line.split(":", 1)[0] ?? "");
    counts.set(path, (counts.get(path) ?? 0) + 1);
  }
  return [...counts.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, errors]) => ({ path, violations: errors, errors }));
}

export function measureShellcheck(root: string, files: readonly string[]): FileStat[] {
  requireTool("shellcheck");
  const counts = new Map<string, number>();
  for (const path of files) {
    const result = run("shellcheck", ["-S", "error", "-f", "json", path], root, TOOL_ENV);
    if (result.status === 0) {
      continue;
    }
    const parsed = JSON.parse(text(result.stdout) || "[]") as unknown[];
    if (parsed.length > 0) {
      counts.set(path, parsed.length);
    }
  }
  return [...counts.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([path, errors]) => ({ path, violations: errors, errors }));
}

export function measureShfmt(root: string, files: readonly string[]): string[] {
  requireTool("shfmt");
  return files.filter((path) => run("shfmt", ["-d", path], root, TOOL_ENV).status !== 0).sort();
}

export function measureBashN(root: string, files: readonly string[]): string[] {
  return files.filter((path) => run("bash", ["-n", path], root, TOOL_ENV).status !== 0).sort();
}

export function measure(root: string, py: readonly string[], sh: readonly string[]): Measured {
  const xenon = measureXenon(root, py);
  return {
    c901: measureC901(root, py),
    xenon: xenon.blocks,
    mypy: measureMypy(root, py),
    shellcheck: measureShellcheck(root, sh),
    shfmt: measureShfmt(root, sh),
    bash_n: measureBashN(root, sh),
    xenon_average_ok: xenon.averageOk,
  };
}
