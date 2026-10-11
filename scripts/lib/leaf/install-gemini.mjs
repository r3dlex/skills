import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { installGemini } from "./install-hosts.mjs";
assertNodeVersion();
if (invokedDirectly(import.meta.url)) {
    process.exit(installGemini(process.argv.slice(2)));
}
//# sourceMappingURL=install-gemini.mjs.map