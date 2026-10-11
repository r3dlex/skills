import { realpathSync } from "node:fs";
import { pathToFileURL } from "node:url";

export function invokedDirectly(metaUrl: string): boolean {
  const invoked = process.argv[1];
  if (invoked === undefined) {
    return false;
  }
  return metaUrl === pathToFileURL(realpathSync(invoked)).href;
}
