import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { installCopilot } from "./install-hosts.mjs";
assertNodeVersion();
if (invokedDirectly(import.meta.url)) {
    process.exit(installCopilot(process.argv.slice(2)));
}
//# sourceMappingURL=install-copilot.mjs.map