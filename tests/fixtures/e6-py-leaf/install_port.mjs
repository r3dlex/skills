import { parseCatalogArgs } from "../../../scripts/lib/leaf/catalog-install.mjs";

const parsed = parseCatalogArgs(["--include-lifecycle", "nope"]);
process.exit(typeof parsed === "number" ? parsed : 0);
