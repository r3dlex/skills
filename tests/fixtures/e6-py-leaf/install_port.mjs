import { parseCatalogArgs } from "../../../scripts/lib/leaf/catalog-install.mjs";

const parsed = parseCatalogArgs(process.argv.slice(2));
process.exit(typeof parsed === "number" ? parsed : 0);
