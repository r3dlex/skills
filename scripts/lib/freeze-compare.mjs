import { RANK } from "./freeze-types.mjs";
function byPath(rows) {
    return new Map(rows.map((row) => [row.path, row]));
}
function missingOrMore(measured, allowed) {
    return allowed === undefined || measured.violations > allowed.violations;
}
function complexityGrew(measured, allowed) {
    return (measured.max ?? 0) > (allowed.max ?? 0);
}
function rankGrew(measured, allowed) {
    return (RANK[measured.worst ?? "A"] ?? 0) > (RANK[allowed.worst ?? "A"] ?? 0);
}
function statGrew(measured, allowed, kind) {
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
function shrunk(measured, allowed) {
    if (measured === undefined || measured.violations < allowed.violations) {
        return true;
    }
    return (measured.max ?? 0) < (allowed.max ?? 0) || (RANK[measured.worst ?? "A"] ?? 0) < (RANK[allowed.worst ?? "A"] ?? 0);
}
function statStale(allowed, measured, kind) {
    return shrunk(measured, allowed) ? `stale baseline: ${kind} ${allowed.path}` : null;
}
function grewOnly(measured, allowed, kind) {
    const allowedByPath = byPath(allowed);
    const problems = [];
    for (const row of measured) {
        const problem = statGrew(row, allowedByPath.get(row.path), kind);
        if (problem !== null) {
            problems.push(problem);
        }
    }
    return problems;
}
export function compareStats(measured, allowed, kind) {
    const measuredByPath = byPath(measured);
    const problems = grewOnly(measured, allowed, kind);
    for (const row of allowed) {
        const problem = statStale(row, measuredByPath.get(row.path), kind);
        if (problem !== null) {
            problems.push(problem);
        }
    }
    return problems;
}
export function comparePaths(measured, allowed, kind) {
    const allowedSet = new Set(allowed);
    const measuredSet = new Set(measured);
    const problems = [];
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
export function compareMeasured(measured, allowed) {
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
function pathsGrew(current, previous, kind) {
    const allowed = new Set(previous);
    return current.filter((path) => !allowed.has(path)).map((path) => `growth: ${kind} ${path}`);
}
export function compareAllowances(current, previous) {
    const problems = [
        ...grewOnly(current.c901, previous.c901, "c901"),
        ...grewOnly(current.xenon, previous.xenon, "xenon"),
        ...grewOnly(current.mypy, previous.mypy, "mypy"),
        ...grewOnly(current.shellcheck, previous.shellcheck, "shellcheck"),
        ...pathsGrew(current.shfmt, previous.shfmt, "shfmt"),
        ...pathsGrew(current.bash_n, previous.bash_n, "bash -n"),
    ];
    if (!current.xenon_average_ok && previous.xenon_average_ok) {
        problems.push("growth: xenon average");
    }
    return problems;
}
//# sourceMappingURL=freeze-compare.mjs.map