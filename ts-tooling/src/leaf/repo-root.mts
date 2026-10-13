import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

export function repoRoot(metaUrl: string): string {
  return resolve(dirname(fileURLToPath(metaUrl)), "../../..");
}
