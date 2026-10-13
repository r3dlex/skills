import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { codexMain } from "./skill-parity.mjs";
assertNodeVersion();
if (invokedDirectly(import.meta.url)) {
    process.exit(codexMain(process.argv.slice(2)));
}
//# sourceMappingURL=check-codex-parity.mjs.map