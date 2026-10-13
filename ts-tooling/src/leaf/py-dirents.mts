import { opendirSync, type Dirent } from "node:fs";

// Python os.scandir order. fs.readdirSync sorts; that order is not the legacy walk.
export function pyDirents(dir: string): Dirent[] {
  const handle = opendirSync(dir);
  const found: Dirent[] = [];
  let entry = handle.readSync();
  while (entry !== null) {
    found.push(entry);
    entry = handle.readSync();
  }
  handle.closeSync();
  return found;
}
