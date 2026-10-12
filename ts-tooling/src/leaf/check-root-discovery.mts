import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { optionHeading } from "./argparse-help.mjs";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";

assertNodeVersion();

const PATTERNS = [
  /(?:r?glob|iglob)\s*\(\s*[rubf]*["'][^"']*SKILL\.md/i,
  /(?:for\s+\w+\s+in|while[^\n]*<)\s*[^\n]*\*[^\n]*SKILL\.md/i,
  /find\s+(?:"?\$?(?:SKILLS_DIR|REPO_ROOT)"?|\.)[^\n]*-name\s+["']?SKILL\.md/i,
  /iterdir\s*\(\s*\).{0,400}SKILL\.md/is,
  /for\s+\w+\s+in\s+[^\n]*"\$\w+"?\/\*[^\n]*\n.{0,300}SKILL\.md/is,
];
const SKIP_NAMES = new Set(["check-root-discovery.py", "root_discovery_guard_test.sh", "skill-catalog_test.sh"]);

function expand(raw: string): string[] {
  const stat = statSync(raw, { throwIfNoEntry: false });
  if (stat?.isFile()) {
    return [raw];
  }
  if (!stat?.isDirectory()) {
    return [];
  }
  const found: string[] = [];
  for (const entry of readdirSync(raw, { withFileTypes: true })) {
    const path = join(raw, entry.name);
    found.push(...(entry.isDirectory() ? expand(path) : [path]));
  }
  return found;
}

function writeDiscoveryHelp(): void {
  process.stdout.write(
    `usage: check-root-discovery.py [-h] [paths ...]\n\npositional arguments:\n  paths\n\n${optionHeading()}\n  -h, --help  show this help message and exit\n`,
  );
}

function helpStatus(argv: readonly string[]): number | undefined {
  if (!argv.includes("--help") && !argv.includes("-h")) {
    return undefined;
  }
  writeDiscoveryHelp();
  return 0;
}

function rejectFlag(argv: readonly string[]): number | undefined {
  const flagged = argv.find((flag) => flag.startsWith("-"));
  if (flagged === undefined) {
    return undefined;
  }
  process.stderr.write(`usage: check-root-discovery.py [-h] [paths ...]\ncheck-root-discovery.py: error: unrecognized arguments: ${flagged}\n`);
  return 2;
}

function scan(argv: readonly string[]): number {
  const roots = argv.length > 0 ? argv : ["scripts", "tests"];
  const failures: string[] = [];
  for (const path of roots.flatMap((raw) => expand(raw))) {
    const name = path.split("/").at(-1) ?? "";
    if (SKIP_NAMES.has(name) || path.split("/").includes("__pycache__")) {
      continue;
    }
    let text: string;
    try {
      text = readFileSync(path, "utf8");
    } catch {
      continue;
    }
    if (PATTERNS.some((pattern) => pattern.test(text))) {
      failures.push(`${path}: unsupported root SKILL.md discovery`);
    }
  }
  if (failures.length > 0) {
    process.stderr.write(`${failures.join("\n")}\n`);
    return 1;
  }
  return 0;
}

export function main(argv: readonly string[]): number {
  return helpStatus(argv) ?? rejectFlag(argv) ?? scan(argv);
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
