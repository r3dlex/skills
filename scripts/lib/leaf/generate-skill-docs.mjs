import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { loadCatalog } from "./catalog-model.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
const START = "<!-- GENERATED:SKILL-CATALOG:START -->";
const END = "<!-- GENERATED:SKILL-CATALOG:END -->";
function description(path) {
    const match = /^description:\s*['"]?(.*?)['"]?\s*$/m.exec(readFileSync(path, "utf8"));
    return match?.[1]?.replace(/['"]$/g, "") ?? "";
}
function replaceRegion(path, body, check) {
    const region = `${START}\n${body.trimEnd()}\n${END}`;
    const old = existsSync(path) ? readFileSync(path, "utf8") : "";
    const start = old.indexOf(START);
    const end = old.indexOf(END);
    const next = start >= 0 && end >= 0 ? `${old.slice(0, start)}${region}${old.slice(end + END.length)}` : `${old.trimEnd()}${old.trim() ? "\n\n" : ""}${region}\n`;
    if (check) {
        if (next !== old) {
            process.stderr.write(`generated catalog drift: ${path}\n`);
            return false;
        }
        return true;
    }
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, next);
    return true;
}
function catalogRows(root, skills) {
    const rows = ["| Skill | When to use | Lifecycle | Owner phase |", "|---|---|---|---|"];
    for (const entry of [...skills].sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0))) {
        const desc = description(join(root, entry.source_path, "SKILL.md")).replaceAll("|", "\\|");
        rows.push(`| [\`${entry.name}\`](${entry.source_path}/SKILL.md) | ${desc} | \`${entry.lifecycle}\` | \`${entry.owner_phase}\` |`);
    }
    return rows.join("\n");
}
function inventory(root, phases, skills) {
    const lines = [];
    for (const phase of phases) {
        const entries = skills.filter((entry) => entry.owner_phase === phase).sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0));
        if (entries.length === 0) {
            continue;
        }
        lines.push(`## ${phase}`, "");
        for (const entry of entries) {
            const desc = description(join(root, entry.source_path, "SKILL.md")).replaceAll("|", "\\|");
            lines.push(`- **\`${entry.name}\`** — ${desc}`);
        }
        lines.push("");
    }
    return lines.join("\n");
}
function phaseReadme(root, phase, skills) {
    const lines = [`# ${phase}`, "", "| Skill | Applies to phases |", "|---|---|"];
    for (const entry of skills.filter((item) => item.owner_phase === phase).sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0))) {
        lines.push(`| [\`${entry.name}\`](../${entry.source_path}/SKILL.md) | ${entry.applies_to_phases.join(", ")} |`);
    }
    return lines.join("\n");
}
export function main(argv, root = repoRoot(import.meta.url)) {
    const check = argv.includes("--check");
    const catalog = loadCatalog(root);
    let ok = replaceRegion(join(root, "README.md"), catalogRows(root, catalog.skills), check);
    ok = replaceRegion(join(root, "AGENTS.md"), catalogRows(root, catalog.skills), check) && ok;
    const router = join(root, "01-discover-decide", "ask-ai-catapult", "CATALOG.md");
    if (existsSync(dirname(router))) {
        ok = replaceRegion(router, inventory(root, catalog.phases, catalog.skills), check) && ok;
    }
    for (const phase of catalog.phases) {
        ok = replaceRegion(join(root, phase, "README.md"), phaseReadme(root, phase, catalog.skills), check) && ok;
    }
    return ok ? 0 : 1;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=generate-skill-docs.mjs.map