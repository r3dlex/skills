import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { repoRoot } from "./repo-root.mjs";
assertNodeVersion();
function blank() {
    return {
        mode: "", repo: ".", project: "", tagline: "", why: "", archetype: "", primary: "", mental: "",
        install: "", first: "", evidence: "", requirements: "", update: "", visibility: "private",
        license: "", badges: "", out: "", sourceSha: "", force: false,
    };
}
function consume(args, flag, value) {
    if (flag === "--force") {
        args.force = true;
        return 0;
    }
    if (flag === "-h" || flag === "--help") {
        process.stdout.write("Usage: readme-generate.sh --mode template|augment|audit-only [options]\n");
        return 0;
    }
    if (value === undefined) {
        process.stderr.write(`${flag} requires a value\n`);
        return 1;
    }
    if (!assign(args, flag, value)) {
        process.stderr.write(`unknown arg: ${flag}\n`);
        return 1;
    }
    return undefined;
}
function parse(argv) {
    const args = blank();
    for (let index = 0; index < argv.length; index += 1) {
        const flag = argv[index] ?? "";
        const consumed = consume(args, flag, argv[index + 1]);
        if (consumed === 1) {
            return 1;
        }
        if (flag !== "--force") {
            index += 1;
        }
        if (consumed === 0 && (flag === "-h" || flag === "--help")) {
            return 0;
        }
    }
    return finishParse(args);
}
function finishParse(args) {
    if (args.mode === "") {
        process.stderr.write("--mode required\n");
        return 1;
    }
    if (args.visibility !== "public" && args.visibility !== "private") {
        process.stderr.write("--visibility must be public or private\n");
        return 1;
    }
    if (args.out === "") {
        args.out = join(args.repo, "README.md");
    }
    return args;
}
function assign(args, flag, value) {
    const fields = {
        "--mode": "mode", "--repo": "repo", "--project": "project", "--tagline": "tagline", "--why": "why",
        "--archetype": "archetype", "--primary-surface": "primary", "--mental-model": "mental",
        "--install-command": "install", "--first-success-command": "first", "--success-evidence": "evidence",
        "--requirements": "requirements", "--update-command": "update", "--visibility": "visibility",
        "--license": "license", "--badges": "badges", "--out": "out", "--source-sha": "sourceSha",
    };
    const key = fields[flag];
    if (key === undefined || key === "force") {
        return false;
    }
    args[key] = value;
    return true;
}
function digestOrFail(path) {
    try {
        return sha256(path);
    }
    catch (error) {
        process.stderr.write(`${error instanceof Error ? error.message : "SHA-256 requires sha256sum or shasum"}\n`);
        return 2;
    }
}
function sha256(path) {
    const sha256sum = spawnSync("sha256sum", [path], { encoding: "utf8" });
    if (sha256sum.status === 0) {
        return sha256sum.stdout.split(/\s/)[0] ?? "";
    }
    const shasum = spawnSync("shasum", ["-a", "256", path], { encoding: "utf8" });
    if (shasum.status === 0) {
        return shasum.stdout.split(/\s/)[0] ?? "";
    }
    throw new Error("SHA-256 requires sha256sum or shasum");
}
function templatePath(root) {
    const here = dirname(fileURLToPath(import.meta.url));
    for (const relative of ["../assets/readme/template.md", "../../assets/readme/template.md"]) {
        const candidate = join(here, relative);
        if (existsSync(candidate)) {
            return candidate;
        }
    }
    return join(root, "03-configure-generate/ai-catapult-init/assets/readme/template.md");
}
function bashCapture(value) {
    return value.replace(/\n+$/, "");
}
function resolvedLicense(args) {
    return args.license !== "" ? args.license : detectLicense(args.repo);
}
function render(args, root) {
    const body = readFileSync(templatePath(root), "utf8");
    const license = resolvedLicense(args);
    const replacements = {
        "@@PROJECT_NAME@@": args.project,
        "@@PROJECT_TAGLINE@@": args.tagline,
        "@@BADGES_BLOCK@@": args.badges === "license" && license !== ""
            ? `[![License: ${license}](https://img.shields.io/badge/license-${license}-blue)](LICENSE)`
            : "",
        "@@INSTALL_COMMAND@@": args.install,
        "@@FIRST_SUCCESS_COMMAND@@": args.first,
        "@@SUCCESS_EVIDENCE@@": args.evidence,
        "@@REQUIREMENTS_SECTION@@": args.requirements === "" ? "" : `## Requirements\n\n- ${args.requirements}`,
        "@@WHY_SECTION@@": `## Why\n\n${args.why}`,
        "@@ARCHETYPE_SECTION@@": bashCapture(archetype(args)),
        "@@UPDATE_SECTION@@": args.update === "" ? "" : `## Update\n\n\`\`\`sh\n${args.update}\n\`\`\``,
        "@@COMMUNITY_SECTION@@": existsSync(join(args.repo, "CONTRIBUTING.md"))
            ? "## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to propose changes or report repository-specific problems."
            : "",
        "@@LICENSE_SECTION@@": license === "" ? "" : `## License\n\n${license} — see [LICENSE](LICENSE).`,
        "@@GOVERNANCE_SECTION@@": bashCapture(governance(args.repo)),
    };
    let rendered = body;
    for (const [needle, value] of Object.entries(replacements)) {
        rendered = rendered.split(needle).join(value);
    }
    return rendered.endsWith("\n") ? rendered : `${rendered}\n`;
}
function governance(repo) {
    const links = [];
    if (existsSync(join(repo, "AGENTS.md"))) {
        links.push("[AGENTS.md](AGENTS.md)");
    }
    else if (existsSync(join(repo, "CLAUDE.md"))) {
        links.push("[CLAUDE.md](CLAUDE.md)");
    }
    if (existsSync(join(repo, "CONTRIBUTING.md"))) {
        links.push("[CONTRIBUTING.md](CONTRIBUTING.md)");
    }
    if (existsSync(join(repo, "docs/architecture/adr"))) {
        links.push("[docs/architecture/adr/](docs/architecture/adr/)");
    }
    if (existsSync(join(repo, "docs/specifications"))) {
        links.push("[docs/specifications/](docs/specifications/)");
    }
    else if (existsSync(join(repo, "docs/specs"))) {
        links.push("[docs/specs/](docs/specs/)");
    }
    if (existsSync(join(repo, ".ai/traceability"))) {
        links.push("[.ai/traceability/](.ai/traceability/)");
    }
    if (links.length === 0) {
        return "";
    }
    return `<!-- AI-SDLC:start -->\nRepository governance and traceability: see ${links.join(", ")}.\n<!-- AI-SDLC:end -->\n`;
}
function archetype(args) {
    if (args.archetype === "cli-tool") {
        return `## How it works\n\n**Primary command surface:** ${args.primary}\n\n**Mental model:** ${args.mental}\n\n1. Install the CLI with the recommended command.\n2. Run the documented command against one target.\n3. Confirm the observable result before using additional commands.\n`;
    }
    return `## How it works\n\n**Skill discovery surface:** ${args.primary}\n\n**Mental model:** ${args.mental}\n\n1. Install the catalog into the supported agent host.\n2. Let the host discover skill metadata from the documented surface.\n3. Invoke one matching skill and confirm the observable result.\n`;
}
function pushMissing(missing, ok, label) {
    if (!ok) {
        missing.push(label);
    }
}
function missingInputs(args) {
    const missing = [];
    pushMissing(missing, args.project !== "", "--project");
    pushMissing(missing, args.tagline !== "", "--tagline");
    pushMissing(missing, args.why !== "" && args.why !== args.tagline, "--why distinct from --tagline");
    pushMissing(missing, args.archetype === "cli-tool" || args.archetype === "skill-catalog", "--archetype cli-tool|skill-catalog");
    pushMissing(missing, args.primary !== "", "--primary-surface");
    pushMissing(missing, args.mental !== "", "--mental-model");
    pushMissing(missing, args.install !== "" && !args.install.trimStart().startsWith("#"), "--install-command with an executable command");
    pushMissing(missing, args.first !== "" && !args.first.trimStart().startsWith("#"), "--first-success-command with an executable command");
    pushMissing(missing, args.evidence !== "", "--success-evidence with observable output or artifact");
    return missing;
}
export function main(argv, root = repoRoot(import.meta.url)) {
    const parsed = parse(argv);
    if (typeof parsed === "number") {
        return parsed;
    }
    parsed.repo = resolve(parsed.repo === "." ? process.cwd() : parsed.repo);
    if (!parsed.out.startsWith("/")) {
        parsed.out = resolve(parsed.repo, parsed.out);
    }
    if (parsed.mode !== "template" && parsed.mode !== "augment" && parsed.mode !== "audit-only") {
        process.stderr.write(`unknown --mode: ${parsed.mode}\n`);
        return 1;
    }
    return dispatch(parsed, root);
}
function readmeStamp() {
    const head = new Date().toISOString().replace(/\.\d+Z$/, "Z").replaceAll(":", "-");
    return `${head}-${process.pid}`;
}
function sourceSections(text) {
    const sections = [];
    for (const line of text.split("\n")) {
        if (line.startsWith("# ") || line.startsWith("## ")) {
            sections.push(line.replace(/^#+/, "").trim());
        }
    }
    return sections;
}
function emitAudit(src, repo, spec) {
    const stamp = readmeStamp();
    const backupDir = join(repo, ".ai/drift/readme-backups");
    mkdirSync(backupDir, { recursive: true });
    const manifest = join(backupDir, `audit-${stamp}.json`);
    let sourceSha = "";
    let backup = "";
    let content = Buffer.alloc(0);
    if (existsSync(src)) {
        content = readFileSync(src);
        sourceSha = sha256(src);
        backup = join(backupDir, `README-${stamp}.bak`);
        copyFileSync(src, backup);
    }
    let newlines = 0;
    for (const byte of content) {
        if (byte === 0x0a) {
            newlines += 1;
        }
    }
    writeFileSync(manifest, `${JSON.stringify({
        timestamp: stamp,
        source_path: src,
        source_sha256: sourceSha,
        source_size: content.length,
        source_lines: newlines,
        source_sections: sourceSections(content.toString("utf8")),
        mode: spec.mode,
        reason: spec.reason,
        visibility: spec.visibility,
        planned_additions: spec.additions,
        planned_modifications: [],
        planned_deletions: [],
        user_response: spec.userResponse,
        backup_path: backup,
    }, null, 2)}\n`);
    return manifest;
}
function dispatch(parsed, root) {
    if (parsed.mode === "audit-only") {
        process.stdout.write(`mode: ${sparse(parsed.out) ? "template (sparse)" : "augment (existing)"}\n`);
        const manifest = emitAudit(parsed.out, parsed.repo, {
            mode: "audit-only",
            reason: "manual",
            additions: [],
            userResponse: "audit-only",
            visibility: parsed.visibility,
        });
        process.stdout.write(`${manifest}\n`);
        process.stdout.write(`ok: ${parsed.mode} ${parsed.out}\n`);
        return 0;
    }
    const missing = missingInputs(parsed);
    if (missing.length > 0) {
        process.stderr.write(`missing canonical README input: ${missing.join(", ")}\n`);
        return 1;
    }
    const licensed = verifyLicense(parsed);
    if (licensed !== 0) {
        return licensed;
    }
    if (parsed.mode === "template") {
        return writeTemplate(parsed, root);
    }
    return augment(parsed);
}
function detectLicense(repo) {
    const file = join(repo, "LICENSE");
    if (!existsSync(file)) {
        return "";
    }
    const text = readFileSync(file, "utf8");
    if (/Apache License, Version 2\.0|Apache License.*Version 2\.0/i.test(text)) {
        return "Apache-2.0";
    }
    if (text.includes("MIT License")) {
        return "MIT";
    }
    if (/Redistribution and use in source and binary forms/i.test(text) && /Neither the name/i.test(text)) {
        return "BSD-3-Clause";
    }
    if (/Redistribution and use in source and binary forms/i.test(text)) {
        return "BSD-2-Clause";
    }
    return "";
}
function verifyLicense(args) {
    if (args.license === "") {
        return 0;
    }
    const detected = detectLicense(args.repo);
    if (!existsSync(join(args.repo, "LICENSE")) || detected === "" || args.license !== detected) {
        process.stderr.write(`proof-signal guard: supplied license '${args.license}' cannot be verified from a recognized LICENSE file\n`);
        return 3;
    }
    return 0;
}
function sparse(path) {
    if (!existsSync(path)) {
        return true;
    }
    const text = readFileSync(path, "utf8");
    if (Buffer.byteLength(text) < 600) {
        return true;
    }
    if (!/^##\s*(quick start|features|installation|usage|why|license|community)/im.test(text)) {
        return true;
    }
    return /^(WIP|TODO|Coming soon|TBD)\s*$/im.test(text);
}
function guard(path, visibility) {
    if (!existsSync(path)) {
        return 0;
    }
    const text = readFileSync(path, "utf8");
    if (/@@[A-Z_]+@@|\{\{[^}]+\}\}|\[\[[^\]]+\]\]|<(your|insert|replace)[^>]*>|content to be filled in|(^|\s)(TODO|TBD|coming soon)(\s|[.!]|$)|shields\.io\/badge\/.*-fake|CI-passing|release-latest|coverage-100%25|downloads-monthly|example\.com\/(badge|release|download)/i.test(text)) {
        process.stderr.write("proof-signal guard: unresolved content or invented claim detected\n");
        return 3;
    }
    if (visibility === "public" && /(internal-only|do-not-share|private-(repo|workflow))/i.test(text)) {
        process.stderr.write("proof-signal guard: private/internal marker in public README\n");
        return 3;
    }
    if (visibility === "private" && /star[- ]history|public[- ]contributors|downloads/i.test(text)) {
        process.stderr.write("proof-signal guard: public proof signal in private README\n");
        return 3;
    }
    return 0;
}
function augmentSections(args, text) {
    const additions = [];
    if (!/^##\s+Why/im.test(text)) {
        additions.push(`## Why\n\n${args.why}`);
    }
    if (!/^##\s+(How it works|Workflows|Mental model)/im.test(text)) {
        additions.push(archetype(args).trimEnd());
    }
    if (args.requirements !== "" && !/^##\s+Requirements/im.test(text)) {
        additions.push(`## Requirements\n\n- ${args.requirements}`);
    }
    if (args.update !== "" && !/^##\s+Update/im.test(text)) {
        additions.push(`## Update\n\n\`\`\`sh\n${args.update}\n\`\`\``);
    }
    const license = resolvedLicense(args);
    if (license !== "" && !/^##\s+License/im.test(text)) {
        additions.push(`## License\n\n${license} — see [LICENSE](LICENSE).`);
    }
    return additions;
}
const LICENSE_CLAIMS = [
    ["Apache-2.0", /Apache(?:[ _-]+License)?[ _-]*2[._]0|Apache License,?\s+Version 2\.0/i],
    ["MIT", /(?<![A-Za-z0-9])MIT(?:[ _-]+License)?(?![A-Za-z0-9])/i],
    ["BSD-3-Clause", /BSD[ _-]+3(?:[ _-]+|--+)Clause/i],
    ["BSD-2-Clause", /BSD[ _-]+2(?:[ _-]+|--+)Clause/i],
    ["AGPL-3.0-Unknown", /AGPL(?:[_ -]*v?3(?:[._-]0)?)|GNU Affero General Public License,?\s*(?:version\s*)?3/i],
    ["GPL-3.0-Unknown", /(?<![A-Za-z0-9])GPL(?:[_ -]*v?3(?:[._-]0)?)|GNU General Public License,?\s*(?:version\s*)?3/i],
    ["GPL-2.0-Unknown", /(?<![A-Za-z0-9])GPL(?:[_ -]*v?2(?:[._-]0)?)|GNU General Public License,?\s*(?:version\s*)?2/i],
];
function licenseClaims(text) {
    return LICENSE_CLAIMS.filter(([, pattern]) => pattern.test(text)).map(([id]) => id);
}
function licenseGuard(args, text) {
    const claims = licenseClaims(text);
    const hasClaim = claims.length > 0 || /^##\s+License(\s|$)/im.test(text) || /img\.shields\.io\/badge\/[Ll]icense/i.test(text);
    if (!hasClaim) {
        return 0;
    }
    if (!existsSync(join(args.repo, "LICENSE"))) {
        process.stderr.write("proof-signal guard: README license claim cannot be verified because LICENSE is missing\n");
        return 3;
    }
    const verified = detectLicense(args.repo);
    if (claims.some((claim) => claim !== verified)) {
        process.stderr.write("proof-signal guard: README license claim conflicts with or overstates the detected LICENSE file\n");
        return 3;
    }
    return 0;
}
function fencedCommands(text) {
    const commands = new Set();
    for (const block of text.matchAll(/^```([^\n]*)\n([\s\S]*?)^```\s*$/gm)) {
        const language = (block[1] ?? "").trim().split(/\s/)[0]?.toLowerCase() ?? "";
        if (!["sh", "bash", "shell", "zsh"].includes(language)) {
            continue;
        }
        for (const line of (block[2] ?? "").split("\n")) {
            if (line.trim() !== "") {
                commands.add(line.trim());
            }
        }
    }
    return commands;
}
function coherent(text, args) {
    const headings = new Set(["quick start", "getting started", "installation", "installation and first success", "setup and first success"]);
    const hasHeading = [...text.matchAll(/^##\s+(.+?)\s*$/gm)].some((match) => headings.has((match[1] ?? "").toLowerCase()));
    const commands = fencedCommands(text);
    return hasHeading && commands.has(args.install) && commands.has(args.first) && text.includes(args.evidence);
}
function augment(args) {
    if (sparse(args.out)) {
        process.stderr.write("refusing to augment sparse README; use --mode template\n");
        return 1;
    }
    const text = readFileSync(args.out, "utf8");
    const licensed = licenseGuard(args, text);
    if (licensed !== 0) {
        return licensed;
    }
    const additions = augmentSections(args, text);
    if (!coherent(text, args)) {
        additions.unshift(`## Setup and first success\n\n\`\`\`sh\n${args.install}\n${args.first}\n\`\`\`\n\n**Expected result:** ${args.evidence}`);
    }
    if (existsSync(join(args.repo, "CONTRIBUTING.md")) && !/^##\s+Community/im.test(text)) {
        additions.push("## Community\n\nSee [CONTRIBUTING.md](CONTRIBUTING.md) to contribute.");
    }
    if (!text.includes("<!-- AI-SDLC:start -->")) {
        const block = governance(args.repo).trimEnd();
        if (block !== "") {
            additions.push(block);
        }
    }
    let next = text;
    for (const section of additions) {
        next += `\n\n${bashCapture(section)}\n`;
    }
    const manifest = emitAudit(args.out, args.repo, {
        mode: "augment",
        reason: "missing canonical onboarding",
        additions: ["complete onboarding sections"],
        userResponse: "source-sha-confirmed",
        visibility: args.visibility,
    });
    process.stderr.write(`audit manifest: ${manifest}\n`);
    writeFileSync(args.out, next);
    const guarded = guard(args.out, args.visibility);
    if (guarded !== 0) {
        writeFileSync(args.out, text);
        return guarded;
    }
    process.stdout.write(`ok: augment ${args.out}\n`);
    return 0;
}
function writeTemplate(parsed, root) {
    if (existsSync(parsed.out) && !parsed.force) {
        process.stderr.write(`refusing to overwrite existing README at ${parsed.out} without --force\n`);
        return 1;
    }
    const candidate = join(mkdtempSync(join(tmpdir(), "readme-")), "README.md");
    writeFileSync(candidate, render(parsed, root));
    mkdirSync(dirname(parsed.out), { recursive: true });
    if (existsSync(parsed.out)) {
        const current = digestOrFail(parsed.out);
        if (typeof current === "number") {
            return current;
        }
        if (current !== parsed.sourceSha) {
            process.stderr.write("guarded write rejected: README no longer matches --source-sha\n");
            return 2;
        }
        const manifest = emitAudit(parsed.out, parsed.repo, {
            mode: "template-force",
            reason: "operator-requested canonical replacement",
            additions: ["canonical README"],
            userResponse: "source-sha-confirmed",
            visibility: parsed.visibility,
        });
        process.stderr.write(`audit manifest: ${manifest}\n`);
    }
    const guarded = guard(candidate, parsed.visibility);
    if (guarded !== 0) {
        return guarded;
    }
    chmodSync(candidate, 0o644);
    renameSync(candidate, parsed.out);
    process.stdout.write(`ok: template ${parsed.out}\n`);
    return 0;
}
if (invokedDirectly(import.meta.url)) {
    process.exit(main(process.argv.slice(2)));
}
//# sourceMappingURL=readme-generate.mjs.map