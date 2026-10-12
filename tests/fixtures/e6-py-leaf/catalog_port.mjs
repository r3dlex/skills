import { CatalogError, loadCatalog, select } from "../../../scripts/lib/leaf/catalog-model.mjs";

const root = process.argv[2];
const mode = process.argv[3] ?? "select";
try {
  const payload = loadCatalog(root);
  if (mode === "unknown-host") {
    select(payload, "nope");
    process.stdout.write("UNEXPECTED\n");
  } else if (mode === "unknown-lifecycle") {
    select(payload, "codex", new Set(["nope"]));
    process.stdout.write("UNEXPECTED\n");
  } else if (mode === "load") {
    process.stdout.write("OK\n");
  } else if (mode === "select") {
    const entries = select(payload, "codex");
    process.stdout.write(`${JSON.stringify({ names: entries.map((entry) => entry.name) })}\n`);
  } else {
    process.stdout.write(`ERR unknown mode ${mode}\n`);
    process.exit(2);
  }
} catch (error) {
  const message = error instanceof CatalogError ? error.message : String(error);
  process.stdout.write(`ERR ${message}\n`);
  process.exit(2);
}
