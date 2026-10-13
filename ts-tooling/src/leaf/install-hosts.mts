import { cpSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { catalogRows, failCatalog, parseCatalogArgs, writeProjection } from "./catalog-install.mjs";
import { flattenedSkillBody, skillDescription } from "./flatten-skill.mjs";
import { repoRoot } from "./repo-root.mjs";

function skillsDir(): string {
  return process.env.SKILLS_CATALOG_ROOT ?? repoRoot(import.meta.url);
}

function eachRow(rows: string, visit: (name: string, source: string) => void): void {
  for (const line of rows.split("\n")) {
    if (line === "") {
      continue;
    }
    const [name, source] = line.split("\t");
    if (name !== undefined && source !== undefined) {
      visit(name, source);
    }
  }
}

function copySkill(root: string, source: string, dest: string, name: string): void {
  rmSync(join(dest, name), { recursive: true, force: true });
  cpSync(join(root, source), join(dest, name), { recursive: true });
  process.stdout.write(`  ✓ ${name}\n`);
}

function installRows(root: string, host: string, includes: readonly string[], skill?: string): { rows: string; projectionText: string } | number {
  try {
    return catalogRows(root, host, includes, skill);
  } catch (error) {
    return failCatalog(error);
  }
}

function scriptArgv0(): string {
  return process.env.SHIM_ARGV0 ?? "";
}

function requiredHome(line: number): string | number {
  const home = process.env.HOME;
  if (home !== undefined) {
    return home;
  }
  process.stderr.write(`${scriptArgv0()}: line ${line}: HOME: unbound variable\n`);
  return 1;
}

function usage(tail: string): number {
  process.stderr.write(`Usage: ${scriptArgv0()} ${tail}\n`);
  return 1;
}

export function installClaude(argv: readonly string[]): number {
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const scope = parsed.rest[0] ?? "--user";
  if (parsed.rest.length > 1 || !["--user", "--project", "--all"].includes(scope)) {
    return usage("[--user | --project | --all] [--include-lifecycle <value>]");
  }
  let home = "";
  if (scope !== "--project") {
    const required = requiredHome(7);
    if (typeof required === "number") {
      return required;
    }
    home = required;
  }
  const root = skillsDir();
  const rows = installRows(root, "claude-code", parsed.includes);
  if (typeof rows === "number") {
    return rows;
  }
  for (const dest of claudeTargets(root, scope, home)) {
    writeProjection(dest, "catalog.json", rows.projectionText);
    eachRow(rows.rows, (name, source) => copySkill(root, source, dest, name));
  }
  return 0;
}

function claudeTargets(root: string, scope: string, home: string): string[] {
  const project = join(root, ".omc/skills");
  if (scope === "--project") {
    return [project];
  }
  const user = join(home, ".claude/skills/omc-learned");
  return scope === "--all" ? [user, project] : [user];
}

export function installCodex(argv: readonly string[]): number {
  const home = requiredHome(3);
  if (typeof home === "number") {
    return home;
  }
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const flag = parsed.rest[0];
  if ((flag !== undefined && flag !== "--skill" && flag !== "--all") || (flag === "--skill" && parsed.rest.length !== 2)) {
    return usage("[--skill <name> | --all] [--include-lifecycle <value>]");
  }
  const root = skillsDir();
  const skill = flag === "--skill" ? parsed.rest[1] : undefined;
  const rows = installRows(root, "codex", parsed.includes, skill);
  if (typeof rows === "number") {
    return rows;
  }
  const dest = join(home, ".codex/skills");
  writeProjection(dest, "catalog.json", rows.projectionText);
  eachRow(rows.rows, (name, source) => copySkill(root, source, dest, name));
  return 0;
}

export function installGemini(argv: readonly string[]): number {
  const home = requiredHome(3);
  if (typeof home === "number") {
    return home;
  }
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const flag = parsed.rest[0] ?? "";
  if (flag !== "" && flag !== "--install" && flag !== "--link" && flag !== "--all") {
    return usage("[--install | --link | --all] [--include-lifecycle <value>]");
  }
  const root = skillsDir();
  const rows = installRows(root, "gemini", parsed.includes);
  if (typeof rows === "number") {
    return rows;
  }
  const dest = join(home, ".gemini/skills");
  writeProjection(dest, "catalog.json", rows.projectionText);
  eachRow(rows.rows, (name, source) => writeFlat(root, dest, name, source, "gemini"));
  return 0;
}

export function installAuggie(argv: readonly string[]): number {
  const home = requiredHome(3);
  if (typeof home === "number") {
    return home;
  }
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const flag = parsed.rest[0] ?? "";
  if (flag !== "" && flag !== "--rules" && flag !== "--all") {
    return usage("[--rules | --all] [--include-lifecycle <value>]");
  }
  const root = skillsDir();
  const rows = installRows(root, "auggie", parsed.includes);
  if (typeof rows === "number") {
    return rows;
  }
  const dest = join(home, ".auggie/rules");
  writeProjection(dest, "catalog.json", rows.projectionText);
  eachRow(rows.rows, (name, source) => writeFlat(root, dest, name, source, "auggie"));
  return 0;
}

function writeFlat(root: string, dest: string, name: string, source: string, host: string): void {
  const skill = join(root, source, "SKILL.md");
  const body = host === "auggie"
    ? ["---", `name: ${name}`, `description: ${skillDescription(skill)}`, "platform: auggie", "---", "", flattenedSkillBody(skill)].join("\n")
    : [`# ${name}`, "", skillDescription(skill), "", "---", "", flattenedSkillBody(skill)].join("\n");
  mkdirSync(dest, { recursive: true });
  writeFileSync(join(dest, `${name}.md`), `${body}\n`);
  process.stdout.write(`  ✓ ${name}\n`);
}

function copilotTarget(rest: readonly string[], root: string): { mode: string; target: string } | number {
  let mode = rest[0] ?? "--consolidated";
  let target = rest[1] ?? join(root, "..");
  if (mode === "--repo") {
    if (rest.length !== 2) {
      return 1;
    }
    mode = "--consolidated";
    target = rest[1] ?? target;
  }
  if (!["--consolidated", "--per-skill", "--all"].includes(mode)) {
    return usage("[--consolidated | --per-skill | --all | --repo <path>] [--include-lifecycle <value>]");
  }
  return { mode, target };
}

export function installCopilot(argv: readonly string[]): number {
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    return parsed;
  }
  const root = skillsDir();
  const located = copilotTarget(parsed.rest, root);
  if (typeof located === "number") {
    return located;
  }
  const rows = installRows(root, "copilot", parsed.includes);
  if (typeof rows === "number") {
    return rows;
  }
  writeProjection(join(located.target, ".github"), "skills-catalog.json", rows.projectionText);
  writeCopilot(root, located.target, located.mode, rows.rows);
  return 0;
}

function writeCopilot(root: string, target: string, mode: string, rows: string): void {
  if (mode === "--consolidated" || mode === "--all") {
    writeConsolidated(root, target, rows);
  }
  if (mode === "--per-skill" || mode === "--all") {
    writePerSkill(root, target, rows);
  }
}

function writeConsolidated(root: string, target: string, rows: string): void {
  const lines = [`# Copilot Instructions — ${basename(target)}`, "", "This file contains agent-facing instructions synthesized from the skills library.", ""];
  for (const line of rows.split("\n").filter((item) => item !== "")) {
    const [name, source] = line.split("\t");
    if (name === undefined || source === undefined) {
      continue;
    }
    lines.push(`## ${name}`, "");
    for (const body of flattenedSkillBody(join(root, source, "SKILL.md")).split("\n")) {
      lines.push(`  ${body}`);
    }
    lines.push("");
  }
  writeFileSync(join(target, ".github/copilot-instructions.md"), `${lines.join("\n")}\n`);
}

function writePerSkill(root: string, target: string, rows: string): void {
  const out = join(target, ".github/copilot-instructions");
  mkdirSync(out, { recursive: true });
  for (const line of rows.split("\n").filter((item) => item !== "")) {
    const [name, source] = line.split("\t");
    if (name === undefined || source === undefined) {
      continue;
    }
    const skill = join(root, source, "SKILL.md");
    writeFileSync(join(out, `${name}.md`), `${[`# ${name}`, "", skillDescription(skill), "", flattenedSkillBody(skill)].join("\n")}\n`);
  }
}
