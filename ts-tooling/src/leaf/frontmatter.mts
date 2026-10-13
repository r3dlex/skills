import { readFileSync } from "node:fs";
import { pySplitlines } from "./py-text.mjs";

function stripQuotes(value: string): string {
  let start = 0;
  let end = value.length;
  while (start < end && (value[start] === "'" || value[start] === '"')) {
    start += 1;
  }
  while (end > start && (value[end - 1] === "'" || value[end - 1] === '"')) {
    end -= 1;
  }
  return value.slice(start, end);
}

export function frontmatterName(path: string): string {
  const lines = pySplitlines(readFileSync(path, "utf8"));
  if (lines.length === 0 || lines[0] !== "---") {
    return "";
  }
  for (const line of lines.slice(1)) {
    if (line === "---") {
      break;
    }
    if (line.startsWith("name:")) {
      return stripQuotes(line.split(":").slice(1).join(":").trim());
    }
  }
  return "";
}

export function frontmatter(path: string): { meta: Record<string, string>; body: string[] } {
  const lines = pySplitlines(readFileSync(path, "utf8"));
  if (lines.length === 0 || lines[0] !== "---") {
    throw new Error(`${path}: missing opening frontmatter delimiter`);
  }
  const end = lines.indexOf("---", 1);
  if (end < 0) {
    throw new Error(`${path}: missing closing frontmatter delimiter`);
  }
  const meta: Record<string, string> = {};
  for (const line of lines.slice(1, end)) {
    if (!line.includes(":") || line.startsWith(" ")) {
      continue;
    }
    const splitAt = line.indexOf(":");
    const key = line.slice(0, splitAt).trim();
    meta[key] = stripQuotes(line.slice(splitAt + 1).trim());
  }
  return { meta, body: lines.slice(end + 1) };
}
