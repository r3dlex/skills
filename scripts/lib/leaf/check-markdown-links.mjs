import { existsSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { loadCatalog } from "./catalog-model.mjs";
import { pySplitlines } from "./py-text.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
const LINK = /(?<!!)\[[^\]]+\]\(([^)]+)\)/g;
function checkedFiles(root, catalog) {
    const files = [join(root, "README.md"), join(root, "AGENTS.md")];
    files.push(...catalog.phases.map((phase) => join(root, phase, "README.md")));
    files.push(...catalog.skills.map((entry) => join(root, entry.source_path, "SKILL.md")));
    return files.filter((path) => existsSync(path));
}
export function logicalTarget(root, sourceName, target, byName) {
    const parts = [];
    for (const part of `${sourceName}/${target}`.split("/")) {
        if (part === "" || part === ".") {
            continue;
        }
        if (part === "..") {
            parts.pop();
            continue;
        }
        parts.push(part);
    }
    const head = parts[0];
    if (head === undefined) {
        return { path: root, installed: false };
    }
    const skill = byName.get(head);
    if (skill) {
        return { path: join(root, skill.source_path, ...parts.slice(1)), installed: true };
    }
    return { path: join(root, ...parts), installed: false };
}
function skillName(path, root, byName) {
    const resolved = resolve(path);
    for (const [name, entry] of byName) {
        const skillRoot = resolve(root, entry.source_path);
        if (resolved === skillRoot || resolved.startsWith(`${skillRoot}/`)) {
            return name;
        }
    }
    throw new Error(`catalog skill target not found for ${path}`);
}
function brokenLink(path, line, target, kind) {
    return `${path}:${line}: ${kind}: ${target}`;
}
function localTarget(raw) {
    const target = raw.split(/\s/)[0]?.replaceAll(/^<|>$/g, "") ?? "";
    if (target.startsWith("#") || target.startsWith("http:") || target.startsWith("https:") || target.startsWith("mailto:")) {
        return undefined;
    }
    const local = target.split("#", 1)[0] ?? "";
    return local === "" ? undefined : target;
}
function scanLine(path, line, lineNumber, root, sourceName, byName, broken) {
    for (const match of line.matchAll(LINK)) {
        const target = localTarget(match[1] ?? "");
        if (target === undefined) {
            continue;
        }
        const local = target.split("#", 1)[0] ?? "";
        if (existsSync(join(path, "..", local))) {
            continue;
        }
        if (sourceName !== undefined && unresolved(root, sourceName, local, byName, path, lineNumber, target, broken)) {
            continue;
        }
        broken.push(brokenLink(path, lineNumber, target, "broken source link"));
    }
}
function scanFile(path, root, byName, byFile) {
    const sourceName = byFile.get(resolve(path));
    const broken = [];
    pySplitlines(readFileSync(path, "utf8")).forEach((line, index) => {
        scanLine(path, line, index + 1, root, sourceName, byName, broken);
    });
    return broken;
}
function unresolved(root, sourceName, local, byName, path, line, target, broken) {
    const found = logicalTarget(root, sourceName, local, byName);
    if (!existsSync(found.path)) {
        return false;
    }
    if (found.installed) {
        const name = skillName(found.path, root, byName);
        const entry = byName.get(name);
        if (entry !== undefined) {
            const skillRoot = resolve(root, entry.source_path);
            const rel = relative(skillRoot, resolve(found.path));
            if (!existsSync(join(skillRoot, rel))) {
                broken.push(brokenLink(path, line, target, "broken installed-flat link"));
            }
        }
    }
    return true;
}
export function failures(root, files, catalog) {
    const byName = new Map(catalog.skills.map((entry) => [entry.name, entry]));
    const byFile = new Map(catalog.skills.map((entry) => [resolve(root, entry.source_path, "SKILL.md"), entry.name]));
    return files.flatMap((path) => scanFile(path, root, byName, byFile));
}
export function main(argv, fallback = repoRoot(import.meta.url)) {
    let root = fallback;
    const files = [];
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index];
        if (flag === "--root" && argv[index + 1] !== undefined) {
            root = argv[index + 1] ?? root;
            index += 1;
        }
        else if (flag !== undefined) {
            files.push(flag);
        }
    }
    const resolved = resolve(root);
    const catalog = loadCatalog(resolved);
    const selected = files.length > 0 ? files.map((path) => resolve(path)) : checkedFiles(resolved, catalog);
    const broken = failures(resolved, selected, catalog);
    if (broken.length > 0) {
        process.stderr.write(`${broken.join("\n")}\n`);
        return 1;
    }
    process.stdout.write(`markdown link check passed (${selected.length} files; source + installed-flat)\n`);
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=check-markdown-links.mjs.map