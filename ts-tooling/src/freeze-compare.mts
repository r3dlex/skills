import { RANK, type FileStat, type Measured } from "./freeze-types.mjs";

function byPath(rows: readonly FileStat[]): Map<string, FileStat> {
  return new Map(rows.map((row) => [row.path, row]));
}

function missingOrMore(measured: FileStat, allowed: FileStat | undefined): boolean {
  return allowed === undefined || measured.violations > allowed.violations;
}

function complexityGrew(measured: FileStat, allowed: FileStat): boolean {
  return (measured.max ?? 0) > (allowed.max ?? 0);
}

function rankGrew(measured: FileStat, allowed: FileStat): boolean {
  return (RANK[measured.worst ?? "A"] ?? 0) > (RANK[allowed.worst ?? "A"] ?? 0);
}

function statGrew(measured: FileStat, allowed: FileStat | undefined, kind: string): string | null {
  if (missingOrMore(measured, allowed)) {
    return `growth: ${kind} ${measured.path}`;
  }
  if (allowed !== undefined && complexityGrew(measured, allowed)) {
    return `growth: ${kind} ${measured.path} complexity`;
  }
  if (allowed !== undefined && rankGrew(measured, allowed)) {
    return `growth: ${kind} ${measured.path} rank`;
  }
  return null;
}

function shrunk(measured: FileStat | undefined, allowed: FileStat): boolean {
  if (measured === undefined || measured.violations < allowed.violations) {
    return true;
  }
  return (measured.max ?? 0) < (allowed.max ?? 0) || (RANK[measured.worst ?? "A"] ?? 0) < (RANK[allowed.worst ?? "A"] ?? 0);
}

function statStale(allowed: FileStat, measured: FileStat | undefined, kind: string): string | null {
  return shrunk(measured, allowed) ? `stale baseline: ${kind} ${allowed.path}` : null;
}

export function compareStats(measured: readonly FileStat[], allowed: readonly FileStat[], kind: string): string[] {
  const allowedByPath = byPath(allowed);
  const measuredByPath = byPath(measured);
  const problems: string[] = [];
  for (const row of measured) {
    const problem = statGrew(row, allowedByPath.get(row.path), kind);
    if (problem !== null) {
      problems.push(problem);
    }
  }
  for (const row of allowed) {
    const problem = statStale(row, measuredByPath.get(row.path), kind);
    if (problem !== null) {
      problems.push(problem);
    }
  }
  return problems;
}

export function comparePaths(measured: readonly string[], allowed: readonly string[], kind: string): string[] {
  const allowedSet = new Set(allowed);
  const measuredSet = new Set(measured);
  const problems: string[] = [];
  for (const path of measured) {
    if (!allowedSet.has(path)) {
      problems.push(`growth: ${kind} ${path}`);
    }
  }
  for (const path of allowed) {
    if (!measuredSet.has(path)) {
      problems.push(`stale baseline: ${kind} ${path}`);
    }
  }
  return problems;
}

export function compareMeasured(measured: Measured, allowed: Measured): string[] {
  const problems = [
    ...compareStats(measured.c901, allowed.c901, "c901"),
    ...compareStats(measured.xenon, allowed.xenon, "xenon"),
    ...compareStats(measured.mypy, allowed.mypy, "mypy"),
    ...compareStats(measured.shellcheck, allowed.shellcheck, "shellcheck"),
    ...comparePaths(measured.shfmt, allowed.shfmt, "shfmt"),
    ...comparePaths(measured.bash_n, allowed.bash_n, "bash -n"),
  ];
  if (!measured.xenon_average_ok && allowed.xenon_average_ok) {
    problems.push("growth: xenon average");
  }
  if (measured.xenon_average_ok && !allowed.xenon_average_ok) {
    problems.push("stale baseline: xenon average");
  }
  return problems;
}
