import { createHash } from "node:crypto";
import { mkdtempSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { installAuggie, installCopilot, installGemini } from "./install-hosts.mjs";
import { repoRoot } from "./repo-root.mjs";

assertNodeVersion();

function files(dir: string): string[] {
  const found: string[] = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      found.push(...files(path));
    } else if (entry.isFile() && entry.name !== "catalog.json" && entry.name !== "skills-catalog.json") {
      found.push(path);
    }
  }
  return found.sort();
}

function hashes(root: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const path of files(root)) {
    out[relative(root, path)] = createHash("sha256").update(readFileSync(path)).digest("hex");
  }
  return out;
}

export function main(root = repoRoot(import.meta.url)): number {
  const home = mkdtempSync(join(tmpdir(), "e6-golden-"));
  const target = join(mkdtempSync(join(tmpdir(), "e6-target-")), "repo");
  mkdirSync(target, { recursive: true });
  const previous = process.env.HOME;
  const catalogRoot = process.env.SKILLS_CATALOG_ROOT;
  process.env.HOME = home;
  process.env.SKILLS_CATALOG_ROOT = root;
  try {
    installGemini(["--link"]);
    installAuggie(["--all"]);
    installCopilot(["--repo", target]);
    const golden = {
      gemini: hashes(join(home, ".gemini/skills")),
      auggie: hashes(join(home, ".auggie/rules")),
      copilot: hashes(join(target, ".github")),
    };
    writeFileSync(join(root, "tests/fixtures/host-default-golden.json"), `${JSON.stringify(golden, null, 2)}\n`);
    process.stdout.write(`regenerated: ${Object.entries(golden).map(([host, value]) => `${host}=${Object.keys(value).length} files`).join(", ")}\n`);
    return 0;
  } finally {
    if (previous === undefined) {
      delete process.env.HOME;
    } else {
      process.env.HOME = previous;
    }
    if (catalogRoot === undefined) {
      delete process.env.SKILLS_CATALOG_ROOT;
    } else {
      process.env.SKILLS_CATALOG_ROOT = catalogRoot;
    }
    rmSync(home, { recursive: true, force: true });
    rmSync(join(target, ".."), { recursive: true, force: true });
  }
}

if (invokedDirectly(import.meta.url)) {
  process.exit(main());
}
