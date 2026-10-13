import { readFileSync } from "node:fs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { pySplitlines } from "./py-text.mjs";

assertNodeVersion();

export interface ParityHit {
  file: string;
  line: number;
  construct: string;
}

function stripInline(line: string): string {
  return line.replace(/`[^`]*`/g, "");
}

function firstHit(text: string, denylist: RegExp): string | undefined {
  const flags = denylist.flags.includes("g") ? denylist.flags : `${denylist.flags}g`;
  const pattern = new RegExp(denylist.source, flags);
  return pattern.exec(text)?.[0];
}

export function scanBody(file: string, text: string, denylist: RegExp, marker: string): { missing: boolean; hits: ParityHit[]; pass: boolean } {
  const hits: ParityHit[] = [];
  let inFence = false;
  let prevMarked = false;
  pySplitlines(text).forEach((raw, index) => {
    if (/^\s*(```|~~~)/.test(raw)) {
      inFence = !inFence;
      prevMarked = false;
      return;
    }
    if (inFence) {
      prevMarked = false;
      return;
    }
    const thisMarked = raw.includes(marker);
    const stripped = stripInline(raw);
    const hit = firstHit(stripped, denylist);
    if (hit !== undefined && !thisMarked && !prevMarked) {
      hits.push({ file, line: index + 1, construct: hit });
    }
    prevMarked = thisMarked;
  });
  return { missing: false, hits, pass: hits.length === 0 };
}

export function checkFiles(files: readonly string[], denylist: RegExp, marker: string, usage: string, label: string): number {
  if (files.length === 0) {
    process.stderr.write(`${usage}\n`);
    return 2;
  }
  let status = 0;
  for (const file of files) {
    let text: string;
    try {
      text = readFileSync(file, "utf8");
    } catch {
      process.stderr.write(`MISSING: ${file}\n`);
      status = 2;
      continue;
    }
    const result = scanBody(file, text, denylist, marker);
    if (result.hits.length === 0) {
      process.stdout.write(`PASS: ${file}\n`);
      continue;
    }
    process.stdout.write(`FAIL: ${file}\n`);
    for (const hit of result.hits) {
      process.stdout.write(`  line ${hit.line}: unmarked ${label}-incompatible construct: ${hit.construct}\n`);
    }
    status = 1;
  }
  return status;
}

export function codexMain(argv: readonly string[]): number {
  return checkFiles(
    argv,
    /AskUserQuestion|Task\(subagent_type=|subagent_type:|Skill\(|TodoWrite|mcp__[A-Za-z0-9_]+/,
    "<!-- codex:optional -->",
    "usage: check-codex-parity.sh <SKILL.md> [<SKILL.md> ...]",
    "Codex",
  );
}

export function opencodeMain(argv: readonly string[]): number {
  return checkFiles(
    argv,
    /AskUserQuestion|Task\(subagent_type=|subagent_type:|TodoWrite|mcp__[A-Za-z0-9_]+|~\/\.claude\S*|\.claude-plugin\/\S*|claude (mcp|settings|--)(?:\S+)?(?: \S+)*/,
    "<!-- opencode:optional -->",
    "usage: check-opencode-parity.sh <SKILL.md> [<SKILL.md> ...]",
    "opencode",
  );
}

if (invokedDirectly(import.meta.url)) {
  const entry = process.argv[1] ?? "";
  const status = entry.includes("opencode") ? opencodeMain(process.argv.slice(2)) : codexMain(process.argv.slice(2));
  process.exit(status);
}
