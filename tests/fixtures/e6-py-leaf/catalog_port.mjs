import { CatalogError, loadCatalog, select } from "../../../scripts/lib/leaf/catalog-model.mjs";

const root = process.argv[2];
try {
  const payload = loadCatalog(root);
  const entries = select(payload, "codex");
  process.stdout.write(`${JSON.stringify({ names: entries.map((entry) => entry.name) })}\n`);
} catch (error) {
  const message = error instanceof CatalogError ? error.message : String(error);
  process.stdout.write(`ERR ${message}\n`);
  process.exit(2);
}
