import { opendirSync } from "node:fs";
// Python os.scandir order. fs.readdirSync sorts; that order is not the legacy walk.
export function pyDirents(dir) {
    const handle = opendirSync(dir);
    const found = [];
    let entry = handle.readSync();
    while (entry !== null) {
        found.push(entry);
        entry = handle.readSync();
    }
    handle.closeSync();
    return found;
}
//# sourceMappingURL=py-dirents.mjs.map