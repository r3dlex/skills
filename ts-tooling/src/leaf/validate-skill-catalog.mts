import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { loadCatalog } from "./catalog-model.mjs";
import { frontmatter } from "./frontmatter.mjs";
import { pyRepr } from "./py-repr.mjs";

assertNodeVersion();

const TARGET_DESCRIPTION_CHARS = 160;
const MAX_DESCRIPTION_CHARS = 180;
const TARGET_BODY_LINES = 100;
const MAX_BODY_LINES = 180;
const REQUIRED_CROSS_SKILL: Record<string, readonly string[]> = {
  "ai-catapult-init": ["workflow", "traceability", "cascade", "catalog"],
  "setup-skills": ["tracker"],
  "to-prd": ["PRD"],
  "to-issues": ["issue"],
  triage: ["issue"],
  "publish-semver": ["release"],
  "write-a-skill": ["skill"],
  "write-agent-docs": ["agent-facing"],
};

interface SkillAudit {
  name: string;
  path: string;
  description_chars: number;
  description_status: string;
  body_lines: number;
  body_status: string;
  cross_skill_links: string;
  ai_sdlc_compatible: boolean;
  status: string;
}

interface AuditPayload {
  schema_version: string;
  policy: Record<string, string | number>;
  skill_count: number;
  warnings: string[];
  failures: string[];
  skills: SkillAudit[];
  status: string;
}

function loadExceptions(root: string, filename: string, label: string): Record<string, Record<string, unknown>> {
  const path = join(root, ".ai/skills", filename);
  if (!existsSync(path)) {
    return {};
  }
  const payload = JSON.parse(readFileSync(path, "utf8")) as { schema_version?: string; exceptions?: Array<Record<string, unknown>> };
  if (payload.schema_version !== "1.0") {
    throw new Error(`${label} exceptions schema_version must be 1.0`);
  }
  if (!Array.isArray(payload.exceptions)) {
    throw new Error(`${label} exceptions must be a list`);
  }
  const bySkill: Record<string, Record<string, unknown>> = {};
  for (const entry of payload.exceptions) {
    for (const field of ["skill", "owner", "reason", "expires"]) {
      if (!entry[field]) {
        throw new Error(`${label} exception missing ${field}`);
      }
    }
    bySkill[String(entry.skill)] = entry;
  }
  return bySkill;
}

function descriptionStatus(length: number, exception: boolean): string {
  if (length <= TARGET_DESCRIPTION_CHARS) {
    return "target";
  }
  return exception && length <= MAX_DESCRIPTION_CHARS ? "exception" : "over-target";
}

function applyLength(status: string, failures: string[], warnings: string[], rel: string, length: number, exception: boolean): { status: string; bodyStatus: string } {
  if (length > MAX_BODY_LINES) {
    failures.push(`${rel}: body length ${length} exceeds maximum ${MAX_BODY_LINES}`);
    return { status: "fail", bodyStatus: "over-maximum" };
  }
  if (length > TARGET_BODY_LINES && exception) {
    warnings.push(`${rel}: body length ${length} uses audited exception above target ${TARGET_BODY_LINES}`);
    return { status, bodyStatus: "exception" };
  }
  if (length > TARGET_BODY_LINES) {
    failures.push(`${rel}: body length ${length} exceeds target ${TARGET_BODY_LINES} without audited exception`);
    return { status: "fail", bodyStatus: "over-target" };
  }
  return { status, bodyStatus: "target" };
}

function crossSkill(name: string, desc: string, body: readonly string[], rel: string, failures: string[]): { status: string; cross: string } {
  let cross = "not-required";
  let failed = false;
  const lowered = body.join("\n").toLowerCase();
  for (const required of REQUIRED_CROSS_SKILL[name] ?? []) {
    if (!lowered.includes(required.toLowerCase()) && !desc.toLowerCase().includes(required.toLowerCase())) {
      failed = true;
      failures.push(`${rel}: missing cross-skill/workflow cue ${pyRepr(required)}`);
    } else {
      cross = "present";
    }
  }
  return { status: failed ? "fail" : "pass", cross };
}

function descriptionFailure(rel: string, desc: string, exception: boolean, failures: string[], warnings: string[]): string {
  if (desc.length > MAX_DESCRIPTION_CHARS) {
    failures.push(`${rel}: description length ${desc.length} exceeds maximum ${MAX_DESCRIPTION_CHARS}`);
    return "fail";
  }
  if (desc.length > TARGET_DESCRIPTION_CHARS && exception) {
    warnings.push(`${rel}: description length ${desc.length} uses audited exception above target ${TARGET_DESCRIPTION_CHARS}`);
    return "pass";
  }
  if (desc.length > TARGET_DESCRIPTION_CHARS) {
    failures.push(`${rel}: description length ${desc.length} exceeds target ${TARGET_DESCRIPTION_CHARS} without audited exception`);
    return "fail";
  }
  return "pass";
}

function auditSkill(root: string, skillPath: string, descriptionExceptions: Record<string, unknown>, bodyExceptions: Record<string, unknown>, failures: string[], warnings: string[]): SkillAudit {
  const rel = relative(root, skillPath);
  const parsed = frontmatter(skillPath);
  const name = parsed.meta.name ?? "";
  const desc = parsed.meta.description ?? "";
  if (!name) {
    failures.push(`${rel}: missing name`);
  }
  if (!desc) {
    failures.push(`${rel}: missing description`);
  }
  const status = descriptionFailure(rel, desc, Boolean(descriptionExceptions[name]), failures, warnings);
  const body = applyLength(status, failures, warnings, rel, parsed.body.length, Boolean(bodyExceptions[name]));
  const links = crossSkill(name, desc, parsed.body, rel, failures);
  return {
    name,
    path: rel,
    description_chars: desc.length,
    description_status: descriptionStatus(desc.length, Boolean(descriptionExceptions[name])),
    body_lines: parsed.body.length,
    body_status: body.bodyStatus,
    cross_skill_links: links.cross,
    ai_sdlc_compatible: true,
    status: body.status === "fail" || links.status === "fail" ? "fail" : status,
  };
}

export function audit(root: string): AuditPayload {
  const descriptionExceptions = loadExceptions(root, "description-exceptions.json", "description");
  const bodyExceptions = loadExceptions(root, "body-line-exceptions.json", "body-line");
  const failures: string[] = [];
  const warnings: string[] = [];
  const skills = loadCatalog(root).skills
    .slice()
    .sort((left, right) => (left.name < right.name ? -1 : left.name > right.name ? 1 : 0))
    .map((entry) => auditSkill(root, join(root, entry.source_path, "SKILL.md"), descriptionExceptions, bodyExceptions, failures, warnings));
  return {
    schema_version: "1.0",
    policy: {
      target_description_chars: TARGET_DESCRIPTION_CHARS,
      max_description_chars: MAX_DESCRIPTION_CHARS,
      target_body_lines: TARGET_BODY_LINES,
      max_body_lines_with_exception: MAX_BODY_LINES,
      catalog_scope: "first-class skill directories plus ai-sdlc-init shim; excludes .agents, reference fixtures, golden outputs, hidden/runtime dirs",
    },
    skill_count: skills.length,
    warnings,
    failures,
    skills,
    status: failures.length > 0 ? "fail" : "pass",
  };
}

function compareCommitted(root: string, payload: AuditPayload): void {
  const path = join(root, ".ai/skills/catalog-audit.json");
  if (!existsSync(path)) {
    return;
  }
  const committed = JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  for (const key of ["schema_version", "policy", "skill_count", "skills", "status"] as const) {
    if (JSON.stringify(committed[key]) !== JSON.stringify(payload[key])) {
      throw new Error(`catalog audit artifact drift at ${key}`);
    }
  }
}

function writeArtifacts(root: string, payload: AuditPayload): void {
  const out = join(root, ".ai/skills");
  mkdirSync(out, { recursive: true });
  for (const filename of ["description-exceptions.json", "body-line-exceptions.json"]) {
    const exc = join(out, filename);
    if (!existsSync(exc)) {
      writeFileSync(exc, `${JSON.stringify({ schema_version: "1.0", exceptions: [] }, null, 2)}\n`);
    }
  }
  writeFileSync(join(out, "catalog-audit.json"), `${JSON.stringify(payload, null, 2)}\n`);
  const lines = [
    "# Skill Modernization Report",
    "",
    payload.status === "pass" ? "status: `pass`" : "status: `fail`",
    `skill_count: \`${payload.skill_count}\``,
    `target_description_chars: \`${TARGET_DESCRIPTION_CHARS}\``,
    `max_description_chars: \`${MAX_DESCRIPTION_CHARS}\``,
    `target_body_lines: \`${TARGET_BODY_LINES}\``,
    `max_body_lines_with_exception: \`${MAX_BODY_LINES}\``,
    `warnings: \`${payload.warnings.length}\``,
    `failures: \`${payload.failures.length}\``,
    "",
    "All first-class descriptions and bodies meet their normal budgets unless explicitly excepted; 180 is absolute.",
  ];
  writeFileSync(join(out, "modernization-report.md"), `${lines.join("\n")}\n`);
}

export function main(argv: readonly string[]): number {
  let root = ".";
  let writeAudit = false;
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--root" && argv[index + 1] !== undefined) {
      root = argv[index + 1] ?? root;
      index += 1;
    } else if (argv[index] === "--write-audit") {
      writeAudit = true;
    }
  }
  const resolved = resolve(root);
  const payload = audit(resolved);
  if (writeAudit) {
    writeArtifacts(resolved, payload);
  } else {
    compareCommitted(resolved, payload);
  }
  if (payload.warnings.length > 0) {
    process.stdout.write(`${payload.warnings.map((warning) => `WARN: ${warning}`).join("\n")}\n`);
  }
  if (payload.failures.length > 0) {
    process.stderr.write(`${payload.failures.map((failure) => `FAIL: ${failure}`).join("\n")}\n`);
    return 1;
  }
  process.stdout.write(`skill catalog validation passed (${payload.skill_count} skills)\n`);
  return 0;
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
