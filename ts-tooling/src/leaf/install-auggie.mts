import { assertNodeVersion } from "../node-version.mjs";
import { invokedDirectly } from "../invoked.mjs";
import { installAuggie } from "./install-hosts.mjs";

assertNodeVersion();

if (invokedDirectly(import.meta.url)) {
  process.exit(installAuggie(process.argv.slice(2)));
}
