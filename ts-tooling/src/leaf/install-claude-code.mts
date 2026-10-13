import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { installClaude } from "./install-hosts.mjs";

assertNodeVersion();

if (invokedDirectly(import.meta.url)) {
  process.exit(installClaude(process.argv.slice(2)));
}
