import { mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { projection, select, loadCatalog, CatalogError } from "./catalog-model.mjs";
import { repoRoot } from "./repo-root.mjs";

assertNodeVersion();

const LIFECYCLES = new Set(["stable", "compatibility", "experimental", "deprecated"]);

export interface InstallArgs {
  includes: string[];
  rest: string[];
}

export function parseCatalogArgs(argv: readonly string[]): InstallArgs | number {
  const includes: string[] = [];
  const rest: string[] = [];
  for (let index = 0; index < argv.length; index += 1) {
    const flag = argv[index];
    if (flag !== "--include-lifecycle") {
      if (flag !== undefined) {
        rest.push(flag);
      }
      continue;
    }
    const value = argv[index + 1];
    if (value === undefined) {
      process.stderr.write("--include-lifecycle requires a value\n");
      return 2;
    }
    if (!LIFECYCLES.has(value)) {
      process.stderr.write(`unknown lifecycle: ${value}\n`);
      return 2;
    }
    includes.push(value);
    index += 1;
  }
  return { includes, rest };
}

export function catalogRows(root: string, host: string, includes: readonly string[], skill?: string): { rows: string; projectionText: string } {
  const payload = loadCatalog(root);
  const entries = select(payload, host, new Set(includes), skill);
  return {
    rows: entries.map((entry) => `${entry.name}\t${entry.source_path}`).join("\n"),
    projectionText: `${JSON.stringify(projection(payload, entries), null, 2)}\n`,
  };
}

export function writeProjection(dir: string, name: string, text: string): void {
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, name), text);
}

export function failCatalog(error: unknown): number {
  const message = error instanceof CatalogError ? error.message : "catalog query failed";
  process.stderr.write(`${message}\n`);
  return 2;
}

if (invokedDirectly(import.meta.url)) {
  const argv = process.argv.slice(2);
  if (argv.length === 0) {
    process.exit(0);
  }
  const parsed = parseCatalogArgs(argv);
  if (typeof parsed === "number") {
    process.exit(parsed);
  }
  try {
    const rows = catalogRows(repoRoot(import.meta.url), parsed.rest[0] ?? "", parsed.includes);
    process.stdout.write(rows.rows);
    process.exit(0);
  } catch (error) {
    process.exit(failCatalog(error));
  }
}
