import { existsSync, readdirSync, readFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { pySplitlines } from "./py-text.mjs";
function walkFiles(dir) {
    if (!existsSync(dir)) {
        return [];
    }
    const found = [];
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
        const path = join(dir, entry.name);
        if (entry.isDirectory()) {
            found.push(...walkFiles(path));
        }
        else if (entry.isFile()) {
            found.push(path);
        }
    }
    return found;
}
function posixRelative(from, path) {
    return relative(from, path).split("\\").join("/");
}
function addSidecars(paths, repo, skillDir, entry) {
    const sourceDir = join(repo, entry.source_path);
    for (const sidecar of walkFiles(sourceDir)) {
        if (sidecar.endsWith("/SKILL.md") || sidecar.endsWith("\\SKILL.md")) {
            continue;
        }
        const rel = posixRelative(sourceDir, sidecar);
        paths.add(`${entry.name}/${rel}`);
        if (resolve(sourceDir) === resolve(skillDir)) {
            paths.add(rel);
        }
    }
}
function sidecarPaths(repo, skillDir) {
    const paths = new Set();
    const catalogPath = join(repo, "catalog.json");
    if (existsSync(catalogPath)) {
        const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));
        for (const entry of catalog.skills) {
            addSidecars(paths, repo, skillDir, entry);
        }
    }
    for (const prefix of ["reference", "tests"]) {
        const root = join(repo, prefix);
        for (const path of walkFiles(root)) {
            paths.add(posixRelative(repo, path));
        }
    }
    return paths;
}
function hasUnavailable(text, paths) {
    for (const path of paths) {
        if (text.includes(path)) {
            return true;
        }
    }
    return false;
}
function removeOrphan(output) {
    while (output.length > 0 && output.at(-1) === "") {
        output.pop();
    }
    let start = output.length;
    while (start > 0 && output[start - 1] !== "" && !output[start - 1]?.startsWith("#")) {
        start -= 1;
    }
    if (start < output.length && output.at(-1)?.trimEnd().endsWith(":")) {
        output.splice(start);
    }
}
const LIST_ITEM = /^(\s*)([-+*]|\d+\.)\s+/;
function splitItems(block) {
    const items = [];
    let current = [];
    for (const line of block) {
        if (LIST_ITEM.test(line)) {
            if (current.length > 0) {
                items.push(current);
            }
            current = [line];
        }
        else if (current.length > 0) {
            current.push(line);
        }
        else {
            items.push([line]);
        }
    }
    if (current.length > 0) {
        items.push(current);
    }
    return items;
}
function emitItem(item, ordered, output) {
    const match = LIST_ITEM.exec(item[0] ?? "");
    let next = ordered;
    if (match?.[2]?.endsWith(".")) {
        next += 1;
        item[0] = (item[0] ?? "").replace(/^(\s*)\d+\./, `$1${next}.`);
    }
    output.push(...item);
    return next;
}
function flushBlock(block, output, paths) {
    if (block.length === 0) {
        return;
    }
    if (!block.some((line) => LIST_ITEM.test(line))) {
        if (hasUnavailable(block.join("\n"), paths) && block[0]?.startsWith("```")) {
            removeOrphan(output);
        }
        else if (!hasUnavailable(block.join("\n"), paths)) {
            output.push(...block);
        }
        return;
    }
    let ordered = 0;
    for (const item of splitItems(block)) {
        if (!hasUnavailable(item.join("\n"), paths)) {
            ordered = emitItem(item, ordered, output);
        }
    }
}
function dropEmptyHeadings(output) {
    const cleaned = [];
    output.forEach((line, index) => {
        const heading = /^(#{2,6})\s+/.exec(line);
        if (heading?.[1] !== undefined) {
            const level = heading[1].length;
            const later = output.slice(index + 1);
            const next = later.findIndex((item) => {
                const mark = /^(#{1,6})\s+/.exec(item);
                return mark?.[1] !== undefined && mark[1].length <= level;
            });
            const window = next < 0 ? later : later.slice(0, next);
            if (!window.some((item) => item.trim() !== "" && !/^(#{1,6})\s+/.test(item))) {
                return;
            }
        }
        cleaned.push(line);
    });
    return cleaned;
}
export function skillDescription(path) {
    for (const line of pySplitlines(readFileSync(path, "utf8")).slice(1)) {
        if (line === "---") {
            break;
        }
        if (line.startsWith("description:")) {
            return line.split(":").slice(1).join(":").trim().replace(/^['"]+|['"]+$/g, "");
        }
    }
    return "";
}
function findRepo(skillDir) {
    let repo = skillDir;
    while (resolve(repo, "..") !== repo && !existsSync(join(repo, "catalog.json"))) {
        repo = resolve(repo, "..");
    }
    return repo;
}
function stripFrontmatter(lines) {
    if (lines[0] !== "---") {
        return lines;
    }
    const end = lines.indexOf("---", 1);
    return end >= 0 ? lines.slice(end + 1) : lines;
}
function takeHeading(line, skipLevel) {
    const heading = /^(#{1,6})\s+(.+?)\s*$/.exec(line);
    if (heading?.[1] === undefined || heading[2] === undefined) {
        return undefined;
    }
    const level = heading[1].length;
    const skip = skipLevel !== undefined && level <= skipLevel ? undefined : skipLevel;
    if (heading[2].toLowerCase() === "references") {
        return { skip: level, emit: false };
    }
    return { skip, emit: skip === undefined };
}
function takeLine(line, block, output, paths) {
    if (line.trim()) {
        block.push(line);
        return block;
    }
    flushBlock(block, output, paths);
    if (output.length > 0 && output.at(-1) !== "") {
        output.push("");
    }
    return [];
}
export function flattenedSkillBody(path) {
    const skillDir = resolve(path, "..");
    const paths = sidecarPaths(findRepo(skillDir), skillDir);
    const output = [];
    let block = [];
    let skipLevel;
    for (const line of stripFrontmatter(pySplitlines(readFileSync(path, "utf8")))) {
        const heading = takeHeading(line, skipLevel);
        if (heading !== undefined) {
            flushBlock(block, output, paths);
            block = [];
            skipLevel = heading.skip;
            if (heading.emit) {
                output.push(line);
            }
            continue;
        }
        if (skipLevel !== undefined) {
            continue;
        }
        block = takeLine(line, block, output, paths);
    }
    flushBlock(block, output, paths);
    const cleaned = dropEmptyHeadings(output);
    while (cleaned.length > 0 && cleaned.at(-1) === "") {
        cleaned.pop();
    }
    return cleaned.join("\n");
}
//# sourceMappingURL=flatten-skill.mjs.map