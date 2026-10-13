import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { opencodeMain } from "./skill-parity.mjs";
assertNodeVersion();
if (invokedDirectly(import.meta.url)) {
    process.exit(opencodeMain(process.argv.slice(2)));
}
//# sourceMappingURL=check-opencode-parity.mjs.map