import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
export function repoRoot(metaUrl) {
    return resolve(dirname(fileURLToPath(metaUrl)), "../../..");
}
//# sourceMappingURL=repo-root.mjs.map